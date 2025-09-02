// Kalibrate/AdaptiveDifficultyManager.swift
// Created: [Current Date]
// Role: Manages adaptive difficulty based on Key Performance Indicators (KPIs) and arousal levels.
//
// The Adaptive Difficulty Manager (ADM) is the core system for dynamically adjusting game difficulty
// based on player performance. It uses a multi-phase approach:
//
// 1. WARMUP PHASE (25% of session):
//    - Starts at 90 of persisted or default difficulty
//    - Adapts 1.7x faster than normal to quickly find appropriate difficulty
//    - Performance target is 0.80 (vs 0.75 in standard phase)
//    - Acts as a recalibration phase, not an automatic ease-in
//    - Exits at adapted values (no reset to original difficulty)
//
// 2. STANDARD PHASE (remaining 75% of session):
//    - Normal adaptation based on performance target of 0.50
//    - Standard adaptation rate and thresholds
//
// Key Features:
// - Performance-based adaptation with configurable KPI weights
// - Arousal-responsive difficulty ranges for each DOM target
// - Hysteresis to prevent oscillation
// - Confidence-based adaptation scaling
// - Cross-session persistence
// - Direction-specific smoothing (faster easing, slower hardening)

import Foundation
import CoreGraphics
import QuartzCore // For CACurrentMediaTime
// import SpriteKit // For SKColor, though not directly used in this file yet
// GameConfiguration now provides DOMTargetType and KPIType

// MARK: - Performance History Structure
struct PerformanceHistoryEntry: Codable {
    let timestamp: TimeInterval
    let overallScore: CGFloat
    let normalizedKPIs: [KPIType: CGFloat]
    let arousalLevel: CGFloat
    let currentDOMValues: [DOMTargetType: CGFloat]
    let sessionContext: String? // e.g., "warmup", "challenge_phase"
}

// MARK: - Persisted State Structure (Phase 4.5)
struct PersistedADMState: Codable {
    let performanceHistory: [PerformanceHistoryEntry]
    let lastAdaptationDirection: AdaptiveDifficultyManager.AdaptationDirection
    let directionStableCount: Int
    let normalizedPositions: [DOMTargetType: CGFloat]
    let domPerformanceProfiles: [DOMTargetType: DOMPerformanceProfile]? // Optional for backward compatibility
    var version: Int = 2 // Incremented for DOM profile support
}

// MARK: - DOM Performance Profile Structure (Phase 5.2)
struct DOMPerformanceProfile: Codable {
    struct PerformanceDataPoint: Codable {
        let timestamp: TimeInterval
        let value: CGFloat
        let performance: CGFloat
    }
    
    let domType: DOMTargetType
    var performanceByValue: [PerformanceDataPoint] = []
    
    mutating func recordPerformance(domValue: CGFloat, performance: CGFloat) {
        performanceByValue.append(PerformanceDataPoint(
            timestamp: CACurrentMediaTime(),
            value: domValue,
            performance: performance
        ))
        // Buffer size of 200 to maintain long-term performance history across sessions
        if performanceByValue.count > 200 {
            performanceByValue.removeFirst()
        }
    }
}

class AdaptiveDifficultyManager {
    var dataLogger: DataLogger = DataLogger.shared
    internal let config: GameConfiguration
    private var currentArousalLevel: CGFloat
    var userId: String // Changed to var and made internal for testing
    
    // MARK: - Thread Safety
    /// Serial queue for protecting ADM state from concurrent access
    private let admQueue = DispatchQueue(label: "com.kalibrate.ADMQueue", qos: .userInitiated)

    // Current actual values of DOM targets (owned by ADM)
    private(set) var currentDiscriminabilityFactor: CGFloat
    private(set) var currentMeanBallSpeed: CGFloat
    private(set) var currentBallSpeedSD: CGFloat
    private(set) var currentResponseTime: TimeInterval
    private(set) var currentTargetCount: Int // Stored as Int, converted to CGFloat for calcs

    // Normalized positions (0.0-1.0) for each DOM target
    // 0.0 = easiest setting, 1.0 = hardest setting
    var normalizedPositions: [DOMTargetType: CGFloat] = [:]

    // Current valid ranges (min/max) for each DOM target at current arousal level
    private var currentValidRanges: [DOMTargetType: (min: CGFloat, max: CGFloat)] = [:]

    // MARK: - Performance History (NEW)
    var performanceHistory: [PerformanceHistoryEntry] = []
    private let maxHistorySize: Int  // Will be set from config

    // MARK: - DOM Performance Profiles (Phase 5.2)
    internal var domPerformanceProfiles: [DOMTargetType: DOMPerformanceProfile] = [:] // Made internal for testing

    // MARK: - Forced Exploration State Tracking (Phase 5)
    internal var domConvergenceCounters: [DOMTargetType: Int] = [:] // Made internal for testing

    // MARK: - Logging Throttling
    private var lastLogTime: TimeInterval = 0
    private let logThrottleInterval: TimeInterval = 1.0 // Log once per second
    
    // MARK: - Hysteresis State Tracking (Phase 3)
    enum AdaptationDirection: String, Codable {
        case increasing, decreasing, stable
    }
    
    internal var lastAdaptationDirection: AdaptationDirection = .stable
    internal var directionStableCount: Int = 0
    internal var lastSignificantChangeTime: TimeInterval = 0

    // MARK: - Session Phase Management (Phase 5)
    
    /// Represents the current phase of the gaming session
    /// - warmup: Initial recalibration phase with reduced difficulty and faster adaptation
    /// - standard: Main gameplay phase with normal adaptation
    enum SessionPhase {
        case warmup
        case standard
    }
    
    /// Current session phase
    private(set) var currentPhase: SessionPhase
    
    /// Number of rounds completed in the current phase
    private var roundsInCurrentPhase: Int = 0
    
    /// Total number of rounds in the warmup phase (calculated based on session duration)
    private let warmupPhaseLength: Int
    
    // MARK: - Hysteresis Helper Structures
    struct AdaptationThresholds {
        let performanceTarget: CGFloat = 0.75
        let increaseThreshold: CGFloat
        let decreaseThreshold: CGFloat
        let baseDeadZone: CGFloat
        let hysteresisEnabled: Bool
    }

    // KPI History (for potential rolling averages - simple array for now)
    // private var recentTaskSuccesses: [Bool] = [] // Example
    // ... other KPI history properties ...
    // private let kpiHistoryWindowSize: Int = 3 // Example: average over last 3 rounds

    init(
        configuration: GameConfiguration,
        initialArousal: CGFloat,
        sessionDuration: TimeInterval,
        userId: String? = nil
    ) {
        self.config = configuration
        self.currentArousalLevel = initialArousal
        self.maxHistorySize = configuration.performanceHistoryWindowSize
        self.userId = userId ?? UserIDManager.getUserId()

        // Calculate dynamic phase lengths
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: configuration,
            initialArousal: initialArousal
        )
        // Ensure at least 1 warmup round if warmup is enabled and there are any rounds
        let calculatedWarmupLength = Int(CGFloat(expectedRounds) * configuration.warmupPhaseProportion)
        self.warmupPhaseLength = (configuration.enableSessionPhases && expectedRounds > 0) ? max(1, calculatedWarmupLength) : calculatedWarmupLength

        if configuration.enableSessionPhases {
            self.currentPhase = .warmup
            print("[ADM Warm-up] === WARMUP INITIALIZATION ===")
            print("[ADM Warm-up] Warmup ENABLED")
            print("[ADM Warm-up] Session duration: \(String(format: "%.1f", sessionDuration)) seconds")
            print("[ADM Warm-up] Expected total rounds: \(expectedRounds)")
            print("[ADM Warm-up] Warmup phase length: \(self.warmupPhaseLength) rounds")
            print("[ADM Warm-up] Warmup proportion: \(String(format: "%.1f%%", configuration.warmupPhaseProportion * 100))")
            print("[ADM Warm-up] Initial difficulty multiplier: \(configuration.warmupInitialDifficultyMultiplier)")
            print("[ADM Warm-up] Performance target: \(configuration.warmupPerformanceTarget)")
            print("[ADM Warm-up] Adaptation rate multiplier: \(configuration.warmupAdaptationRateMultiplier)")
        } else {
            self.currentPhase = .standard
            print("[ADM Warm-up] Warmup DISABLED - starting in standard phase")
        }

        // Initialize stored properties with placeholder values first
        self.currentDiscriminabilityFactor = 0.0
        self.currentMeanBallSpeed = 0.0
        self.currentBallSpeedSD = 0.0
        self.currentResponseTime = 0.0
        self.currentTargetCount = 0
        
        // Initialize normalized positions to middle of range (0.5)
        // All DOMs start at 0.5 (conditional kept for potential future tweaking)
        for domType in [DOMTargetType.discriminatoryLoad, .meanBallSpeed, .ballSpeedSD, .responseTime, .targetCount] {
            if domType == .targetCount {
                normalizedPositions[domType] = 0.5 // Start at midpoint (same as others)
            } else {
                normalizedPositions[domType] = 0.5 // Others start at midpoint
            }
        }
        
        // Initialize DOM performance profiles (Phase 5.2)
        for domType in DOMTargetType.allCases {
            domPerformanceProfiles[domType] = DOMPerformanceProfile(domType: domType)
        }

        var didLoadState = false
        
        // Phase 4.5: Load persisted state if available and not clearing
        print("[ADM] === PERSISTENCE INITIALIZATION ===")
        print("[ADM] User ID: \(self.userId)")
        print("[ADM] Clear Past Session Data Flag: \(configuration.clearPastSessionData)")
        
        if !configuration.clearPastSessionData {
            print("[ADM] Attempting to load persisted state...")
            if let persistedState = ADMPersistenceManager.loadState(for: self.userId) {
                print("[ADM] ✅ Found persisted state! Loading...")
                loadState(from: persistedState)
                
                // Validate that positions were actually loaded
                print("[ADM] === VERIFYING LOADED POSITIONS ===")
                var allPositionsDefault = true
                for (dom, position) in normalizedPositions {
                    print("[ADM]   \(dom): \(String(format: "%.3f", position))")
                    // Check if any position differs from default (0.5)
                    if abs(position - 0.5) > 0.001 {
                        allPositionsDefault = false
                    }
                }
                
                if allPositionsDefault && !persistedState.normalizedPositions.isEmpty {
                    print("[ADM] ⚠️ WARNING: All positions are at default despite loading state!")
                    print("[ADM] ⚠️ Persisted positions were:")
                    for (dom, position) in persistedState.normalizedPositions {
                        print("[ADM]   \(dom): \(String(format: "%.3f", position))")
                    }
                }
                print("[ADM] === END VERIFICATION ===")
                
                didLoadState = true
            } else {
                print("[ADM] ⚠️ No persisted state found - starting fresh")
            }
        } else {
            print("[ADM] Clearing mode enabled - removing any existing state")
            ADMPersistenceManager.clearState(for: self.userId)
            print("[ADM] ✅ Cleared past session data")
        }
        
        print("[ADM] === END PERSISTENCE INITIALIZATION ===")

