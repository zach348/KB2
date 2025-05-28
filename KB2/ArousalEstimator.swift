import Foundation
import CoreGraphics
import QuartzCore

/// Responsible for estimating user's arousal level based on various inputs
class ArousalEstimator {
    
    // MARK: - Types
    
    /// Structure to store performance metrics from an identification task (enhanced)
    struct IdentificationPerformance {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let success: Bool
        let totalTaps: Int
        let correctTaps: Int
        let incorrectTaps: Int
        let reactionTime: TimeInterval?  // Time to first tap
        let tapEvents: [TapEventDetail]  // NEW: Detailed tap-by-tap data
        let taskStateSnapshot: DynamicTaskStateSnapshot  // NEW: Game state snapshot
        
        var duration: TimeInterval {
            return endTime - startTime
        }
        
        var accuracy: Double {
            return totalTaps > 0 ? Double(correctTaps) / Double(totalTaps) : 0.0
        }
    }
    
    /// Structure to store detailed information about a single tap event
    struct TapEventDetail {
        let timestamp: TimeInterval
        let tapLocation: CGPoint
        let tappedElementID: String?  // nil if no element was tapped
        let wasCorrect: Bool
        let ballPositions: [String: CGPoint]  // ballID -> position at time of tap
        let targetBallIDs: Set<String>        // which balls were targets at time of tap
        let distractorBallIDs: Set<String>    // which balls were distractors at time of tap
    }
    
    /// Structure to store a comprehensive snapshot of all arousal-modulated game parameters
    struct DynamicTaskStateSnapshot {
        // Core arousal values
        let currentArousalLevel: CGFloat
        let normalizedTrackingArousal: CGFloat
        
        // Target and motion parameters
        let currentTargetCount: Int
        let targetMeanSpeed: CGFloat
        let targetSpeedSD: CGFloat
        
        // Timing parameters
        let currentIdentificationDuration: TimeInterval
        let currentMinShiftInterval: TimeInterval
        let currentMaxShiftInterval: TimeInterval
        let currentMinIDInterval: TimeInterval
        let currentMaxIDInterval: TimeInterval
        let currentTimerFrequency: Double
        let visualPulseDuration: TimeInterval
        
        // Color parameters (stored as RGB components for easier logging)
        let activeTargetColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        let activeDistractorColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        
        // Audio parameters
        let currentTargetAudioFrequency: Float
        let currentAmplitude: Float?  // Optional in case not accessible
        
        // Flash parameters (from last target assignment)
        let lastFlashColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)?
        let lastNumberOfFlashes: Int?
        let lastFlashDuration: TimeInterval?
        let flashSpeedFactor: CGFloat
        
        // Feedback parameters
        let normalizedFeedbackArousal: CGFloat
        
        // Breathing parameters (if relevant)
        let currentBreathingInhaleDuration: TimeInterval?
        let currentBreathingExhaleDuration: TimeInterval?
        
