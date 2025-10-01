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
// KB2/ArousalManager.swift
// Created: [Current Date]
// Role: Manages arousal levels and associated parameter calculations

import SpriteKit
import Foundation

protocol ArousalManagerDelegate: AnyObject {
    func arousalLevelDidChange(from oldValue: CGFloat, to newValue: CGFloat)
    func parametersDidUpdate()
}

class ArousalManager {
    // MARK: - Properties
    
    private let gameConfiguration: GameConfiguration
    weak var delegate: ArousalManagerDelegate?
    
    // Backing variable with proper clamp handling
    private var _currentArousalLevel: CGFloat = 0.75
    
    // MARK: - Warmup Ramp Properties
    
    /// Whether the warmup arousal ramp is currently active
    private var isWarmupRampActive: Bool = false
    
    /// The target arousal level for the current round during warmup ramp
    private var warmupRoundTargetArousal: CGFloat = 0.0
    
    /// The amount the target arousal increases after each warmup round
    private var warmupRampIncrement: CGFloat = 0.0
    
    /// Number of warmup rounds completed
    private var warmupRoundsCompleted: Int = 0
    
    /// Total number of rounds in the warmup phase
    private var totalWarmupRounds: Int = 0
    
    // Public accessor with delegate notifications
    var currentArousalLevel: CGFloat {
        get { return _currentArousalLevel }
        set {
            let oldValue = _currentArousalLevel
            let clampedValue = max(0.0, min(newValue, 1.0))
            
            if clampedValue != _currentArousalLevel {
                _currentArousalLevel = clampedValue
                //Removed Arousal Level Diagnostic logging
                
                // Notify delegate about the change
                delegate?.arousalLevelDidChange(from: oldValue, to: _currentArousalLevel)
                
                // Calculate new parameters
                calculateParameters()
                
                // Notify delegate about parameter updates
                delegate?.parametersDidUpdate()
            }
        }
    }
    
    // Calculated parameters that vary with arousal level
    var timerFrequency: Double = 5.0
    var targetAudioFrequency: Float = 440.0
    var normalizedTrackingArousal: CGFloat = 0.0
    
    // Motion parameters
    var targetMeanSpeed: CGFloat = 0.0
    var targetSpeedSD: CGFloat = 0.0
    var targetCount: Int = 3
    
    // Task timing parameters
    var identificationDuration: TimeInterval = 5.0
    var minShiftInterval: TimeInterval = 10.0
    var maxShiftInterval: TimeInterval = 20.0
    var minIDInterval: TimeInterval = 20.0
    var maxIDInterval: TimeInterval = 30.0
    
    // Visual parameters
    var activeTargetColor: SKColor = .blue
    var activeDistractorColor: SKColor = .green
    
    // Audio parameters
    var audioAmplitude: Float = 0.5
    var audioSquareness: Float = 0.5
    var audioPulseRate: Double = 4.0
    
    
    // MARK: - Initialization
    
    init(gameConfiguration: GameConfiguration, initialArousalLevel: CGFloat = 0.75) {
        self.gameConfiguration = gameConfiguration
        self._currentArousalLevel = initialArousalLevel
        
        // Initial parameter calculation
        calculateParameters()
    }
    
    // MARK: - Public Methods
    
    func incrementArousalLevel() {
        let tolerance: CGFloat = 0.01
        guard let currentIndex = gameConfiguration.arousalSteps.lastIndex(where: { $0 <= currentArousalLevel + tolerance }) else {
            currentArousalLevel = gameConfiguration.arousalSteps.first ?? 0.0
            return
        }
        
        let nextIndex = (currentIndex + 1) % gameConfiguration.arousalSteps.count
        currentArousalLevel = gameConfiguration.arousalSteps[nextIndex]
    }
    
    func decrementArousalLevel() {
        let tolerance: CGFloat = 0.01
        guard let currentIndex = gameConfiguration.arousalSteps.firstIndex(where: { $0 >= currentArousalLevel - tolerance }) else {
            currentArousalLevel = gameConfiguration.arousalSteps.last ?? 1.0
            return
        }
        
        let nextIndex = (currentIndex == 0) ? (gameConfiguration.arousalSteps.count - 1) : (currentIndex - 1)
        currentArousalLevel = gameConfiguration.arousalSteps[nextIndex]
    }
    
