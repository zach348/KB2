// Copyright 2025 Training State, LLC. All rights reserved.
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
    
    // Schema versioning
    private static let currentSchemaVersion: Int = 2
    
    /// Reads the raw "version" from JSON data, if present (used to make pre-decode decisions)
    private static func readRawVersion(from data: Data) -> Int? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any] else {
            return nil
        }
        return dict["version"] as? Int
    }
    
    /// Idempotent migration to the current schema version.
    /// - Note: This will persist the migrated state to disk if changes are applied.
    private static func migrateIfNeeded(_ state: PersistedADMState, rawVersion: Int?, for userId: String) -> PersistedADMState {
        var migrated = state
        var didMigrate = false
        
        // Guard: If the on-disk version is newer than we support, warn but attempt to proceed.
        if let fileVersion = rawVersion, fileVersion > currentSchemaVersion {
            print("[ADMPersistenceManager] ⚠️ State file version (\(fileVersion)) is newer than supported (\(currentSchemaVersion)). Attempting to proceed safely.")
            // Do not attempt to downgrade; return as-is.
            return migrated
        }
        
        // v1 -> v2: Initialize DOM performance profiles if missing (older saves had none)
        if migrated.domPerformanceProfiles == nil {
            print("[ADMPersistenceManager] ⏩ Migrating: Initializing missing DOM performance profiles (v1 → v2)")
            var profiles: [DOMTargetType: DOMPerformanceProfile] = [:]
            for dom in DOMTargetType.allCases {
                profiles[dom] = DOMPerformanceProfile(domType: dom)
            }
            // Rebuild state with initialized profiles (domPerformanceProfiles is 'let' in PersistedADMState)
            migrated = PersistedADMState(
                performanceHistory: migrated.performanceHistory,
                lastAdaptationDirection: migrated.lastAdaptationDirection,
                directionStableCount: migrated.directionStableCount,
                normalizedPositions: migrated.normalizedPositions,
                domPerformanceProfiles: profiles,
                version: migrated.version
            )
            didMigrate = true
        }
        
        // Ensure version field is set to current (handles missing or older versions)
        if rawVersion == nil || (rawVersion ?? 0) < currentSchemaVersion || migrated.version != currentSchemaVersion {
            print("[ADMPersistenceManager] ⏩ Migrating: Setting schema version to \(currentSchemaVersion)")
            migrated.version = currentSchemaVersion
            didMigrate = true
        }
        
        // Optionally: sanitize anomalous data (defensive). Keep minimal to avoid semantics changes.
        // Example (disabled by default): trim NaN scores, negative timestamps, etc.
        // if migrated.performanceHistory.contains(where: { !$0.overallScore.isFinite }) { ... }
        
        if didMigrate {
            print("[ADMPersistenceManager] 💾 Persisting migrated state for user: \(userId)")
            saveState(migrated, for: userId)
        }
        
        return migrated
    }
    
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
            
            // Read raw version before decoding (if present)
            let rawVersion = readRawVersion(from: data)
            if let v = rawVersion {
                print("  └─ Detected schema version in file: \(v)")
            } else {
                print("  └─ No schema version found in file (assuming legacy v1)")
            }
            
            let decoder = JSONDecoder()
            let state: PersistedADMState
            if rawVersion == nil {
                // Decode legacy v1 payload (no "version", no "domPerformanceProfiles"), then migrate
                struct PersistedADMStateV1Local: Decodable {
                    let performanceHistory: [PerformanceHistoryEntry]
                    let lastAdaptationDirection: AdaptiveDifficultyManager.AdaptationDirection
                    let directionStableCount: Int
                    let normalizedPositions: [String: CGFloat]
                }
                let legacy = try decoder.decode(PersistedADMStateV1Local.self, from: data)
                let mappedPositions: [DOMTargetType: CGFloat] = Dictionary(uniqueKeysWithValues:
                    legacy.normalizedPositions.compactMap { (key, value) in
                        guard let dom = DOMTargetType(rawValue: key) else { return nil }
                        return (dom, value)
                    }
                )
                let lifted = PersistedADMState(
                    performanceHistory: legacy.performanceHistory,
                    lastAdaptationDirection: legacy.lastAdaptationDirection,
                    directionStableCount: legacy.directionStableCount,
                    normalizedPositions: mappedPositions,
                    domPerformanceProfiles: nil,
                    version: 1
                )
                // Apply schema migration (idempotent); persists if changes applied
                state = migrateIfNeeded(lifted, rawVersion: nil, for: userId)
            } else {
                // Attempt normal decode first
                do {
                    var decoded = try decoder.decode(PersistedADMState.self, from: data)
                    // Apply schema migration (idempotent); persists if changes applied
                    decoded = migrateIfNeeded(decoded, rawVersion: rawVersion, for: userId)
                    state = decoded
                } catch {
                    // Fallback: handle payloads where normalizedPositions are string-keyed
                    struct PersistedADMStateFlexible: Decodable {
                        let performanceHistory: [PerformanceHistoryEntry]
                        let lastAdaptationDirection: AdaptiveDifficultyManager.AdaptationDirection
                        let directionStableCount: Int
                        let normalizedPositions: [String: CGFloat]
                        let version: Int
                    }
                    let flex = try decoder.decode(PersistedADMStateFlexible.self, from: data)
                    let mappedPositions: [DOMTargetType: CGFloat] = Dictionary(uniqueKeysWithValues:
                        flex.normalizedPositions.compactMap { (key, value) in
                            guard let dom = DOMTargetType(rawValue: key) else { return nil }
                            return (dom, value)
                        }
                    )
                    let lifted = PersistedADMState(
                        performanceHistory: flex.performanceHistory,
                        lastAdaptationDirection: flex.lastAdaptationDirection,
                        directionStableCount: flex.directionStableCount,
                        normalizedPositions: mappedPositions,
                        domPerformanceProfiles: nil,
                        version: flex.version
                    )
                    // For future versions, pass rawVersion through so we don't downgrade
                    state = migrateIfNeeded(lifted, rawVersion: rawVersion, for: userId)
                }
            }
            
            print("[ADMPersistenceManager] ✅ LOAD SUCCESSFUL")
            print("  ├─ Schema version: \(state.version)")
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