        // Phase 5: Apply warmup difficulty reduction if applicable
        // The warmup phase serves as a recalibration period where:
        // - Difficulty starts at 90% of normal to ensure a comfortable start
        // - But with a floor of 0.3 to ensure room for easing
        // - Adaptation happens 1.7x faster to quickly find appropriate difficulty
        // - Performance target is slightly higher (0.80) to avoid over-hardening
        if self.currentPhase == .warmup {
            print("[ADM Warm-up] === APPLYING WARMUP DIFFICULTY SCALING ===")
            if didLoadState {
                print("[ADM Warm-up] Starting from persisted state")
                // Reduce difficulty from the persisted level for the warm-up, with floor of 0.3
                for (dom, position) in self.normalizedPositions {
                    let originalPosition = position
                    let scaledPosition = position * config.warmupInitialDifficultyMultiplier
                    self.normalizedPositions[dom] = max(scaledPosition, 0.3)
                    print("[ADM Warm-up] \(dom): \(String(format: "%.3f", originalPosition)) → \(String(format: "%.3f", self.normalizedPositions[dom] ?? 0))")
                }
                DataLogger.shared.logCustomEvent(eventType: "ADM_Warmup_Started_From_Persistence", data: [:])
            } else {
                print("[ADM Warm-up] Starting fresh (no persisted state)")
                // If starting fresh, still apply the multiplier to the default 0.5
                 for (dom, position) in self.normalizedPositions {
                    let originalPosition = position
                    let scaledPosition = position * config.warmupInitialDifficultyMultiplier
                    self.normalizedPositions[dom] = max(scaledPosition, 0.3)
                    print("[ADM Warm-up] \(dom): \(String(format: "%.3f", originalPosition)) → \(String(format: "%.3f", self.normalizedPositions[dom] ?? 0))")
                }
                DataLogger.shared.logCustomEvent(eventType: "ADM_Warmup_Started_Fresh_Session", data: [:])
            }
            print("[ADM Warm-up] === WARMUP SCALING COMPLETE ===")
        }
        
        // Initialize current valid ranges based on initial arousal
        updateValidRangesForCurrentArousal()
        
        // Initialize absolute DOM values based on normalized positions and ranges
        updateAbsoluteValuesFromNormalizedPositions()
        
