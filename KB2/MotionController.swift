// NeuroGlide/MotionController.swift
// Created: [Current Date]
// Role: Calculates motion statistics and applies corrections to balls. (COMPLETE FILE)

import Foundation
import SpriteKit // For CGPoint, CGVector, etc.

struct MotionController {

    // --- Public Entry Point ---

    /// Applies all motion corrections to the given balls based on settings.
    static func applyCorrections(balls: [Ball], settings: MotionSettings, scene: SKScene?) {
        guard !balls.isEmpty else { return }

        let currentStats = calculateStats(balls: balls)

        correctSpeedSD(balls: balls, settings: settings, currentStats: currentStats)
        correctMeanSpeed(balls: balls, settings: settings, currentStats: currentStats)
        correctSpeedRange(balls: balls, settings: settings)
        // Optional: Wall push correction
        if let validScene = scene {
             wallPush(balls: balls, settings: settings, scene: validScene)
        }
    }

    // --- Statistics Calculation ---

    struct MotionStats {
        let meanSpeed: CGFloat
        let speedSD: CGFloat
    }

    /// Calculates the current mean speed and standard deviation of speeds for the balls.
    static func calculateStats(balls: [Ball]) -> MotionStats {
        guard !balls.isEmpty else { return MotionStats(meanSpeed: 0, speedSD: 0) }

        let speeds = balls.map { $0.currentSpeed() }
        let count = CGFloat(speeds.count)

        // Calculate Mean
        let totalSpeed = speeds.reduce(0, +)
        // Avoid division by zero if count is somehow zero despite guard
        let meanSpeed = count > 0 ? totalSpeed / count : 0

        // Calculate Standard Deviation
        var sumOfSquaredDifferences: CGFloat = 0
        for speed in speeds {
            let difference = speed - meanSpeed
            sumOfSquaredDifferences += difference * difference
        }
        // Use population standard deviation (divide by N)
        let variance = count > 0 ? sumOfSquaredDifferences / count : 0
        // Ensure variance is non-negative before sqrt
        let speedSD = variance >= 0 ? sqrt(variance) : 0

        return MotionStats(meanSpeed: meanSpeed, speedSD: speedSD)
    }


    // --- Correction Logic ---

    /// Adjusts speeds to move the mean towards the target mean.
    private static func correctMeanSpeed(balls: [Ball], settings: MotionSettings, currentStats: MotionStats) {
        for ball in balls {
            let speed = ball.currentSpeed()
            // If mean is too low, speed up balls below max speed
            if currentStats.meanSpeed < settings.targetMeanSpeed && speed < settings.maxSpeed {
                ball.modifySpeed(factor: settings.meanCorrectionFactorUp)
            }
            // If mean is too high, slow down balls above min speed
            else if currentStats.meanSpeed > settings.targetMeanSpeed && speed > settings.minSpeed {
                ball.modifySpeed(factor: settings.meanCorrectionFactorDown)
            }
        }
    }

    /// Adjusts speeds to move the standard deviation towards the target SD.
    private static func correctSpeedSD(balls: [Ball], settings: MotionSettings, currentStats: MotionStats) {
        for ball in balls {
            let speed = ball.currentSpeed()
            // If SD is too low (speeds too similar), increase variance
            if currentStats.speedSD < settings.targetSpeedSD {
                // Speed up balls already faster than mean (pushing them further out)
                if speed > currentStats.meanSpeed && speed < settings.maxSpeed {
                    ball.modifySpeed(factor: settings.sdCorrectionFactorExpand)
                }
                // Slow down balls already slower than mean (pushing them further out)
                else if speed < currentStats.meanSpeed && speed > settings.minSpeed {
                    ball.modifySpeed(factor: settings.sdCorrectionFactorContract) // Contract factor used to slow down
                }
            }
            // If SD is too high (speeds too varied), decrease variance
            else if currentStats.speedSD > settings.targetSpeedSD {
                // Slow down balls faster than mean (pulling them closer)
                if speed > currentStats.meanSpeed && speed > settings.minSpeed {
                    ball.modifySpeed(factor: settings.sdCorrectionFactorContract)
                }
                // Speed up balls slower than mean (pulling them closer)
                else if speed < currentStats.meanSpeed && speed < settings.maxSpeed {
                    ball.modifySpeed(factor: settings.sdCorrectionFactorExpand) // Expand factor used to speed up
                }
            }
        }
    }

    /// Enforces the minimum and maximum speed limits.
    private static func correctSpeedRange(balls: [Ball], settings: MotionSettings) {
        for ball in balls {
            let speed = ball.currentSpeed()
            if speed < settings.minSpeed && speed > 0 { // Don't apply if already zero
                // Gradually increase speed if below min
                ball.modifySpeed(factor: settings.rangeCorrectionFactorUp)
            } else if speed > settings.maxSpeed {
                // Gradually decrease speed if above max
                ball.modifySpeed(factor: settings.rangeCorrectionFactorDown)
            }
        }
    }

    /// Applies a small impulse to balls stuck near walls (optional).
    private static func wallPush(balls: [Ball], settings: MotionSettings, scene: SKScene) {
        let sceneBounds = scene.frame // Use scene frame directly

        for ball in balls {
            // Update history *before* checking
            ball.updatePositionHistory()

            // Check if stuck horizontally
            if ball.ballStuckX() {
                let impulseX: CGFloat = (ball.position.x > sceneBounds.midX) ? -settings.wallPushImpulse : settings.wallPushImpulse
                ball.physicsBody?.applyImpulse(CGVector(dx: impulseX, dy: 0))
                // print("WallPush X applied to \(ball.name ?? "")") // Debug
            }

            // Check if stuck vertically
            if ball.ballStuckY() {
                let impulseY: CGFloat = (ball.position.y > sceneBounds.midY) ? -settings.wallPushImpulse : settings.wallPushImpulse
                ball.physicsBody?.applyImpulse(CGVector(dx: 0, dy: impulseY))
                // print("WallPush Y applied to \(ball.name ?? "")") // Debug
            }
        }
    }
}
