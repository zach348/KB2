// NeuroGlide/MotionSettings.swift
// Created: [Current Date]
// Role: Holds target parameters for ball motion control. (COMPLETE FILE)

import Foundation
import CoreGraphics // For CGFloat

struct MotionSettings {
    // Target values (will be driven by arousal model later)
    var targetMeanSpeed: CGFloat = 150.0 // Target average speed (points per second)
    var targetSpeedSD: CGFloat = 50.0   // Target standard deviation of speeds

    // Absolute limits
    var minSpeed: CGFloat = 25.0
    var maxSpeed: CGFloat = 1200.0

    // Adjustment factors (how aggressively to correct)
    var meanCorrectionFactorUp: CGFloat = 1.01   // Factor to increase speed towards mean
    var meanCorrectionFactorDown: CGFloat = 0.99 // Factor to decrease speed towards mean
    var sdCorrectionFactorExpand: CGFloat = 1.01 // Factor to increase speed variance
    var sdCorrectionFactorContract: CGFloat = 0.99// Factor to decrease speed variance
    var rangeCorrectionFactorUp: CGFloat = 1.01  // Factor to nudge speed up from min
    var rangeCorrectionFactorDown: CGFloat = 0.99// Factor to nudge speed down from max

    // Wall push (optional)
    var wallPushImpulse: CGFloat = 2.0 // How hard to push balls stuck at walls

    // Add other configurable parameters as needed
}
