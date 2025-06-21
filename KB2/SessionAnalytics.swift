import Foundation

struct SessionAnalytics {

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

    private static func calculateArousalForProgress(progress: Double, initialLevel: CGFloat) -> CGFloat {
        let endArousal: CGFloat = 0.0
        let decayConstant: Double = 1.5 // Further reduced to achieve more rounds in longer sessions
        let result = endArousal + (initialLevel - endArousal) * CGFloat(exp(-decayConstant * progress))
        return max(0.0, min(initialLevel, result))
    }

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
