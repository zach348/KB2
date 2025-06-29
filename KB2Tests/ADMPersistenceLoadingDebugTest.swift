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
}
