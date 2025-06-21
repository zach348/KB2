// Kalibrate/AdaptiveDifficultyManager.swift
// Created: [Current Date]
// Role: Manages adaptive difficulty based on Key Performance Indicators (KPIs) and arousal levels.

import Foundation
import CoreGraphics
import SpriteKit // For SKColor, though not directly used in this file yet

// Kalibrate/AdaptiveDifficultyManager.swift
// Created: [Current Date]
// Role: Manages adaptive difficulty based on Key Performance Indicators (KPIs) and arousal levels.

import Foundation
import CoreGraphics
// import SpriteKit // For SKColor, though not directly used in this file yet
// GameConfiguration now provides DOMTargetType and KPIType

// MARK: - Performance History Structure
struct PerformanceHistoryEntry {
    let timestamp: TimeInterval
    let overallScore: CGFloat
    let normalizedKPIs: [KPIType: CGFloat]
    let arousalLevel: CGFloat
    let currentDOMValues: [DOMTargetType: CGFloat]
    let sessionContext: String? // e.g., "warmup", "challenge_phase"
}

class AdaptiveDifficultyManager {
    var dataLogger: DataLogger = DataLogger.shared
    private let config: GameConfiguration // Resolved: GameConfiguration is now findable
    private var currentArousalLevel: CGFloat

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

    // MARK: - Logging Throttling
    private var lastLogTime: TimeInterval = 0
    private let logThrottleInterval: TimeInterval = 1.0 // Log once per second
    
    // MARK: - Hysteresis State Tracking (Phase 3)
    enum AdaptationDirection {
        case increasing, decreasing, stable
    }
    
    internal var lastAdaptationDirection: AdaptationDirection = .stable
    internal var directionStableCount: Int = 0
    internal var lastSignificantChangeTime: TimeInterval = 0
    
    // MARK: - Hysteresis Helper Structures
    struct AdaptationThresholds {
        let performanceTarget: CGFloat = 0.5
        let increaseThreshold: CGFloat
        let decreaseThreshold: CGFloat
        let baseDeadZone: CGFloat
        let hysteresisEnabled: Bool
    }

    // KPI History (for potential rolling averages - simple array for now)
    // private var recentTaskSuccesses: [Bool] = [] // Example
    // ... other KPI history properties ...
    // private let kpiHistoryWindowSize: Int = 3 // Example: average over last 3 rounds

