// NeuroGlide/GameConfiguration.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 11 Part 2: Variable Interval Config
// Role: Centralized configuration settings for the game parameters.

import Foundation
import CoreGraphics // For CGFloat
import SpriteKit // For SKColor if needed later

struct GameConfiguration {

    // --- General ---
    let numberOfBalls: Int = 10

    // --- Arousal Mapping & Thresholds ---
    let trackingArousalThresholdLow: CGFloat = 0.35
    let trackingArousalThresholdHigh: CGFloat = 1.0
    let breathingFadeOutThreshold: CGFloat = 0.20
    let arousalSteps: [CGFloat] = [0.15, 0.25, 0.35, 0.50, 0.75, 1.00]

    // --- Tracking Task Parameter Ranges (Mapped within Tracking Thresholds) ---
    // Motion
    let minTargetSpeedAtTrackingThreshold: CGFloat = 100.0
    let maxTargetSpeedAtTrackingThreshold: CGFloat = 1000.0
    let minTargetSpeedSDAtTrackingThreshold: CGFloat = 20.0
    let maxTargetSpeedSDAtTrackingThreshold: CGFloat = 150.0
    // Rhythmic Pulse Frequency
    let minTimerFrequencyAtTrackingThreshold: Double = 6.0  // Hz
    let maxTimerFrequencyAtTrackingThreshold: Double = 20.0 // Hz
    // Target Count
    let maxTargetsAtLowTrackingArousal: Int = 5
    let minTargetsAtHighTrackingArousal: Int = 1

    // ** MODIFIED: Variable Intervals **
    // Target Shift Intervals (Seconds)
    let shiftIntervalMin_LowArousal: TimeInterval = 35.0 // Min delay at arousal 0.35
    let shiftIntervalMax_LowArousal: TimeInterval = 65.0 // Max delay at arousal 0.35 (Wide range = unpredictable)
    let shiftIntervalMin_HighArousal: TimeInterval = 2.5 // Min delay at arousal 1.0
    let shiftIntervalMax_HighArousal: TimeInterval = 6.0 // Max delay at arousal 1.0 (Narrow range = predictable)

    // Identification Prompt Intervals (Seconds)
    let idIntervalMin_LowArousal: TimeInterval = 30.0 // Min delay at arousal 0.35
    let idIntervalMax_LowArousal: TimeInterval = 50.0 // Max delay at arousal 0.35 (Wide range = unpredictable)
    let idIntervalMin_HighArousal: TimeInterval = 8.0  // Min delay at arousal 1.0
    let idIntervalMax_HighArousal: TimeInterval = 12.0 // Max delay at arousal 1.0 (Narrow range = predictable)

    // Identification Duration (Base value, could be mapped too)
    let identificationDuration: TimeInterval = 5.0

    // --- TODO: Add ranges/factors for other parameters ---
    // let minIdentificationDuration: TimeInterval = ...
    // let maxIdentificationDuration: TimeInterval = ...
    // let lowArousalTargetColor: SKColor = ...
    // let highArousalTargetColor: SKColor = ...

    // --- Breathing Task ---
    let breathingTimerFrequency: Double = 3.0 // Hz during breathing
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

    // --- Visuals ---
    let visualPulseOnDurationRatio: Double = 0.2
    let flashCooldownDuration: TimeInterval = 0.5
    let fadeDuration: TimeInterval = 0.75

    // --- Motion Control Fine Tuning ---
    // MotionSettings struct remains separate for now.
}
