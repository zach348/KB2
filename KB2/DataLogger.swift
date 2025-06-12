import Foundation
import CoreGraphics
import Network
import Combine

/// A comprehensive data logger for collecting arousal-related data points with file persistence
class DataLogger {
    
    // MARK: - Properties
    
    static let shared = DataLogger()
    
    private var events: [[String: Any]] = []
    private var currentSessionId: String?
    private var sessionStartTime: TimeInterval?
    private var userId: String?
    
    // Real-time streaming properties
    private var isStreamingEnabled: Bool = false
    private var streamingBuffer: [[String: Any]] = []
    private var streamingTimer: Timer?
    private var streamingInterval: TimeInterval = 1.0 // Stream every second
    private var maxBufferSize: Int = 100
    
    // Network connectivity
    private var networkMonitor: NWPathMonitor?
    private var networkQueue: DispatchQueue?
    private var isNetworkAvailable: Bool = false
    
    // Cloud export configuration
    private var cloudEndpointURL: URL?
    private var cloudAPIKey: String?
    private var cloudUploadQueue: [URL] = []
    private var isCloudExportEnabled: Bool = false
    
    // Event subscribers for real-time data distribution
    private var eventSubscribers: [(([String: Any]) -> Void)] = []
    private let subscriberQueue = DispatchQueue(label: "datalogger.subscribers", qos: .utility)
    
    // MARK: - Initialization
    
    private init() {
        // Private initializer for singleton pattern
        // Ensure the logger starts in a clean state.
        events.removeAll()
        
        // Fetch the persistent user ID when the logger is first created.
        self.userId = UserIDManager.getUserId()
    }
    
    // MARK: - Session Management
    
