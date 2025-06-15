// Kalibrate/GameConfiguration.swift
// Created: [Previous Date]
// Updated: [Current Date] - Added Adaptive Difficulty Manager Configuration
// Role: Centralized configuration settings for the game parameters.

import Foundation
import CoreGraphics // For CGFloat
import SpriteKit // For SKColor

// Enum for Difficulty Optimization Matrix (DOM) targets
enum DOMTargetType: Hashable, CaseIterable { // Made Hashable
    case discriminatoryLoad
    case meanBallSpeed
    case ballSpeedSD
    case responseTime
    case targetCount
}

// Enum for Key Performance Indicator (KPI) types
enum KPIType: Hashable { // Made Hashable
    case taskSuccess
    case tfTtfRatio
    case reactionTime
    case responseDuration
    case tapAccuracy
}

// Structure to hold KPI weights for adaptive difficulty
struct KPIWeights {
    let taskSuccess: CGFloat
    let tfTtfRatio: CGFloat
    let reactionTime: CGFloat
    let responseDuration: CGFloat
    let tapAccuracy: CGFloat
}

// Add this before the struct definition
enum SessionProfile {
    case standard          // Traditional descending curve
    case fluctuating       // Includes random small fluctuations
    case challenge         // Includes defined challenge phases
    case variable          // Unpredictable with both fluctuations and challenges
    case manual            // No automatic arousal modulation, manual control only
}

struct GameConfiguration {

    // --- General ---
    let numberOfBalls: Int = 12

    // --- Arousal Mapping & Thresholds ---
    let trackingArousalThresholdLow: CGFloat = 0.35
    let trackingArousalThresholdHigh: CGFloat = 1.0
    let breathingFadeOutThreshold: CGFloat = 0.025
    // MODIFIED: Expanded arousal steps for finer control (0.025 increment)
    let arousalSteps: [CGFloat] = stride(from: 0.0, through: 1.0, by: 0.025).map { $0 }
    // Generates [0.0, 0.025, 0.05, 0.075, ..., 0.975, 1.0]

