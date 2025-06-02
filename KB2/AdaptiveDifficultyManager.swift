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
        
        // Now, set their actual initial values using a helper method
        setInitialDOMValues(arousal: initialArousal)
        
        print("[ADM] Initialized with arousal: \(initialArousal)")
        print("[ADM] Initial DF: \(currentDiscriminabilityFactor)")
        print("[ADM] Initial MeanSpeed: \(currentMeanBallSpeed)")
        print("[ADM] Initial SpeedSD: \(currentBallSpeedSD)")
        print("[ADM] Initial ResponseTime: \(currentResponseTime)")
        print("[ADM] Initial TargetCount: \(currentTargetCount)")
    }

    private func setInitialDOMValues(arousal: CGFloat) {
        // Initialize DOMs to mid-point of their range for initialArousal
        self.currentDiscriminabilityFactor = calculateInitialDOMValue(for: .discriminatoryLoad, arousal: arousal)
        self.currentMeanBallSpeed = calculateInitialDOMValue(for: .meanBallSpeed, arousal: arousal)
        self.currentBallSpeedSD = calculateInitialDOMValue(for: .ballSpeedSD, arousal: arousal)
        self.currentResponseTime = TimeInterval(calculateInitialDOMValue(for: .responseTime, arousal: arousal))
        self.currentTargetCount = Int(round(calculateInitialDOMValue(for: .targetCount, arousal: arousal)))
    }

    // MARK: - Public API
    func updateArousalLevel(_ arousal: CGFloat) {
        self.currentArousalLevel = max(0.0, min(1.0, arousal))
        // Potentially log or react if arousal changes significantly, though DOM modulation handles continuous changes.
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

        // 3. Iterate through the hierarchy
        for domTargetType in hierarchy {
            if abs(remainingAdaptationSignalBudget) < 0.001 { // Budget effectively exhausted
                print("[ADM] Budget exhausted or negligible (\(String(format: "%.4f", remainingAdaptationSignalBudget))). Stopping modulation.")
                break
            }

            // A. Get current state and arousal-gated range for this DOM Target
            let currentActualValue = getCurrentValue(for: domTargetType)
            let arousalGated_Easiest = getArousalGatedEasiestSetting(for: domTargetType, currentArousal: currentArousalLevel)
            let arousalGated_Hardest = getArousalGatedHardestSetting(for: domTargetType, currentArousal: currentArousalLevel)

            // If range is zero (easiest == hardest), this DOM cannot adapt. Skip.
            if abs(arousalGated_Hardest - arousalGated_Easiest) < 0.0001 { // Using a small epsilon
                print("[ADM] DOM \(domTargetType) has no adaptation range [\(arousalGated_Easiest) - \(arousalGated_Hardest)]. Skipping.")
                continue
            }

            // B. Convert currentActualValue to a Normalized Position (0.0 at Easiest, 1.0 at Hardest)
            var currentNormalizedPosition = (currentActualValue - arousalGated_Easiest) / (arousalGated_Hardest - arousalGated_Easiest)
            currentNormalizedPosition = max(0.0, min(1.0, currentNormalizedPosition)) // Clamp due to potential float inaccuracies or prior clamping

            // C. Determine Desired Normalized Position based on Budget
            let desiredNormalizedPositionAttempt = currentNormalizedPosition + remainingAdaptationSignalBudget
            
            // D. Calculate Actual Achievable Normalized Position and "Spent" Budget
            let achievedNormalizedPosition = max(0.0, min(1.0, desiredNormalizedPositionAttempt))
            
            let signalSpentByThisDOM = achievedNormalizedPosition - currentNormalizedPosition
            
            // E. Update remainingAdaptationSignalBudget
            remainingAdaptationSignalBudget -= signalSpentByThisDOM

            // F. Convert achievedNormalizedPosition back to a raw target value for this DOM
            var targetRawValue = arousalGated_Easiest + (arousalGated_Hardest - arousalGated_Easiest) * achievedNormalizedPosition

            // G. Apply Smoothing and Set Value (Handle Integers)
            let smoothingFactor = config.domSmoothingFactors[domTargetType] ?? 0.1 // Default smoothing

            let smoothedNewValue: CGFloat
            if domTargetType == .targetCount {
                let currentActualIntValueAsFloat = CGFloat(currentTargetCount) // Use the precise current float value for smoothing if available, or the int casted
                let smoothedFloatValue = currentActualIntValueAsFloat + (targetRawValue - currentActualIntValueAsFloat) * smoothingFactor
                
                var finalIntValue = Int(round(smoothedFloatValue))
                
                // Clamp to integer representation of arousal-gated limits
                // Ensure correct clamping when easiest > hardest (e.g. target count at high arousal)
                let intEasiest = Int(round(arousalGated_Easiest))
                let intHardest = Int(round(arousalGated_Hardest))
                
                if intEasiest <= intHardest {
                    finalIntValue = max(intEasiest, min(intHardest, finalIntValue))
                } else { // Easiest is numerically greater than hardest (e.g. target count 4 easy, 2 hard)
                    finalIntValue = max(intHardest, min(intEasiest, finalIntValue))
                }
                setCurrentValue(for: domTargetType, rawValue: CGFloat(finalIntValue))
                smoothedNewValue = CGFloat(finalIntValue) // For logging
            } else {
                let smoothedFloatValue = currentActualValue + (targetRawValue - currentActualValue) * smoothingFactor
                // Clamp to the float representation of arousal-gated limits
                let finalClampedValue = max(min(arousalGated_Easiest, arousalGated_Hardest), min(max(arousalGated_Easiest, arousalGated_Hardest), smoothedFloatValue))
                setCurrentValue(for: domTargetType, rawValue: finalClampedValue)
                smoothedNewValue = finalClampedValue // For logging
            }
            
            print("[ADM] Modulated \(domTargetType): Budget=\(String(format: "%.3f", remainingAdaptationSignalBudget + signalSpentByThisDOM)) -> Spent=\(String(format: "%.3f", signalSpentByThisDOM)) -> Rem=\(String(format: "%.3f", remainingAdaptationSignalBudget)). NormPos: \(String(format: "%.2f", currentNormalizedPosition)) -> AchievedNorm: \(String(format: "%.2f", achievedNormalizedPosition)). RawVal: \(String(format: "%.2f", currentActualValue)) -> TargetRaw: \(String(format: "%.2f", targetRawValue)) -> Smoothed: \(String(format: "%.2f", smoothedNewValue))")
        }
        if abs(remainingAdaptationSignalBudget) > 0.001 {
             print("[ADM] Modulation complete. Unspent budget: \(String(format: "%.4f", remainingAdaptationSignalBudget))")
        }
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
