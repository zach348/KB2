import Foundation
import CoreGraphics

/// A comprehensive data logger for collecting arousal-related data points with file persistence
class DataLogger {
    
    // MARK: - Properties
    
    static let shared = DataLogger()
    
    private var events: [[String: Any]] = []
    private var currentSessionId: String?
    private var sessionStartTime: TimeInterval?
    
    // MARK: - Initialization
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    // MARK: - Session Management
    
    /// Start a new logging session
    func startSession() {
        currentSessionId = UUID().uuidString
        sessionStartTime = Date().timeIntervalSince1970
        events.removeAll()
        
        let event: [String: Any] = [
            "type": "session_start",
            "timestamp": sessionStartTime!,
            "session_id": currentSessionId!
        ]
        events.append(event)
        print("DATA_LOG: Session started - ID: \(currentSessionId!)")
    }
    
    /// End the current session and save to file
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
        
        saveSessionToFile()
        
        // Reset session state
        currentSessionId = nil
        sessionStartTime = nil
        events.removeAll()
        
        print("DATA_LOG: Session ended - ID: \(sessionId)")
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
}
