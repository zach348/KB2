// Kalibrate/ADMPersistenceManager.swift
// Created: 6/21/2025
// Role: Manages persistence of ADM state across sessions

import Foundation
import QuartzCore

class ADMPersistenceManager {
    
    // MARK: - Properties
    
    private static let documentsDirectory = FileManager.default.urls(for: .documentDirectory, 
                                                                   in: .userDomainMask).first!
    private static let admStateDirectoryName = "ADMState"
    
    // MARK: - Public Methods
    
    /// Saves the ADM state for a specific user
    /// - Parameters:
    ///   - state: The persisted ADM state to save
    ///   - userId: The user ID to associate with this state
    static func saveState(_ state: PersistedADMState, for userId: String) {
        do {
            print("[ADMPersistenceManager] SAVE INITIATED")
            print("  ├─ User ID: \(userId)")
            print("  ├─ Performance history entries: \(state.performanceHistory.count)")
            print("  ├─ Last adaptation direction: \(state.lastAdaptationDirection)")
            print("  ├─ Direction stable count: \(state.directionStableCount)")
            print("  └─ Normalized positions: \(state.normalizedPositions.count) DOMs")
            
            // Create ADM state directory if it doesn't exist
            let admStateDirectory = documentsDirectory.appendingPathComponent(admStateDirectoryName)
            try FileManager.default.createDirectory(at: admStateDirectory, 
                                                  withIntermediateDirectories: true, 
                                                  attributes: nil)
            
            // Create file path for this user's state
            let fileName = "adm_state_\(userId).json"
            let fileURL = admStateDirectory.appendingPathComponent(fileName)
            
            print("  └─ File path: \(fileURL.path)")
            
            // Encode and save
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)
            try data.write(to: fileURL)
            
            print("[ADMPersistenceManager] ✅ SAVE SUCCESSFUL")
            print("  └─ Saved \(data.count) bytes to disk")
            
        } catch {
            print("[ADMPersistenceManager] ❌ SAVE FAILED")
            print("  └─ Error: \(error)")
        }
    }
    
    /// Loads the ADM state for a specific user
    /// - Parameter userId: The user ID whose state to load
    /// - Returns: The persisted ADM state if found, nil otherwise
    static func loadState(for userId: String) -> PersistedADMState? {
        do {
            print("[ADMPersistenceManager] LOAD INITIATED")
            print("  └─ User ID: \(userId)")
            
            // Construct file path
            let admStateDirectory = documentsDirectory.appendingPathComponent(admStateDirectoryName)
            let fileName = "adm_state_\(userId).json"
            let fileURL = admStateDirectory.appendingPathComponent(fileName)
            
            print("  └─ Looking for file at: \(fileURL.path)")
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("[ADMPersistenceManager] ⚠️ NO SAVED STATE FOUND")
                print("  └─ File does not exist for user: \(userId)")
                return nil
            }
            
            // Load and decode
            let data = try Data(contentsOf: fileURL)
            print("  └─ Found file with \(data.count) bytes")
            
            let decoder = JSONDecoder()
            let state = try decoder.decode(PersistedADMState.self, from: data)
            
            print("[ADMPersistenceManager] ✅ LOAD SUCCESSFUL")
            print("  ├─ Performance history entries: \(state.performanceHistory.count)")
            print("  ├─ Last adaptation direction: \(state.lastAdaptationDirection)")
            print("  ├─ Direction stable count: \(state.directionStableCount)")
            print("  ├─ Normalized positions: \(state.normalizedPositions.count) DOMs")
            
            // Print individual DOM positions
            if !state.normalizedPositions.isEmpty {
                print("  ├─ DOM Normalized Positions:")
                let sortedPositions = state.normalizedPositions.sorted { $0.key.rawValue < $1.key.rawValue }
                for (index, (domType, position)) in sortedPositions.enumerated() {
                    let isLast = index == sortedPositions.count - 1 && state.performanceHistory.isEmpty
                    let prefix = isLast ? "  └─" : "  ├─"
                    print("\(prefix)   \(domType.rawValue): \(String(format: "%.3f", position))")
                }
            }
            
            if !state.performanceHistory.isEmpty {
                let oldestEntry = state.performanceHistory.first!
                let newestEntry = state.performanceHistory.last!
                let oldestAge = (CACurrentMediaTime() - oldestEntry.timestamp) / 3600.0
                let newestAge = (CACurrentMediaTime() - newestEntry.timestamp) / 3600.0
                print("  ├─ Oldest entry: \(String(format: "%.1f", oldestAge)) hours ago")
                print("  └─ Newest entry: \(String(format: "%.1f", newestAge)) hours ago")
            }
            
            return state
            
        } catch {
            print("[ADMPersistenceManager] ❌ LOAD FAILED")
            print("  └─ Error: \(error)")
            return nil
        }
    }
    
    /// Clears the saved ADM state for a specific user
    /// - Parameter userId: The user ID whose state to clear
    static func clearState(for userId: String) {
        do {
            print("[ADMPersistenceManager] CLEAR INITIATED")
            print("  └─ User ID: \(userId)")
            
            // Construct file path
            let admStateDirectory = documentsDirectory.appendingPathComponent(admStateDirectoryName)
            let fileName = "adm_state_\(userId).json"
            let fileURL = admStateDirectory.appendingPathComponent(fileName)
            
            print("  └─ File path: \(fileURL.path)")
            
            // Remove file if it exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                print("[ADMPersistenceManager] ✅ CLEAR SUCCESSFUL")
                print("  └─ Removed saved state for user: \(userId)")
            } else {
                print("[ADMPersistenceManager] ⚠️ CLEAR SKIPPED")
                print("  └─ No saved state exists for user: \(userId)")
            }
            
        } catch {
            print("[ADMPersistenceManager] ❌ CLEAR FAILED")
            print("  └─ Error: \(error)")
        }
    }
    
    /// Lists all saved user states (for debugging)
    /// - Returns: Array of user IDs that have saved states
    static func listSavedStates() -> [String] {
        do {
            let admStateDirectory = documentsDirectory.appendingPathComponent(admStateDirectoryName)
            
            // Check if directory exists
            guard FileManager.default.fileExists(atPath: admStateDirectory.path) else {
                return []
            }
            
            // List all files
            let files = try FileManager.default.contentsOfDirectory(at: admStateDirectory, 
                                                                   includingPropertiesForKeys: nil)
            
            // Extract user IDs from filenames
            let userIds = files.compactMap { fileURL -> String? in
                let filename = fileURL.lastPathComponent
                guard filename.hasPrefix("adm_state_") && filename.hasSuffix(".json") else {
                    return nil
                }
                
                // Extract user ID from filename
                let startIndex = filename.index(filename.startIndex, offsetBy: 10) // "adm_state_".count
                let endIndex = filename.index(filename.endIndex, offsetBy: -5) // ".json".count
                return String(filename[startIndex..<endIndex])
            }
            
            return userIds
            
        } catch {
            print("[ADMPersistenceManager] Error listing saved states: \(error)")
            return []
        }
    }
}