    func calculateNormalizedFeedbackArousal() -> CGFloat {
        let minArousal = gameConfiguration.feedbackMinArousalThreshold
        let maxArousal = gameConfiguration.feedbackMaxArousalThreshold
        guard currentArousalLevel >= minArousal else { return 0.0 }
        
        let arousalRange = maxArousal - minArousal
        if arousalRange > 0 {
            return min(1.0, (currentArousalLevel - minArousal) / arousalRange)
        } else {
            // Handle edge case where min == max
            return (currentArousalLevel >= maxArousal) ? 1.0 : 0.0
        }
    }
    
    func updateArousalForSession(sessionMode: Bool, sessionStartTime: TimeInterval, sessionDuration: TimeInterval, initialArousalLevel: CGFloat) -> Bool {
        guard sessionMode else { return false }
        
        let currentTime = CACurrentMediaTime()
        let elapsedTime = currentTime - sessionStartTime
        let progress = min(1.0, elapsedTime / sessionDuration)
        
        // Calculate new arousal level using exponential decay formula
        let newArousalLevel = calculateArousalForProgress(progress: Double(progress), initialLevel: initialArousalLevel)
        
        // Only update if there's a meaningful change
        if abs(newArousalLevel - currentArousalLevel) > 0.001 {
            currentArousalLevel = newArousalLevel
            return true
        }
        
        return false
    }
    
    // MARK: - Warmup Ramp Methods
    
    /// Starts the warmup arousal ramp, setting up the parameters for smooth progression
    /// - Parameters:
    ///   - targetArousal: The final arousal level to reach at the end of warmup
    ///   - warmupRounds: The total number of rounds in the warmup phase
    func startWarmupRamp(targetArousal: CGFloat, warmupRounds: Int) {
        guard warmupRounds > 0 else {
            print("[ArousalManager] Warmup ramp not started: warmupRounds must be > 0")
            return
        }
        
        // Calculate starting arousal level
        let startingArousal = targetArousal * gameConfiguration.warmupArousalStartMultiplier
        
        // Calculate the increment per round
        let totalArousalGain = targetArousal - startingArousal
        warmupRampIncrement = totalArousalGain / CGFloat(warmupRounds)
        
        // Set initial state
        currentArousalLevel = startingArousal
        warmupRoundTargetArousal = startingArousal + warmupRampIncrement
        warmupRoundsCompleted = 0
        totalWarmupRounds = warmupRounds
        isWarmupRampActive = true
        
        print("[ArousalManager] Warmup ramp started:")
        print("  ├─ Target arousal: \(String(format: "%.3f", targetArousal))")
        print("  ├─ Starting arousal: \(String(format: "%.3f", startingArousal))")
        print("  ├─ Increment per round: \(String(format: "%.3f", warmupRampIncrement))")
        print("  ├─ Total warmup rounds: \(warmupRounds)")
        print("  └─ First round target: \(String(format: "%.3f", warmupRoundTargetArousal))")
    }
    
    /// Advances the warmup ramp by one round, updating the target arousal for the next round
    func advanceWarmupRampRound() {
        guard isWarmupRampActive else {
            print("[ArousalManager] Warning: advanceWarmupRampRound called but warmup ramp is not active")
            return
        }
        
        warmupRoundsCompleted += 1
        
        print("[ArousalManager] Warmup ramp advanced:")
        print("  ├─ Rounds completed: \(warmupRoundsCompleted)/\(totalWarmupRounds)")
        print("  ├─ Current arousal: \(String(format: "%.3f", currentArousalLevel))")
        
        if warmupRoundsCompleted >= totalWarmupRounds {
            // Warmup complete
            isWarmupRampActive = false
            print("  └─ Warmup ramp COMPLETE - transitioning to standard arousal management")
        } else {
            // Set next round's target
            warmupRoundTargetArousal += warmupRampIncrement
            print("  └─ Next round target: \(String(format: "%.3f", warmupRoundTargetArousal))")
        }
    }
    
