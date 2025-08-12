// Kalibrate/GameConfiguration.swift
// Created: [Previous Date]
// Updated: [Current Date] - Added Adaptive Difficulty Manager Configuration
// Role: Centralized configuration settings for the game parameters.

import Foundation
import CoreGraphics // For CGFloat
import SpriteKit // For SKColor

// Enum for Difficulty Optimization Matrix (DOM) targets
enum DOMTargetType: String, Codable, Hashable, CaseIterable { // Made Hashable and Codable
    case discriminatoryLoad
    case meanBallSpeed
    case ballSpeedSD
    case responseTime
    case targetCount
}

// Enum for Key Performance Indicator (KPI) types
enum KPIType: String, Codable, Hashable, CaseIterable { // Made Hashable and Codable
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

    // --- Debug/QA ---
    /// When true, onboarding will be shown on every app launch regardless of completion state.
    /// Use for refining copy and interaction. Default: false.
    var forceShowOnboarding: Bool = false

    /// When true, the tutorial will be shown regardless of completion state.
    /// Use for refining copy and interaction. Default: false.
    var forceShowTutorial: Bool = false

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
    
    // Proportions for dynamic hold durations (as percentage of inhale/exhale duration)
    let holdAfterInhaleProportionLowArousal: CGFloat = 0.30  // 30% of inhale duration at minimum arousal
    let holdAfterInhaleProportionHighArousal: CGFloat = 0.05 // 5% of inhale duration at tracking threshold
    let holdAfterExhaleProportionLowArousal: CGFloat = 0.50  // 50% of exhale duration at minimum arousal
    let holdAfterExhaleProportionHighArousal: CGFloat = 0.20 // 20% of exhale duration at tracking threshold
    
    // NEW: Proportion of exhale that occurs *before* the first hold (now mid-exhale)
    let preHoldExhaleProportion: TimeInterval = 0.035 // % of exhale, then hold, then remaining %
    
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
    
    // Breathing haptic tempo parameters
    let breathingHapticMinDelay: TimeInterval = 0.013  // ~77Hz - Fastest tempo at max radius (was 0.04)
    let breathingHapticMaxDelay: TimeInterval = 0.075   // ~6.7Hz - Slowest tempo at min radius
    let breathingHapticTempoExponent: Double = 1.2     // Controls the curve mapping (higher = more dramatic change)

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
    let breathingStateTargetRangeMin: Double = 0.6  // Breathing starts around 60% of session
    let breathingStateTargetRangeMax: Double = 0.75  // Breathing starts around 75% of session
    let interactiveSessionProportion: CGFloat = 0.65 // Proportion of the session that is interactive
    
    // Default session profile
    let defaultSessionProfile: SessionProfile = .fluctuating
    
// --- Motion Control Fine Tuning ---
// MotionSettings struct remains separate for now.

    //====================================================================================================
    // MARK: - ADAPTIVE DIFFICULTY CONFIGURATION
    //====================================================================================================
    
    // --- DOM Target Parameter Ranges ---
    // Target Count (fewer is easier at high arousal, more is harder)
    let targetCount_MinArousal_EasiestSetting: Int = 5
    let targetCount_MinArousal_HardestSetting: Int = 7
    let targetCount_MaxArousal_EasiestSetting: Int = 1
    let targetCount_MaxArousal_HardestSetting: Int = 1
    
    // Discriminability Factor (higher is easier - more different colors)
    let discriminabilityFactor_MinArousal_EasiestSetting: CGFloat = 1.0
    let discriminabilityFactor_MinArousal_HardestSetting: CGFloat = 0.65
    let discriminabilityFactor_MaxArousal_EasiestSetting: CGFloat = 0.3
    let discriminabilityFactor_MaxArousal_HardestSetting: CGFloat = 0.075
    
    // Mean Ball Speed (lower is easier)
    let meanBallSpeed_MinArousal_EasiestSetting: CGFloat = 25.0
    let meanBallSpeed_MinArousal_HardestSetting: CGFloat = 75.0
    let meanBallSpeed_MaxArousal_EasiestSetting: CGFloat = 700.0
    let meanBallSpeed_MaxArousal_HardestSetting: CGFloat = 1000.0
    
