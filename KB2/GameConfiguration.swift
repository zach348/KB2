// NeuroGlide/GameConfiguration.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 11 FIX 3: Reversed Target Count Mapping
// Role: Centralized configuration settings for the game parameters.

import Foundation
import CoreGraphics // For CGFloat
import SpriteKit // For SKColor if needed later

struct GameConfiguration {

    // --- General ---
    let numberOfBalls: Int = 10 // Total balls in scene

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
    // Target Count (Working Memory Load / Attentional Breadth)
    // MODIFIED: Renamed and values set for reversed mapping
    let maxTargetsAtLowTrackingArousal: Int = 5 // Max targets when arousal is at trackingArousalThresholdLow
    let minTargetsAtHighTrackingArousal: Int = 1 // Min targets when arousal is at trackingArousalThresholdHigh (1.0)

    // Tracking/ID Intervals (Base values, variability added later)
    let targetShiftInterval: TimeInterval = 5.0
    let identificationInterval: TimeInterval = 10.0
    let identificationDuration: TimeInterval = 5.0 // Base duration (could be mapped too)

    // --- TODO: Add ranges/factors for predictability and other parameters ---
    // let targetShiftPredictabilityFactor: CGFloat = ...
    // let identificationPredictabilityFactor: CGFloat = ...
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
