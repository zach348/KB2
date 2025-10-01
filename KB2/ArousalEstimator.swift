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
        let tapDuration: TimeInterval?        // time between touch down and touch up
    }
    
    /// Structure to store a comprehensive snapshot of all arousal-modulated game parameters
    struct DynamicTaskStateSnapshot {
        // Core arousal values
        let systemCurrentArousalLevel: CGFloat // Explicitly system's current
        let userCurrentArousalLevel: CGFloat?  // User's estimated current (optional)
        let normalizedTrackingArousal: CGFloat
        
        // Target and motion parameters
        let totalBallCount: Int               // Total number of balls in the game
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
        let currentBreathingHoldAfterInhaleDuration: TimeInterval?
        let currentBreathingExhaleDuration: TimeInterval?
        let currentBreathingHoldAfterExhaleDuration: TimeInterval?
        
        // Timestamp when this snapshot was taken
        let snapshotTimestamp: TimeInterval
    }
    
    /// Structure to store session context information
    struct SessionContext {
        let sessionStartTime: TimeInterval
        let timeOfDay: String        // e.g., "14:30:25"
        let dayOfWeek: String        // e.g., "Tuesday"
        let systemInitialArousalLevel: CGFloat  // System's starting arousal level
        let userInitialArousalLevel: CGFloat?   // User's estimated arousal at session start (optional)
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
    var recentPerformanceHistory: [IdentificationPerformance] = [] // Changed from private to internal (default)
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
        currentTapEvents.removeAll()
        currentTaskStateSnapshot = nil
        
        print("PROXY: Started tracking identification task at \(String(format: "%.2f", time))")
    }
    
    /// Set the initial task snapshot for the current identification task
    func setInitialTaskSnapshot(_ snapshot: DynamicTaskStateSnapshot) {
        currentTaskStateSnapshot = snapshot
        print("AROUSAL_ESTIMATOR: Task snapshot set - System arousal: \(String(format: "%.2f", snapshot.systemCurrentArousalLevel)), User arousal: \(snapshot.userCurrentArousalLevel.map { String(format: "%.2f", $0) } ?? "nil")")
        
        // Log comprehensive snapshot details to console for debugging
        print("DATA_LOG: Dynamic Task State Snapshot:")
        print("  - System Arousal: \(String(format: "%.3f", snapshot.systemCurrentArousalLevel))")
        print("  - User Arousal: \(snapshot.userCurrentArousalLevel.map { String(format: "%.3f", $0) } ?? "nil")")
        print("  - Normalized Tracking Arousal: \(String(format: "%.3f", snapshot.normalizedTrackingArousal))")
        print("  - Target Count: \(snapshot.currentTargetCount) / \(snapshot.totalBallCount)")
        print("  - Target Speed: \(String(format: "%.1f", snapshot.targetMeanSpeed)) ± \(String(format: "%.1f", snapshot.targetSpeedSD))")
        print("  - ID Duration: \(String(format: "%.2f", snapshot.currentIdentificationDuration))s")
        print("  - Shift Interval: \(String(format: "%.1f", snapshot.currentMinShiftInterval))-\(String(format: "%.1f", snapshot.currentMaxShiftInterval))s")
        print("  - ID Interval: \(String(format: "%.1f", snapshot.currentMinIDInterval))-\(String(format: "%.1f", snapshot.currentMaxIDInterval))s")
        print("  - Timer Freq: \(String(format: "%.2f", snapshot.currentTimerFrequency))Hz")
        print("  - Visual Pulse: \(String(format: "%.3f", snapshot.visualPulseDuration))s")
        print("  - Target Color: R:\(String(format: "%.2f", snapshot.activeTargetColor.r)) G:\(String(format: "%.2f", snapshot.activeTargetColor.g)) B:\(String(format: "%.2f", snapshot.activeTargetColor.b))")
        print("  - Distractor Color: R:\(String(format: "%.2f", snapshot.activeDistractorColor.r)) G:\(String(format: "%.2f", snapshot.activeDistractorColor.g)) B:\(String(format: "%.2f", snapshot.activeDistractorColor.b))")
        print("  - Audio Freq: \(String(format: "%.1f", snapshot.currentTargetAudioFrequency))Hz")
        if let amplitude = snapshot.currentAmplitude {
            print("  - Audio Amplitude: \(String(format: "%.3f", amplitude))")
        }
        print("  - Flash Speed Factor: \(String(format: "%.2f", snapshot.flashSpeedFactor))")
        if let flashCount = snapshot.lastNumberOfFlashes {
            print("  - Last Flash Count: \(flashCount)")
        }
        if let flashDuration = snapshot.lastFlashDuration {
            print("  - Last Flash Duration: \(String(format: "%.2f", flashDuration))s")
        }
        print("  - Normalized Feedback Arousal: \(String(format: "%.3f", snapshot.normalizedFeedbackArousal))")
        if let inhaleDuration = snapshot.currentBreathingInhaleDuration {
            print("  - Breathing Inhale: \(String(format: "%.2f", inhaleDuration))s")
        }
        if let holdAfterInhaleDuration = snapshot.currentBreathingHoldAfterInhaleDuration {
            print("  - Breathing Hold After Inhale: \(String(format: "%.2f", holdAfterInhaleDuration))s")
        }
        if let exhaleDuration = snapshot.currentBreathingExhaleDuration {
            print("  - Breathing Exhale: \(String(format: "%.2f", exhaleDuration))s")
        }
        if let holdAfterExhaleDuration = snapshot.currentBreathingHoldAfterExhaleDuration {
            print("  - Breathing Hold After Exhale: \(String(format: "%.2f", holdAfterExhaleDuration))s")
        }
        print("  - Snapshot Timestamp: \(String(format: "%.3f", snapshot.snapshotTimestamp))")
        
        // Log the complete snapshot to DataLogger for comprehensive data collection
        DataLogger.shared.logDynamicTaskStateSnapshot(
            currentArousalLevel: snapshot.systemCurrentArousalLevel,
            normalizedTrackingArousal: snapshot.normalizedTrackingArousal,
            targetCount: snapshot.currentTargetCount,
            targetMeanSpeed: snapshot.targetMeanSpeed,
            targetSpeedSD: snapshot.targetSpeedSD,
            identificationDuration: snapshot.currentIdentificationDuration,
            minShiftInterval: snapshot.currentMinShiftInterval,
            maxShiftInterval: snapshot.currentMaxShiftInterval,
            minIDInterval: snapshot.currentMinIDInterval,
            maxIDInterval: snapshot.currentMaxIDInterval,
            timerFrequency: snapshot.currentTimerFrequency,
            visualPulseDuration: snapshot.visualPulseDuration,
            activeTargetColor: snapshot.activeTargetColor,
            activeDistractorColor: snapshot.activeDistractorColor,
            targetAudioFrequency: snapshot.currentTargetAudioFrequency,
            amplitude: snapshot.currentAmplitude,
            lastFlashColor: snapshot.lastFlashColor,
            lastNumberOfFlashes: snapshot.lastNumberOfFlashes,
            lastFlashDuration: snapshot.lastFlashDuration,
            flashSpeedFactor: snapshot.flashSpeedFactor,
            normalizedFeedbackArousal: snapshot.normalizedFeedbackArousal,
            breathingInhaleDuration: snapshot.currentBreathingInhaleDuration,
            breathingExhaleDuration: snapshot.currentBreathingExhaleDuration,
            additionalContext: [
                "user_arousal_level": snapshot.userCurrentArousalLevel as Any,
                "total_ball_count": snapshot.totalBallCount,
                "breathing_hold_after_inhale_duration": snapshot.currentBreathingHoldAfterInhaleDuration as Any,
                "breathing_hold_after_exhale_duration": snapshot.currentBreathingHoldAfterExhaleDuration as Any
            ]
        )
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
    
    /// Record a detailed tap event with comprehensive context
    func recordDetailedTapEvent(
        timestamp: TimeInterval,
        tapLocation: CGPoint,
        tappedElementID: String?,
        wasCorrect: Bool,
        ballPositions: [String: CGPoint],
        targetBallIDs: Set<String>,
        distractorBallIDs: Set<String>,
        tapDuration: TimeInterval? = nil
    ) {
        let tapEvent = TapEventDetail(
            timestamp: timestamp,
            tapLocation: tapLocation,
            tappedElementID: tappedElementID,
            wasCorrect: wasCorrect,
            ballPositions: ballPositions,
            targetBallIDs: targetBallIDs,
            distractorBallIDs: distractorBallIDs,
            tapDuration: tapDuration
        )
        
        currentTapEvents.append(tapEvent)
        
        // Also call the simple recordTap for reaction time tracking
        recordTap(at: timestamp, wasCorrect: wasCorrect)
        
        print("AROUSAL_ESTIMATOR: Detailed tap recorded - Element: \(tappedElementID ?? "none"), Targets: \(targetBallIDs.count), Distractors: \(distractorBallIDs.count)")
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
        
        // Log comprehensive performance data
        print("AROUSAL_ESTIMATOR: Enhanced performance data - Duration: \(String(format: "%.2f", performance.duration))s, Success: \(performance.success), Taps: \(performance.tapEvents.count), RT: \(performance.reactionTime.map { String(format: "%.3f", $0) } ?? "nil")s")
        
        // Log enhanced performance data to DataLogger
        DataLogger.shared.logEnhancedIdentificationPerformance(
            startTime: performance.startTime,
            endTime: performance.endTime,
            success: performance.success,
            totalTaps: performance.totalTaps,
            correctTaps: performance.correctTaps,
            incorrectTaps: performance.incorrectTaps,
            reactionTime: performance.reactionTime,
            tapEvents: performance.tapEvents.map(convertTapEventToDict),
            taskStateSnapshot: convertSnapshotToDict(performance.taskStateSnapshot)
        )
        
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
    
    /// Convert TapEventDetail struct to dictionary for logging
    private func convertTapEventToDict(_ tapEvent: TapEventDetail) -> [String: Any] {
        var dict: [String: Any] = [
            "timestamp": tapEvent.timestamp,
            "tap_location": ["x": tapEvent.tapLocation.x, "y": tapEvent.tapLocation.y],
            "tapped_element_id": tapEvent.tappedElementID as Any,
            "was_correct": tapEvent.wasCorrect,
            "ball_positions": tapEvent.ballPositions.mapValues { ["x": $0.x, "y": $0.y] },
            "target_ball_ids": Array(tapEvent.targetBallIDs),
            "distractor_ball_ids": Array(tapEvent.distractorBallIDs)
        ]
        
        // Add tap duration if available
        if let duration = tapEvent.tapDuration {
            dict["tap_duration"] = duration
        }
        
        return dict
    }
    
    /// Convert DynamicTaskStateSnapshot struct to dictionary for logging
    private func convertSnapshotToDict(_ snapshot: DynamicTaskStateSnapshot) -> [String: Any] {
        var dict: [String: Any] = [
            "system_current_arousal_level": snapshot.systemCurrentArousalLevel,
            "user_current_arousal_level": snapshot.userCurrentArousalLevel as Any,
            "normalized_tracking_arousal": snapshot.normalizedTrackingArousal,
            "current_target_count": snapshot.currentTargetCount,
            "target_mean_speed": snapshot.targetMeanSpeed,
            "target_speed_sd": snapshot.targetSpeedSD,
            "current_identification_duration": snapshot.currentIdentificationDuration,
            "current_min_shift_interval": snapshot.currentMinShiftInterval,
            "current_max_shift_interval": snapshot.currentMaxShiftInterval,
            "current_min_id_interval": snapshot.currentMinIDInterval,
            "current_max_id_interval": snapshot.currentMaxIDInterval,
            "current_timer_frequency": snapshot.currentTimerFrequency,
            "visual_pulse_duration": snapshot.visualPulseDuration,
            "active_target_color": [
                "r": snapshot.activeTargetColor.r,
                "g": snapshot.activeTargetColor.g,
                "b": snapshot.activeTargetColor.b,
                "a": snapshot.activeTargetColor.a
            ],
            "active_distractor_color": [
                "r": snapshot.activeDistractorColor.r,
                "g": snapshot.activeDistractorColor.g,
                "b": snapshot.activeDistractorColor.b,
                "a": snapshot.activeDistractorColor.a
            ],
            "current_target_audio_frequency": snapshot.currentTargetAudioFrequency,
            "current_amplitude": snapshot.currentAmplitude as Any,
            "flash_speed_factor": snapshot.flashSpeedFactor,
            "normalized_feedback_arousal": snapshot.normalizedFeedbackArousal,
            "snapshot_timestamp": snapshot.snapshotTimestamp
        ]
        
        // Add optional flash parameters
        if let flashColor = snapshot.lastFlashColor {
            dict["last_flash_color"] = [
                "r": flashColor.r,
                "g": flashColor.g,
                "b": flashColor.b,
                "a": flashColor.a
            ]
        }
        if let flashCount = snapshot.lastNumberOfFlashes {
            dict["last_number_of_flashes"] = flashCount
        }
        if let flashDuration = snapshot.lastFlashDuration {
            dict["last_flash_duration"] = flashDuration
        }
        
        // Add optional breathing parameters (updated to include hold durations)
        if let inhaleDuration = snapshot.currentBreathingInhaleDuration,
           let holdAfterInhaleDuration = snapshot.currentBreathingHoldAfterInhaleDuration,
           let exhaleDuration = snapshot.currentBreathingExhaleDuration,
           let holdAfterExhaleDuration = snapshot.currentBreathingHoldAfterExhaleDuration {
            dict["current_breathing_inhale_duration"] = inhaleDuration
            dict["current_breathing_hold_after_inhale_duration"] = holdAfterInhaleDuration
            dict["current_breathing_exhale_duration"] = exhaleDuration
            dict["current_breathing_hold_after_exhale_duration"] = holdAfterExhaleDuration
        }
        
        return dict
    }
    
    /// Create an empty snapshot with default values as fallback
    private func createEmptySnapshot() -> DynamicTaskStateSnapshot {
        let currentTime = CACurrentMediaTime()
        return DynamicTaskStateSnapshot(
            systemCurrentArousalLevel: 0.5,
            userCurrentArousalLevel: _currentUserArousalLevel,
            normalizedTrackingArousal: 0.5,
            totalBallCount: 10,
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
            currentBreathingHoldAfterInhaleDuration: nil,
            currentBreathingExhaleDuration: nil,
            currentBreathingHoldAfterExhaleDuration: nil,
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