    // Ball Speed Standard Deviation (lower is easier)
    let ballSpeedSD_MinArousal_EasiestSetting: CGFloat = 0.0
    let ballSpeedSD_MinArousal_HardestSetting: CGFloat = 25.0
    let ballSpeedSD_MaxArousal_EasiestSetting: CGFloat = 75.0
    let ballSpeedSD_MaxArousal_HardestSetting: CGFloat = 200.0
    
    // Response Time for ID phase (higher is easier - more time to respond)
    let responseTime_MinArousal_EasiestSetting: TimeInterval = 10.0
    let responseTime_MinArousal_HardestSetting: TimeInterval = 5.0
    let responseTime_MaxArousal_EasiestSetting: TimeInterval = 2.0
    let responseTime_MaxArousal_HardestSetting: TimeInterval = 1.0
    
    // --- Arousal Thresholds for DOM Scaling ---
    let arousalOperationalMinForDOMScaling: CGFloat = 0.35
    let arousalOperationalMaxForDOMScaling: CGFloat = 1.0
    let arousalThresholdForKPIAndHierarchySwitch: CGFloat = 0.7
    
    // --- KPI Weights ---
    // High Arousal (>= 0.7)
    let kpiWeights_HighArousal = KPIWeights(
        taskSuccess: 0.6,
        tfTtfRatio: 0.1,
        reactionTime: 0.15,
        responseDuration: 0.10,
        tapAccuracy: 0.05
    )
    
    // Low/Mid Arousal (0.35 < arousal < 0.7)
    let kpiWeights_LowMidArousal = KPIWeights(
        taskSuccess: 0.6,
        tfTtfRatio: 0.225,
        reactionTime: 0.025,
        responseDuration: 0.05,
        tapAccuracy: 0.10
    )
    
    
    // --- KPI Normalization Parameters ---
    let reactionTime_BestExpected: TimeInterval = 0.2
    let reactionTime_WorstExpected: TimeInterval = 1.75
    let responseDuration_PerTarget_BestExpected: TimeInterval = 0.2
    let responseDuration_PerTarget_WorstExpected: TimeInterval = 1.0
    let tapAccuracy_BestExpected_Points: CGFloat = 0.0
    let tapAccuracy_WorstExpected_Points: CGFloat = 225.0
    
    // --- Adaptive System Tuning Parameters ---
    let initialStartupArousalForDefaults: CGFloat = 0.5
    
    // Direction-specific smoothing factors
    // For hardening (making the game harder)
    let domHardeningSmoothingFactors: [DOMTargetType: CGFloat] = [
        .discriminatoryLoad: 0.3,  // Original value
        .meanBallSpeed: 0.2,       // Original value
        .ballSpeedSD: 0.1,         // Original value
        .responseTime: 0.1,       // Original value
        .targetCount: 0.3          // Original value
    ]
    
    // For easing (making the game easier - higher values for faster response to poor performance)
    let domEasingSmoothingFactors: [DOMTargetType: CGFloat] = [
        .discriminatoryLoad: 0.5,  // 2x hardening factor
        .meanBallSpeed: 0.3,       // 2x hardening factor
        .ballSpeedSD: 0.2,         // 2x hardening factor
        .responseTime: 0.15,        // 2x hardening factor
        .targetCount: 0.15          // 2x hardening factor
    ]
    
    // Keeping this for backward compatibility, now maps to hardening factors
    var domSmoothingFactors: [DOMTargetType: CGFloat] {
        return domHardeningSmoothingFactors
    }
    let adaptationSignalSensitivity: CGFloat = 1.5  // Increased from 1.0 to amplify performance responses
    let adaptationSignalDeadZone: CGFloat = 0.02     // Reduced from 0.05 to react to smaller performance changes
    
