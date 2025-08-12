import XCTest
@testable import KB2

class ADMPersistenceLoadingDebugTest: XCTestCase {
    var config: GameConfiguration!
    
    override func setUp() {
        super.setUp()
        config = GameConfiguration()
    }
    
    func test_persistenceLoadingDebug() {
        // Create a unique user ID for this test
        let testUserId = "TEST_USER_\(UUID().uuidString)"
        
        // Step 1: Create ADM with custom positions and save state
        let adm1 = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 900,
            userId: testUserId
        )
        
        // Set custom positions
        adm1.normalizedPositions[.discriminatoryLoad] = 0.7
        adm1.normalizedPositions[.meanBallSpeed] = 0.6
        adm1.normalizedPositions[.ballSpeedSD] = 0.55
        adm1.normalizedPositions[.responseTime] = 0.65
        adm1.normalizedPositions[.targetCount] = 0.4
        
        print("\n=== SAVING STATE ===")
        print("Positions before save:")
        for (dom, pos) in adm1.normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  \(dom): \(String(format: "%.3f", pos))")
        }
        
        // Save state
        adm1.saveState()
        
        // Step 2: Load the saved state directly to verify it was saved correctly
        if let savedState = ADMPersistenceManager.loadState(for: testUserId) {
            print("\n=== VERIFYING SAVED STATE ===")
            print("Positions in saved state:")
            for (dom, pos) in savedState.normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                print("  \(dom): \(String(format: "%.3f", pos))")
            }
            
            // Verify saved positions match what we set
            XCTAssertEqual(savedState.normalizedPositions[.discriminatoryLoad] ?? 0, 0.7, accuracy: 0.001)
            XCTAssertEqual(savedState.normalizedPositions[.meanBallSpeed] ?? 0, 0.6, accuracy: 0.001)
            XCTAssertEqual(savedState.normalizedPositions[.ballSpeedSD] ?? 0, 0.55, accuracy: 0.001)
            XCTAssertEqual(savedState.normalizedPositions[.responseTime] ?? 0, 0.65, accuracy: 0.001)
            XCTAssertEqual(savedState.normalizedPositions[.targetCount] ?? 0, 0.4, accuracy: 0.001)
        } else {
            XCTFail("Failed to load saved state")
        }
        
        // Step 3: Create a new ADM instance to test loading
        print("\n=== CREATING NEW ADM INSTANCE ===")
        config.clearPastSessionData = false // Ensure we load persisted state
        config.enableSessionPhases = false // Disable warmup to simplify testing
        
        let adm2 = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 900,
            userId: testUserId
        )
        
        print("\n=== FINAL POSITIONS IN NEW ADM ===")
        print("Positions after initialization:")
        for (dom, pos) in adm2.normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  \(dom): \(String(format: "%.3f", pos))")
        }
        
        // Verify positions were loaded correctly
        XCTAssertEqual(adm2.normalizedPositions[.discriminatoryLoad] ?? 0, 0.7, accuracy: 0.001, 
                      "discriminatoryLoad position should be loaded from persistence")
        XCTAssertEqual(adm2.normalizedPositions[.meanBallSpeed] ?? 0, 0.6, accuracy: 0.001,
                      "meanBallSpeed position should be loaded from persistence")
        XCTAssertEqual(adm2.normalizedPositions[.ballSpeedSD] ?? 0, 0.55, accuracy: 0.001,
                      "ballSpeedSD position should be loaded from persistence")
        XCTAssertEqual(adm2.normalizedPositions[.responseTime] ?? 0, 0.65, accuracy: 0.001,
                      "responseTime position should be loaded from persistence")
        XCTAssertEqual(adm2.normalizedPositions[.targetCount] ?? 0, 0.4, accuracy: 0.001,
                      "targetCount position should be loaded from persistence")
        
        // Clean up
        ADMPersistenceManager.clearState(for: testUserId)
    }
    
    func test_persistenceLoadingWithWarmupDebug() {
        // Test the same scenario but with warmup enabled
        let testUserId = "TEST_USER_WARMUP_\(UUID().uuidString)"
        
        // Step 1: Create ADM with custom positions and save state
        let adm1 = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 900,
            userId: testUserId
        )
        
        // Set custom positions
        adm1.normalizedPositions[.discriminatoryLoad] = 0.7
        adm1.normalizedPositions[.meanBallSpeed] = 0.6
        adm1.normalizedPositions[.ballSpeedSD] = 0.55
        adm1.normalizedPositions[.responseTime] = 0.65
        adm1.normalizedPositions[.targetCount] = 0.4
        
        // Save state
        adm1.saveState()
        
        // Step 2: Create a new ADM instance with warmup enabled
        print("\n=== CREATING NEW ADM WITH WARMUP ===")
        config.clearPastSessionData = false
        config.enableSessionPhases = true
        // warmupInitialDifficultyMultiplier is already set to 0.9 by default in GameConfiguration
        
        let adm2 = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 900,
            userId: testUserId
        )
        
        print("\n=== FINAL POSITIONS WITH WARMUP ===")
        for (dom, pos) in adm2.normalizedPositions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  \(dom): \(String(format: "%.3f", pos))")
        }
        
        // Verify positions were loaded and then scaled by warmup
        // Expected: loaded position * 0.9, with floor of 0.3
        XCTAssertEqual(adm2.normalizedPositions[.discriminatoryLoad] ?? 0, max(0.7 * 0.9, 0.3), accuracy: 0.001)
        XCTAssertEqual(adm2.normalizedPositions[.meanBallSpeed] ?? 0, max(0.6 * 0.9, 0.3), accuracy: 0.001)
        XCTAssertEqual(adm2.normalizedPositions[.ballSpeedSD] ?? 0, max(0.55 * 0.9, 0.3), accuracy: 0.001)
        XCTAssertEqual(adm2.normalizedPositions[.responseTime] ?? 0, max(0.65 * 0.9, 0.3), accuracy: 0.001)
        XCTAssertEqual(adm2.normalizedPositions[.targetCount] ?? 0, max(0.4 * 0.9, 0.3), accuracy: 0.001)
        
        // Clean up
        ADMPersistenceManager.clearState(for: testUserId)
    }
    
    // MARK: - Migration Tests
    
    func test_migrationFromV1AddsProfilesAndSetsVersion() throws {
        let userId = "TEST_MIGRATE_V1_\(UUID().uuidString)"
        
        // Craft a legacy v1 JSON (no "version", no "domPerformanceProfiles")
        let v1Dict: [String: Any] = [
            "performanceHistory": [],
            "lastAdaptationDirection": "stable",
            "directionStableCount": 0,
            "normalizedPositions": [
                "discriminatoryLoad": 0.5,
                "meanBallSpeed": 0.5,
                "ballSpeedSD": 0.5,
                "responseTime": 0.5,
                "targetCount": 0.5
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: v1Dict, options: [.prettyPrinted])
        
        // Write to expected path
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ADMState")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let fileURL = dir.appendingPathComponent("adm_state_\(userId).json")
        try data.write(to: fileURL)
        
        // Load via manager (should migrate and persist)
        guard let state = ADMPersistenceManager.loadState(for: userId) else {
            XCTFail("Failed to load legacy v1 state")
            return
        }
        
        // Verify migration effected
        XCTAssertEqual(state.version, 2, "Schema version should be migrated to 2")
        XCTAssertNotNil(state.domPerformanceProfiles, "domPerformanceProfiles should be initialized on migration")
        if let profiles = state.domPerformanceProfiles {
            XCTAssertEqual(profiles.keys.count, DOMTargetType.allCases.count, "All DOMs should have profiles after migration")
            for dom in DOMTargetType.allCases {
                XCTAssertNotNil(profiles[dom], "Missing profile for \(dom)")
                // Buffer starts empty; correctness is that it exists
            }
        }
        
        // Verify persisted file now contains "version": 2
        let persisted = try Data(contentsOf: fileURL)
        let obj = try JSONSerialization.jsonObject(with: persisted, options: [])
        let dict = obj as? [String: Any]
        let fileVersion = dict?["version"] as? Int
        XCTAssertEqual(fileVersion, 2, "Migrated file should persist schema version 2")
        
        // Cleanup
        ADMPersistenceManager.clearState(for: userId)
    }
    
    func test_unknownFutureVersionLoadsWithoutDowngrade() throws {
        let userId = "TEST_MIGRATE_FUTURE_\(UUID().uuidString)"
        
        // Craft a future version JSON (e.g., 99). Omit domPerformanceProfiles (optional) to simulate unknown layout.
        let futureDict: [String: Any] = [
            "version": 99,
            "performanceHistory": [],
            "lastAdaptationDirection": "stable",
            "directionStableCount": 0,
            "normalizedPositions": [
                "discriminatoryLoad": 0.4,
                "meanBallSpeed": 0.6,
                "ballSpeedSD": 0.5,
                "responseTime": 0.5,
                "targetCount": 0.5
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: futureDict, options: [.prettyPrinted])
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ADMState")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let fileURL = dir.appendingPathComponent("adm_state_\(userId).json")
        try data.write(to: fileURL)
        
        // Load via manager (should warn and proceed without downgrading)
        guard let state = ADMPersistenceManager.loadState(for: userId) else {
            XCTFail("Failed to load future-version state")
            return
        }
        XCTAssertEqual(state.version, 99, "Future version should not be downgraded by migration")
        
        ADMPersistenceManager.clearState(for: userId)
    }
    
    func test_idempotentMigration() throws {
        let userId = "TEST_MIGRATE_IDEMPOTENT_\(UUID().uuidString)"
        
        // Write legacy v1 JSON
        let v1Dict: [String: Any] = [
            "performanceHistory": [],
            "lastAdaptationDirection": "stable",
            "directionStableCount": 0,
            "normalizedPositions": [
                "discriminatoryLoad": 0.5,
                "meanBallSpeed": 0.5,
                "ballSpeedSD": 0.5,
                "responseTime": 0.5,
                "targetCount": 0.5
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: v1Dict, options: [.prettyPrinted])
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ADMState")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let fileURL = dir.appendingPathComponent("adm_state_\(userId).json")
        try data.write(to: fileURL)
        
        // First load => triggers migration
        guard let state1 = ADMPersistenceManager.loadState(for: userId) else {
            XCTFail("First load failed")
            return
        }
        XCTAssertEqual(state1.version, 2)
        XCTAssertNotNil(state1.domPerformanceProfiles)
        
        // Capture file size after first migration persist
        let sizeAfterFirst = (try? Data(contentsOf: fileURL).count) ?? -1
        
        // Second load => should not re-migrate / should be stable
        guard let state2 = ADMPersistenceManager.loadState(for: userId) else {
            XCTFail("Second load failed")
            return
        }
        XCTAssertEqual(state2.version, 2)
        XCTAssertNotNil(state2.domPerformanceProfiles)
        
        let sizeAfterSecond = (try? Data(contentsOf: fileURL).count) ?? -1
        XCTAssertEqual(sizeAfterFirst, sizeAfterSecond, "Repeated loads should be idempotent on-disk")
        
        ADMPersistenceManager.clearState(for: userId)
    }
}