    /// Start a new logging session
    func startSession() {
        // If a session is already active, end it before starting a new one.
        if currentSessionId != nil {
            print("DATA_LOG: Warning - A new session is being started while another is active. Ending the previous session first.")
            endSession()
        }
        
        // Now, clear the events for the new session. This is the only place events should be cleared before a session starts.
        events.removeAll()
        
        currentSessionId = UUID().uuidString
        sessionStartTime = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "session_start",
            "timestamp": sessionStartTime!,
            "session_id": currentSessionId!
        ]
        events.append(event)
        print("DATA_LOG: Session started - ID: \(currentSessionId!)")
    }
    
    /// End the current session, save to file, and upload to the cloud.
    func endSession() {
        guard let sessionId = currentSessionId else {
            print("DATA_LOG: Warning - No active session to end")
            return
        }
        
        let timestamp = Date().timeIntervalSince1970
        let event: [String: Any] = [
            "type": "session_end",
            "timestamp": timestamp,
            "session_id": sessionId
        ]
        events.append(event)
        
        // Save a local copy first
        saveSessionToFile()
        
        // Attempt to upload the session data to the cloud
        uploadCurrentSessionToCloud { success, error in
            if success {
                print("DATA_LOG: Cloud upload successful for session \(sessionId).")
            } else {
                // If the upload fails, the data is still saved locally.
                // The syncAllSessionsToCloud() method could be used later to retry.
                print("DATA_LOG: Cloud upload failed for session \(sessionId): \(error ?? "Unknown error")")
            }
        }
        
        // Reset session state for the next run
        currentSessionId = nil
        sessionStartTime = nil
        events.removeAll()
        
        print("DATA_LOG: Session ended and processed - ID: \(sessionId)")
    }
    
    // MARK: - Public Methods
    
    /// Log a self-report event
    func logSelfReport(arousalLevel: CGFloat, phase: String) {
        let timestamp = Date().timeIntervalSince1970
        let event: [String: Any] = [
            "type": "self_report",
            "timestamp": timestamp,
            "arousal_level": arousalLevel,
            "phase": phase
        ]
        
        events.append(event)
        addToStreamingBuffer(event)
        print("DATA_LOG: Self-report (\(phase)) - Arousal Level: \(String(format: "%.2f", arousalLevel))")
    }
    
    /// Log game state transition
    func logStateTransition(from oldState: String, to newState: String) {
        let timestamp = Date().timeIntervalSince1970
        let event: [String: Any] = [
            "type": "state_transition",
            "timestamp": timestamp,
            "old_state": oldState,
            "new_state": newState
        ]
        
        events.append(event)
        print("DATA_LOG: State transition from \(oldState) to \(newState)")
    }
    
    /// Log a tap event with timing and accuracy information
    func logTapEvent(isCorrect: Bool, reactionTime: TimeInterval, targetPosition: CGPoint, tapPosition: CGPoint, ballId: String? = nil) {
        let timestamp = Date().timeIntervalSince1970
        let accuracy = calculateTapAccuracy(target: targetPosition, tap: tapPosition)
        
        let event: [String: Any] = [
            "type": "tap_event",
            "timestamp": timestamp,
            "is_correct": isCorrect,
            "reaction_time": reactionTime,
            "target_position": ["x": targetPosition.x, "y": targetPosition.y],
            "tap_position": ["x": tapPosition.x, "y": tapPosition.y],
            "tap_accuracy": accuracy,
            "ball_id": ballId ?? "unknown"
        ]
        
        events.append(event)
        addToStreamingBuffer(event)
        print("DATA_LOG: Tap event - Correct: \(isCorrect), RT: \(String(format: "%.3f", reactionTime))s, Accuracy: \(String(format: "%.2f", accuracy))px")
    }
    
    /// Log game performance metrics
    func logGamePerformance(score: Int, streak: Int, difficultyLevel: Double, targetsHit: Int, targetsMissed: Int, currentPhase: String) {
        let timestamp = Date().timeIntervalSince1970
        let hitRate = targetsHit + targetsMissed > 0 ? Double(targetsHit) / Double(targetsHit + targetsMissed) : 0.0
        
        let event: [String: Any] = [
            "type": "game_performance",
            "timestamp": timestamp,
            "score": score,
            "streak": streak,
            "difficulty_level": difficultyLevel,
            "targets_hit": targetsHit,
            "targets_missed": targetsMissed,
            "hit_rate": hitRate,
            "current_phase": currentPhase
        ]
        
        events.append(event)
        print("DATA_LOG: Game performance - Score: \(score), Streak: \(streak), Hit Rate: \(String(format: "%.1f", hitRate * 100))%")
    }
    
    /// Log audio feedback events
    func logAudioFeedback(feedbackType: String, soundFile: String, volume: Float = 1.0, context: String = "") {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "audio_feedback",
            "timestamp": timestamp,
            "feedback_type": feedbackType,
            "sound_file": soundFile,
            "volume": volume,
            "context": context
        ]
        
        events.append(event)
        print("DATA_LOG: Audio feedback - Type: \(feedbackType), Sound: \(soundFile)")
    }
    
    /// Log difficulty adjustment events
    func logDifficultyAdjustment(oldDifficulty: Double, newDifficulty: Double, reason: String, performanceMetric: Double? = nil) {
        let timestamp = Date().timeIntervalSince1970
        
        var event: [String: Any] = [
            "type": "difficulty_adjustment",
            "timestamp": timestamp,
            "old_difficulty": oldDifficulty,
            "new_difficulty": newDifficulty,
            "adjustment_reason": reason
        ]
        
        if let metric = performanceMetric {
            event["performance_metric"] = metric
        }
        
        events.append(event)
        print("DATA_LOG: Difficulty adjusted - \(String(format: "%.2f", oldDifficulty)) → \(String(format: "%.2f", newDifficulty)) (\(reason))")
    }
    
    /// Log EMA (Ecological Momentary Assessment) responses
    func logEMAResponse(questionId: String, questionText: String, response: Any, responseType: String, completionTime: TimeInterval, context: String = "") {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "ema_response",
            "timestamp": timestamp,
            "question_id": questionId,
            "question_text": questionText,
            "response": response,
            "response_type": responseType,
            "completion_time": completionTime,
            "context": context
        ]
        
        events.append(event)
        print("DATA_LOG: EMA response - \(questionId): \(response) (\(String(format: "%.2f", completionTime))s)")
    }
    
    /// Log IMU (Inertial Measurement Unit) sensor data
    func logIMUData(accelerometerX: Double, accelerometerY: Double, accelerometerZ: Double, 
                   gyroscopeX: Double, gyroscopeY: Double, gyroscopeZ: Double,
                   magnetometerX: Double? = nil, magnetometerY: Double? = nil, magnetometerZ: Double? = nil,
                   attitude: [String: Double]? = nil) {
        let timestamp = Date().timeIntervalSince1970
        
        var event: [String: Any] = [
            "type": "imu_data",
            "timestamp": timestamp,
            "accelerometer": [
                "x": accelerometerX,
                "y": accelerometerY,
                "z": accelerometerZ
            ],
            "gyroscope": [
                "x": gyroscopeX,
                "y": gyroscopeY,
                "z": gyroscopeZ
            ]
        ]
        
        if let magX = magnetometerX, let magY = magnetometerY, let magZ = magnetometerZ {
            event["magnetometer"] = [
                "x": magX,
                "y": magY,
                "z": magZ
            ]
        }
        
        if let attitudeData = attitude {
            event["attitude"] = attitudeData
        }
        
        events.append(event)
        // Note: IMU logging typically doesn't print to console due to high frequency
    }
    
    /// Log session configuration and metadata
    func logSessionConfiguration(participantId: String, studyCondition: String, configuration: [String: Any]) {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "session_configuration",
            "timestamp": timestamp,
            "participant_id": participantId,
            "study_condition": studyCondition,
            "configuration": configuration
        ]
        
        events.append(event)
        print("DATA_LOG: Session configured - Participant: \(participantId), Condition: \(studyCondition)")
    }
    
    /// Log physiological data (heart rate, skin conductance, etc.)
    func logPhysiologicalData(dataType: String, value: Double, unit: String, sensorId: String? = nil, quality: String? = nil) {
        let timestamp = Date().timeIntervalSince1970
        
        var event: [String: Any] = [
            "type": "physiological_data",
            "timestamp": timestamp,
            "data_type": dataType,
            "value": value,
            "unit": unit
        ]
        
        if let sensor = sensorId {
            event["sensor_id"] = sensor
        }
        
        if let qualityMeasure = quality {
            event["quality"] = qualityMeasure
        }
        
        events.append(event)
        print("DATA_LOG: Physiological data - \(dataType): \(String(format: "%.2f", value)) \(unit)")
    }
    
    /// Log arousal estimation from various sources
    func logArousalEstimation(estimatedArousal: Double, source: String, confidence: Double? = nil, features: [String: Double]? = nil) {
        let timestamp = Date().timeIntervalSince1970
        
        var event: [String: Any] = [
            "type": "arousal_estimation",
            "timestamp": timestamp,
            "estimated_arousal": estimatedArousal,
            "estimation_source": source
        ]
        
        if let confidenceLevel = confidence {
            event["confidence"] = confidenceLevel
        }
        
        if let featureVector = features {
            event["features"] = featureVector
        }
        
        events.append(event)
        print("DATA_LOG: Arousal estimated - \(String(format: "%.3f", estimatedArousal)) from \(source)")
    }
    
    /// Log breathing pattern change events with detailed duration and arousal information
    func logBreathingPatternChange(
        oldInhaleDuration: Double, newInhaleDuration: Double,
        oldExhaleDuration: Double, newExhaleDuration: Double,
        oldHoldAfterInhaleDuration: Double, newHoldAfterInhaleDuration: Double,
        oldHoldAfterExhaleDuration: Double, newHoldAfterExhaleDuration: Double,
        arousalLevel: Double,
        normalizedBreathingArousal: Double
    ) {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "breathing_pattern_change",
            "timestamp": timestamp,
            "inhale_duration": [
                "old": oldInhaleDuration,
                "new": newInhaleDuration
            ],
            "exhale_duration": [
                "old": oldExhaleDuration,
                "new": newExhaleDuration
            ],
            "hold_after_inhale_duration": [
                "old": oldHoldAfterInhaleDuration,
                "new": newHoldAfterInhaleDuration
            ],
            "hold_after_exhale_duration": [
                "old": oldHoldAfterExhaleDuration,
                "new": newHoldAfterExhaleDuration
            ],
            "arousal_level": arousalLevel,
            "normalized_breathing_arousal": normalizedBreathingArousal
        ]
        
        events.append(event)
        addToStreamingBuffer(event)
        
        print("DATA_LOG: Breathing pattern change - Inhale: \(String(format: "%.2f", oldInhaleDuration))s -> \(String(format: "%.2f", newInhaleDuration))s, HoldInhale: \(String(format: "%.2f", oldHoldAfterInhaleDuration))s -> \(String(format: "%.2f", newHoldAfterInhaleDuration))s, Exhale: \(String(format: "%.2f", oldExhaleDuration))s -> \(String(format: "%.2f", newExhaleDuration))s, HoldExhale: \(String(format: "%.2f", oldHoldAfterExhaleDuration))s -> \(String(format: "%.2f", newHoldAfterExhaleDuration))s. Arousal: \(String(format: "%.2f", arousalLevel)), NormBreathingArousal: \(String(format: "%.2f", normalizedBreathingArousal))")
    }

    /// Log system and user arousal levels at a specific phase
    func logArousalLevels(systemArousal: CGFloat, userArousal: CGFloat?, phase: String) {
        let timestamp = Date().timeIntervalSince1970
        var event: [String: Any] = [
            "type": "arousal_levels",
            "timestamp": timestamp,
            "system_arousal": systemArousal,
            "phase": phase
        ]
        if let uArousal = userArousal {
            event["user_arousal"] = uArousal
        }
        
        events.append(event)
        addToStreamingBuffer(event)
        
        var logMessage = "DATA_LOG: Arousal Levels (\(phase)) - System: \(String(format: "%.2f", systemArousal))"
        if let uArousal = userArousal {
            logMessage += ", User: \(String(format: "%.2f", uArousal))"
        }
        print(logMessage)
    }
    
    // MARK: - Enhanced Data Structures (Kalibrate Implementation)
    
    /// Log enhanced identification performance data with comprehensive metrics
    func logEnhancedIdentificationPerformance(
        startTime: TimeInterval,
        endTime: TimeInterval,
        success: Bool,
        totalTaps: Int,
        correctTaps: Int,
        incorrectTaps: Int,
        reactionTime: TimeInterval?,
        tapEvents: [[String: Any]],
        taskStateSnapshot: [String: Any]
    ) {
        let timestamp = Date().timeIntervalSince1970
        let duration = endTime - startTime
        let accuracy = totalTaps > 0 ? Double(correctTaps) / Double(totalTaps) : 0.0
        
        let event: [String: Any] = [
            "type": "enhanced_identification_performance",
            "timestamp": timestamp,
            "start_time": startTime,
            "end_time": endTime,
            "duration": duration,
            "success": success,
            "total_taps": totalTaps,
            "correct_taps": correctTaps,
            "incorrect_taps": incorrectTaps,
            "accuracy": accuracy,
            "reaction_time": reactionTime as Any,
            "tap_events": tapEvents,
            "task_state_snapshot": taskStateSnapshot
        ]
        
        events.append(event)
        addToStreamingBuffer(event)
        
        print("DATA_LOG: Enhanced ID performance - Duration: \(String(format: "%.2f", duration))s, Success: \(success), Accuracy: \(String(format: "%.1f", accuracy * 100))%")
        if let rt = reactionTime {
            print("DATA_LOG: - Reaction time: \(String(format: "%.3f", rt))s, Taps: \(totalTaps), Events: \(tapEvents.count)")
        }
    }
    
    /// Log detailed tap event with comprehensive context
    func logDetailedTapEvent(
        timestamp: TimeInterval,
        tapLocation: CGPoint,
        tappedElementID: String?,
        wasCorrect: Bool,
        ballPositions: [String: CGPoint],
        targetBallIDs: Set<String>,
        distractorBallIDs: Set<String>,
        reactionTimeFromTaskStart: TimeInterval? = nil,
        gameContext: [String: Any] = [:],
        tapDuration: TimeInterval? = nil
    ) {
        var event: [String: Any] = [
            "type": "detailed_tap_event",
            "timestamp": timestamp,
            "tap_location": ["x": tapLocation.x, "y": tapLocation.y],
            "tapped_element_id": tappedElementID as Any,
            "was_correct": wasCorrect,
            "ball_positions": ballPositions.mapValues { ["x": $0.x, "y": $0.y] },
            "target_ball_ids": Array(targetBallIDs),
            "distractor_ball_ids": Array(distractorBallIDs),
            "reaction_time_from_task_start": reactionTimeFromTaskStart as Any,
            "game_context": gameContext
        ]
        
        // Add tap duration if available
        if let duration = tapDuration {
            event["tap_duration"] = duration
        }
        
        events.append(event)
        addToStreamingBuffer(event)
        
        print("DATA_LOG: Detailed tap - Correct: \(wasCorrect), Element: \(tappedElementID ?? "none"), Targets: \(targetBallIDs.count), Distractors: \(distractorBallIDs.count)")
    }
    
    /// Log comprehensive dynamic task state snapshot
    func logDynamicTaskStateSnapshot(
        currentArousalLevel: CGFloat,
        normalizedTrackingArousal: CGFloat,
        targetCount: Int,
        targetMeanSpeed: CGFloat,
        targetSpeedSD: CGFloat,
        identificationDuration: TimeInterval,
        minShiftInterval: TimeInterval,
        maxShiftInterval: TimeInterval,
        minIDInterval: TimeInterval,
        maxIDInterval: TimeInterval,
        timerFrequency: Double,
        visualPulseDuration: TimeInterval,
        activeTargetColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        activeDistractorColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        targetAudioFrequency: Float,
        amplitude: Float?,
        lastFlashColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)?,
        lastNumberOfFlashes: Int?,
        lastFlashDuration: TimeInterval?,
        flashSpeedFactor: CGFloat,
        normalizedFeedbackArousal: CGFloat,
        breathingInhaleDuration: TimeInterval?,
        breathingExhaleDuration: TimeInterval?,
        additionalContext: [String: Any] = [:]
    ) {
        let timestamp = Date().timeIntervalSince1970
        
        var event: [String: Any] = [
            "type": "dynamic_task_state_snapshot",
            "timestamp": timestamp,
            "snapshot_timestamp": timestamp, // When this snapshot was captured
            "arousal_levels": [
                "current": currentArousalLevel,
                "normalized_tracking": normalizedTrackingArousal,
                "normalized_feedback": normalizedFeedbackArousal
            ],
            "target_parameters": [
                "count": targetCount,
                "mean_speed": targetMeanSpeed,
                "speed_sd": targetSpeedSD
            ],
            "timing_parameters": [
                "identification_duration": identificationDuration,
                "min_shift_interval": minShiftInterval,
                "max_shift_interval": maxShiftInterval,
                "min_id_interval": minIDInterval,
                "max_id_interval": maxIDInterval,
                "timer_frequency": timerFrequency,
                "visual_pulse_duration": visualPulseDuration
            ],
            "color_parameters": [
                "active_target_color": [
                    "r": activeTargetColor.r,
                    "g": activeTargetColor.g,
                    "b": activeTargetColor.b,
                    "a": activeTargetColor.a
                ],
                "active_distractor_color": [
                    "r": activeDistractorColor.r,
                    "g": activeDistractorColor.g,
                    "b": activeDistractorColor.b,
                    "a": activeDistractorColor.a
                ]
            ],
            "audio_parameters": [
                "target_frequency": targetAudioFrequency,
                "amplitude": amplitude as Any
            ],
            "flash_parameters": [
                "speed_factor": flashSpeedFactor,
                "last_number_of_flashes": lastNumberOfFlashes as Any,
                "last_flash_duration": lastFlashDuration as Any
            ],
            "additional_context": additionalContext
        ]
        
        // Add optional flash color if provided
        if let flashColor = lastFlashColor {
            event["flash_parameters"] = (event["flash_parameters"] as! [String: Any]).merging([
                "last_flash_color": [
                    "r": flashColor.r,
                    "g": flashColor.g,
                    "b": flashColor.b,
                    "a": flashColor.a
                ]
            ]) { _, new in new }
        }
        
        // Add breathing parameters if provided
        if let inhale = breathingInhaleDuration, let exhale = breathingExhaleDuration {
            event["breathing_parameters"] = [
                "inhale_duration": inhale,
                "exhale_duration": exhale
            ]
        }
        
        events.append(event)
        addToStreamingBuffer(event)
        
        print("DATA_LOG: Task state snapshot - Arousal: \(String(format: "%.2f", currentArousalLevel)), Targets: \(targetCount), Speed: \(String(format: "%.1f", targetMeanSpeed))", "Active TC: \(activeTargetColor), DC: \(activeDistractorColor)")
    }
    
    /// Log session context information for comprehensive session analysis
    func logSessionContext(
        sessionStartTime: TimeInterval,
        timeOfDay: String,
        dayOfWeek: String,
        initialArousalLevel: CGFloat,
        sessionDuration: TimeInterval,
        sessionProfile: String,
        participantMetadata: [String: Any] = [:],
        environmentalFactors: [String: Any] = [:]
    ) {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "session_context",
            "timestamp": timestamp,
            "session_start_time": sessionStartTime,
            "time_of_day": timeOfDay,
            "day_of_week": dayOfWeek,
            "initial_arousal_level": initialArousalLevel,
            "session_duration": sessionDuration,
            "session_profile": sessionProfile,
            "participant_metadata": participantMetadata,
            "environmental_factors": environmentalFactors
        ]
        
        events.append(event)
        
        print("DATA_LOG: Session context - Start: \(timeOfDay) (\(dayOfWeek)), Duration: \(String(format: "%.1f", sessionDuration))s, Profile: \(sessionProfile)")
        print("DATA_LOG: - Initial arousal: \(String(format: "%.2f", initialArousalLevel))")
    }
    
    /// Log performance history data for trend analysis
    func logPerformanceHistory(performanceRecords: [[String: Any]], analysisContext: [String: Any] = [:]) {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "performance_history",
            "timestamp": timestamp,
            "record_count": performanceRecords.count,
            "performance_records": performanceRecords,
            "analysis_context": analysisContext
        ]
        
        events.append(event)
        
        print("DATA_LOG: Performance history - \(performanceRecords.count) records logged")
    }
    
    /// Log arousal estimation data with enhanced context from ArousalEstimator
    func logEnhancedArousalData(
        currentLevel: CGFloat,
        historyCount: Int,
        source: String = "arousal_estimator",
        performanceMetrics: [String: Any] = [:],
        metadata: [String: Any] = [:]
    ) {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "enhanced_arousal_data",
            "timestamp": timestamp,
            "current_level": currentLevel,
            "history_count": historyCount,
            "source": source,
            "performance_metrics": performanceMetrics,
            "metadata": metadata
        ]
        
        events.append(event)
        addToStreamingBuffer(event)
        
        print("DATA_LOG: Enhanced arousal data - Level: \(String(format: "%.3f", currentLevel)), History: \(historyCount) records")
    }
    
    /// Log custom events with flexible structure
    func logCustomEvent(eventType: String, data: [String: Any], description: String = "") {
        let timestamp = Date().timeIntervalSince1970
        
        var event: [String: Any] = [
            "type": "custom_event",
            "timestamp": timestamp,
            "event_type": eventType,
            "data": data
        ]
        
        if !description.isEmpty {
            event["description"] = description
        }
        
        events.append(event)
        print("DATA_LOG: Custom event - \(eventType): \(description)")
    }
    
    /// Print a summary of collected data
    func printSummary() {
        print("DATA_LOG: Summary of \(events.count) events collected")
        
        // Group events by type
        var eventCounts: [String: Int] = [:]
        for event in events {
            guard let type = event["type"] as? String else { continue }
            eventCounts[type] = (eventCounts[type] ?? 0) + 1
        }
        
        // Print count by type
        for (type, count) in eventCounts {
            print("DATA_LOG: - \(type): \(count) events")
        }
    }
    
    // MARK: - Data Export and Analysis
    
    /// Export current session data as CSV string
    func exportAsCSV() -> String {
        var csvLines: [String] = []
        
        // CSV Header
        csvLines.append("timestamp,session_id,event_type,data")
        
        // Data rows
        for event in events {
            let timestamp = event["timestamp"] as? TimeInterval ?? 0
            let sessionId = currentSessionId ?? "unknown"
            let eventType = event["type"] as? String ?? "unknown"
            
            // Convert event data to JSON string for CSV
            if let jsonData = try? JSONSerialization.data(withJSONObject: event, options: .fragmentsAllowed),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let escapedJson = jsonString.replacingOccurrences(of: "\"", with: "\"\"")
                csvLines.append("\(timestamp),\(sessionId),\(eventType),\"\(escapedJson)\"")
            }
        }
        
        return csvLines.joined(separator: "\n")
    }
    
    /// Export current session data as JSON string
    func exportAsJSON() -> String? {
        let exportData: [String: Any] = [
            "user_id": self.userId ?? "unknown",
            "session_id": currentSessionId ?? "unknown",
            "export_timestamp": Date().timeIntervalSince1970,
            "event_count": events.count,
            "events": events
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("DATA_LOG: Error exporting data as JSON")
            return nil
        }
        
        return jsonString
    }
    
    /// Get data summary statistics
    func getDataSummary() -> [String: Any] {
        guard !events.isEmpty else {
            return ["event_count": 0, "session_duration": 0]
        }
        
        // Calculate session duration
        let timestamps = events.compactMap { $0["timestamp"] as? TimeInterval }
        let sessionDuration = timestamps.isEmpty ? 0 : (timestamps.max()! - timestamps.min()!)
        
        // Count events by type
        var eventCounts: [String: Int] = [:]
        for event in events {
            if let type = event["type"] as? String {
                eventCounts[type] = (eventCounts[type] ?? 0) + 1
            }
        }
        
        // Calculate data rate (events per second)
        let dataRate = sessionDuration > 0 ? Double(events.count) / sessionDuration : 0
        
        return [
            "session_id": currentSessionId ?? "unknown",
            "event_count": events.count,
            "session_duration": sessionDuration,
            "data_rate_eps": dataRate,
            "event_types": eventCounts,
            "first_timestamp": timestamps.min() ?? 0,
            "last_timestamp": timestamps.max() ?? 0
        ]
    }
    
    // MARK: - Batch Operations
    
    /// Log multiple events at once for high-frequency data
    func logBatchEvents(_ batchEvents: [[String: Any]]) {
        events.append(contentsOf: batchEvents)
        print("DATA_LOG: Batch logged \(batchEvents.count) events")
    }
    
    /// Create a batch event for efficient logging
    func createBatchEvent(type: String, timestamp: TimeInterval? = nil, data: [String: Any]) -> [String: Any] {
        var event = data
        event["type"] = type
        event["timestamp"] = timestamp ?? Date().timeIntervalSince1970
        return event
    }
    
    /// Log high-frequency IMU data in batches
    func logIMUBatch(_ readings: [(timestamp: TimeInterval, accel: (x: Double, y: Double, z: Double), gyro: (x: Double, y: Double, z: Double))]) {
        let batchEvents = readings.map { reading in
            createBatchEvent(
                type: "imu_data",
                timestamp: reading.timestamp,
                data: [
                    "accelerometer": [
                        "x": reading.accel.x,
                        "y": reading.accel.y,
                        "z": reading.accel.z
                    ],
                    "gyroscope": [
                        "x": reading.gyro.x,
                        "y": reading.gyro.y,
                        "z": reading.gyro.z
                    ]
                ]
            )
        }
        
        logBatchEvents(batchEvents)
    }
    
    // MARK: - Data Validation and Integrity
    
    /// Validate data integrity and report issues
    func validateDataIntegrity() -> [String] {
        var issues: [String] = []
        
        // Check for missing timestamps
        let eventsWithoutTimestamp = events.filter { $0["timestamp"] == nil }
        if !eventsWithoutTimestamp.isEmpty {
            issues.append("Found \(eventsWithoutTimestamp.count) events without timestamps")
        }
        
        // Check for missing event types
        let eventsWithoutType = events.filter { $0["type"] == nil }
        if !eventsWithoutType.isEmpty {
            issues.append("Found \(eventsWithoutType.count) events without type")
        }
        
        // Check timestamp ordering
        let timestamps = events.compactMap { $0["timestamp"] as? TimeInterval }
        let sortedTimestamps = timestamps.sorted()
        if timestamps != sortedTimestamps {
            issues.append("Events are not in chronological order")
        }
        
        // Check for duplicate events (same timestamp and type)
        var seenEvents: Set<String> = []
        for event in events {
            if let timestamp = event["timestamp"] as? TimeInterval,
               let type = event["type"] as? String {
                let key = "\(timestamp)_\(type)"
                if seenEvents.contains(key) {
                    issues.append("Found duplicate event: \(type) at \(timestamp)")
                }
                seenEvents.insert(key)
            }
        }
        
        if issues.isEmpty {
            print("DATA_LOG: Data integrity validation passed")
        } else {
            print("DATA_LOG: Data integrity issues found: \(issues.count)")
            for issue in issues {
                print("DATA_LOG: - \(issue)")
            }
        }
        
        return issues
    }
    
    /// Get memory usage statistics
    func getMemoryUsage() -> [String: Any] {
        let eventCount = events.count
        let estimatedSize = events.reduce(0) { total, event in
            // Rough estimation of memory usage per event
            return total + MemoryLayout.size(ofValue: event) + 200 // Base overhead
        }
        
        return [
            "event_count": eventCount,
            "estimated_memory_bytes": estimatedSize,
            "estimated_memory_mb": Double(estimatedSize) / (1024 * 1024)
        ]
    }
    
    // MARK: - Integration Utilities
    
    /// Connect with GameScene for automatic event logging
    func setupGameSceneIntegration() {
        // This would be called to set up automatic logging hooks
        print("DATA_LOG: Game scene integration ready")
    }
    
    /// Log game state transition with automatic context capture
    func logGameStateWithContext(from oldState: String, to newState: String, gameContext: [String: Any] = [:]) {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "game_state_transition",
            "timestamp": timestamp,
            "old_state": oldState,
            "new_state": newState,
            "game_context": gameContext
        ]
        
        events.append(event)
        print("DATA_LOG: Game state: \(oldState) → \(newState)")
    }
    
    /// Create a timestamped annotation for marking important events
    func logAnnotation(_ text: String, category: String = "general") {
        let timestamp = Date().timeIntervalSince1970
        
        let event: [String: Any] = [
            "type": "annotation",
            "timestamp": timestamp,
            "text": text,
            "category": category
        ]
        
        events.append(event)
        print("DATA_LOG: Annotation [\(category)]: \(text)")
    }
    
    /// Log performance metrics with system context
    func logPerformanceMetrics(framerate: Double? = nil, memoryUsage: Double? = nil, cpuUsage: Double? = nil) {
        let timestamp = Date().timeIntervalSince1970
        
        var event: [String: Any] = [
            "type": "performance_metrics",
            "timestamp": timestamp
        ]
        
        if let fps = framerate {
            event["framerate"] = fps
        }
        
        if let memory = memoryUsage {
            event["memory_usage_mb"] = memory
        }
        
        if let cpu = cpuUsage {
            event["cpu_usage_percent"] = cpu
        }
        
        events.append(event)
        print("DATA_LOG: Performance - FPS: \(framerate ?? 0), Memory: \(memoryUsage ?? 0)MB")
    }
    
    /// Get events filtered by type and time range
    func getFilteredEvents(types: [String]? = nil, fromTime: TimeInterval? = nil, toTime: TimeInterval? = nil) -> [[String: Any]] {
        return events.filter { event in
            // Filter by type if specified
            if let types = types,
               let eventType = event["type"] as? String,
               !types.contains(eventType) {
                return false
            }
            
            // Filter by time range if specified
            if let timestamp = event["timestamp"] as? TimeInterval {
                if let fromTime = fromTime, timestamp < fromTime {
                    return false
                }
                if let toTime = toTime, timestamp > toTime {
                    return false
                }
            }
            
            return true
        }
    }
    
    /// Clear old events to manage memory usage
    func clearEventsOlderThan(_ timeInterval: TimeInterval) {
        let cutoffTime = Date().timeIntervalSince1970 - timeInterval
        let initialCount = events.count
        
        events = events.filter { event in
            if let timestamp = event["timestamp"] as? TimeInterval {
                return timestamp >= cutoffTime
            }
            return true // Keep events without timestamps
        }
        
        let removedCount = initialCount - events.count
        if removedCount > 0 {
            print("DATA_LOG: Cleared \(removedCount) old events")
        }
    }
    
    // MARK: - Real-time Data Streaming
    
    /// Start real-time data streaming with configurable interval
    func startRealTimeStreaming(interval: TimeInterval = 1.0, bufferSize: Int = 100) {
        guard !isStreamingEnabled else {
            print("DATA_LOG: Real-time streaming already enabled")
            return
        }
        
        streamingInterval = interval
        maxBufferSize = bufferSize
        isStreamingEnabled = true
        streamingBuffer.removeAll()
        
        // Start periodic streaming timer
        streamingTimer = Timer.scheduledTimer(withTimeInterval: streamingInterval, repeats: true) { [weak self] _ in
            self?.flushStreamingBuffer()
        }
        
        print("DATA_LOG: Real-time streaming started - Interval: \(interval)s, Buffer: \(bufferSize)")
    }
    
    /// Stop real-time data streaming
    func stopRealTimeStreaming() {
        guard isStreamingEnabled else {
            print("DATA_LOG: Real-time streaming not active")
            return
        }
        
        streamingTimer?.invalidate()
        streamingTimer = nil
        isStreamingEnabled = false
        
        // Flush any remaining buffered events
        flushStreamingBuffer()
        
        print("DATA_LOG: Real-time streaming stopped")
    }
    
    /// Subscribe to real-time event notifications
    func subscribeToEvents(_ callback: @escaping ([String: Any]) -> Void) {
        subscriberQueue.async { [weak self] in
            self?.eventSubscribers.append(callback)
        }
        print("DATA_LOG: Event subscriber added")
    }
    
    /// Remove all event subscribers
    func clearEventSubscribers() {
        subscriberQueue.async { [weak self] in
            self?.eventSubscribers.removeAll()
        }
        print("DATA_LOG: All event subscribers cleared")
    }
    
    /// Flush current streaming buffer to subscribers
    private func flushStreamingBuffer() {
        guard !streamingBuffer.isEmpty else { return }
        
        let bufferCopy = streamingBuffer
        streamingBuffer.removeAll()
        
        subscriberQueue.async { [weak self] in
            guard let self = self else { return }
            for subscriber in self.eventSubscribers {
                for event in bufferCopy {
                    subscriber(event)
                }
            }
        }
        
        print("DATA_LOG: Streamed \(bufferCopy.count) events to \(eventSubscribers.count) subscribers")
    }
    
    /// Add event to streaming buffer and notify subscribers
    private func addToStreamingBuffer(_ event: [String: Any]) {
        guard isStreamingEnabled else { return }
        
        streamingBuffer.append(event)
        
        // Manage buffer size
        if streamingBuffer.count >= maxBufferSize {
            flushStreamingBuffer()
        }
    }
    
    // MARK: - Network Connectivity
    
    /// Start monitoring network connectivity for cloud features
    func startNetworkMonitoring() {
        networkQueue = DispatchQueue(label: "datalogger.network", qos: .utility)
        networkMonitor = NWPathMonitor()
        
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            let wasAvailable = self?.isNetworkAvailable ?? false
            self?.isNetworkAvailable = path.status == .satisfied
            
            if !wasAvailable && self?.isNetworkAvailable == true {
                print("DATA_LOG: Network connection restored")
                self?.processCloudUploadQueue()
            } else if wasAvailable && self?.isNetworkAvailable == false {
                print("DATA_LOG: Network connection lost")
            }
        }
        
        networkMonitor?.start(queue: networkQueue!)
        print("DATA_LOG: Network monitoring started")
    }
    
    /// Stop network monitoring
    func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
        networkQueue = nil
        isNetworkAvailable = false
        print("DATA_LOG: Network monitoring stopped")
    }
    
    /// Get current network connectivity status
    func getNetworkStatus() -> [String: Any] {
        return [
            "is_available": isNetworkAvailable,
            "cloud_export_enabled": isCloudExportEnabled,
            "upload_queue_size": cloudUploadQueue.count
        ]
    }
    
    // MARK: - Cloud Export and Sync
    
    /// Configure cloud export settings
    func configureCloudExport(endpointURL: String, apiKey: String) {
        guard let url = URL(string: endpointURL) else {
            print("DATA_LOG: Invalid cloud endpoint URL: \(endpointURL)")
            return
        }
        
        cloudEndpointURL = url
        cloudAPIKey = apiKey
        isCloudExportEnabled = true
        
        print("DATA_LOG: Cloud export configured - Endpoint: \(endpointURL)")
        
        // Process any queued uploads
        if isNetworkAvailable {
            processCloudUploadQueue()
        }
    }
    
    /// Disable cloud export functionality
    func disableCloudExport() {
        isCloudExportEnabled = false
        cloudEndpointURL = nil
        cloudAPIKey = nil
        cloudUploadQueue.removeAll()
        print("DATA_LOG: Cloud export disabled")
    }
    
    /// Upload session data to configured cloud endpoint
    func uploadToCloud(sessionFilePath: URL, completion: @escaping (Bool, String?) -> Void) {
        guard isCloudExportEnabled,
              let endpoint = cloudEndpointURL,
              let apiKey = cloudAPIKey else {
            completion(false, "Cloud export not properly configured")
            return
        }
        
        guard isNetworkAvailable else {
            // Queue for later upload
            cloudUploadQueue.append(sessionFilePath)
            completion(false, "Network unavailable - queued for upload")
            return
        }
        
        // Create upload request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let fileData = try Data(contentsOf: sessionFilePath)
            request.httpBody = fileData
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, "Upload error: \(error.localizedDescription)")
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                            print("DATA_LOG: Successfully uploaded \(sessionFilePath.lastPathComponent)")
                            completion(true, nil)
                        } else {
                            completion(false, "Server error: HTTP \(httpResponse.statusCode)")
                        }
                    } else {
                        completion(false, "Invalid server response")
                    }
                }
            }.resume()
            
        } catch {
            completion(false, "File read error: \(error.localizedDescription)")
        }
    }
    
    /// Upload current session data directly to the configured cloud endpoint.
    /// This method sends the in-memory event data without creating a temporary file.
    func uploadCurrentSessionToCloud(completion: @escaping (Bool, String?) -> Void) {
        guard isCloudExportEnabled,
              let endpoint = cloudEndpointURL,
              let apiKey = cloudAPIKey else {
            let message = "Cloud export not properly configured. Call configureCloudExport() from your app's startup sequence."
            print("DATA_LOG: \(message)")
            completion(false, message)
            return
        }

        guard currentSessionId != nil else {
            completion(false, "No active session to upload")
            return
        }

        // exportAsJSON() creates the JSON structure that includes the session_id and all events.
        guard let jsonString = exportAsJSON(), let jsonData = jsonString.data(using: .utf8) else {
            completion(false, "Failed to serialize session data to JSON.")
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, "Upload network error: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if (200...299).contains(httpResponse.statusCode) {
                        completion(true, nil)
                    } else {
                        var responseBody = "No response body"
                        if let data = data, let bodyString = String(data: data, encoding: .utf8) {
                            responseBody = bodyString
                        }
                        completion(false, "Server error: HTTP \(httpResponse.statusCode). Response: \(responseBody)")
                    }
                } else {
                    completion(false, "Invalid server response received.")
                }
            }
        }.resume()
    }
    
    /// Process queued cloud uploads when network becomes available
    private func processCloudUploadQueue() {
        guard isNetworkAvailable && isCloudExportEnabled else { return }
        
        let queueCopy = cloudUploadQueue
        cloudUploadQueue.removeAll()
        
        for fileURL in queueCopy {
            uploadToCloud(sessionFilePath: fileURL) { success, error in
                if !success {
                    print("DATA_LOG: Failed to upload queued file: \(error ?? "Unknown error")")
                    // Re-queue failed uploads
                    self.cloudUploadQueue.append(fileURL)
                }
            }
        }
        
        if !queueCopy.isEmpty {
            print("DATA_LOG: Processing \(queueCopy.count) queued cloud uploads")
        }
    }
    
    /// Get cloud sync statistics
    func getCloudSyncStats() -> [String: Any] {
        return [
            "cloud_enabled": isCloudExportEnabled,
            "endpoint_configured": cloudEndpointURL != nil,
            "api_key_configured": cloudAPIKey != nil,
            "upload_queue_size": cloudUploadQueue.count,
            "network_available": isNetworkAvailable
        ]
    }
    
    /// Force sync all local session files to cloud
    func syncAllSessionsToCloud(completion: @escaping (Int, Int, [String]) -> Void) {
        guard isCloudExportEnabled else {
            completion(0, 0, ["Cloud export not enabled"])
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var uploadedCount = 0
        var failedCount = 0
        var errors: [String] = []
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, 
                                                                     includingPropertiesForKeys: nil)
            let sessionFiles = fileURLs.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("kb2_session_") }
            
            let group = DispatchGroup()
            
            for fileURL in sessionFiles {
                group.enter()
                uploadToCloud(sessionFilePath: fileURL) { success, error in
                    if success {
                        uploadedCount += 1
                    } else {
                        failedCount += 1
                        if let error = error {
                            errors.append("\(fileURL.lastPathComponent): \(error)")
                        }
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completion(uploadedCount, failedCount, errors)
            }
            
        } catch {
            completion(0, 0, ["Failed to enumerate session files: \(error.localizedDescription)"])
        }
    }
    
    // MARK: - Private Methods
    
    /// Calculate the distance between target and tap positions
    private func calculateTapAccuracy(target: CGPoint, tap: CGPoint) -> CGFloat {
        let dx = target.x - tap.x
        let dy = target.y - tap.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Save current session events to a JSON file
    private func saveSessionToFile() {
        guard let sessionId = currentSessionId else { return }
        
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sessionFileName = "kb2_session_\(sessionId).json"
            let fileURL = documentsPath.appendingPathComponent(sessionFileName)
            
            let jsonData = try JSONSerialization.data(withJSONObject: events, options: .prettyPrinted)
            try jsonData.write(to: fileURL)
            
            print("DATA_LOG: Session data saved to \(sessionFileName)")
        } catch {
            print("DATA_LOG: Error saving session data: \(error)")
        }
    }

    // MARK: - Adaptive Difficulty Logging
    func logAdaptiveDifficultyStep(
        arousalLevel: CGFloat,
        performanceScore: CGFloat,
        normalizedKPIs: [KPIType: CGFloat], // KPIType is from GameConfiguration
        domValues: [DOMTargetType: CGFloat] // DOMTargetType is from GameConfiguration
    ) {
        let timestamp = Date().timeIntervalSince1970
        
        // Convert KPIType and DOMTargetType keys to strings for JSON serialization
        // Ensuring the correct global enums are used.
        let kpisAsString = Dictionary(uniqueKeysWithValues: normalizedKPIs.map { (key: KPIType, value: CGFloat) -> (String, CGFloat) in (String(describing: key), value) })
        let domsAsString = Dictionary(uniqueKeysWithValues: domValues.map { (key: DOMTargetType, value: CGFloat) -> (String, CGFloat) in (String(describing: key), value) })

        let event: [String: Any] = [
            "type": "adaptive_difficulty_step",
            "timestamp": timestamp,
            "arousal_level": arousalLevel,
            "performance_score": performanceScore,
            "normalized_kpis": kpisAsString,
            "dom_values": domsAsString
        ]
        
        events.append(event)
        addToStreamingBuffer(event)
        
        print("DATA_LOG: Adaptive Difficulty Step - Arousal: \(String(format: "%.2f", arousalLevel)), PerfScore: \(String(format: "%.2f", performanceScore))")
        // Consider logging more details if needed, e.g., specific DOM values
    }
}