    // --- Tracking Task Parameter Ranges (Mapped within Tracking Thresholds) ---
    // Motion
    let minTargetSpeedAtTrackingThreshold: CGFloat = 100.0
    let maxTargetSpeedAtTrackingThreshold: CGFloat = 1000.0
    let minTargetSpeedSDAtTrackingThreshold: CGFloat = 20.0
    let maxTargetSpeedSDAtTrackingThreshold: CGFloat = 150.0
    // Rhythmic Pulse Frequency
    let minTimerFrequency: Double = 1.5  // Hz (at arousal 0.0)
    let maxTimerFrequency: Double = 16.0 // Hz (at arousal 1.0)
    // Target Count
    let maxTargetsAtLowTrackingArousal: Int = 5
    let minTargetsAtHighTrackingArousal: Int = 1
    // Target Shift Intervals (Seconds)
    let shiftIntervalMin_LowArousal: TimeInterval = 20.0
    let shiftIntervalMax_LowArousal: TimeInterval = 30.0
    let shiftIntervalMin_HighArousal: TimeInterval = 2.5
    let shiftIntervalMax_HighArousal: TimeInterval = 4.0
    // Identification Prompt Intervals (Seconds)
    let idIntervalMin_LowArousal: TimeInterval = 30.0
    let idIntervalMax_LowArousal: TimeInterval = 50.0
    let idIntervalMin_HighArousal: TimeInterval = 10.0
    let idIntervalMax_HighArousal: TimeInterval = 15.0
    // Identification Duration Ranges/Values
    let maxIdentificationDurationAtLowArousal: TimeInterval = 8.0
    let minIdentificationDurationAtHighArousal: TimeInterval = 0.75
    // Color Similarity / Discriminatory Load
    let targetColor_LowArousal: SKColor = SKColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0) // Bright Blue
    let distractorColor_LowArousal: SKColor = SKColor(red: 0.3, green: 1.0, blue: 0.6, alpha: 1.0) // Bright Green
    let targetColor_HighArousal: SKColor = SKColor(red: 1.0, green: 0.4, blue: 0.2, alpha: 1.0) // Orange-Red
    let distractorColor_HighArousal: SKColor = SKColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 1.0) // Orange-Yellow
    // REMOVED: hiddenColor (will use activeDistractorColor)
    let flashColor: SKColor = .white // Color for flash animation
    let flashSpeedFactor: CGFloat = 0.85 // Speed multiplier for flash iterations (0.7 = 30% faster)

    // --- TODO: Add ranges/factors for predictability ---

    // --- Breathing Task ---
    // Base/default breathing durations
    let breathingInhaleDuration: TimeInterval = 4.25
    let breathingHoldAfterInhaleDuration: TimeInterval = 0.5
    let breathingExhaleDuration: TimeInterval = 4.25
    let breathingHoldAfterExhaleDuration: TimeInterval = 1.0
    // NEW: Dynamic breathing min/max durations for inhale/exhale, driven by arousal
    let dynamicBreathingMinInhaleDuration: TimeInterval = 3.5
    let dynamicBreathingMaxInhaleDuration: TimeInterval = 4.25
    let dynamicBreathingMinExhaleDuration: TimeInterval = 4.25
    let dynamicBreathingMaxExhaleDuration: TimeInterval = 8.0
    
    // Dynamic breathing duration ranges (for arousal-based adjustment) - RETAINED FOR NOW, POTENTIALLY FOR HOLDS
    let breathingInhaleDuration_Min: TimeInterval = 3.5 // Matches dynamicBreathingMinInhaleDuration
    let breathingInhaleDuration_Max: TimeInterval = 4.25 // Matches dynamicBreathingMaxInhaleDuration
    let breathingExhaleDuration_Min: TimeInterval = 4.25 // Matches dynamicBreathingMinExhaleDuration
    let breathingExhaleDuration_Max: TimeInterval = 8.0 // Matches dynamicBreathingMaxExhaleDuration
    
    // Proportions for dynamic hold durations (as percentage of inhale/exhale duration)
    let holdAfterInhaleProportion_LowArousal: CGFloat = 0.30  // 30% of inhale duration at minimum arousal
    let holdAfterInhaleProportion_HighArousal: CGFloat = 0.05 // 5% of inhale duration at tracking threshold
    let holdAfterExhaleProportion_LowArousal: CGFloat = 0.50  // 50% of exhale duration at minimum arousal
    let holdAfterExhaleProportion_HighArousal: CGFloat = 0.20 // 20% of exhale duration at tracking threshold
    
    // NEW: Proportion of exhale that occurs *before* the first hold (now mid-exhale)
    let preHoldExhaleProportion: TimeInterval = 0.0075 // 5% of exhale, then hold, then remaining 95%
    
    // Breathing animation settings
    let breathingCircleMinRadius: CGFloat = 60.0
    let breathingCircleMaxRadius: CGFloat = 180.0
    let transitionSpeedFactor: CGFloat = 0.8
    let breathingMinTransitionSpeed: CGFloat = 50.0
    let maxTransitionDuration: TimeInterval = 4.0
    
    // Breathing haptics
    let breathingHapticIntensity: Float = 0.8
    let breathingHapticSharpnessMin: Float = 0.35
    let breathingHapticSharpnessMax: Float = 0.8
    let breathingHapticAccelFactor: Double = 0.13

    // --- Identification Task ---
    let identificationStartDelay: TimeInterval = 0.5
    let identificationDuration: TimeInterval = 4.625 // Base duration (midpoint of 1.25 and 8.0)
    // --- Feedback Settings ---
    let correctTapParticleEffectFileName: String = "CorrectTapEffect.sks" // Ensure this file exists
    let correctTapSoundFileName: String = "correct_sound" // Base name, assumes extension
    let groupCompleteSoundFileName: String = "streak_sound" // Base name, assumes extension
    let incorrectTapSoundFileName: String = "wrong_sound" // Base name, assumes extension
    let targetShiftSoundFileName: String = "radar_blip"   // Base name, assumes extension
    let feedbackMinArousalThreshold: CGFloat = 0.5 // Arousal level below which feedback is zero
    let feedbackMaxArousalThreshold: CGFloat = 1.0 // Arousal level at which feedback is maximum
    // Particle Feedback Mapping
    let particleFeedbackMaxBirthRate: CGFloat = 200 // Example: Birth rate at max arousal
    let particleFeedbackMaxScale: CGFloat = 1.0 // Example: Scale at max arousal
    // Audio Feedback Mapping
    let audioFeedbackMaxVolume: Float = 1.0 // Volume at max arousal

    //====================================================================================================
    // MARK: - AUDIO SYSTEM CONFIGURATION (NEW)
    //====================================================================================================
    let usePreciseAudio: Bool = true // Feature flag for PreciseAudioPulser
    let minAudioFrequency: Float = 75.0 // Min frequency for rhythmic audio
    let maxAudioFrequency: Float = 350.0 // Max frequency for rhythmic audio
    let audioMinAmplitude: Float = 0.15   // Min amplitude for audio pulse
    let audioMaxAmplitude: Float = 0.325   // Max amplitude for audio pulse
    let audioPulseRateFactor: Double = 0.8 // Factor to derive pulser rate from timer frequency

    // --- Visuals ---
    let visualPulseOnDurationRatio: Double = 0.2
    let flashCooldownDuration: TimeInterval = 0.5
    let fadeDuration: TimeInterval = 4.0 // User adjusted

    //====================================================================================================
    // MARK: - SESSION CONFIGURATION (NEW)
    //====================================================================================================
    // Challenge Phase Parameters
    let challengePhaseProbability: Double = 1.0       // Kept at 1.0 for testing
    let challengePhaseCount: ClosedRange<Int> = 2...4 // Keeping the increased count
    let challengePhaseRelativeStart: ClosedRange<Double> = 0.1...0.7 // Restrict to first 70% of session
    let challengePhaseDuration: ClosedRange<Double> = 0.15...0.25   // Changed to 15-25% as requested
    let challengePhaseIntensity: ClosedRange<Double> = 0.3...0.5   // Changed to 30-50% as requested
    
    // Breathing State Timing
    let breathingStateTargetRangeMin: Double = 0.4  // Breathing starts around 40% of session
    let breathingStateTargetRangeMax: Double = 0.6  // Breathing starts around 60% of session
    
    // Default session profile
    let defaultSessionProfile: SessionProfile = .fluctuating
    