    init(configuration: GameConfiguration, initialArousal: CGFloat) {
        self.config = configuration
        self.currentArousalLevel = initialArousal
        self.maxHistorySize = configuration.performanceHistoryWindowSize

        // Initialize stored properties with placeholder values first
        self.currentDiscriminabilityFactor = 0.0
        self.currentMeanBallSpeed = 0.0
        self.currentBallSpeedSD = 0.0
        self.currentResponseTime = 0.0
        self.currentTargetCount = 0
        
        // Initialize normalized positions to middle of range (0.5)
        // EXCEPT targetCount which starts at easiest (0.0)
        for domType in [DOMTargetType.discriminatoryLoad, .meanBallSpeed, .ballSpeedSD, .responseTime, .targetCount] {
            if domType == .targetCount {
                normalizedPositions[domType] = 0.5 // Start at easier end of range
            } else {
                normalizedPositions[domType] = 0.5 // Others start at midpoint
            }
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
        guard let range = currentValidRanges[domType] else { return 0 }
        
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
    private func updateAbsoluteValuesFromNormalizedPositions() {
        for (domType, normalizedPosition) in normalizedPositions {
            let absoluteValue = normalizedToAbsoluteValue(normalizedValue: normalizedPosition, for: domType)
            setCurrentValue(for: domType, rawValue: absoluteValue)
            
            // Diagnostic logging for target count
            if domType == .targetCount {
                let range = currentValidRanges[domType] ?? (min: 0, max: 0)
                print("[ADM] TargetCount Update:")
                print("  - Arousal: \(String(format: "%.3f", currentArousalLevel))")
                print("  - Normalized Position: \(String(format: "%.3f", normalizedPosition))")
                print("  - Valid Range: [\(String(format: "%.1f", range.min)) - \(String(format: "%.1f", range.max))]")
                print("  - Absolute Value (pre-round): \(String(format: "%.3f", absoluteValue))")
                print("  - Final Target Count: \(Int(round(absoluteValue)))")
            }
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

    func recordIdentificationPerformance(
        taskSuccess: Bool,
        tfTtfRatio: CGFloat, // Targets Found / Targets To Find
        reactionTime: TimeInterval,
        responseDuration: TimeInterval,
        averageTapAccuracy: CGFloat, // In points
        actualTargetsToFindInRound: Int // Needed for normalizing responseDuration
    ) {
        // TODO: Implement KPI history/averaging if desired
        
        // 1. Normalize all relevant KPIs
        let normalizedKPIs = normalizeAllKPIs(
            rawTaskSuccess: taskSuccess,
            rawTfTtfRatio: tfTtfRatio,
            rawReactionTime: reactionTime,
            rawResponseDuration: responseDuration,
            rawAverageTapAccuracy: averageTapAccuracy,
            actualTargetsToFind: actualTargetsToFindInRound
        )
        
        // 2. Calculate overallPerformanceScore
        let performanceScore = calculateOverallPerformanceScore(normalizedKPIs: normalizedKPIs)
        
        // 3. Store performance history (if enabled)
        if config.usePerformanceHistory {
            let domValues = DOMTargetType.allCases.reduce(into: [DOMTargetType: CGFloat]()) {
                $0[$1] = getCurrentValue(for: $1)
            }
            
            let entry = PerformanceHistoryEntry(
                timestamp: CACurrentMediaTime(),
                overallScore: performanceScore,
                normalizedKPIs: normalizedKPIs,
                arousalLevel: currentArousalLevel,
                currentDOMValues: domValues,
                sessionContext: nil // Placeholder for now
            )
            addPerformanceEntry(entry)
            
            // Log performance metrics after adding to history (with throttling)
            let currentTime = Date().timeIntervalSince1970
            if currentTime - lastLogTime >= logThrottleInterval {
                let (average, trend, variance) = getPerformanceMetrics()
                dataLogger.logCustomEvent(
                    eventType: "adm_performance_history",
                    data: [
                        "history_size": performanceHistory.count,
                        "performance_average": average,
                        "performance_trend": trend,
                        "performance_variance": variance,
                        "recent_score": performanceScore
                    ],
                    description: "ADM performance history metrics"
                )
                lastLogTime = currentTime
            }
        }
        
        // 4. Modulate DOM targets
        modulateDOMTargets(overallPerformanceScore: performanceScore)
        
        // Log the adaptive difficulty step (with throttling)
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastLogTime >= logThrottleInterval {
            let domValues = DOMTargetType.allCases.reduce(into: [DOMTargetType: CGFloat]()) {
                $0[$1] = getCurrentValue(for: $1)
            }
            dataLogger.logAdaptiveDifficultyStep(
                arousalLevel: currentArousalLevel,
                performanceScore: performanceScore,
                normalizedKPIs: normalizedKPIs,
                domValues: domValues
            )
            lastLogTime = currentTime
        }
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
        guard config.usePerformanceHistory && performanceHistory.count >= config.minimumHistoryForTrend else {
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
    
    func modulateDOMTargets(overallPerformanceScore: CGFloat) {
        let adaptiveScore = calculateAdaptivePerformanceScore(currentScore: overallPerformanceScore)
        
        if config.usePerformanceHistory && performanceHistory.count >= config.minimumHistoryForTrend {
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
            thresholds: effectiveThresholds
        )
        
        var adaptationSignalBudget = adaptationSignal
        
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
                directionStableCount = 0
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
        }
        
        // Apply sensitivity (potentially different for easing vs hardening)
        if adaptationSignalBudget < 0 {
            // Apply standard sensitivity for easing
            adaptationSignalBudget *= config.adaptationSignalSensitivity
        } else {
            // Apply standard sensitivity for hardening
            adaptationSignalBudget *= config.adaptationSignalSensitivity
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
    
    /// Calculates adaptation signal with hysteresis to prevent oscillation
    func calculateAdaptationSignalWithHysteresis(performanceScore: CGFloat, thresholds: AdaptationThresholds) -> (signal: CGFloat, direction: AdaptationDirection) {
        guard config.enableHysteresis else {
            // Original logic without hysteresis
            let signal = (performanceScore - 0.5) * 2.0
            
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
            
            let signal = (performanceScore - thresholds.performanceTarget) * 2.0
            return (signal, .increasing)
            
        } else if performanceScore < thresholds.decreaseThreshold {
            // Check if we're reversing direction too quickly
            if lastAdaptationDirection == .increasing && 
               directionStableCount < config.minStableRoundsBeforeDirectionChange {
                print("[ADM Hysteresis] Preventing immediate reversal from increasing to decreasing. Stable rounds: \(directionStableCount)")
                return (0.0, .stable)
            }
            
            let signal = (performanceScore - thresholds.performanceTarget) * 2.0
            return (signal, .decreasing)
            
        } else {
            // Performance is in the neutral zone
            let distanceFromTarget = abs(performanceScore - thresholds.performanceTarget)
            
            // Apply additional dead zone in neutral region
            if distanceFromTarget < thresholds.baseDeadZone {
                return (0.0, .stable)
            }
            
            // Small adaptation within neutral zone (dampened)
            let signal = (performanceScore - thresholds.performanceTarget) * 1.0 // Reduced multiplier
            
            // Maintain current direction if signal is very small
            if abs(signal) < config.adaptationSignalDeadZone {
                return (0.0, .stable)
            }
            
            return (signal, signal < 0 ? .decreasing : .increasing)
        }
    }

    // MARK: - Confidence Calculation (Phase 4)

    /// Calculates the confidence of the current adaptation decision
    func calculateAdaptationConfidence() -> (total: CGFloat, variance: CGFloat, direction: CGFloat, history: CGFloat) {
        guard !performanceHistory.isEmpty else { return (0.5, 0.5, 0.5, 0.0) }
        
        let (_, _, variance) = getPerformanceMetrics()
        
        // 1. Variance Confidence (lower variance = higher confidence)
        let varianceConfidence = max(0, 1.0 - min(variance / 0.5, 1.0))
        
        // 2. Direction Confidence (consistent direction = higher confidence)
        let directionConfidence = min(CGFloat(directionStableCount) / 5.0, 1.0)
        
        // 3. History Confidence (more data = more confidence)
        let historyConfidence = min(CGFloat(performanceHistory.count) / CGFloat(config.performanceHistoryWindowSize), 1.0)
        
        // Combine the confidence scores (equal weighting for now)
        let totalConfidence = (varianceConfidence + directionConfidence + historyConfidence) / 3.0
        
        return (
            total: max(0.0, min(1.0, totalConfidence)),
            variance: varianceConfidence,
            direction: directionConfidence,
            history: historyConfidence
        )
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

    func applyModulation(domType: DOMTargetType, currentPosition: CGFloat, desiredPosition: CGFloat, confidence: (total: CGFloat, variance: CGFloat, direction: CGFloat, history: CGFloat)) -> CGFloat {
        let achievedPosition = max(0.0, min(1.0, desiredPosition))
        let rawChange = achievedPosition - currentPosition
        
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
        
        let smoothedChange = rawChange * smoothing
        let smoothedPosition = currentPosition + smoothedChange
        
        normalizedPositions[domType] = smoothedPosition
        
        let confidenceString = String(format: "C:%.2f (V:%.2f, D:%.2f, H:%.2f)", confidence.total, confidence.variance, confidence.direction, confidence.history)
        print("[ADM] Modulated \(domType): BudgetShare=\(String(format: "%.3f", rawChange / (smoothing > 0 ? smoothing : 1) )) -> ActualChange=\(String(format: "%.3f", smoothedChange)). \(confidenceString). NormPos: \(String(format: "%.2f", currentPosition)) -> SmoothNorm: \(String(format: "%.2f", smoothedPosition))")
        
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
        
        // Calculate average
        let scores = performanceHistory.map { $0.overallScore }
        let average = scores.reduce(0.0, +) / CGFloat(scores.count)
        
        // Calculate trend using linear regression
        let trend = calculateLinearTrend()
        
        // Calculate variance
        let variance = calculatePerformanceVariance()
        
        return (average: average, trend: trend, variance: variance)
    }
    
    // MARK: - DOM Modulation & Interpolation (Phase 2.5)

    func calculateInterpolatedDOMPriority(domType: DOMTargetType, arousal: CGFloat, invert: Bool) -> CGFloat {
        let lowPriority = config.domPriorities_LowMidArousal[domType] ?? 1.0
        let highPriority = config.domPriorities_HighArousal[domType] ?? 1.0
        
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
                let domLowP = config.domPriorities_LowMidArousal[$0] ?? 1.0
                let domHighP = config.domPriorities_HighArousal[$0] ?? 1.0
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
}