    /// Updates arousal smoothly toward the current round target (called per frame during warmup)
    /// - Parameter deltaTime: Time elapsed since last frame
    func updateWarmupRampSmoothing(deltaTime: TimeInterval) {
        guard isWarmupRampActive else { return }
        
        let targetDifference = warmupRoundTargetArousal - currentArousalLevel
        
        // Only smooth if there's a meaningful difference
        guard abs(targetDifference) > 0.001 else { return }
        
        // Frame-rate independent smoothing using exponential decay
        let smoothingRate = 1.0 - pow(1.0 - gameConfiguration.warmupArousalSmoothingFactor, CGFloat(deltaTime))
        let arousalChange = targetDifference * smoothingRate
        
        currentArousalLevel += arousalChange
    }
    
    // MARK: - Private Methods
    
    private func calculateParameters() {
        // --- Global Parameter Updates ---
        
        // Frequency Calculation (Global, Non-Linear)
        let clampedArousal = max(0.0, min(currentArousalLevel, 1.0))
        let normalizedPosition = pow(Float(clampedArousal), 2.0) // Quadratic curve (x^2)
        let minFreq = gameConfiguration.minTimerFrequency
        let maxFreq = gameConfiguration.maxTimerFrequency
        let freqRange = maxFreq - minFreq
        timerFrequency = minFreq + freqRange * Double(normalizedPosition)
        
        // Audio Pitch Calculation (Linear 0.0-1.0)
        let minAudioFreq: Float = 200.0
        let maxAudioFreq: Float = 1000.0
        let audioFreqRange = maxAudioFreq - minAudioFreq
        targetAudioFrequency = minAudioFreq + (audioFreqRange * Float(clampedArousal))
        
        // Audio amplitude and squareness factors
        audioAmplitude = 0.3 + (0.4 * Float(clampedArousal)) // Range 0.3-0.7
        audioSquareness = Float(clampedArousal) // More square at higher arousal
        audioPulseRate = timerFrequency * 0.8 // Slight adjustment factor
        
        // Calculate normalized arousal in tracking range
        let trackingRange = gameConfiguration.trackingArousalThresholdHigh - gameConfiguration.trackingArousalThresholdLow
        normalizedTrackingArousal = 0.0
        if trackingRange > 0 {
            let clampedTrackingArousal = max(gameConfiguration.trackingArousalThresholdLow, 
                                             min(currentArousalLevel, gameConfiguration.trackingArousalThresholdHigh))
            normalizedTrackingArousal = (clampedTrackingArousal - gameConfiguration.trackingArousalThresholdLow) / trackingRange
        }
        
        // Motion parameters 
        let speedRange = gameConfiguration.maxTargetSpeedAtTrackingThreshold - gameConfiguration.minTargetSpeedAtTrackingThreshold
        targetMeanSpeed = gameConfiguration.minTargetSpeedAtTrackingThreshold + (speedRange * normalizedTrackingArousal)
        
        let sdRange = gameConfiguration.maxTargetSpeedSDAtTrackingThreshold - gameConfiguration.minTargetSpeedSDAtTrackingThreshold
        targetSpeedSD = gameConfiguration.minTargetSpeedSDAtTrackingThreshold + (sdRange * normalizedTrackingArousal)
        
        // Target count (inverse relationship with arousal)
        let targetCountRange = CGFloat(gameConfiguration.maxTargetsAtLowTrackingArousal - gameConfiguration.minTargetsAtHighTrackingArousal)
        let calculatedTargetCount = CGFloat(gameConfiguration.maxTargetsAtLowTrackingArousal) - (targetCountRange * normalizedTrackingArousal)
        targetCount = max(gameConfiguration.minTargetsAtHighTrackingArousal, 
                          min(gameConfiguration.maxTargetsAtLowTrackingArousal, 
                              Int(calculatedTargetCount.rounded())))
        
        // Identification duration (inverse relationship)
        let idDurationRange = gameConfiguration.maxIdentificationDurationAtLowArousal - gameConfiguration.minIdentificationDurationAtHighArousal
        identificationDuration = gameConfiguration.maxIdentificationDurationAtLowArousal - (idDurationRange * normalizedTrackingArousal)
        identificationDuration = max(0.1, identificationDuration)
        
        // Shift intervals
        let shiftMinRange = gameConfiguration.shiftIntervalMin_HighArousal - gameConfiguration.shiftIntervalMin_LowArousal
        minShiftInterval = gameConfiguration.shiftIntervalMin_LowArousal + (shiftMinRange * normalizedTrackingArousal)
        
        let shiftMaxRange = gameConfiguration.shiftIntervalMax_HighArousal - gameConfiguration.shiftIntervalMax_LowArousal
        maxShiftInterval = gameConfiguration.shiftIntervalMax_LowArousal + (shiftMaxRange * normalizedTrackingArousal)
        
        if minShiftInterval > maxShiftInterval { 
            minShiftInterval = maxShiftInterval 
        }
        
        // Identification intervals
        let idMinRange = gameConfiguration.idIntervalMin_HighArousal - gameConfiguration.idIntervalMin_LowArousal
        minIDInterval = gameConfiguration.idIntervalMin_LowArousal + (idMinRange * normalizedTrackingArousal)
        
        let idMaxRange = gameConfiguration.idIntervalMax_HighArousal - gameConfiguration.idIntervalMax_LowArousal
        maxIDInterval = gameConfiguration.idIntervalMax_LowArousal + (idMaxRange * normalizedTrackingArousal)
        
        if minIDInterval > maxIDInterval { 
            minIDInterval = maxIDInterval 
        }
        
        // Colors
        activeTargetColor = interpolateColor(
            from: gameConfiguration.targetColor_LowArousal,
            to: gameConfiguration.targetColor_HighArousal,
            t: normalizedTrackingArousal
        )
        
        activeDistractorColor = interpolateColor(
            from: gameConfiguration.distractorColor_LowArousal,
            to: gameConfiguration.distractorColor_HighArousal,
            t: normalizedTrackingArousal
        )
        
    }
    
