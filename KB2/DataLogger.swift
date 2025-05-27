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
