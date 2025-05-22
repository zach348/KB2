import Foundation
import CoreGraphics

/// A simple data logger for collecting arousal-related data points
class DataLogger {
    
    // MARK: - Properties
    
    static let shared = DataLogger()
    
    private var events: [[String: Any]] = []
    
    // MARK: - Initialization
    
    private init() {
        // Private initializer for singleton pattern
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
} 