    // --- Performance History Configuration (NEW) ---
    var performanceHistoryWindowSize: Int = 20  // Increased from 10 to provide better historical context
    
    // --- KPI Weight Interpolation Configuration (Phase 1.5) ---
    let kpiWeightTransitionStart: CGFloat = 0.55
    let kpiWeightTransitionEnd: CGFloat = 0.85
    var useKPIWeightInterpolation: Bool = true

    // --- Trend-Based Adaptation Configuration (Phase 2) ---
    let currentPerformanceWeight: CGFloat = 0.85 // Emphasize the most recent performance
    let historyInfluenceWeight: CGFloat = 0.15   // Stabilize with a small historical influence
    let trendInfluenceWeight: CGFloat = 0.15     // Nudge based on trajectory
    let minimumHistoryForTrend: Int = 3

    // --- DOM Adaptation Rates (Phase 5) ---
    // These now act as base adaptation rates, not budget shares
    let domAdaptationRates_LowMidArousal: [DOMTargetType: CGFloat] = [
        .targetCount: 7.0,
        .responseTime: 3.0,
        .discriminatoryLoad: 3.0,
        .meanBallSpeed: 3.0,
        .ballSpeedSD: 2.0
    ]
    
    let domAdaptationRates_HighArousal: [DOMTargetType: CGFloat] = [
        .discriminatoryLoad: 6.0,
        .meanBallSpeed: 3.0,
        .ballSpeedSD: 3.0,
        .responseTime: 2.0,
        .targetCount: 1.0
    ]
    
    // --- Global Performance Target ---
    let globalPerformanceTarget: CGFloat = 0.6
    
    // --- Hysteresis Configuration (Phase 3) ---
    let adaptationIncreaseThreshold: CGFloat = 0.8    // Must exceed to increase difficulty
    let adaptationDecreaseThreshold: CGFloat = 0.75    // Must fall below to decrease
    let enableHysteresis: Bool = true
    let minStableRoundsBeforeDirectionChange: Int = 2
    let hysteresisDeadZone: CGFloat = 0.02            // Additional dead zone when in neutral

    // --- Confidence-Based Adaptation (Phase 4) ---
    let enableConfidenceScaling: Bool = true
    let minConfidenceMultiplier: CGFloat = 0.2  // Minimum adaptation strength
    let confidenceThresholdWideningFactor: CGFloat = 0.05 // How much thresholds expand when confidence is low
    
    // --- Cross-Session Persistence (Phase 4.5) ---
    var clearPastSessionData: Bool = false  // Set to true to clear previous session data on startup
    /// Whether to include DOM performance profiles in persisted state (large payload).
    /// Set to false to improve save performance; set to true only when debugging PD profiles across sessions.
    var persistDomPerformanceProfilesInState: Bool = true

    // --- Session-Aware Adaptation (Phase 5) ---
    
    /// Enables session phase management (warmup, standard)
    /// When true, sessions start with a warmup phase for recalibration
    var enableSessionPhases: Bool = true
    
    /// Proportion of the session dedicated to warmup phase (0.0-1.0)
    /// Default: 0.25 (25% of expected rounds)
    /// The warmup phase serves as a recalibration period to find appropriate difficulty
    var warmupPhaseProportion: CGFloat = 0.2
    
    /// Initial difficulty multiplier applied during warmup phase
    /// Default: 0.85 (85% of normal difficulty)
    /// This ensures players start at a comfortable level while the system recalibrates
    let warmupInitialDifficultyMultiplier: CGFloat = 0.9
    
    /// Performance target during warmup phase (0.0-1.0)
    /// Default: 0.60 (vs 0.50 in standard phase)
    /// Higher target prevents over-hardening while finding appropriate difficulty
    let warmupPerformanceTarget: CGFloat = 0.7
    
    /// Adaptation rate multiplier during warmup phase
    /// Default: 1.7 (1.7x faster than normal)
    /// Faster adaptation helps quickly find the player's current appropriate difficulty
    let warmupAdaptationRateMultiplier: CGFloat = 1.5
    