    private func calculateArousalForProgress(progress: Double, initialLevel: CGFloat) -> CGFloat {
        // Use exponential decay: A(p) = A_end + (A_start - A_end) * e^(-k*p)
        // Where:
        // - A_start = initialLevel (initial arousal level)
        // - A_end = 0.0 (target arousal level)
        // - k ≈ 2.0 (decay constant calculated to hit 0.35 at 50% progress)
        
        // Values that define our curve
        let startArousal: CGFloat = initialLevel
        let endArousal: CGFloat = 0.0
        let decayConstant: Double = 2.0
        
        // Apply exponential decay formula
        let result = endArousal + (startArousal - endArousal) * CGFloat(exp(-decayConstant * progress))
        
        // Ensure we stay within valid range
        return max(0.0, min(initialLevel, result))
    }
    
    /// Interpolates between two SKColors
    private func interpolateColor(from: SKColor, to: SKColor, t: CGFloat) -> SKColor {
        var fromRed: CGFloat = 0, fromGreen: CGFloat = 0, fromBlue: CGFloat = 0, fromAlpha: CGFloat = 0
        var toRed: CGFloat = 0, toGreen: CGFloat = 0, toBlue: CGFloat = 0, toAlpha: CGFloat = 0
        
        from.getRed(&fromRed, green: &fromGreen, blue: &fromBlue, alpha: &fromAlpha)
        to.getRed(&toRed, green: &toGreen, blue: &toBlue, alpha: &toAlpha)
        
        let interpolatedRed = fromRed + (toRed - fromRed) * t
        let interpolatedGreen = fromGreen + (toGreen - fromGreen) * t
        let interpolatedBlue = fromBlue + (toBlue - fromBlue) * t
        let interpolatedAlpha = fromAlpha + (toAlpha - fromAlpha) * t
        
        return SKColor(red: interpolatedRed, green: interpolatedGreen, blue: interpolatedBlue, alpha: interpolatedAlpha)
    }
}