// --- Motion Control Fine Tuning ---
// MotionSettings struct remains separate for now.

    //====================================================================================================
    // MARK: - ADAPTIVE DIFFICULTY CONFIGURATION
    //====================================================================================================
    
    // --- DOM Target Parameter Ranges ---
    // Target Count (fewer is easier at high arousal, more is harder)
    let targetCount_MinArousal_EasiestSetting: Int = 4
    let targetCount_MinArousal_HardestSetting: Int = 7
    let targetCount_MaxArousal_EasiestSetting: Int = 1
    let targetCount_MaxArousal_HardestSetting: Int = 2
    
    // Discriminability Factor (higher is easier - more different colors)
    let discriminabilityFactor_MinArousal_EasiestSetting: CGFloat = 1.0
    let discriminabilityFactor_MinArousal_HardestSetting: CGFloat = 0.65
    let discriminabilityFactor_MaxArousal_EasiestSetting: CGFloat = 0.4
    let discriminabilityFactor_MaxArousal_HardestSetting: CGFloat = 0.0
    
    // Mean Ball Speed (lower is easier)
    let meanBallSpeed_MinArousal_EasiestSetting: CGFloat = 25.0
    let meanBallSpeed_MinArousal_HardestSetting: CGFloat = 125.0
    let meanBallSpeed_MaxArousal_EasiestSetting: CGFloat = 750.0
    let meanBallSpeed_MaxArousal_HardestSetting: CGFloat = 1150.0
    
    // Ball Speed Standard Deviation (lower is easier)
    let ballSpeedSD_MinArousal_EasiestSetting: CGFloat = 0.0
    let ballSpeedSD_MinArousal_HardestSetting: CGFloat = 25.0
    let ballSpeedSD_MaxArousal_EasiestSetting: CGFloat = 75.0
    let ballSpeedSD_MaxArousal_HardestSetting: CGFloat = 200.0
    
    // Response Time for ID phase (higher is easier - more time to respond)
    let responseTime_MinArousal_EasiestSetting: TimeInterval = 8.0
    let responseTime_MinArousal_HardestSetting: TimeInterval = 4.0
    let responseTime_MaxArousal_EasiestSetting: TimeInterval = 1.5
    let responseTime_MaxArousal_HardestSetting: TimeInterval = 0.75
    
    // --- Arousal Thresholds for DOM Scaling ---
    let arousalOperationalMinForDOMScaling: CGFloat = 0.35
    let arousalOperationalMaxForDOMScaling: CGFloat = 1.0
    let arousalThresholdForKPIAndHierarchySwitch: CGFloat = 0.7
    
    // --- KPI Weights ---
    // High Arousal (>= 0.7)
    let kpiWeights_HighArousal = KPIWeights(
        taskSuccess: 0.35,
        tfTtfRatio: 0.2,
        reactionTime: 0.25,
        responseDuration: 0.15,
        tapAccuracy: 0.05
    )
    
    // Low/Mid Arousal (0.35 < arousal < 0.7)
    let kpiWeights_LowMidArousal = KPIWeights(
        taskSuccess: 0.40,
        tfTtfRatio: 0.2,
        reactionTime: 0.15,
        responseDuration: 0.15,
        tapAccuracy: 0.10
    )
    
    // --- DOM Target Hierarchies ---
    // High Arousal Hierarchy (>= 0.7)
    let domHierarchy_HighArousal: [DOMTargetType] = [
        .discriminatoryLoad,
        .meanBallSpeed,
        .ballSpeedSD,
        .responseTime,
        .targetCount
    ]
    
    // Low/Mid Arousal Hierarchy (0.35 < arousal < 0.7)
    let domHierarchy_LowMidArousal: [DOMTargetType] = [
        .targetCount,
        .responseTime,
        .discriminatoryLoad,
        .meanBallSpeed,
        .ballSpeedSD
    ]
    
    // --- KPI Normalization Parameters ---
    let reactionTime_BestExpected: TimeInterval = 0.2
    let reactionTime_WorstExpected: TimeInterval = 1.75
    let responseDuration_PerTarget_BestExpected: TimeInterval = 0.2
    let responseDuration_PerTarget_WorstExpected: TimeInterval = 1.0
    let tapAccuracy_BestExpected_Points: CGFloat = 0.0
    let tapAccuracy_WorstExpected_Points: CGFloat = 225.0
    
    // --- Adaptive System Tuning Parameters ---
    let initialStartupArousalForDefaults: CGFloat = 0.5
    let domSmoothingFactors: [DOMTargetType: CGFloat] = [
        .discriminatoryLoad: 0.3,  // Increased from 0.15 for more responsive color changes
        .meanBallSpeed: 0.15,       // Increased from 0.10 for more noticeable speed changes
        .ballSpeedSD: 0.1,         // Increased from 0.08 for more dynamic speed variation
        .responseTime: 0.2,        // Increased from 0.12 for more responsive time adjustments
        .targetCount: 0.3          // Increased from 0.20 for quicker target count changes
    ]
    let adaptationSignalSensitivity: CGFloat = 1.5  // Increased from 1.0 to amplify performance responses
    let adaptationSignalDeadZone: CGFloat = 0.02     // Reduced from 0.05 to react to smaller performance changes
    
    // --- Performance History Configuration (NEW) ---
    let performanceHistoryWindowSize: Int = 10
    let usePerformanceHistory: Bool = false  // Start disabled for safety
    
    // --- KPI Weight Interpolation Configuration (Phase 1.5) ---
    let kpiWeightTransitionStart: CGFloat = 0.6
    let kpiWeightTransitionEnd: CGFloat = 0.8
    let useKPIWeightInterpolation: Bool = true
}