        print("[ADM] Initialized with arousal: \(initialArousal)")
        print("[ADM] Initial DF: \(currentDiscriminabilityFactor)")
        print("[ADM] Initial MeanSpeed: \(currentMeanBallSpeed)")
        print("[ADM] Initial SpeedSD: \(currentBallSpeedSD)")
        print("[ADM] Initial ResponseTime: \(currentResponseTime)")
        print("[ADM] Initial TargetCount: \(currentTargetCount)")
    }

    // MARK: - Continuous Arousal Update Methods
    
    /// Updates the current valid ranges for all DOM targets based on current arousal
    private func updateValidRangesForCurrentArousal() {
        for domType in [DOMTargetType.discriminatoryLoad, .meanBallSpeed, .ballSpeedSD, .responseTime, .targetCount] {
            let easiestSetting = getArousalGatedEasiestSetting(for: domType, currentArousal: currentArousalLevel)
            let hardestSetting = getArousalGatedHardestSetting(for: domType, currentArousal: currentArousalLevel)
            currentValidRanges[domType] = (min: min(easiestSetting, hardestSetting), 
                                          max: max(easiestSetting, hardestSetting))
        }
    }
    
    /// Converts a normalized value (0-1) to an absolute value for a DOM target
    private func normalizedToAbsoluteValue(normalizedValue: CGFloat, for domType: DOMTargetType) -> CGFloat {
        guard let _ = currentValidRanges[domType] else { return 0 }
        
        // Clamp normalized value between 0 and 1
        let clampedNormalized = max(0.0, min(1.0, normalizedValue))
        
        // For most DOM targets, easiest is at 0.0 and hardest at 1.0
        // But for some (like discriminatoryLoad), this may be reversed
        let easiest = getArousalGatedEasiestSetting(for: domType, currentArousal: currentArousalLevel)
        let hardest = getArousalGatedHardestSetting(for: domType, currentArousal: currentArousalLevel)
        
        // If easiest > hardest (e.g., in discriminatory load where higher value means easier)
        // we need to reverse the interpolation
        if easiest > hardest {
            return easiest - (easiest - hardest) * clampedNormalized
        } else {
            return easiest + (hardest - easiest) * clampedNormalized
        }
    }
    
    /// Updates all absolute DOM values based on their normalized positions and current ranges
    internal func updateAbsoluteValuesFromNormalizedPositions() {
        for (domType, normalizedPosition) in normalizedPositions {
            let absoluteValue = normalizedToAbsoluteValue(normalizedValue: normalizedPosition, for: domType)
            setCurrentValue(for: domType, rawValue: absoluteValue)
        }
    }
    
    /// Public method to continuously update DOM targets based on current arousal
    public func updateForCurrentArousal() {
        // Update valid ranges based on current arousal
        updateValidRangesForCurrentArousal()
        
        // Update absolute values based on normalized positions and new ranges
        updateAbsoluteValuesFromNormalizedPositions()
        
        // Add diagnostic logging for discriminatory load (with throttling)
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastLogTime >= logThrottleInterval {
            dataLogger.logCustomEvent(
                eventType: "adm_discriminatory_load_tracking",
                data: [
                    "discriminatory_load_position": normalizedPositions[.discriminatoryLoad] ?? 0.5,
                    "arousal_level": currentArousalLevel
                ],
                description: "Tracking discriminatory load position during arousal updates"
            )
            lastLogTime = currentTime
        }
    }
    
    /// Legacy method - kept for backwards compatibility but not used in the new system
    private func setInitialDOMValues(arousal: CGFloat) {
        // This method is now a no-op as initialization is handled by 
        // updateValidRangesForCurrentArousal and updateAbsoluteValuesFromNormalizedPositions
    }

    // MARK: - Public API
    func updateArousalLevel(_ arousal: CGFloat) {
        let oldArousal = self.currentArousalLevel
        self.currentArousalLevel = max(0.0, min(1.0, arousal))
        
        // If arousal changed significantly, immediately update ranges and values
        if abs(oldArousal - self.currentArousalLevel) > 0.001 {
            updateForCurrentArousal()
        }
    }

    /// Asynchronous version of recordIdentificationPerformance that performs intensive calculations on a background thread
    /// - Parameters:
    ///   - taskSuccess: Whether the identification task was successful
    ///   - tfTtfRatio: Targets Found / Targets To Find ratio
    ///   - reactionTime: User's reaction time
    ///   - responseDuration: Duration of response phase
    ///   - averageTapAccuracy: Average tap accuracy in points
    ///   - actualTargetsToFindInRound: Number of targets in the round
    ///   - completion: Completion handler called on main thread when processing is complete
    func recordIdentificationPerformanceAsync(
        taskSuccess: Bool,
        tfTtfRatio: CGFloat,
        reactionTime: TimeInterval,
        responseDuration: TimeInterval,
        averageTapAccuracy: CGFloat,
        actualTargetsToFindInRound: Int,
        completion: @escaping () -> Void
    ) {
        // Perform all intensive calculations on background thread
        admQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion() }
                return
            }
            
            // 1. Normalize all relevant KPIs
            let normalizedKPIs = self.normalizeAllKPIs(
                rawTaskSuccess: taskSuccess,
                rawTfTtfRatio: tfTtfRatio,
                rawReactionTime: reactionTime,
                rawResponseDuration: responseDuration,
                rawAverageTapAccuracy: averageTapAccuracy,
                actualTargetsToFind: actualTargetsToFindInRound
            )
            
            // 2. Calculate overallPerformanceScore
            let performanceScore = self.calculateOverallPerformanceScore(normalizedKPIs: normalizedKPIs)
            
            // Phase 5.2: Collect DOM-specific performance data (passive)
            for domType in DOMTargetType.allCases {
                let currentValue = self.getCurrentValue(for: domType)
                self.domPerformanceProfiles[domType]?.recordPerformance(
                    domValue: currentValue,
                    performance: performanceScore
                )
                
                // Temporary logging to verify data collection
                if let profile = self.domPerformanceProfiles[domType] {
                    print("[ADM DOM Profiling] \(domType): value=\(String(format: "%.3f", currentValue)), performance=\(String(format: "%.3f", performanceScore)), buffer_size=\(profile.performanceByValue.count)")
                }
            }
            
            // 3. Store performance history
            let domValues = DOMTargetType.allCases.reduce(into: [DOMTargetType: CGFloat]()) {
                $0[$1] = self.getCurrentValue(for: $1)
            }
            
            let entry = PerformanceHistoryEntry(
                timestamp: CACurrentMediaTime(),
                overallScore: performanceScore,
                normalizedKPIs: normalizedKPIs,
                arousalLevel: self.currentArousalLevel,
                currentDOMValues: domValues,
                sessionContext: nil // Placeholder for now
            )
            self.addPerformanceEntry(entry)
            
            // Log performance metrics after adding to history (with throttling)
            var currentTime = Date().timeIntervalSince1970
            if currentTime - self.lastLogTime >= self.logThrottleInterval {
                let (average, trend, variance) = self.getPerformanceMetrics()
                self.dataLogger.logCustomEvent(
                    eventType: "adm_performance_history",
                    data: [
                        "history_size": self.performanceHistory.count,
                        "performance_average": average,
                        "performance_trend": trend,
                        "performance_variance": variance,
                        "recent_score": performanceScore
                    ],
                    description: "ADM performance history metrics"
                )
                self.lastLogTime = currentTime
            }
            
            // 4. Modulate DOM targets (this is the most intensive part)
            self.modulateDOMTargets(overallPerformanceScore: performanceScore)
            
            // Log the adaptive difficulty step (with throttling)
            currentTime = Date().timeIntervalSince1970
            if currentTime - self.lastLogTime >= self.logThrottleInterval {
                let domValues = DOMTargetType.allCases.reduce(into: [DOMTargetType: CGFloat]()) {
                    $0[$1] = self.getCurrentValue(for: $1)
                }
                self.dataLogger.logAdaptiveDifficultyStep(
                    arousalLevel: self.currentArousalLevel,
                    performanceScore: performanceScore,
                    normalizedKPIs: normalizedKPIs,
                    domValues: domValues
                )
                self.lastLogTime = currentTime
            }
            
            // Call completion handler on main thread
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    /// Synchronous version (deprecated) - use recordIdentificationPerformanceAsync instead
    /// This method now calls the async version and blocks until completion
    @available(*, deprecated, message: "Use recordIdentificationPerformanceAsync instead to avoid blocking the main thread")
    func recordIdentificationPerformance(
        taskSuccess: Bool,
        tfTtfRatio: CGFloat, // Targets Found / Targets To Find
        reactionTime: TimeInterval,
        responseDuration: TimeInterval,
        averageTapAccuracy: CGFloat, // In points
        actualTargetsToFindInRound: Int // Needed for normalizing responseDuration
    ) {
        // For backward compatibility, call the async version and wait
        let semaphore = DispatchSemaphore(value: 0)
        
        recordIdentificationPerformanceAsync(
            taskSuccess: taskSuccess,
            tfTtfRatio: tfTtfRatio,
            reactionTime: reactionTime,
            responseDuration: responseDuration,
            averageTapAccuracy: averageTapAccuracy,
            actualTargetsToFindInRound: actualTargetsToFindInRound
        ) {
            semaphore.signal()
        }
        
        semaphore.wait()
    }

    // MARK: - Core Logic (Placeholders - to be implemented next)
    
    private func normalizeAllKPIs(
        rawTaskSuccess: Bool,
        rawTfTtfRatio: CGFloat,
        rawReactionTime: TimeInterval,
        rawResponseDuration: TimeInterval,
        rawAverageTapAccuracy: CGFloat,
        actualTargetsToFind: Int
    ) -> [KPIType: CGFloat] { // Changed ADM_KPIType to global KPIType
        // Placeholder - detailed implementation next
        var normalized: [KPIType: CGFloat] = [:] // Changed ADM_KPIType to global KPIType
        normalized[.taskSuccess] = rawTaskSuccess ? 1.0 : 0.0
        normalized[.tfTtfRatio] = rawTfTtfRatio // Already 0-1

        // Reaction Time (lower is better)
        let bestRT = config.reactionTime_BestExpected
        let worstRT = config.reactionTime_WorstExpected
        if worstRT > bestRT {
            normalized[.reactionTime] = 1.0 - max(0.0, min(1.0, (CGFloat(rawReactionTime) - CGFloat(bestRT)) / (CGFloat(worstRT) - CGFloat(bestRT))))
        } else { // Should ideally not happen if worstRT is always > bestRT
            normalized[.reactionTime] = (rawReactionTime <= bestRT) ? 1.0 : 0.0
        }
        
        // Response Duration (lower is better, scaled by target count)
        let dynamicBestRD = config.responseDuration_PerTarget_BestExpected * TimeInterval(actualTargetsToFind)
        let dynamicWorstRD = config.responseDuration_PerTarget_WorstExpected * TimeInterval(actualTargetsToFind)
        if dynamicWorstRD > dynamicBestRD {
             normalized[.responseDuration] = 1.0 - max(0.0, min(1.0, (CGFloat(rawResponseDuration) - CGFloat(dynamicBestRD)) / (CGFloat(dynamicWorstRD) - CGFloat(dynamicBestRD))))
        } else { // Should ideally not happen
            normalized[.responseDuration] = (rawResponseDuration <= dynamicBestRD) ? 1.0 : 0.0
        }

        // Tap Accuracy (lower is better - points)
        let bestAcc = config.tapAccuracy_BestExpected_Points
        let worstAcc = config.tapAccuracy_WorstExpected_Points
        if worstAcc > bestAcc {
            normalized[.tapAccuracy] = 1.0 - max(0.0, min(1.0, (rawAverageTapAccuracy - bestAcc) / (worstAcc - bestAcc)))
        } else { // Should ideally not happen
            normalized[.tapAccuracy] = (rawAverageTapAccuracy <= bestAcc) ? 1.0 : 0.0
        }
        
        return normalized
    }
    
    func calculateOverallPerformanceScore(normalizedKPIs: [KPIType: CGFloat]) -> CGFloat { // Changed ADM_KPIType
        // Get interpolated weights based on current arousal (Phase 1.5)
        let weights = getInterpolatedKPIWeights(arousal: currentArousalLevel)
        
        var score: CGFloat = 0.0
        // Using global KPIType for dictionary keys
        score += (normalizedKPIs[.taskSuccess] ?? 0.0) * weights.taskSuccess
        score += (normalizedKPIs[.tfTtfRatio] ?? 0.0) * weights.tfTtfRatio
        score += (normalizedKPIs[.reactionTime] ?? 0.0) * weights.reactionTime
        score += (normalizedKPIs[.responseDuration] ?? 0.0) * weights.responseDuration
        score += (normalizedKPIs[.tapAccuracy] ?? 0.0) * weights.tapAccuracy
        
        return max(0.0, min(1.0, score)) // Ensure score is clamped 0-1
    }

    func calculateAdaptivePerformanceScore(currentScore: CGFloat) -> CGFloat {
        guard performanceHistory.count >= config.minimumHistoryForTrend else {
            return currentScore
        }
        
        let (average, trend, _) = getPerformanceMetrics()
        
        // Weight recent performance more heavily
        let recentWeight = config.currentPerformanceWeight
        let historyWeight = config.historyInfluenceWeight
        let trendWeight = config.trendInfluenceWeight
        
        // Consider trend in final score
        let trendAdjustment = trend * trendWeight
        
        let weightedScore = (currentScore * recentWeight) +
                            (average * historyWeight) +
                            trendAdjustment
        
        return max(0.0, min(1.0, weightedScore)) // Clamp the final adaptive score
    }
    
    /// Modulates DOM targets based on performance score
    /// - Parameter overallPerformanceScore: Normalized performance score (0.0-1.0)
    /// 
    /// This method:
    /// 1. Updates the session phase
    /// 2. Applies phase-specific performance targets and adaptation rates
    /// 3. Calculates adaptation signal with hysteresis
    /// 4. Distributes adaptation budget across DOM targets
    /// 5. Updates absolute values from normalized positions
    func modulateDOMTargets(overallPerformanceScore: CGFloat) {
        updateSessionPhase() // Update phase at the start of each round

        // Phase 5: Check if DOM-specific profiling should be used
        if config.enableDomSpecificProfiling && currentPhase == .standard {
            // Try to use DOM-specific profiling
            let pdControllerRan = modulateDOMsWithProfiling()
            
            if pdControllerRan {
                // PD controller successfully handled adaptation
                return
            } else {
                // PD controller couldn't run - fall back to global adaptation
                print("[ADM] PD Controller not ready (insufficient data), falling back to global adaptation")
                let currentTime = Date().timeIntervalSince1970
                if currentTime - lastLogTime >= logThrottleInterval {
                    dataLogger.logCustomEvent(
                        eventType: "ADM_PD_Controller_Fallback",
                        data: [
                            "reason": "insufficient_data",
                            "phase": "standard"
                        ]
                    )
                    lastLogTime = currentTime
                }
                // Continue with global adaptation below
            }
        }

        var performanceTarget = config.globalPerformanceTarget // Use configured global target
        var adaptationRateMultiplier: CGFloat = 1.0

        switch currentPhase {
        case .warmup:
            // Warmup phase uses higher performance target and faster adaptation
            // to quickly find the player's appropriate difficulty level
            performanceTarget = config.warmupPerformanceTarget
            adaptationRateMultiplier = config.warmupAdaptationRateMultiplier
            
            // Calculate warmup progress
            let warmupProgress = CGFloat(roundsInCurrentPhase) / CGFloat(max(1, warmupPhaseLength))
            let progressPercentage = min(100, warmupProgress * 100)
            
            print("[ADM Warm-up] === ROUND \(roundsInCurrentPhase) OF \(warmupPhaseLength) ===")
            print("[ADM Warm-up] Progress: \(String(format: "%.1f%%", progressPercentage)) complete")
            print("[ADM Warm-up] Performance score: \(String(format: "%.3f", overallPerformanceScore))")
            print("[ADM Warm-up] Target performance: \(String(format: "%.3f", performanceTarget))")
            print("[ADM Warm-up] Adaptation rate multiplier: \(adaptationRateMultiplier)")
            
            // Visual progress bar
            let barLength = 20
            let filledLength = Int(warmupProgress * CGFloat(barLength))
            let emptyLength = barLength - filledLength
            let progressBar = String(repeating: "█", count: filledLength) + String(repeating: "░", count: emptyLength)
            print("[ADM Warm-up] Progress bar: [\(progressBar)]")
            
        case .standard:
            break // Use default values
        }

        let adaptiveScore = calculateAdaptivePerformanceScore(currentScore: overallPerformanceScore)
        
        if performanceHistory.count >= config.minimumHistoryForTrend {
            let currentTime = Date().timeIntervalSince1970
            if currentTime - lastLogTime >= logThrottleInterval {
                let (_, trend, _) = getPerformanceMetrics()
                dataLogger.logCustomEvent(
                    eventType: "adm_trend_metrics",
                    data: [
                        "raw_performance_score": overallPerformanceScore,
                        "adaptive_performance_score": adaptiveScore,
                        "performance_trend": trend
                    ],
                    description: "ADM trend-based adaptation metrics"
                )
                lastLogTime = currentTime
            }
        }

        // Get effective thresholds based on confidence (Phase 4)
        let effectiveThresholds = getEffectiveAdaptationThresholds()

        // Apply hysteresis logic if enabled
        let (adaptationSignal, newDirection) = calculateAdaptationSignalWithHysteresis(
            performanceScore: adaptiveScore,
            thresholds: effectiveThresholds,
            performanceTarget: performanceTarget
        )
        
        var adaptationSignalBudget = adaptationSignal * adaptationRateMultiplier
        
        // Scale adaptation by confidence (Phase 4)
        if config.enableConfidenceScaling {
            let confidence = calculateAdaptationConfidence().total
            let confidenceMultiplier = config.minConfidenceMultiplier + (1.0 - config.minConfidenceMultiplier) * confidence
            adaptationSignalBudget *= confidenceMultiplier
            
            // Log confidence metrics
            let currentTime = Date().timeIntervalSince1970
            if currentTime - lastLogTime >= logThrottleInterval {
                dataLogger.logCustomEvent(
                    eventType: "adm_confidence_metrics",
                    data: [
                        "confidence_score": confidence,
                        "confidence_multiplier": confidenceMultiplier,
                        "original_signal": adaptationSignal,
                        "scaled_signal": adaptationSignalBudget
                    ],
                    description: "ADM confidence-based adaptation scaling"
                )
                lastLogTime = currentTime
            }
        }
        
        // Update direction tracking
        if newDirection != lastAdaptationDirection {
            if newDirection == .stable {
                // Don't reset stable count if we're in stable due to hysteresis
                // Only reset if we were actively adapting and now genuinely stable
                if lastAdaptationDirection != .stable && abs(adaptationSignal) < config.adaptationSignalDeadZone {
                    directionStableCount = 0
                }
                // Otherwise, maintain the count to allow eventual direction change
            } else if lastAdaptationDirection == .stable {
                // Starting to adapt after being stable
                directionStableCount = 1
                lastSignificantChangeTime = CACurrentMediaTime()
            } else if (lastAdaptationDirection == .increasing && newDirection == .decreasing) ||
                      (lastAdaptationDirection == .decreasing && newDirection == .increasing) {
                // Direction reversal
                directionStableCount = 1
                lastSignificantChangeTime = CACurrentMediaTime()
                
                // Log direction change
                let currentTime = Date().timeIntervalSince1970
                if currentTime - lastLogTime >= logThrottleInterval {
                    dataLogger.logCustomEvent(
                        eventType: "adm_hysteresis_direction_change",
                        data: [
                            "previous_direction": String(describing: lastAdaptationDirection),
                            "new_direction": String(describing: newDirection),
                            "performance_score": adaptiveScore,
                            "adaptation_signal": adaptationSignal
                        ],
                        description: "ADM hysteresis direction change detected"
                    )
                    lastLogTime = currentTime
                }
            }
            lastAdaptationDirection = newDirection
        } else if newDirection != .stable {
            directionStableCount += 1
        } else if newDirection == .stable && lastAdaptationDirection != .stable {
            // Continue counting stable rounds while in stable state after being non-stable
            // This allows accumulation of rounds to eventually permit direction change
            directionStableCount += 1
        }
        
        // Apply sensitivity (potentially different for easing vs hardening)
        if adaptationSignalBudget < 0 {
            // Apply standard sensitivity for easing
            adaptationSignalBudget *= config.adaptationSignalSensitivity
        } else {
            // Apply standard sensitivity for hardening
            adaptationSignalBudget *= config.adaptationSignalSensitivity
        }
        
        // Add warmup-specific adaptation debug output
        if currentPhase == .warmup {
            print("[ADM Warm-up] === DOM ADAPTATION ===")
            print("[ADM Warm-up] Pre-rate multiplier signal: \(String(format: "%.3f", adaptationSignal))")
            print("[ADM Warm-up] Post-rate multiplier budget: \(String(format: "%.3f", adaptationSignal * adaptationRateMultiplier))")
            print("[ADM Warm-up] Post-confidence scaling: \(String(format: "%.3f", adaptationSignalBudget))")
            print("[ADM Warm-up] Direction: \(newDirection)")
            print("[ADM Warm-up] Adaptation is \(adaptationSignalBudget < 0 ? "EASING (making easier)" : adaptationSignalBudget > 0 ? "HARDENING (making harder)" : "STABLE (no change)")")
        }
        
        print("[ADM] Modulating DOMs. Initial Budget: \(String(format: "%.3f", adaptationSignalBudget)) from AdaptiveScore: \(String(format: "%.3f", adaptiveScore))")

        updateValidRangesForCurrentArousal()

        if adaptationSignalBudget < 0 {
            // Easing logic with inverted priorities
            adaptationSignalBudget = modulateDOMsWithWeightedBudget(totalBudget: adaptationSignalBudget, arousal: currentArousalLevel, invertPriorities: true)
        } else {
            // Hardening logic with standard priorities
            adaptationSignalBudget = modulateDOMsWithWeightedBudget(totalBudget: adaptationSignalBudget, arousal: currentArousalLevel, invertPriorities: false)
        }
        
        if abs(adaptationSignalBudget) > 0.001 {
             print("[ADM] Modulation complete. Unspent budget: \(String(format: "%.4f", adaptationSignalBudget))")
        }
        
        updateAbsoluteValuesFromNormalizedPositions()
    }
    
    // MARK: - Hysteresis & Confidence Implementation (Phase 3 & 4)
    
    // MARK: - Session Phase Logic (Phase 5)
    
    /// Updates the current session phase based on round count and performance metrics
    /// Called at the start of each round to check for phase transitions
    private func updateSessionPhase() {
        guard config.enableSessionPhases else { return }
        
        roundsInCurrentPhase += 1
        
        switch currentPhase {
        case .warmup:
            // Warmup phase completes after a fixed number of rounds
            // Transitions to standard phase with adapted difficulty values
            if roundsInCurrentPhase >= warmupPhaseLength {
                print("[ADM Warm-up] === WARMUP PHASE COMPLETE ===")
                print("[ADM Warm-up] Total rounds in warmup: \(warmupPhaseLength)")
                
                // Calculate warmup performance summary
                if !performanceHistory.isEmpty {
                    let warmupEntries = performanceHistory.suffix(warmupPhaseLength)
                    let avgScore = warmupEntries.reduce(0.0) { $0 + $1.overallScore } / CGFloat(warmupEntries.count)
                    print("[ADM Warm-up] Average performance during warmup: \(String(format: "%.3f", avgScore))")
                }
                
                print("[ADM Warm-up] Final DOM positions at end of warmup:")
                for (domType, position) in normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    let absoluteValue = getCurrentValue(for: domType)
                    print("[ADM Warm-up]   - \(domType): \(String(format: "%.3f", position)) (absolute: \(String(format: "%.1f", absoluteValue)))")
                }
                
                print("[ADM Warm-up] === TRANSITIONING TO STANDARD PHASE ===")
                // NOTE: Difficulty remains at adapted values - no reset to pre-warmup levels
                currentPhase = .standard
                roundsInCurrentPhase = 0
                DataLogger.shared.logCustomEvent(eventType: "ADM_Phase_Transition_To_Standard", data: [:])
            }
        case .standard:
            // Standard phase continues for the rest of the session
            break
        }
    }


    // MARK: - Hysteresis & Confidence Implementation (Phase 3 & 4)
    
    /// Calculates adaptation signal with hysteresis to prevent oscillation
    func calculateAdaptationSignalWithHysteresis(performanceScore: CGFloat, thresholds: AdaptationThresholds, performanceTarget: CGFloat) -> (signal: CGFloat, direction: AdaptationDirection) {
        guard config.enableHysteresis else {
            // Original logic without hysteresis
            let rawSignal = (performanceScore - performanceTarget) * 2.0
            let signal = max(-1.0, min(1.0, rawSignal)) // Clamp signal to [-1, 1]
            
            if abs(signal) < config.adaptationSignalDeadZone {
                return (0.0, .stable)
            }
            
            return (signal, signal < 0 ? .decreasing : .increasing)
        }
        
        // Check if we should increase difficulty (performance is too good)
        if performanceScore > thresholds.increaseThreshold {
            // Check if we're reversing direction too quickly
            if lastAdaptationDirection == .decreasing && 
               directionStableCount < config.minStableRoundsBeforeDirectionChange {
                print("[ADM Hysteresis] Preventing immediate reversal from decreasing to increasing. Stable rounds: \(directionStableCount)")
                return (0.0, .stable)
            }
            
            let rawSignal = (performanceScore - performanceTarget) * 2.0
            let signal = max(-1.0, min(1.0, rawSignal)) // Clamp signal to [-1, 1]
            return (signal, .increasing)
            
        } else if performanceScore < thresholds.decreaseThreshold {
            // Check if we're reversing direction too quickly
            if lastAdaptationDirection == .increasing && 
               directionStableCount < config.minStableRoundsBeforeDirectionChange {
                print("[ADM Hysteresis] Preventing immediate reversal from increasing to decreasing. Stable rounds: \(directionStableCount)")
                return (0.0, .stable)
            }
            
            let rawSignal = (performanceScore - performanceTarget) * 2.0
            let signal = max(-1.0, min(1.0, rawSignal)) // Clamp signal to [-1, 1]
            return (signal, .decreasing)
            
        } else {
            // Performance is in the neutral zone
            let distanceFromTarget = abs(performanceScore - performanceTarget)
            
            // Apply additional dead zone in neutral region
            if distanceFromTarget < thresholds.baseDeadZone {
                return (0.0, .stable)
            }
            
            // Small adaptation within neutral zone (dampened)
            let rawSignal = (performanceScore - performanceTarget) * 1.0 // Reduced multiplier
            let signal = max(-1.0, min(1.0, rawSignal)) // Clamp signal to [-1, 1]
            
            // Maintain current direction if signal is very small
            if abs(signal) < config.adaptationSignalDeadZone {
                return (0.0, .stable)
            }
            
            return (signal, signal < 0 ? .decreasing : .increasing)
        }
    }

    // MARK: - Recency Weighting Helper
    
    /// Calculates recency-weighted history entries using exponential decay
    private func getRecencyWeightedHistory() -> [(entry: PerformanceHistoryEntry, weight: CGFloat)] {
        guard !performanceHistory.isEmpty else { return [] }
        
        let currentTime = CACurrentMediaTime()
        return performanceHistory.map { entry in
            let age = (currentTime - entry.timestamp) / 3600.0 // Convert to hours
            // Exponential decay: full weight for recent data, decreasing weight for older data
            // Using configurable half-life from GameConfiguration
            let weight = CGFloat(exp(-age * log(2.0) / config.domRecencyWeightHalfLifeHours))
            return (entry: entry, weight: weight)
        }
    }
    
    // MARK: - Confidence Calculation (Phase 4)

    /// Calculates the confidence of the current adaptation decision
    func calculateAdaptationConfidence() -> (total: CGFloat, variance: CGFloat, direction: CGFloat, history: CGFloat) {
        guard !performanceHistory.isEmpty else { return (0.5, 0.5, 0.5, 0.0) }
        
        // Get recency-weighted history
        let recencyWeightedHistory = getRecencyWeightedHistory()
        
        // Calculate weighted variance
        let weightedVariance = calculateWeightedVariance(recencyWeightedHistory)
        
        // 1. Variance Confidence (lower variance = higher confidence)
        let varianceConfidence = max(0, 1.0 - min(weightedVariance / 0.5, 1.0))
        
        // 2. Direction Confidence (consistent direction = higher confidence)
        // Give more weight to recent direction stability
        let recentDirectionWeight = recencyWeightedHistory.last?.weight ?? 1.0
        let weightedDirectionConfidence = min(CGFloat(directionStableCount) / 5.0, 1.0) * recentDirectionWeight
        
        // 3. History Confidence (more data = more confidence, but weighted by recency)
        let effectiveHistorySize = recencyWeightedHistory.reduce(0.0) { $0 + $1.weight }
        // Use a reasonable baseline of 10 entries for full confidence instead of the full window size
        // This allows the system to reach full confidence with reasonable data while still supporting larger history
        let historyConfidenceBaseline: CGFloat = 10.0
        let historyConfidence = min(effectiveHistorySize / historyConfidenceBaseline, 1.0)
        
        // Log recency weighting details if significant aging detected
        if !recencyWeightedHistory.isEmpty {
            let oldestWeight = recencyWeightedHistory.first?.weight ?? 1.0
            let newestWeight = recencyWeightedHistory.last?.weight ?? 1.0
            
            if oldestWeight < 0.5 { // If oldest data has less than 50% weight
                let currentTime = CACurrentMediaTime()
                let oldestAge = (currentTime - performanceHistory.first!.timestamp) / 3600.0
                print("[ADM] Recency weighting applied:")
                print("  ├─ Oldest entry: \(String(format: "%.1f", oldestAge)) hours old (weight: \(String(format: "%.2f", oldestWeight)))")
                print("  ├─ Newest entry weight: \(String(format: "%.2f", newestWeight))")
                print("  └─ Effective history size: \(String(format: "%.1f", effectiveHistorySize)) of \(performanceHistory.count)")
            }
        }
        
        // Combine the confidence scores with adjusted weights
        // Give slightly more weight to recency-adjusted metrics
        let totalConfidence = (varianceConfidence * 0.35 + weightedDirectionConfidence * 0.35 + historyConfidence * 0.30)
        
        return (
            total: max(0.0, min(1.0, totalConfidence)),
            variance: varianceConfidence,
            direction: weightedDirectionConfidence,
            history: historyConfidence
        )
    }
    
    /// Calculates weighted variance considering recency of data points
    private func calculateWeightedVariance(_ weightedHistory: [(entry: PerformanceHistoryEntry, weight: CGFloat)]) -> CGFloat {
        guard weightedHistory.count >= 2 else { return 0.0 }
        
        // Calculate weighted mean
        let totalWeight = weightedHistory.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0.0 }
        
        let weightedMean = weightedHistory.reduce(0.0) { 
            $0 + ($1.entry.overallScore * $1.weight) 
        } / totalWeight
        
        // Calculate weighted variance
        let weightedSquaredDifferences = weightedHistory.reduce(0.0) { result, item in
            let diff = item.entry.overallScore - weightedMean
            return result + (pow(diff, 2) * item.weight)
        }
        
        let weightedVariance = weightedSquaredDifferences / totalWeight
        
        return weightedVariance
    }

    /// Gets effective adaptation thresholds, widened by low confidence
    func getEffectiveAdaptationThresholds() -> AdaptationThresholds {
        guard config.enableConfidenceScaling else {
            return AdaptationThresholds(
                increaseThreshold: config.adaptationIncreaseThreshold,
                decreaseThreshold: config.adaptationDecreaseThreshold,
                baseDeadZone: config.hysteresisDeadZone,
                hysteresisEnabled: true
            )
        }
        
        let confidence = calculateAdaptationConfidence().total
        // Uncertainty is the inverse of confidence
        let uncertaintyMultiplier = 1.0 - confidence // Ranges from 0 (high confidence) to 1 (low confidence)
        
        let wideningAmount = config.confidenceThresholdWideningFactor * uncertaintyMultiplier
        
        return AdaptationThresholds(
            increaseThreshold: config.adaptationIncreaseThreshold + wideningAmount,
            decreaseThreshold: config.adaptationDecreaseThreshold - wideningAmount,
            baseDeadZone: config.hysteresisDeadZone + (config.hysteresisDeadZone * uncertaintyMultiplier),
            hysteresisEnabled: true
        )
    }

    func modulateDOMsWithWeightedBudget(totalBudget: CGFloat, arousal: CGFloat, invertPriorities: Bool) -> CGFloat {
        var remainingBudget = totalBudget
        let confidence = calculateAdaptationConfidence()
        
        // Pass 1: Reset-to-Midpoint (only for easing)
        if invertPriorities && totalBudget < 0 {
            // Include positions that are at or above midpoint
            let overHardenedDOMs = normalizedPositions.filter { $0.value >= 0.5 }.map { $0.key }
            if !overHardenedDOMs.isEmpty {
                // Log discriminatory load normalized position for debugging
                if let discLoadPos = normalizedPositions[.discriminatoryLoad] {
                    print("[ADM] DiscriminatoryLoad normalized position: \(discLoadPos), included in reset: \(overHardenedDOMs.contains(.discriminatoryLoad))")
                }
                
                let budgetForReset = distributeAdaptationBudget(
                    totalBudget: remainingBudget,
                    arousal: arousal,
                    invertPriorities: true,
                    subset: overHardenedDOMs
                )
                
                var budgetSpentInPass1: CGFloat = 0
                for (domType, budgetShare) in budgetForReset {
                    let currentPosition = normalizedPositions[domType] ?? 0.5
                    let targetPosition = max(0.5, currentPosition + budgetShare) // Don't go below 0.5 in this pass
                    let actualChange = applyModulation(domType: domType, currentPosition: currentPosition, desiredPosition: targetPosition, confidence: confidence)
                    budgetSpentInPass1 += actualChange
                }
                remainingBudget -= budgetSpentInPass1
            }
        }
        
        // Pass 2: Standard Modulation
        let budgetForStandardPass = distributeAdaptationBudget(
            totalBudget: remainingBudget,
            arousal: arousal,
            invertPriorities: invertPriorities,
            subset: nil // All DOMs
        )
        
        var budgetSpentInPass2: CGFloat = 0
        for (domType, budgetShare) in budgetForStandardPass {
            let currentPosition = normalizedPositions[domType] ?? 0.5
            let targetPosition = currentPosition + budgetShare
            let actualChange = applyModulation(domType: domType, currentPosition: currentPosition, desiredPosition: targetPosition, confidence: confidence)
            budgetSpentInPass2 += actualChange
        }
        remainingBudget -= budgetSpentInPass2
        
        return remainingBudget
    }

    func applyModulation(domType: DOMTargetType, currentPosition: CGFloat, desiredPosition: CGFloat, confidence: (total: CGFloat, variance: CGFloat, direction: CGFloat, history: CGFloat), bypassSmoothing: Bool = false) -> CGFloat {
        let achievedPosition = max(0.0, min(1.0, desiredPosition))
        let rawChange = achievedPosition - currentPosition
        
        let smoothedChange: CGFloat
        let smoothedPosition: CGFloat
        
        if bypassSmoothing {
            // When using PD controller, don't apply additional smoothing
            smoothedChange = rawChange
            smoothedPosition = achievedPosition
        } else {
            // Choose smoothing factor based on direction of change
            let smoothing: CGFloat
            if rawChange < 0 {
                // We're easing (making game easier)
                smoothing = config.domEasingSmoothingFactors[domType] ?? 0.1
                if domType == .discriminatoryLoad {
                    print("[ADM] Using EASING factor for \(domType): \(smoothing)")
                }
            } else {
                // We're hardening (making game harder)
                smoothing = config.domHardeningSmoothingFactors[domType] ?? 0.1
                if domType == .discriminatoryLoad {
                    print("[ADM] Using HARDENING factor for \(domType): \(smoothing)")
                }
            }
            
            smoothedChange = rawChange * smoothing
            smoothedPosition = currentPosition + smoothedChange
        }
        
        // Clamp the final position to ensure it stays within the 0.0-1.0 range
        let finalPosition = max(0.0, min(1.0, smoothedPosition))
        
        normalizedPositions[domType] = finalPosition
        
        let confidenceString = String(format: "C:%.2f (V:%.2f, D:%.2f, H:%.2f)", confidence.total, confidence.variance, confidence.direction, confidence.history)
        if bypassSmoothing {
            print("[ADM PD] Modulated \(domType): Signal=\(String(format: "%.3f", rawChange)) -> ActualChange=\(String(format: "%.3f", smoothedChange)). \(confidenceString). NormPos: \(String(format: "%.2f", currentPosition)) -> \(String(format: "%.2f", finalPosition))")
        } else {
            print("[ADM] Modulated \(domType): BudgetShare=\(String(format: "%.3f", rawChange / ((rawChange != 0 && !bypassSmoothing) ? (smoothedChange / rawChange) : 1))) -> ActualChange=\(String(format: "%.3f", smoothedChange)). \(confidenceString). NormPos: \(String(format: "%.2f", currentPosition)) -> SmoothNorm: \(String(format: "%.2f", finalPosition))")
        }
        
        // Add warmup-specific DOM tracking
        if currentPhase == .warmup {
            let warmupProgress = CGFloat(roundsInCurrentPhase) / CGFloat(max(1, warmupPhaseLength))
            print("[ADM Warm-up] DOM progression for \(domType):")
            print("[ADM Warm-up]   - Position: \(String(format: "%.3f", currentPosition)) → \(String(format: "%.3f", smoothedPosition))")
            print("[ADM Warm-up]   - Change: \(smoothedChange > 0 ? "↑" : smoothedChange < 0 ? "↓" : "→") \(String(format: "%.3f", abs(smoothedChange)))")
            print("[ADM Warm-up]   - Warmup completion: \(String(format: "%.1f%%", warmupProgress * 100))")
        }
        
        return smoothedChange
    }

    // MARK: - Performance History Helper Methods (NEW)
    
    /// Adds a performance entry to the history, maintaining the rolling window
    func addPerformanceEntry(_ entry: PerformanceHistoryEntry) {
        performanceHistory.append(entry)
        if performanceHistory.count > maxHistorySize {
            performanceHistory.removeFirst()
        }
    }
    
    // MARK: - History Analytics Functions (NEW)
    
    /// Calculates performance metrics from the history
    func getPerformanceMetrics() -> (average: CGFloat, trend: CGFloat, variance: CGFloat) {
        guard !performanceHistory.isEmpty else {
            return (average: 0.5, trend: 0.0, variance: 0.0)
        }
        
        if performanceHistory.count == 1 {
            return (average: performanceHistory[0].overallScore, trend: 0.0, variance: 0.0)
        }
        
        // Get recency-weighted history
        let weightedHistory = getRecencyWeightedHistory()
        
        // Calculate weighted average
        let totalWeight = weightedHistory.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return (average: 0.5, trend: 0.0, variance: 0.0)
        }
        
        let weightedAverage = weightedHistory.reduce(0.0) { 
            $0 + ($1.entry.overallScore * $1.weight) 
        } / totalWeight
        
        // Calculate trend using weighted linear regression
        let trend = calculateWeightedLinearTrend(weightedHistory)
        
        // Calculate variance using existing weighted variance function
        let variance = calculateWeightedVariance(weightedHistory)
        
        return (average: weightedAverage, trend: trend, variance: variance)
    }
    
    // MARK: - DOM Modulation & Interpolation (Phase 2.5)

    func calculateInterpolatedDOMPriority(domType: DOMTargetType, arousal: CGFloat, invert: Bool) -> CGFloat {
        let lowPriority = config.domAdaptationRates_LowMidArousal[domType] ?? 1.0
        let highPriority = config.domAdaptationRates_HighArousal[domType] ?? 1.0
        
        let t = smoothstep(config.kpiWeightTransitionStart, config.kpiWeightTransitionEnd, arousal)
        let interpolatedPriority = lerp(lowPriority, highPriority, t)
        
        if invert {
            // Dynamically calculate max priority for proper inversion
            // This avoids issues with hard-coded scale assumptions
            if domType == .discriminatoryLoad {
                print("[ADM] DiscriminatoryLoad original priority: \(interpolatedPriority)")
            }
            
            // Find the max priority across all DOM types
            let allPriorities = DOMTargetType.allCases.map { 
                let domLowP = config.domAdaptationRates_LowMidArousal[$0] ?? 1.0
                let domHighP = config.domAdaptationRates_HighArousal[$0] ?? 1.0
                let domT = smoothstep(config.kpiWeightTransitionStart, config.kpiWeightTransitionEnd, arousal)
                return lerp(domLowP, domHighP, domT)
            }
            let maxPriority = allPriorities.max() ?? 6.0
            
            // Add a small buffer to ensure the max value gets some non-zero priority when inverted
            let invertedPriority = (maxPriority + 1.0 - interpolatedPriority)
            
            if domType == .discriminatoryLoad {
                print("[ADM] DiscriminatoryLoad inverted priority: \(invertedPriority) (max was \(maxPriority))")
            }
            
            return invertedPriority
        }
        
        return interpolatedPriority
    }

    func distributeAdaptationBudget(totalBudget: CGFloat, arousal: CGFloat, invertPriorities: Bool, subset: [DOMTargetType]?) -> [DOMTargetType: CGFloat] {
        let targetDOMs = subset ?? DOMTargetType.allCases
        
        let priorities = targetDOMs.map {
            (dom: $0, priority: calculateInterpolatedDOMPriority(domType: $0, arousal: arousal, invert: invertPriorities))
        }
        
        let totalPriority = priorities.reduce(0) { $0 + $1.priority }
        
        guard totalPriority > 0 else { return [:] }
        
        return Dictionary(uniqueKeysWithValues: priorities.map {
            ($0.dom, ($0.priority / totalPriority) * totalBudget)
        })
    }
    
    /// Linear interpolation between two values
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }
    
    /// Smooth step interpolation with cubic smoothing
    /// Creates an S-curve for more natural transitions
    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        // Scale, bias and saturate x to 0..1 range
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        // Evaluate polynomial
        return t * t * (3 - 2 * t)
    }
    
    /// Get interpolated KPI weights based on arousal level
    func getInterpolatedKPIWeights(arousal: CGFloat) -> KPIWeights {
        guard config.useKPIWeightInterpolation else {
            // Fallback to original behavior
            return arousal >= config.arousalThresholdForKPIAndHierarchySwitch ?
                   config.kpiWeights_HighArousal : config.kpiWeights_LowMidArousal
        }
        
        let start = config.kpiWeightTransitionStart
        let end = config.kpiWeightTransitionEnd
        
        if arousal <= start {
            return config.kpiWeights_LowMidArousal
        } else if arousal >= end {
            return config.kpiWeights_HighArousal
        } else {
            // Calculate smooth interpolation factor
            let t = smoothstep(start, end, arousal)
            
            // Interpolate each weight component
            return KPIWeights(
                taskSuccess: lerp(config.kpiWeights_LowMidArousal.taskSuccess,
                                config.kpiWeights_HighArousal.taskSuccess, t),
                tfTtfRatio: lerp(config.kpiWeights_LowMidArousal.tfTtfRatio,
                               config.kpiWeights_HighArousal.tfTtfRatio, t),
                reactionTime: lerp(config.kpiWeights_LowMidArousal.reactionTime,
                                 config.kpiWeights_HighArousal.reactionTime, t),
                responseDuration: lerp(config.kpiWeights_LowMidArousal.responseDuration,
                                     config.kpiWeights_HighArousal.responseDuration, t),
                tapAccuracy: lerp(config.kpiWeights_LowMidArousal.tapAccuracy,
                                config.kpiWeights_HighArousal.tapAccuracy, t)
            )
        }
    }
    
    /// Calculates linear trend from performance history using least squares regression
    private func calculateLinearTrend() -> CGFloat {
        guard performanceHistory.count >= 2 else {
            return 0.0
        }
        
        // Use normalized time indices (0, 1, 2, ...) instead of absolute timestamps
        let n = CGFloat(performanceHistory.count)
        var sumX: CGFloat = 0.0
        var sumY: CGFloat = 0.0
        var sumXY: CGFloat = 0.0
        var sumX2: CGFloat = 0.0
        
        for (index, entry) in performanceHistory.enumerated() {
            let x = CGFloat(index)
            let y = entry.overallScore
            
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }
        
        // Calculate slope using least squares formula
        let denominator = n * sumX2 - sumX * sumX
        
        // Avoid division by zero
        guard abs(denominator) > 0.0001 else {
            return 0.0
        }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        
        // Normalize slope to be meaningful in the context of performance (typically -1 to 1)
        // Since we're using indices, a slope of 1 means performance increases by 1 per sample
        // We'll scale this to be more reasonable
        let normalizedSlope = slope / max(1.0, n / 10.0) // Scale down for larger histories
        
        return max(-1.0, min(1.0, normalizedSlope))
    }
    
    /// Calculates weighted linear trend using weighted least squares regression
    private func calculateWeightedLinearTrend(_ weightedHistory: [(entry: PerformanceHistoryEntry, weight: CGFloat)]) -> CGFloat {
        guard weightedHistory.count >= 2 else {
            return 0.0
        }
        
        let totalWeight = weightedHistory.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return 0.0
        }
        
        // Use normalized time indices (0, 1, 2, ...) for x values
        var sumW: CGFloat = 0.0    // sum of weights
        var sumWX: CGFloat = 0.0   // sum of weighted x
        var sumWY: CGFloat = 0.0   // sum of weighted y
        var sumWXY: CGFloat = 0.0  // sum of weighted x*y
        var sumWX2: CGFloat = 0.0  // sum of weighted x^2
        
        for (index, item) in weightedHistory.enumerated() {
            let x = CGFloat(index)
            let y = item.entry.overallScore
            let w = item.weight
            
            sumW += w
            sumWX += w * x
            sumWY += w * y
            sumWXY += w * x * y
            sumWX2 += w * x * x
        }
        
        // Calculate weighted slope using weighted least squares formula
        let denominator = sumW * sumWX2 - sumWX * sumWX
        
        // Avoid division by zero
        guard abs(denominator) > 0.0001 else {
            return 0.0
        }
        
        let slope = (sumW * sumWXY - sumWX * sumWY) / denominator
        
        // Normalize slope to be meaningful in the context of performance
        let n = CGFloat(weightedHistory.count)
        let normalizedSlope = slope / max(1.0, n / 10.0) // Scale down for larger histories
        
        return max(-1.0, min(1.0, normalizedSlope))
    }
    
    /// Calculates the variance of performance scores
    private func calculatePerformanceVariance() -> CGFloat {
        guard performanceHistory.count >= 2 else {
            return 0.0
        }
        
        let scores = performanceHistory.map { $0.overallScore }
        let mean = scores.reduce(0.0, +) / CGFloat(scores.count)
        
        let squaredDifferences = scores.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0.0, +) / CGFloat(scores.count)
        
        return variance
    }
    
    /// Gets a recent window of performance entries for focused analysis
    private func getRecentPerformanceWindow(windowSize: Int? = nil) -> [PerformanceHistoryEntry] {
        let size = windowSize ?? min(5, performanceHistory.count) // Default to last 5 or all if less
        
        guard performanceHistory.count > size else {
            return performanceHistory
        }
        
        return Array(performanceHistory.suffix(size))
    }

    // MARK: - Helper Functions for DOM Target Management
    
    // Using global DOMTargetType
    private func calculateInitialDOMValue(for domTargetType: DOMTargetType, arousal: CGFloat) -> CGFloat {
        let easiest = getArousalGatedEasiestSetting(for: domTargetType, currentArousal: arousal)
        let hardest = getArousalGatedHardestSetting(for: domTargetType, currentArousal: arousal)
        // Ensure easiest and hardest are not the same to avoid division by zero if used in normalization
        if abs(hardest - easiest) < 0.0001 { // Using a small epsilon
            return easiest // Or hardest, doesn't matter if they are the same
        }
        return easiest + (hardest - easiest) * 0.5
    }

    private func getCurrentValue(for domTargetType: DOMTargetType) -> CGFloat {
        switch domTargetType {
        case .discriminatoryLoad: return currentDiscriminabilityFactor
        case .meanBallSpeed: return currentMeanBallSpeed
        case .ballSpeedSD: return currentBallSpeedSD
        case .responseTime: return CGFloat(currentResponseTime)
        case .targetCount: return CGFloat(currentTargetCount)
        }
    }
    
    private func setCurrentValue(for domTargetType: DOMTargetType, rawValue: CGFloat) {
        switch domTargetType {
        case .discriminatoryLoad: currentDiscriminabilityFactor = rawValue
        case .meanBallSpeed: currentMeanBallSpeed = rawValue
        case .ballSpeedSD: currentBallSpeedSD = rawValue
        case .responseTime: currentResponseTime = TimeInterval(rawValue)
        case .targetCount: currentTargetCount = Int(round(rawValue)) // Round for integer type
        }
    }
    
    private func getArousalGatedEasiestSetting(for domTargetType: DOMTargetType, currentArousal: CGFloat) -> CGFloat {
        let normArousal = (currentArousal - config.arousalOperationalMinForDOMScaling) / (config.arousalOperationalMaxForDOMScaling - config.arousalOperationalMinForDOMScaling)
        let clampedNormArousal = max(0.0, min(1.0, normArousal))
        
        let (minA_Easiest, maxA_Easiest) = getMinMaxArousalSettings(for: domTargetType, easiest: true)
        // Resolved: No '+' candidates produce the expected contextual result type 'CGFloat'
        // This is likely due to type mismatch if getMinMaxArousalSettings returns non-CGFloat for some.
        // Ensured getMinMaxArousalSettings consistently returns (CGFloat, CGFloat)
        return minA_Easiest + (maxA_Easiest - minA_Easiest) * clampedNormArousal
    }

    private func getArousalGatedHardestSetting(for domTargetType: DOMTargetType, currentArousal: CGFloat) -> CGFloat {
        let normArousal = (currentArousal - config.arousalOperationalMinForDOMScaling) / (config.arousalOperationalMaxForDOMScaling - config.arousalOperationalMinForDOMScaling)
        let clampedNormArousal = max(0.0, min(1.0, normArousal))

        let (minA_Hardest, maxA_Hardest) = getMinMaxArousalSettings(for: domTargetType, easiest: false) // easiest: false means get hardest
        return minA_Hardest + (maxA_Hardest - minA_Hardest) * clampedNormArousal
    }

    // Helper to fetch base Easiest/Hardest values from config for a DOM type
    // Ensures return type is (CGFloat, CGFloat)
    private func getMinMaxArousalSettings(for domTargetType: DOMTargetType, easiest: Bool) -> (minArousalSetting: CGFloat, maxArousalSetting: CGFloat) {
        switch domTargetType {
        case .discriminatoryLoad:
            return easiest ? (config.discriminabilityFactor_MinArousal_EasiestSetting, config.discriminabilityFactor_MaxArousal_EasiestSetting)
                           : (config.discriminabilityFactor_MinArousal_HardestSetting, config.discriminabilityFactor_MaxArousal_HardestSetting)
        case .meanBallSpeed:
            return easiest ? (config.meanBallSpeed_MinArousal_EasiestSetting, config.meanBallSpeed_MaxArousal_EasiestSetting)
                           : (config.meanBallSpeed_MinArousal_HardestSetting, config.meanBallSpeed_MaxArousal_HardestSetting)
        case .ballSpeedSD:
            return easiest ? (config.ballSpeedSD_MinArousal_EasiestSetting, config.ballSpeedSD_MaxArousal_EasiestSetting)
                           : (config.ballSpeedSD_MinArousal_HardestSetting, config.ballSpeedSD_MaxArousal_HardestSetting)
        case .responseTime:
             let minA_Val = easiest ? CGFloat(config.responseTime_MinArousal_EasiestSetting) : CGFloat(config.responseTime_MinArousal_HardestSetting)
             let maxA_Val = easiest ? CGFloat(config.responseTime_MaxArousal_EasiestSetting) : CGFloat(config.responseTime_MaxArousal_HardestSetting)
             return (minA_Val, maxA_Val)
        case .targetCount:
             let minA_Val = easiest ? CGFloat(config.targetCount_MinArousal_EasiestSetting) : CGFloat(config.targetCount_MinArousal_HardestSetting)
             let maxA_Val = easiest ? CGFloat(config.targetCount_MaxArousal_EasiestSetting) : CGFloat(config.targetCount_MaxArousal_HardestSetting)
             return (minA_Val, maxA_Val)
        // Removed default case as DOMTargetType is exhaustive
        }
    }
    
    // MARK: - DOM-Specific Profiling Methods (Phase 5)
    
    /// Calculates the standard deviation of a set of values
    internal func calculateStandardDeviation(values: [CGFloat]) -> CGFloat {
        guard values.count > 1 else { return 0.0 }
        
        let mean = values.reduce(0.0, +) / CGFloat(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0.0, +) / CGFloat(values.count)
        
        return sqrt(variance)
    }
    
    /// Gets interpolated DOM adaptation rate based on current arousal level
    /// This is used by the PD controller and does NOT include inversion logic
    private func getInterpolatedDOMAdaptationRate(for domType: DOMTargetType) -> CGFloat {
        let lowRate = config.domAdaptationRates_LowMidArousal[domType] ?? 1.0
        let highRate = config.domAdaptationRates_HighArousal[domType] ?? 1.0
        
        let t = smoothstep(config.kpiWeightTransitionStart, 
                           config.kpiWeightTransitionEnd, 
                           currentArousalLevel)
        return lerp(lowRate, highRate, t)
    }
    
    /// Calculates local confidence based only on DOM-specific performance data
    private func calculateLocalConfidence(for profile: DOMPerformanceProfile) -> CGFloat {
        let dataPoints = profile.performanceByValue
        
        // If we have very few data points, confidence is low
        guard dataPoints.count >= 5 else {
            return CGFloat(dataPoints.count) / 5.0 // Linear scale up to 5 points
        }
        
        // Calculate variance in performance values
        let performances = dataPoints.map { $0.performance }
        let performanceVariance = calculateStandardDeviation(values: performances)
        
        // Lower variance = higher confidence (capped at 0.5 variance)
        let varianceConfidence = max(0, 1.0 - min(performanceVariance / 0.5, 1.0))
        
        // More data points = higher confidence (tunable via config.domMinDataPointsForProfiling)
        let baselineForData = CGFloat(config.domMinDataPointsForProfiling)
        let dataPointConfidence = min(CGFloat(dataPoints.count) / baselineForData, 1.0)
        
        // Calculate DOM value diversity (are we exploring the parameter space?)
        let domValues = dataPoints.map { $0.value }
        let domValueStdDev = calculateStandardDeviation(values: domValues)
        let diversityConfidence = min(domValueStdDev / 0.25, 1.0) // 0.25 = 25% of normalized range is good diversity
        
        // Combine metrics
        let totalConfidence = (varianceConfidence * 0.4 + dataPointConfidence * 0.3 + diversityConfidence * 0.3)
        
        return max(0.0, min(1.0, totalConfidence))
    }
    
    /// Calculates weighted average performance for a DOM profile
    internal func calculateWeightedAveragePerformance(data: [DOMPerformanceProfile.PerformanceDataPoint], weights: [CGFloat]) -> CGFloat {
        guard !data.isEmpty, data.count == weights.count else { return 0.5 }
        
        let totalWeight = weights.reduce(0.0, +)
        guard totalWeight > 0 else { return 0.5 }
        
        let weightedSum = zip(data, weights).reduce(0.0) { result, pair in
            result + (pair.0.performance * pair.1)
        }
        
        return weightedSum / totalWeight
    }
    
    /// Calculates weighted linear regression slope for DOM performance data
    internal func calculateWeightedSlope(data: [DOMPerformanceProfile.PerformanceDataPoint], weights: [CGFloat]) -> CGFloat {
        guard data.count >= 2, data.count == weights.count else { return 0.0 }
        
        let totalWeight = weights.reduce(0.0, +)
        guard totalWeight > 0 else { return 0.0 }
        
        // Calculate weighted means
        var sumWX: CGFloat = 0.0   // sum of weighted x (DOM values)
        var sumWY: CGFloat = 0.0   // sum of weighted y (performance)
        
        for (index, point) in data.enumerated() {
            let w = weights[index]
            sumWX += w * point.value
            sumWY += w * point.performance
        }
        
        let meanX = sumWX / totalWeight
        let meanY = sumWY / totalWeight
        
        // Calculate weighted covariance and variance
        var sumWXY: CGFloat = 0.0  // sum of weighted (x - meanX)(y - meanY)
        var sumWXX: CGFloat = 0.0  // sum of weighted (x - meanX)^2
        
        for (index, point) in data.enumerated() {
            let w = weights[index]
            let dx = point.value - meanX
            let dy = point.performance - meanY
            
            sumWXY += w * dx * dy
            sumWXX += w * dx * dx
        }
        
        // Avoid division by zero
        guard sumWXX > 0.0001 else { return 0.0 }
        
        // Slope = covariance / variance
        let slope = sumWXY / sumWXX
        
        return slope
    }
    
    /// Calculates DOM-specific adaptation signal based on performance profiling
    internal func calculateDOMSpecificAdaptationSignal(for domType: DOMTargetType) -> CGFloat {
        guard let profile = domPerformanceProfiles[domType] else { return 0.0 }
        
        let dataPoints = profile.performanceByValue
        
        // Guard clause 1: Minimum history size
        guard dataPoints.count >= 7 else {
            print("[ADM DOM Signal] Insufficient data for \(domType): \(dataPoints.count) points (need 7+)")
            return 0.0
        }
        
        // Extract DOM values for variance check
        let domValues = dataPoints.map { $0.value }
        let domStdDev = calculateStandardDeviation(values: domValues)
        
        // Guard clause 2: Minimum variance threshold
        let minimumVarianceThreshold = config.minimumDOMVarianceThreshold
        guard domStdDev >= minimumVarianceThreshold else {
            print("[ADM DOM Signal] Insufficient variance for \(domType): σ=\(String(format: "%.3f", domStdDev)) (need ≥\(minimumVarianceThreshold))")
            return 0.0
        }
        
        // Calculate recency weights using configurable half-life
        let currentTime = CACurrentMediaTime()
        let weights = dataPoints.map { entry in
            let ageInHours = (currentTime - entry.timestamp) / 3600.0
            return CGFloat(exp(-ageInHours * log(2.0) / config.domRecencyWeightHalfLifeHours))
        }
        
        // Calculate weighted slope
        let slope = calculateWeightedSlope(data: dataPoints, weights: weights)
        
        print("[ADM DOM Signal] \(domType): slope=\(String(format: "%.3f", slope)), σ=\(String(format: "%.3f", domStdDev)), n=\(dataPoints.count)")
        
        // Return the slope as the adaptation signal
        // Positive slope = performance improves with higher DOM values (can handle harder)
        // Negative slope = performance degrades with higher DOM values (struggling)
        return slope
    }
    
    /// Entry point for DOM-specific profiling modulation with PD controller and forced exploration
    /// - Returns: true if at least one DOM was successfully modulated, false if no DOMs had sufficient data
    internal func modulateDOMsWithProfiling() -> Bool {
        print("[ADM PD Controller] === PROFILE-BASED PD CONTROLLER ADAPTATION ===")
        
        var anyDOMModulated = false  // Track if any DOM was processed
        
        // Process each DOM independently
        for domType in DOMTargetType.allCases {
            guard let profile = domPerformanceProfiles[domType] else { continue }
            
            let dataPoints = profile.performanceByValue
            
            // Guard clause: Check minimum data points
            guard dataPoints.count >= config.domMinDataPointsForProfiling else {
                print("[ADM PD Controller] \(domType): Insufficient data (\(dataPoints.count)/\(config.domMinDataPointsForProfiling) points)")
                continue
            }
            
            // If we get here, we're modulating this DOM
            anyDOMModulated = true
            
            // a. Calculate localized, arousal-gated adaptation rate
            let baseAdaptationRate = getInterpolatedDOMAdaptationRate(for: domType)
            let localConfidence = calculateLocalConfidence(for: profile)
            let confidenceAdjustedRate = baseAdaptationRate * localConfidence
            
            // b. Calculate performance gap (P-term)
            let currentTime = CACurrentMediaTime()
            let weights = dataPoints.map { entry in
                let ageInHours = (currentTime - entry.timestamp) / 3600.0
                return CGFloat(exp(-ageInHours * log(2.0) / config.domRecencyWeightHalfLifeHours))
            }
            let averagePerformance = calculateWeightedAveragePerformance(data: dataPoints, weights: weights)
            let performanceGap = averagePerformance - config.domProfilingPerformanceTarget
            
            // c. Apply direction-specific rate multiplier
            // When performance > target, we need to harden (make harder)
            // When performance < target, we need to ease (make easier)
            // Prefer per-DOM overrides when provided, else fall back to global multipliers
            let baseDirMultiplier = (performanceGap > 0) ? config.domHardeningRateMultiplier : config.domEasingRateMultiplier
            let perDomDirMultiplier: CGFloat? = (performanceGap > 0)
                ? (config.domHardeningRateMultiplierByDOM[domType])
                : (config.domEasingRateMultiplierByDOM[domType])
            let directionMultiplier = perDomDirMultiplier ?? baseDirMultiplier
            let directionAdjustedRate = confidenceAdjustedRate * directionMultiplier
            print("[ADM PD Controller]   ├─ Direction multipliers -> base: \(String(format: "%.3f", baseDirMultiplier)), perDOM: \(perDomDirMultiplier != nil ? String(format: "%.3f", perDomDirMultiplier!) : "nil"), chosen: \(String(format: "%.3f", directionMultiplier))")
            
            // d. Calculate slope-based gain modifier (D-term)
            let slope = calculateWeightedSlope(data: dataPoints, weights: weights)
            let gainModifier = 1.0 / (1.0 + abs(slope) * config.domSlopeDampeningFactor)
            
            // e. Calculate final signal
            let rawSignal = performanceGap * directionAdjustedRate * gainModifier
            
            // Apply signal clamping to prevent jarring difficulty changes
            let finalSignal = max(-config.domMaxSignalPerRound, min(config.domMaxSignalPerRound, rawSignal))
            
            print("[ADM PD Controller] \(domType):")
            print("  ├─ Data points: \(dataPoints.count)")
            print("  ├─ Local confidence: \(String(format: "%.3f", localConfidence))")
            print("  ├─ Avg performance: \(String(format: "%.3f", averagePerformance)) (target: \(String(format: "%.3f", config.domProfilingPerformanceTarget))")
            print("  ├─ Performance gap (P): \(String(format: "%.3f", performanceGap))")
            print("  ├─ Slope: \(String(format: "%.3f", slope))")
            print("  ├─ Gain modifier (D): \(String(format: "%.3f", gainModifier))")
            print("  ├─ Raw signal: \(String(format: "%.3f", rawSignal))")
            print("  └─ Final signal: \(String(format: "%.3f", finalSignal))\(abs(rawSignal) > config.domMaxSignalPerRound ? " (CLAMPED)" : "")")
            
            // e. Implement forced exploration logic (effective movement-aware + boundary-aware)
            let currentConvergenceCount = domConvergenceCounters[domType] ?? 0
            let currentPosition = normalizedPositions[domType] ?? 0.5
            let potentialTarget = max(0.0, min(1.0, currentPosition + finalSignal))
            let potentialChange = potentialTarget - currentPosition
            // Treat saturation at bounds pushing outward as convergence (no effective movement possible)
            let saturatedOutward = (currentPosition <= 0.0 && finalSignal < 0) || (currentPosition >= 1.0 && finalSignal > 0)
            
            if abs(potentialChange) < config.domConvergenceThreshold || saturatedOutward {
                // DOM is effectively stable/converged
                domConvergenceCounters[domType] = currentConvergenceCount + 1
                
                // Determine appropriate convergence criterion based on boundary saturation
                let convergenceCriterion = saturatedOutward ? config.domBoundaryConvergenceDuration : config.domConvergenceDuration
                
                print("[ADM PD Controller]   └─ Convergence (effective) count: \(currentConvergenceCount + 1)/\(convergenceCriterion) (Δ=\(String(format: "%.4f", potentialChange))\(saturatedOutward ? ", SATURATED [boundary criterion]" : ""))")
                
                // Check if ready for exploration nudge using the appropriate criterion
                if domConvergenceCounters[domType]! >= convergenceCriterion {
                    // Apply exploration nudge away from current position (boundary-tunable if saturated)
                    let nudgeDirection: CGFloat = (currentPosition < 0.5) ? 1.0 : -1.0
                    let nudgeMagnitude: CGFloat = saturatedOutward
                        ? max(config.domExplorationNudgeFactor, config.domBoundaryNudgeFactor)
                        : config.domExplorationNudgeFactor
                    let nudgedPosition = currentPosition + (nudgeDirection * nudgeMagnitude)
                    let clampedPosition = max(0.0, min(1.0, nudgedPosition))
                    
                    normalizedPositions[domType] = clampedPosition
                    domConvergenceCounters[domType] = 0 // Reset counter
                    
                    print("[ADM PD Controller]   └─ EXPLORATION NUDGE applied: \(String(format: "%.3f", currentPosition)) → \(String(format: "%.3f", clampedPosition))\(saturatedOutward ? " [boundary]" : "")")
                    
                    // Skip regular modulation for this DOM this round
                    continue
                }
            } else {
                // DOM is actively adapting, reset convergence counter
                domConvergenceCounters[domType] = 0
            }
            
            // f. Apply modulation (standard adaptation)
            let targetPosition = currentPosition + finalSignal
            
            // Create local confidence structure based on DOM-specific data
            // Calculate components for local confidence structure
            let performances = dataPoints.map { $0.performance }
            let performanceStdDev = calculateStandardDeviation(values: performances)
            let varianceComponent = max(0, 1.0 - min(performanceStdDev / 0.5, 1.0))
            let dataPointComponent = min(CGFloat(dataPoints.count) / CGFloat(config.domMinDataPointsForProfiling), 1.0)
            
            // For PD controller, we use DOM-specific confidence, not global
            let localConfidenceStruct = (
                total: localConfidence,  // This is the DOM-specific confidence
                variance: varianceComponent,
                direction: CGFloat(1.0),  // DOM-specific direction confidence (simplified for now)
                history: dataPointComponent
            )
            
            _ = applyModulation(
                domType: domType,
                currentPosition: currentPosition,
                desiredPosition: targetPosition,
                confidence: localConfidenceStruct,
                bypassSmoothing: true // PD controller bypasses additional smoothing because:
                                      // 1. PD controller already provides smoothing via D-term (slope dampening)
                                      // 2. Direction-specific rate multipliers provide asymmetric adaptation
                                      // 3. Signal clamping prevents jarring changes
                                      // 4. Additional smoothing would interfere with PD control precision
            )
        }
        
        // Update absolute values after all modulations
        updateAbsoluteValuesFromNormalizedPositions()
        
        print("[ADM PD Controller] === PD CONTROLLER ADAPTATION COMPLETE ===")
        
        return anyDOMModulated
    }
    
    // MARK: - Persistence Methods (Phase 4.5)
    
    /// Saves the current ADM state
    func saveState() {
        print("[ADM] === SAVE STATE INITIATED ===")
        print("[ADM] User ID: \(self.userId)")
        print("[ADM] Current state snapshot:")
        print("  ├─ Performance history entries: \(performanceHistory.count)")
        print("  ├─ Last adaptation direction: \(lastAdaptationDirection)")
        print("  ├─ Direction stable count: \(directionStableCount)")
        print("  └─ Normalized DOM positions:")
        for (domType, position) in normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let absoluteValue = getCurrentValue(for: domType)
            print("     ├─ \(domType): \(String(format: "%.3f", position)) (absolute: \(String(format: "%.1f", absoluteValue)))")
        }
        
        let state = PersistedADMState(
            performanceHistory: performanceHistory,
            lastAdaptationDirection: lastAdaptationDirection,
            directionStableCount: directionStableCount,
            normalizedPositions: normalizedPositions,
            domPerformanceProfiles: config.persistDomPerformanceProfilesInState ? domPerformanceProfiles : nil
        )
        
        ADMPersistenceManager.saveState(state, for: self.userId)
        print("[ADM] === SAVE STATE COMPLETED ===")
    }
    
    /// Loads persisted state into the current ADM instance
    internal func loadState(from state: PersistedADMState) {
        print("[ADM] === LOADING PERSISTED STATE ===")
        
        // Load performance history (apply recency weighting)
        performanceHistory = state.performanceHistory
        print("[ADM] Performance history:")
        print("  ├─ Loaded entries: \(state.performanceHistory.count)")
        
        // Show performance score summary
        if !state.performanceHistory.isEmpty {
            let scores = state.performanceHistory.map { $0.overallScore }
            let avgScore = scores.reduce(0.0, +) / CGFloat(scores.count)
            print("  ├─ Average performance score: \(String(format: "%.3f", avgScore))")
            print("  ├─ Min score: \(String(format: "%.3f", scores.min() ?? 0))")
            print("  └─ Max score: \(String(format: "%.3f", scores.max() ?? 0))")
        }
        
        // Trim history to max size if needed
        let originalCount = performanceHistory.count
        if performanceHistory.count > maxHistorySize {
            performanceHistory = Array(performanceHistory.suffix(maxHistorySize))
            print("  ├─ Trimmed to max size: \(maxHistorySize) (removed \(originalCount - maxHistorySize) oldest entries)")
        }
        
        // Check age of data
        if !performanceHistory.isEmpty {
            let currentTime = CACurrentMediaTime()
            let oldestTime = performanceHistory.first?.timestamp ?? currentTime
            let newestTime = performanceHistory.last?.timestamp ?? currentTime
            let oldestAge = (currentTime - oldestTime) / 3600.0 // Convert to hours
            let newestAge = (currentTime - newestTime) / 3600.0
            
            print("  ├─ Oldest entry age: \(String(format: "%.1f", oldestAge)) hours")
            print("  └─ Newest entry age: \(String(format: "%.1f", newestAge)) hours")
            
            // If data is older than 24 hours, note it
            if oldestAge > 24 {
                print("  ⚠️ Some data is >24 hours old - confidence calculations will apply recency weighting")
            }
        }
        
        // Load adaptation state
        lastAdaptationDirection = state.lastAdaptationDirection
        directionStableCount = state.directionStableCount
        print("[ADM] Adaptation state:")
        print("  ├─ Last direction: \(lastAdaptationDirection)")
        print("  └─ Direction stable count: \(directionStableCount)")
        
        // Load normalized positions
        print("[ADM] BEFORE loading positions:")
        for (dom, position) in normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  ├─ \(dom): \(String(format: "%.3f", position))")
        }
        
        normalizedPositions = state.normalizedPositions
        
        print("[ADM] AFTER loading positions from state:")
        for (dom, position) in normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  ├─ \(dom): \(String(format: "%.3f", position))")
        }
        
        print("[ADM] Loaded DOM positions (0.0=easiest, 1.0=hardest):")
        
        // Define human-readable labels for each DOM type
        let domLabels: [DOMTargetType: String] = [
            .discriminatoryLoad: "Discriminatory Load (visual similarity)",
            .meanBallSpeed: "Mean Ball Speed",
            .ballSpeedSD: "Ball Speed Variability (SD)",
            .responseTime: "Response Time Window",
            .targetCount: "Number of Targets"
        ]
        
        let sortedPositions = normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        for (index, (domType, position)) in sortedPositions.enumerated() {
            let isLast = index == sortedPositions.count - 1
            let prefix = isLast ? "  └─" : "  ├─"
            let label = domLabels[domType] ?? domType.rawValue
            
            // Add difficulty interpretation
            let difficulty: String
            if position < 0.3 {
                difficulty = "Easy"
            } else if position < 0.7 {
                difficulty = "Medium"
            } else {
                difficulty = "Hard"
            }
            
            print("\(prefix) \(label):")
            print("     └─ Position: \(String(format: "%.3f", position)) (\(difficulty))")
        }
        
        // Load DOM performance profiles (Phase 5.2)
        if let persistedProfiles = state.domPerformanceProfiles {
            domPerformanceProfiles = persistedProfiles
            print("[ADM] DOM Performance Profiles:")
            
            let sortedProfiles = persistedProfiles.sorted(by: { $0.key.rawValue < $1.key.rawValue })
            for (index, (domType, profile)) in sortedProfiles.enumerated() {
                let isLast = index == sortedProfiles.count - 1
                let prefix = isLast ? "  └─" : "  ├─"
                
                let entryCount = profile.performanceByValue.count
                print("\(prefix) \(domType): \(entryCount) data points")
                
                // Show summary statistics if data exists
                if !profile.performanceByValue.isEmpty {
                    let values = profile.performanceByValue.map { $0.value }
                    let performances = profile.performanceByValue.map { $0.performance }
                    
                    let avgValue = values.reduce(0, +) / CGFloat(values.count)
                    let avgPerformance = performances.reduce(0, +) / CGFloat(performances.count)
                    
                    print("     ├─ Avg DOM value: \(String(format: "%.2f", avgValue))")
                    print("     └─ Avg performance: \(String(format: "%.2f", avgPerformance))")
                }
            }
        } else {
            print("[ADM] No DOM performance profiles found in persisted state (older save format)")
            // Profiles are already initialized fresh in init()
        }
        
        // Calculate initial confidence based on loaded data
        let confidence = calculateAdaptationConfidence()
        print("[ADM] Initial confidence based on loaded data:")
        print("  ├─ Total: \(String(format: "%.2f", confidence.total))")
        print("  ├─ Variance: \(String(format: "%.2f", confidence.variance))")
        print("  ├─ Direction: \(String(format: "%.2f", confidence.direction))")
        print("  └─ History: \(String(format: "%.2f", confidence.history))")
        
        print("[ADM] === LOAD COMPLETED ===")
    }
}
