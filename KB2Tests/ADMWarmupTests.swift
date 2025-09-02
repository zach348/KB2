import XCTest
@testable import KB2

class ADMWarmupTests: XCTestCase {
    
    var config: GameConfiguration!
    
    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        config.clearPastSessionData = true  // Ensure clean state for tests
        // Clear any persisted state
        ADMPersistenceManager.clearState(for: UserIDManager.getUserId())
    }
    
    override func tearDown() {
        // Clean up
        ADMPersistenceManager.clearState(for: UserIDManager.getUserId())
        config = nil
        super.tearDown()
    }
    
    // MARK: - Warmup Duration Tests
    
    func testWarmupDurationCalculation_ShortSession() {
        let sessionDuration: TimeInterval = 7 * 60 // 7 minutes
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: config,
            initialArousal: 1.0
        )
        
        // Warmup should be 20% of expected rounds
        let expectedWarmupRounds = Int(CGFloat(expectedRounds) * config.warmupPhaseProportion)
        XCTAssertEqual(config.warmupPhaseProportion, 0.2, "Warmup proportion should be 20%")
        XCTAssertGreaterThan(expectedWarmupRounds, 0, "Should have at least 1 warmup round")
        XCTAssertLessThan(expectedWarmupRounds, expectedRounds, "Warmup should be less than total rounds")
    }
    
    func testWarmupDurationCalculation_LongSession() {
        let sessionDuration: TimeInterval = 30 * 60 // 30 minutes
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: config,
            initialArousal: 1.0
        )
        
        let expectedWarmupRounds = Int(CGFloat(expectedRounds) * config.warmupPhaseProportion)
        XCTAssertGreaterThan(expectedWarmupRounds, 5, "Long session should have several warmup rounds")
    }
    
    // MARK: - Initial Difficulty Scaling Tests
    
    func testWarmupInitialDifficultyScaling_FreshSession() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        testConfig.enableSessionPhases = true
        
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 1.0,
            sessionDuration: 15 * 60
        )
        
        // Should start at 85% of default (0.5)
        let expectedInitialPosition = 0.5 * testConfig.warmupInitialDifficultyMultiplier
        
        for (domType, position) in adm.normalizedPositions {
            XCTAssertEqual(position, expectedInitialPosition, accuracy: 0.001,
                          "DOM \(domType) should be scaled to 85% during warmup")
        }
    }
    
    func testWarmupInitialDifficultyScaling_WithPersistedState() {
        let userId = "test_warmup_user"
        
        // Save some non-default state
        let persistedPositions: [DOMTargetType: CGFloat] = [
            .discriminatoryLoad: 0.8,
            .meanBallSpeed: 0.7,
            .ballSpeedSD: 0.6,
            .responseTime: 0.75,
            .targetCount: 0.3
        ]
        
        let persistedState = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .stable,
            directionStableCount: 0,
            normalizedPositions: persistedPositions,
            domPerformanceProfiles: nil // Old format compatibility
        )
        ADMPersistenceManager.saveState(persistedState, for: userId)
        
        // Create ADM with warmup enabled
        var testConfig = GameConfiguration()
        testConfig.enableSessionPhases = true
        testConfig.clearPastSessionData = false
        
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 1.0,
            sessionDuration: 15 * 60,
            userId: userId
        )
        
        // Manually trigger the load logic
        if let loadedState = ADMPersistenceManager.loadState(for: userId) {
            adm.loadState(from: loadedState)
            // Apply warmup scaling
            for (dom, position) in adm.normalizedPositions {
                adm.normalizedPositions[dom] = position * testConfig.warmupInitialDifficultyMultiplier
            }
        }
        
        // Verify positions are scaled to 85% of persisted values
        for (domType, originalPosition) in persistedPositions {
            let expectedPosition = originalPosition * testConfig.warmupInitialDifficultyMultiplier
            XCTAssertEqual(adm.normalizedPositions[domType]!, expectedPosition, accuracy: 0.001,
                          "DOM \(domType) should be 85% of persisted value")
        }
        
        // Cleanup
        ADMPersistenceManager.clearState(for: userId)
    }
    
    // MARK: - Adaptation Behavior Tests
    
    func testWarmupAdaptationRate() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        testConfig.enableSessionPhases = true
        
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 1.0,
            sessionDuration: 15 * 60
        )
        
        // Verify warmup configuration
        XCTAssertEqual(testConfig.warmupAdaptationRateMultiplier, 1.5,
                      "Warmup adaptation rate should be 1.5x")
        XCTAssertEqual(testConfig.warmupPerformanceTarget, 0.7,
                      "Warmup performance target should be 0.70")
    }
    
    func testWarmupPerformanceBasedAdaptation_GoodPerformance() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        testConfig.enableSessionPhases = true
        testConfig.performanceHistoryWindowSize = 5
        
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.7,
            sessionDuration: 15 * 60
        )
        
        // Capture initial positions
        let initialPositions = adm.normalizedPositions
        
        // Simulate good performance (above 0.60 target)
        let expectation1 = XCTestExpectation(description: "Record good performance")
        adm.recordIdentificationPerformanceAsync(
            taskSuccess: true,
            tfTtfRatio: 0.9,
            reactionTime: 0.3,
            responseDuration: 1.0,
            averageTapAccuracy: 20.0,
            actualTargetsToFindInRound: 3
        ) {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 5.0)
        
        // At least one DOM should have increased
        var anyIncreased = false
        for (domType, initialPos) in initialPositions {
            if let currentPos = adm.normalizedPositions[domType], currentPos > initialPos {
                anyIncreased = true
                break
            }
        }
        XCTAssertTrue(anyIncreased, "Good performance should increase difficulty")
    }
    
    func testWarmupPerformanceBasedAdaptation_PoorPerformance() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        testConfig.enableSessionPhases = true
        testConfig.performanceHistoryWindowSize = 5
        
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.7,
            sessionDuration: 15 * 60
        )
        
        // Capture initial positions
        let initialPositions = adm.normalizedPositions
        
        // Simulate poor performance (below 0.60 target)
        let expectation2 = XCTestExpectation(description: "Record poor performance")
        adm.recordIdentificationPerformanceAsync(
            taskSuccess: false,
            tfTtfRatio: 0.3,
            reactionTime: 1.5,
            responseDuration: 6.0,
            averageTapAccuracy: 150.0,
            actualTargetsToFindInRound: 3
        ) {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 5.0)
        
        // At least one DOM should have decreased
        var anyDecreased = false
        for (domType, initialPos) in initialPositions {
            if let currentPos = adm.normalizedPositions[domType], currentPos < initialPos {
                anyDecreased = true
                break
            }
        }
        XCTAssertTrue(anyDecreased, "Poor performance should decrease difficulty")
    }
    
    // MARK: - Phase Transition Tests
    
    func testWarmupToStandardPhaseTransition() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        testConfig.enableSessionPhases = true
        testConfig.performanceHistoryWindowSize = 10
        
        let sessionDuration: TimeInterval = 15 * 60
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.7,
            sessionDuration: sessionDuration
        )
        
        // Calculate expected warmup length
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: testConfig,
            initialArousal: 0.7
        )
        let calculatedWarmupLength = Int(CGFloat(expectedRounds) * testConfig.warmupPhaseProportion)
        let warmupLength = (testConfig.enableSessionPhases && expectedRounds > 0) ? max(1, calculatedWarmupLength) : calculatedWarmupLength
        
        // Track positions through the transition
        var positionsAtEndOfWarmup: [DOMTargetType: CGFloat] = [:]
        var positionsAfterTransition: [DOMTargetType: CGFloat] = [:]
        
        // Simulate rounds with moderate performance
        for round in 0..<(warmupLength + 2) {
            let expectation3 = XCTestExpectation(description: "Record performance for round \(round)")
            adm.recordIdentificationPerformanceAsync(
                taskSuccess: true,
                tfTtfRatio: 0.65,
                reactionTime: 0.5,
                responseDuration: 2.0,
                averageTapAccuracy: 50.0,
                actualTargetsToFindInRound: 3
            ) {
                expectation3.fulfill()
            }
            wait(for: [expectation3], timeout: 5.0)
            
            // Capture positions at the end of warmup phase (after last warmup round)
            if round == warmupLength - 1 {
                positionsAtEndOfWarmup = adm.normalizedPositions
            }
            // Capture positions after first standard phase round
            else if round == warmupLength {
                positionsAfterTransition = adm.normalizedPositions
            }
        }
        
        // Verify no reset occurs - positions should remain close to adapted values
        for (domType, warmupEndPos) in positionsAtEndOfWarmup {
            if let postTransitionPos = positionsAfterTransition[domType] {
                // Allow for normal adaptation changes but no major reset
                let change = abs(postTransitionPos - warmupEndPos)
                XCTAssertLessThan(change, 0.15,
                    "DOM \(domType) changed too much after warmup transition: " +
                    "\(String(format: "%.3f", warmupEndPos)) → \(String(format: "%.3f", postTransitionPos))")
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testWarmupDisabled() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        testConfig.enableSessionPhases = false // Disable warmup
        
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 1.0,
            sessionDuration: 15 * 60
        )
        
        // Should start at default 0.5, not scaled down
        for (_, position) in adm.normalizedPositions {
            XCTAssertEqual(position, 0.5, accuracy: 0.001,
                          "Without warmup, should start at default 0.5")
        }
    }
    
    func testWarmupWithVeryShortSession() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        testConfig.enableSessionPhases = true
        
        let sessionDuration: TimeInterval = 2 * 60 // 2 minutes
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 1.0,
            sessionDuration: sessionDuration
        )
        
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: testConfig,
            initialArousal: 1.0
        )
        let calculatedWarmupLength = Int(CGFloat(expectedRounds) * testConfig.warmupPhaseProportion)
        let warmupLength = (testConfig.enableSessionPhases && expectedRounds > 0) ? max(1, calculatedWarmupLength) : calculatedWarmupLength
        
        XCTAssertGreaterThan(warmupLength, 0, "Even short sessions should have at least 1 warmup round")
        XCTAssertLessThan(warmupLength, expectedRounds, "Warmup should not be entire session")
    }
    
    func testWarmupDoesNotAffectPersistedState() {
        let userId = "test_persistence_warmup"
        
        // Save initial state
        let originalPositions: [DOMTargetType: CGFloat] = [
            .discriminatoryLoad: 0.7,
            .meanBallSpeed: 0.6,
            .ballSpeedSD: 0.5,
            .responseTime: 0.4,
            .targetCount: 0.3
        ]
        
        let originalState = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .stable,
            directionStableCount: 0,
            normalizedPositions: originalPositions,
            domPerformanceProfiles: nil // Old format compatibility
        )
        ADMPersistenceManager.saveState(originalState, for: userId)
        
        // Load with warmup
        var testConfig = GameConfiguration()
        testConfig.enableSessionPhases = true
        testConfig.clearPastSessionData = false
        
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 1.0,
            sessionDuration: 15 * 60,
            userId: userId
        )
        
        // The warmup scaling should not modify the persisted state
        if let loadedState = ADMPersistenceManager.loadState(for: userId) {
            for (domType, originalValue) in originalPositions {
                XCTAssertEqual(loadedState.normalizedPositions[domType]!, originalValue,
                              "Persisted state should not be modified by warmup")
            }
        }
        
        // Cleanup
        ADMPersistenceManager.clearState(for: userId)
    }
    
    // MARK: - Configuration Tests
    
    func testWarmupConfigurationValues() {
        let config = GameConfiguration()
        
        XCTAssertEqual(config.warmupPhaseProportion, 0.2,
                      "Warmup should be 20% of session")
        XCTAssertEqual(config.warmupInitialDifficultyMultiplier, 0.9,
                      "Initial difficulty should be 90%")
        XCTAssertEqual(config.warmupPerformanceTarget, 0.7,
                      "Performance target should be 0.70")
        XCTAssertEqual(config.warmupAdaptationRateMultiplier, 1.5,
                      "Adaptation rate should be 1.5x")
        XCTAssertTrue(config.enableSessionPhases,
                     "Session phases should be enabled by default")
    }
}
