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

class AdaptiveDifficultyManager {
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
    private var normalizedPositions: [DOMTargetType: CGFloat] = [:]

    // Current valid ranges (min/max) for each DOM target at current arousal level
    private var currentValidRanges: [DOMTargetType: (min: CGFloat, max: CGFloat)] = [:]

    // KPI History (for potential rolling averages - simple array for now)
    // private var recentTaskSuccesses: [Bool] = [] // Example
    // ... other KPI history properties ...
    // private let kpiHistoryWindowSize: Int = 3 // Example: average over last 3 rounds

    init(configuration: GameConfiguration, initialArousal: CGFloat) {
        self.config = configuration
        self.currentArousalLevel = initialArousal

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
                normalizedPositions[domType] = 0.25 // Start at easier end of range
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
        
        // 3. Modulate DOM targets
        modulateDOMTargets(overallPerformanceScore: performanceScore)
        
        // Log the outcome
        // DataLogger.shared.logAdaptiveDifficultyStep(...) // Resolved: DataLogger needs this method
        // For now, we'll add a placeholder in DataLogger or comment this out until DataLogger is updated.
        // Let's assume DataLogger will be updated later.
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
    
    private func calculateOverallPerformanceScore(normalizedKPIs: [KPIType: CGFloat]) -> CGFloat { // Changed ADM_KPIType
        // Placeholder - detailed implementation next
        let weights = currentArousalLevel >= config.arousalThresholdForKPIAndHierarchySwitch ?
                      config.kpiWeights_HighArousal :
                      config.kpiWeights_LowMidArousal
        
        var score: CGFloat = 0.0
        // Using global KPIType for dictionary keys
        score += (normalizedKPIs[.taskSuccess] ?? 0.0) * weights.taskSuccess
        score += (normalizedKPIs[.tfTtfRatio] ?? 0.0) * weights.tfTtfRatio
        score += (normalizedKPIs[.reactionTime] ?? 0.0) * weights.reactionTime
        score += (normalizedKPIs[.responseDuration] ?? 0.0) * weights.responseDuration
        score += (normalizedKPIs[.tapAccuracy] ?? 0.0) * weights.tapAccuracy
        
        return max(0.0, min(1.0, score)) // Ensure score is clamped 0-1
    }
    
    private func modulateDOMTargets(overallPerformanceScore: CGFloat) {
        // 1. Calculate initial adaptation signal (-1.0 to +1.0)
        var remainingAdaptationSignalBudget = (overallPerformanceScore - 0.5) * 2.0

        // Apply sensitivity and dead zone
        if abs(remainingAdaptationSignalBudget) < config.adaptationSignalDeadZone {
            remainingAdaptationSignalBudget = 0.0
        }
        remainingAdaptationSignalBudget *= config.adaptationSignalSensitivity
        
        print("[ADM] Modulating DOMs. Initial Budget: \(String(format: "%.3f", remainingAdaptationSignalBudget)) from PerfScore: \(String(format: "%.3f", overallPerformanceScore))")

        // 2. Select DOM Hierarchy based on currentArousalLevel
        let hierarchy = currentArousalLevel >= config.arousalThresholdForKPIAndHierarchySwitch ?
                        config.domHierarchy_HighArousal :
                        config.domHierarchy_LowMidArousal

        // Ensure valid ranges are up-to-date before modulation
        updateValidRangesForCurrentArousal()

        // 3. Iterate through the hierarchy
        for domTargetType in hierarchy {
            if abs(remainingAdaptationSignalBudget) < 0.001 { // Budget effectively exhausted
                print("[ADM] Budget exhausted or negligible (\(String(format: "%.4f", remainingAdaptationSignalBudget))). Stopping modulation.")
                break
            }

            // A. Get current normalized position and valid range for this DOM
            let currentNormalizedPosition = normalizedPositions[domTargetType] ?? 0.5
            let arousalGated_Easiest = getArousalGatedEasiestSetting(for: domTargetType, currentArousal: currentArousalLevel)
            let arousalGated_Hardest = getArousalGatedHardestSetting(for: domTargetType, currentArousal: currentArousalLevel)

            // If range is zero (easiest == hardest), this DOM cannot adapt. Skip.
            if abs(arousalGated_Hardest - arousalGated_Easiest) < 0.0001 { // Using a small epsilon
                print("[ADM] DOM \(domTargetType) has no adaptation range [\(arousalGated_Easiest) - \(arousalGated_Hardest)]. Skipping.")
                continue
            }

            // B. Determine Desired Normalized Position based on Budget
            let desiredNormalizedPositionAttempt = currentNormalizedPosition + remainingAdaptationSignalBudget
            
            // C. Calculate Actual Achievable Normalized Position and "Spent" Budget
            let achievedNormalizedPosition = max(0.0, min(1.0, desiredNormalizedPositionAttempt))
            
            let signalSpentByThisDOM = achievedNormalizedPosition - currentNormalizedPosition
            
            // D. Update remainingAdaptationSignalBudget
            remainingAdaptationSignalBudget -= signalSpentByThisDOM

            // E. Update the normalized position with smoothing
            let normalizedSmoothing = config.domSmoothingFactors[domTargetType] ?? 0.1
            let smoothedNormalizedPosition = currentNormalizedPosition + (achievedNormalizedPosition - currentNormalizedPosition) * normalizedSmoothing
            
            // Store the updated normalized position
            normalizedPositions[domTargetType] = smoothedNormalizedPosition
            
            // F. Calculate and set the absolute value based on the new normalized position
            let absoluteValue = normalizedToAbsoluteValue(normalizedValue: smoothedNormalizedPosition, for: domTargetType)
            setCurrentValue(for: domTargetType, rawValue: absoluteValue)
            
            print("[ADM] Modulated \(domTargetType): Budget=\(String(format: "%.3f", remainingAdaptationSignalBudget + signalSpentByThisDOM)) -> Spent=\(String(format: "%.3f", signalSpentByThisDOM)) -> Rem=\(String(format: "%.3f", remainingAdaptationSignalBudget)). NormPos: \(String(format: "%.2f", currentNormalizedPosition)) -> SmoothNorm: \(String(format: "%.2f", smoothedNormalizedPosition)) -> AbsVal: \(String(format: "%.2f", absoluteValue))")
        }
        
        if abs(remainingAdaptationSignalBudget) > 0.001 {
             print("[ADM] Modulation complete. Unspent budget: \(String(format: "%.4f", remainingAdaptationSignalBudget))")
        }
        
        // After updating the normalized positions, immediately convert them to absolute values
        // This ensures changes take effect without waiting for arousal changes
        updateAbsoluteValuesFromNormalizedPositions()
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