    // --- DOM-Specific Performance Profiling (Phase 5.2) ---
    
    /// Enables DOM-specific performance profiling and adaptation
    /// When true, the system tracks performance for each difficulty parameter individually
    /// and can adapt them independently based on the player's specific strengths/weaknesses
    var enableDomSpecificProfiling: Bool = true
    
    // --- PD Controller Parameters (Phase 5) ---
    
    /// Target performance level for DOM-specific adaptation (0.0-1.0)
    /// Default: 0.75 (75% performance target)
    /// The PD controller will try to maintain this performance level for each DOM
    let domProfilingPerformanceTarget: CGFloat = 0.6
    
    /// Dampening factor for the derivative term in the PD controller
    /// Default: 10.0
    /// Higher values reduce the impact of performance trend slope on adaptation
    let domSlopeDampeningFactor: CGFloat = 20.0
    
    /// Minimum number of data points required before DOM-specific adaptation begins
    /// Default: 15
    /// Ensures statistical stability before making adaptation decisions
    var domMinDataPointsForProfiling: Int = 12
    
    // --- Forced Exploration Parameters (Phase 5) ---
    
    /// Signal magnitude threshold below which a DOM is considered stable/converged
    /// Default: 0.0175 (1.75% of normalized range)
    /// When adaptation signals fall below this threshold, the DOM has reached equilibrium
    let domConvergenceThreshold: CGFloat = 0.015
    
    /// Number of consecutive rounds a DOM must be stable to be considered converged
    /// Default: 5 rounds
    /// Prevents premature convergence detection due to temporary stability
    var domConvergenceDuration: Int = 3
    
    /// Controlled nudge factor applied to converged DOMs to stimulate learning
    /// Default: 0.03 (3% of normalized range)
    /// This deterministic exploration replaces the previous random jitter approach
    var domExplorationNudgeFactor: CGFloat = 0.03
    /// Additional nudge magnitude specifically for boundary saturation (positions at 0.0 or 1.0)
    /// Used when the PD signal would push outward but is clamped by bounds to re-initiate exploration
    var domBoundaryNudgeFactor: CGFloat = 0.05
    
    /// Minimum standard deviation in DOM values required before adaptation signals are calculated
    /// Default: 0.05 (05% of the 0-1 normalized range)
    /// This prevents adaptation decisions based on insufficient exploration of the parameter space
    let minimumDOMVarianceThreshold: CGFloat = 0.05
    
    /// Maximum signal magnitude per round to prevent jarring difficulty changes
    /// Default: 0.15 (15% of normalized range)
    /// This clamps the PD controller output to ensure smooth difficulty transitions
    var domMaxSignalPerRound: CGFloat = 0.15
    
    // --- Direction-Specific Adaptation Rates (Phase 5 - bypassSmoothing resolution) ---
    
    /// Rate multiplier applied when easing (making the game easier) 
    /// Default: 1.0 (full adaptation speed when helping struggling players)
    /// This ensures quick response when players need difficulty reduction
    let domEasingRateMultiplier: CGFloat = 1.0
    
    /// Rate multiplier applied when hardening (making the game harder)
    /// Default: 0.75  (75% adaptation speed when increasing difficulty)
    /// This provides a more cautious approach to difficulty increases
    let domHardeningRateMultiplier: CGFloat = 0.85

    // Optional per-DOM overrides for direction multipliers (fallback to globals if absent)
    // Example: [.meanBallSpeed: 0.6, .ballSpeedSD: 0.6] to make hardening more conservative for speed DOMs
    var domEasingRateMultiplierByDOM: [DOMTargetType: CGFloat] = [
        .meanBallSpeed: 0.8,
        .ballSpeedSD: 0.8,
        .discriminatoryLoad: 1.25
    ]
    var domHardeningRateMultiplierByDOM: [DOMTargetType: CGFloat] = [
        .meanBallSpeed: 0.5,
        .ballSpeedSD: 0.5,
        .discriminatoryLoad: 1.1
    ]
}