        // Timestamp when this snapshot was taken
        let snapshotTimestamp: TimeInterval
    }
    
    /// Structure to store session context information
    struct SessionContext {
        let sessionStartTime: TimeInterval
        let timeOfDay: String        // e.g., "14:30:25"
        let dayOfWeek: String        // e.g., "Tuesday"
        let initialArousalLevel: CGFloat
        let sessionDuration: TimeInterval
        let sessionProfile: String   // e.g., "standard", "fluctuating", etc.
    }
    
    // MARK: - Properties
    
    /// The estimated arousal level of the user (0-1 scale)
    private var _currentUserArousalLevel: CGFloat = 0.5
    
    /// Public accessor for the current user arousal level
    var currentUserArousalLevel: CGFloat {
        get { 
            return _currentUserArousalLevel 
        }
        set { 
            _currentUserArousalLevel = min(1.0, max(0.0, newValue)) 
        }
    }
    
    /// Recent performance metrics history (most recent first)
    private var recentPerformanceHistory: [IdentificationPerformance] = []
    private let maxHistoryItems = 5
    
    /// Current identification task tracking
    private var currentIdentificationStartTime: TimeInterval?
    private var currentFirstTapTime: TimeInterval?
    private var currentCorrectTaps = 0
    private var currentIncorrectTaps = 0
    
    /// Enhanced tracking for current identification task
    private var currentTapEvents: [TapEventDetail] = []
    private var currentTaskStateSnapshot: DynamicTaskStateSnapshot?
    
    /// Session context information (stored once per session)
    private var sessionContext: SessionContext?
    
    
    // MARK: - Initialization
    
    /// Initialize with an optional initial arousal value from self-report
    init(initialArousal: CGFloat? = nil) {
        if let initialValue = initialArousal {
            _currentUserArousalLevel = min(1.0, max(0.0, initialValue))
            logArousalChange(from: 0.5, to: _currentUserArousalLevel, source: "initial-self-report")
        }
    }
    
    // MARK: - Public Methods
    
    /// Configure DataLogger integration (called from ArousalManager)
    func enableDataLoggerIntegration() {
        print("AROUSAL_ESTIMATOR: DataLogger integration enabled")
    }
    
    /// Get current arousal data in structured format for logging
    func getArousalData() -> [String: Any] {
        return [
            "currentLevel": _currentUserArousalLevel,
            "timestamp": Date().timeIntervalSince1970,
            "historyCount": recentPerformanceHistory.count
        ]
    }
    
    /// Get performance history data in structured format for analysis
    func getPerformanceHistory() -> [[String: Any]] {
        return recentPerformanceHistory.map { performance in
            var data: [String: Any] = [
                "startTime": performance.startTime,
                "endTime": performance.endTime,
                "duration": performance.duration,
                "success": performance.success,
                "totalTaps": performance.totalTaps,
                "correctTaps": performance.correctTaps,
                "incorrectTaps": performance.incorrectTaps,
                "accuracy": performance.accuracy
            ]
            if let reactionTime = performance.reactionTime {
                data["reactionTime"] = reactionTime
            }
            return data
        }
    }
    
    /// Update the user arousal estimate based on a direct self-report
    func updateFromSelfReport(reportedArousal: CGFloat) {
        let oldValue = _currentUserArousalLevel
        _currentUserArousalLevel = min(1.0, max(0.0, reportedArousal))
        logArousalChange(from: oldValue, to: _currentUserArousalLevel, source: "self-report")
    }
    
    /// Record the start of an identification task
    func startIdentificationTask(at time: TimeInterval) {
        // Reset current task tracking
        currentIdentificationStartTime = time
        currentFirstTapTime = nil
        currentCorrectTaps = 0
        currentIncorrectTaps = 0
        
        print("PROXY: Started tracking identification task at \(String(format: "%.2f", time))")
    }
    
    /// Record a tap during the identification task
    func recordTap(at time: TimeInterval, wasCorrect: Bool) {
        print("PROXY_DEBUG: Recording tap at time \(String(format: "%.2f", time))s, wasCorrect: \(wasCorrect)")
        
        // If this is the first tap, record reaction time
        if currentFirstTapTime == nil {
            currentFirstTapTime = time
            
            if let startTime = currentIdentificationStartTime {
                let reactionTime = time - startTime
                print("PROXY: First tap reaction time: \(String(format: "%.2f", reactionTime)) seconds (start: \(String(format: "%.2f", startTime)))")
            } else {
                print("PROXY_ERROR: No start time recorded for the current identification task")
            }
        }
        
        // Track tap correctness
        if wasCorrect {
            currentCorrectTaps += 1
        } else {
            currentIncorrectTaps += 1
        }
        
        print("PROXY: Recorded \(wasCorrect ? "correct" : "incorrect") tap, totals - correct: \(currentCorrectTaps), incorrect: \(currentIncorrectTaps)")
    }
    
    /// Complete the current identification task
    func completeIdentificationTask(at time: TimeInterval, wasSuccessful: Bool) {
        // Only process if we have a valid start time
        guard let startTime = currentIdentificationStartTime else {
            print("PROXY: Cannot complete identification task - no start time recorded")
            return
        }
        
        // Calculate reaction time if available
        let reactionTime = currentFirstTapTime.map { $0 - startTime }
        
        // Create performance record with enhanced data
        let performance = IdentificationPerformance(
            startTime: startTime,
            endTime: time,
            success: wasSuccessful,
            totalTaps: currentCorrectTaps + currentIncorrectTaps,
            correctTaps: currentCorrectTaps,
            incorrectTaps: currentIncorrectTaps,
            reactionTime: reactionTime,
            tapEvents: currentTapEvents,
            taskStateSnapshot: currentTaskStateSnapshot ?? createEmptySnapshot()
        )
        
        // Add to history, keeping most recent entries
        recentPerformanceHistory.insert(performance, at: 0)
        if recentPerformanceHistory.count > maxHistoryItems {
            recentPerformanceHistory.removeLast()
        }
        
        // Log the performance
        logPerformance(performance)
        
        // Update arousal estimate based on performance (very simple heuristic for now)
        updateArousalFromPerformance(performance)
        
        // Reset tracking for next task
        currentIdentificationStartTime = nil
        currentFirstTapTime = nil
        currentCorrectTaps = 0
        currentIncorrectTaps = 0
        currentTapEvents.removeAll()
        currentTaskStateSnapshot = nil
    }
    
    // MARK: - Private Methods
    
    /// Create an empty snapshot with default values as fallback
    private func createEmptySnapshot() -> DynamicTaskStateSnapshot {
        let currentTime = CACurrentMediaTime()
        return DynamicTaskStateSnapshot(
            currentArousalLevel: 0.5,
            normalizedTrackingArousal: 0.5,
            currentTargetCount: 1,
            targetMeanSpeed: 100.0,
            targetSpeedSD: 20.0,
            currentIdentificationDuration: 3.0,
            currentMinShiftInterval: 5.0,
            currentMaxShiftInterval: 10.0,
            currentMinIDInterval: 10.0,
            currentMaxIDInterval: 15.0,
            currentTimerFrequency: 5.0,
            visualPulseDuration: 0.1,
            activeTargetColor: (r: 1.0, g: 1.0, b: 1.0, a: 1.0),
            activeDistractorColor: (r: 0.5, g: 0.5, b: 0.5, a: 1.0),
            currentTargetAudioFrequency: 440.0,
            currentAmplitude: nil,
            lastFlashColor: nil,
            lastNumberOfFlashes: nil,
            lastFlashDuration: nil,
            flashSpeedFactor: 1.0,
            normalizedFeedbackArousal: 0.5,
            currentBreathingInhaleDuration: nil,
            currentBreathingExhaleDuration: nil,
            snapshotTimestamp: currentTime
        )
    }
    
    private func logArousalChange(from oldValue: CGFloat, to newValue: CGFloat, source: String) {
        print("USER AROUSAL changed from \(String(format: "%.2f", oldValue)) to \(String(format: "%.2f", newValue)) via \(source)")
    }
    
    private func logPerformance(_ performance: IdentificationPerformance) {
        print("PROXY: Identification task completed - Duration: \(String(format: "%.2f", performance.duration))s, Success: \(performance.success)")
        if let reactionTime = performance.reactionTime {
            print("PROXY: Reaction time: \(String(format: "%.2f", reactionTime))s")
        }
        print("PROXY: Accuracy: \(String(format: "%.1f", performance.accuracy * 100))% (\(performance.correctTaps)/\(performance.totalTaps) taps correct)")
    }
    
    private func updateArousalFromPerformance(_ performance: IdentificationPerformance) {
        // Simple heuristic (to be refined in future iterations):
        // - Very fast reaction time + high accuracy = lower arousal (calm, focused)
        // - Very fast reaction time + low accuracy = higher arousal (anxious, rushed)
        // - Very slow reaction time + low accuracy = higher arousal (overwhelmed)
        // - Very slow reaction time + high accuracy = lower arousal (distracted, bored)
        
        // Skip if no reaction time is available
        guard let reactionTime = performance.reactionTime else { 
            print("PROXY: No reaction time available, skipping arousal update")
            return 
        }
        
        // Log all performance data for debugging
        print("PROXY: Detailed performance data - Reaction time: \(String(format: "%.2f", reactionTime))s, Accuracy: \(String(format: "%.1f", performance.accuracy * 100))%, Success: \(performance.success)")
        print("PROXY: Tap metrics - Total: \(performance.totalTaps), Correct: \(performance.correctTaps), Incorrect: \(performance.incorrectTaps)")
        
        let oldArousal = _currentUserArousalLevel
        var arousalDelta: CGFloat = 0.0
        
        // Consider reaction time (scaled against some reasonable baseline)
        // Fast reaction < 0.5s, Slow reaction > 2.0s
        let isReactionFast = reactionTime < 0.5
        let isReactionSlow = reactionTime > 2.0
        
        // Consider accuracy
        let isAccuracyHigh = performance.accuracy > 0.8
        let isAccuracyLow = performance.accuracy < 0.5
        
        // Log classification
        print("PROXY: Performance classification - ReactionFast: \(isReactionFast), ReactionSlow: \(isReactionSlow), AccuracyHigh: \(isAccuracyHigh), AccuracyLow: \(isAccuracyLow)")
        
        // Simple decision matrix (very minimal first pass)
        if isReactionFast && isAccuracyHigh {
            // Fast + accurate = calm focus (lower arousal)
            arousalDelta = -0.02
            print("PROXY: Detected pattern: Fast + accurate = calm focus")
        } else if isReactionFast && isAccuracyLow {
            // Fast + inaccurate = anxious, rushed (higher arousal)
            arousalDelta = 0.03
            print("PROXY: Detected pattern: Fast + inaccurate = anxious, rushed")
        } else if isReactionSlow && isAccuracyLow {
            // Slow + inaccurate = overwhelmed (higher arousal)
            arousalDelta = 0.03
            print("PROXY: Detected pattern: Slow + inaccurate = overwhelmed")
        } else if isReactionSlow && isAccuracyHigh {
            // Slow + accurate = distracted or bored (complex but generally lower arousal)
            arousalDelta = -0.01
            print("PROXY: Detected pattern: Slow + accurate = distracted or bored")
        } else {
            // No clear pattern detected
            print("PROXY: No clear performance pattern detected")
        }
        
        // Apply the delta (with limits)
        if arousalDelta != 0 {
            _currentUserArousalLevel = min(1.0, max(0.0, _currentUserArousalLevel + arousalDelta))
            print("PROXY: Performance-based arousal adjustment: \(String(format: "%+.2f", arousalDelta)) (from \(String(format: "%.2f", oldArousal)) to \(String(format: "%.2f", _currentUserArousalLevel)))")
        } else {
            print("PROXY: No arousal adjustment made")
        }
    }
}
