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
import Foundation

/// SessionAnalytics provides calculations for session-related metrics
/// including round estimation which is crucial for determining warmup phase length
struct SessionAnalytics {

    /// Estimates the expected number of rounds for a given session duration
    /// - Parameters:
    ///   - sessionDuration: Total session duration in seconds
    ///   - config: Game configuration containing timing parameters
    ///   - initialArousal: Starting arousal level (0.0-1.0)
    /// - Returns: Estimated number of rounds that will fit in the session
    /// 
    /// This estimate is used by AdaptiveDifficultyManager to calculate:
    /// - Warmup phase length (25% of expected rounds)
    /// - Fatigue detection threshold (starts after 70% of expected rounds)
    /// 
    /// The calculation considers:
    /// - Interactive portion of session (typically 65%)
    /// - Arousal decay over time
    /// - Round duration changes based on arousal level
    static func estimateExpectedRounds(
        forSessionDuration sessionDuration: TimeInterval,
        config: GameConfiguration,
        initialArousal: CGFloat
    ) -> Int {
        let interactiveDuration = sessionDuration * config.interactiveSessionProportion
        
        var estimatedRounds = 0
        var currentTime: TimeInterval = 0
        
        while currentTime < interactiveDuration {
            let progress = currentTime / interactiveDuration
            
            // 1. Calculate arousal at current progress
            let currentArousal = calculateArousalForProgress(
                progress: progress, 
                initialLevel: initialArousal
            )
            
            // 2. Calculate the total time for one round at this arousal level
            let roundDuration = calculateRoundDuration(
                arousal: currentArousal,
                config: config
            )
            
            // Ensure round duration is positive to prevent infinite loops
            guard roundDuration > 0 else {
                // Log an error or handle gracefully
                return estimatedRounds
            }
            
            currentTime += roundDuration
            
            if currentTime < interactiveDuration {
                estimatedRounds += 1
            }
        }
        
        return estimatedRounds
    }

    /// Calculates arousal level at a given progress point in the session
    /// Uses exponential decay model for arousal reduction over time
    private static func calculateArousalForProgress(progress: Double, initialLevel: CGFloat) -> CGFloat {
        let endArousal: CGFloat = 0.0
        let decayConstant: Double = 1.5 // Controls steepness of arousal decay
        let result = endArousal + (initialLevel - endArousal) * CGFloat(exp(-decayConstant * progress))
        return max(0.0, min(initialLevel, result))
    }

    /// Calculates the expected duration of a single round at the given arousal level
    /// - Parameters:
    ///   - arousal: Current arousal level (0.0-1.0)
    ///   - config: Game configuration containing timing parameters
    /// - Returns: Expected round duration in seconds
    /// 
    /// A round consists of:
    /// - Inter-trial interval (ITI) - time between identification phases
    /// - Response time - time allowed for player to identify targets
    private static func calculateRoundDuration(
        arousal: CGFloat,
        config: GameConfiguration
    ) -> TimeInterval {
        // For estimation, we assume an average difficulty (0.5)
        let normalizedDifficulty: CGFloat = 0.5

        // Interpolate the response time based on arousal and average difficulty
        let easiestResponseTime = lerp(
            config.responseTime_MinArousal_EasiestSetting,
            config.responseTime_MaxArousal_EasiestSetting,
            arousal
        )
        let hardestResponseTime = lerp(
            config.responseTime_MinArousal_HardestSetting,
            config.responseTime_MaxArousal_HardestSetting,
            arousal
        )
        // For response time, "easiest" is the max value, so we invert the interpolation for difficulty
        let responseTime = hardestResponseTime + (easiestResponseTime - hardestResponseTime) * (1.0 - normalizedDifficulty)

        // Interpolate the ITI based on arousal
        let lowArousalITI = (config.idIntervalMin_LowArousal + config.idIntervalMax_LowArousal) / 2.0
        let highArousalITI = (config.idIntervalMin_HighArousal + config.idIntervalMax_HighArousal) / 2.0
        let iti = lerp(lowArousalITI, highArousalITI, arousal)
        
        return responseTime + iti
    }
    
    private static func lerp(_ a: TimeInterval, _ b: TimeInterval, _ t: CGFloat) -> TimeInterval {
        return a + (b - a) * t
    }
}
