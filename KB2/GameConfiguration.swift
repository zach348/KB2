// Kalibrate/GameConfiguration.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 11 FIX 8: Revised Arousal Steps, Removed Hidden Color
// Role: Centralized configuration settings for the game parameters.

import Foundation
import CoreGraphics // For CGFloat
import SpriteKit // For SKColor

struct GameConfiguration {

    // --- General ---
    let numberOfBalls: Int = 10

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
    let maxIdentificationDurationAtLowArousal: TimeInterval = 10.0
    let minIdentificationDurationAtHighArousal: TimeInterval = 1.75
    // Color Similarity / Discriminatory Load
    let targetColor_LowArousal: SKColor = SKColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0) // Bright Blue
    let distractorColor_LowArousal: SKColor = SKColor(red: 0.3, green: 1.0, blue: 0.6, alpha: 1.0) // Bright Green
    let targetColor_HighArousal: SKColor = SKColor(red: 1.0, green: 0.4, blue: 0.2, alpha: 1.0) // Orange-Red
    let distractorColor_HighArousal: SKColor = SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0) // Orange-Yellow
    // REMOVED: hiddenColor (will use activeDistractorColor)
    let flashColor: SKColor = .white // Color for flash animation
    let flashSpeedFactor: CGFloat = 0.7 // Speed multiplier for flash iterations (0.7 = 30% faster)

    // --- TODO: Add ranges/factors for predictability ---

    // --- Breathing Task ---
    let breathingInhaleDuration: TimeInterval = 4.0
    let breathingHoldAfterInhaleDuration: TimeInterval = 1.5
    let breathingExhaleDuration: TimeInterval = 6.0
    let breathingHoldAfterExhaleDuration: TimeInterval = 1.0
    let breathingCircleMinRadius: CGFloat = 60.0
    let breathingCircleMaxRadius: CGFloat = 180.0
    let transitionSpeedFactor: CGFloat = 0.8
    let breathingMinTransitionSpeed: CGFloat = 50.0
    let maxTransitionDuration: TimeInterval = 4.0
    // Breathing Haptics
    let breathingHapticIntensity: Float = 0.8
    let breathingHapticSharpnessMin: Float = 0.35
    let breathingHapticSharpnessMax: Float = 0.8
    let breathingHapticAccelFactor: Double = 0.13

    // --- Identification Task ---
    let identificationStartDelay: TimeInterval = 0.5
    let identificationDuration: TimeInterval = 5.0 // Base duration
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

    // --- Visuals ---
    let visualPulseOnDurationRatio: Double = 0.2
    let flashCooldownDuration: TimeInterval = 0.5
    let fadeDuration: TimeInterval = 4.0 // User adjusted

    // --- Motion Control Fine Tuning ---
    // MotionSettings struct remains separate for now.
}
