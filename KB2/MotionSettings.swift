// Copyright 2025 Training State, LLC. All rights reserved.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
// Kalibrate/MotionSettings.swift
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
    var meanCorrectionFactorUp: CGFloat = 1.025  // Factor to increase speed towards mean
    var meanCorrectionFactorDown: CGFloat = 0.99 // Factor to decrease speed towards mean
    var sdCorrectionFactorExpand: CGFloat = 1.005 // Factor to increase speed variance
    var sdCorrectionFactorContract: CGFloat = 0.975// Factor to decrease speed variance
    var rangeCorrectionFactorUp: CGFloat = 1.01  // Factor to nudge speed up from min
    var rangeCorrectionFactorDown: CGFloat = 0.96// Factor to nudge speed down from max

    // Wall push (optional)
    var wallPushImpulse: CGFloat = 2.0 // How hard to push balls stuck at walls

    // Add other configurable parameters as needed
}
