// Kalibrate/ADMPersistenceManager.swift
// Created: 6/21/2025
// Role: Manages persistence of ADM state across sessions

import Foundation

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
            // Create ADM state directory if it doesn't exist
            let admStateDirectory = documentsDirectory.appendingPathComponent(admStateDirectoryName)
            try FileManager.default.createDirectory(at: admStateDirectory, 
                                                  withIntermediateDirectories: true, 
                                                  attributes: nil)
            
            // Create file path for this user's state
            let fileName = "adm_state_\(userId).json"
            let fileURL = admStateDirectory.appendingPathComponent(fileName)
            
            // Encode and save
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)
            try data.write(to: fileURL)
            
            print("[ADMPersistenceManager] Successfully saved state for user: \(userId)")
            
        } catch {
            print("[ADMPersistenceManager] Error saving state: \(error)")
        }
    }
    
    /// Loads the ADM state for a specific user
    /// - Parameter userId: The user ID whose state to load
    /// - Returns: The persisted ADM state if found, nil otherwise
    static func loadState(for userId: String) -> PersistedADMState? {
        do {
            // Construct file path
            let admStateDirectory = documentsDirectory.appendingPathComponent(admStateDirectoryName)
            let fileName = "adm_state_\(userId).json"
            let fileURL = admStateDirectory.appendingPathComponent(fileName)
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("[ADMPersistenceManager] No saved state found for user: \(userId)")
                return nil
            }
            
            // Load and decode
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let state = try decoder.decode(PersistedADMState.self, from: data)
            
            print("[ADMPersistenceManager] Successfully loaded state for user: \(userId)")
            return state
            
        } catch {
            print("[ADMPersistenceManager] Error loading state: \(error)")
            return nil
        }
    }
    
    /// Clears the saved ADM state for a specific user
    /// - Parameter userId: The user ID whose state to clear
    static func clearState(for userId: String) {
        do {
            // Construct file path
            let admStateDirectory = documentsDirectory.appendingPathComponent(admStateDirectoryName)
            let fileName = "adm_state_\(userId).json"
            let fileURL = admStateDirectory.appendingPathComponent(fileName)
            
            // Remove file if it exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                print("[ADMPersistenceManager] Successfully cleared state for user: \(userId)")
            }
            
        } catch {
            print("[ADMPersistenceManager] Error clearing state: \(error)")
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
