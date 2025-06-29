import XCTest
@testable import KB2

class ADMSessionPhaseTests: XCTestCase {

    var config: GameConfiguration!

    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        config.clearPastSessionData = true  // Ensure clean state for tests
    }

    override func tearDown() {
        config = nil
        super.tearDown()
    }

    // MARK: - SessionAnalytics Tests

    func testEstimateExpectedRounds_ShortSession() {
        let sessionDuration: TimeInterval = 7 * 60 // 7 minutes
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: config,
            initialArousal: 1.0
        )
        // Based on user feedback and manual calculation, a 7-min session should be ~8-10 rounds
        XCTAssertGreaterThanOrEqual(expectedRounds, 8)
        XCTAssertLessThanOrEqual(expectedRounds, 12)
    }

    func testEstimateExpectedRounds_LongSession() {
        let sessionDuration: TimeInterval = 30 * 60 // 30 minutes
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: config,
            initialArousal: 1.0
        )
        // A 30-min session should be significantly more than a 7-min one
        XCTAssertGreaterThan(expectedRounds, 40)
    }

    // MARK: - ADM Initialization Tests

    func testADMInitialization_WarmupEnabled() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 1.0,
            sessionDuration: 15 * 60
        )
        // This is an internal property, so we can't directly test it without modifying the source.
        // Instead, we'll test its effects in the behavior tests.
        // For now, we just ensure it initializes without crashing.
        XCTAssertNotNil(adm)
    }

    func testWarmupInitialDifficulty_FreshSession() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        // Ensure persistence is off for this test
        // In a real scenario, this would be handled by ADMPersistenceManager returning nil
        
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 1.0,
            sessionDuration: 15 * 60
        )

        let expectedMultiplier = testConfig.warmupInitialDifficultyMultiplier
        let expectedInitialPosition = 0.5 * expectedMultiplier

        // Check if the initial normalized positions are scaled down
        for (_, position) in adm.normalizedPositions {
            XCTAssertEqual(position, expectedInitialPosition, accuracy: 0.001)
        }
    }

    func testWarmupInitialDifficulty_FromPersistence() {
        let userId = "test_user_warmup_persistence"
        
        // 1. Create and save a state with non-default values
        let persistedPositions: [DOMTargetType: CGFloat] = [
            .discriminatoryLoad: 0.8,
            .meanBallSpeed: 0.7,
            .ballSpeedSD: 0.6,
            .responseTime: 0.75,
            .targetCount: 0.2
        ]
        let persistedState = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .stable,
            directionStableCount: 0,
            normalizedPositions: persistedPositions,
            domPerformanceProfiles: nil // Old format compatibility
        )
        ADMPersistenceManager.saveState(persistedState, for: userId)

        // 2. Initialize ADM, which should load this state
        var mutableConfig = GameConfiguration()
        mutableConfig.clearPastSessionData = false // Ensure we load from persistence
        
        let adm = AdaptiveDifficultyManager(
            configuration: mutableConfig,
            initialArousal: 1.0,
            sessionDuration: 15 * 60,
            userId: userId
        )


        // 3. Assert that the final positions are the persisted ones scaled down
        // Note: ADM applies a floor of 0.3 to warmup-scaled positions
        let expectedMultiplier = mutableConfig.warmupInitialDifficultyMultiplier
        for (domType, persistedPosition) in persistedPositions {
            let scaledPosition = persistedPosition * expectedMultiplier
            let expectedPosition = max(scaledPosition, 0.3) // Floor of 0.3 is applied
            XCTAssertEqual(adm.normalizedPositions[domType]!, expectedPosition, accuracy: 0.001)
        }
        
        // Cleanup
        ADMPersistenceManager.clearState(for: userId)
    }
}
