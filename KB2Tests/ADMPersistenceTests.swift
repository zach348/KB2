import XCTest
@testable import KB2

class ADMPersistenceTests: XCTestCase {
    
    var adm: AdaptiveDifficultyManager!
    var config: GameConfiguration!
    let testUserId = "testUser123"
    var actualUserId: String = ""
    
    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        
        // Get the actual userId that ADM will use
        actualUserId = UserIDManager.getUserId()
        
        // Clear any existing test data for both userIds
        ADMPersistenceManager.clearState(for: testUserId)
        ADMPersistenceManager.clearState(for: actualUserId)
    }
    
    override func tearDown() {
        // Clean up test data
        ADMPersistenceManager.clearState(for: testUserId)
        ADMPersistenceManager.clearState(for: actualUserId)
        super.tearDown()
    }
    
    // MARK: - ADMPersistenceManager Tests
    
    func testSaveAndLoadState() {
        // Create test state
        let testHistory = [
            PerformanceHistoryEntry(
                timestamp: CACurrentMediaTime(),
                overallScore: 0.75,
                normalizedKPIs: [.taskSuccess: 1.0, .tfTtfRatio: 0.8],
                arousalLevel: 0.6,
                currentDOMValues: [.targetCount: 3.0, .meanBallSpeed: 150.0],
                sessionContext: "test"
            )
        ]
        
        let testState = PersistedADMState(
            performanceHistory: testHistory,
            lastAdaptationDirection: .increasing,
            directionStableCount: 3,
            normalizedPositions: [.targetCount: 0.5, .meanBallSpeed: 0.6],
            domPerformanceProfiles: nil
        )
        
        // Save state using actual userId
        ADMPersistenceManager.saveState(testState, for: actualUserId)
        
        // Load state
        let loadedState = ADMPersistenceManager.loadState(for: actualUserId)
        
        XCTAssertNotNil(loadedState)
        XCTAssertEqual(loadedState?.performanceHistory.count, 1)
        XCTAssertEqual(loadedState?.lastAdaptationDirection, .increasing)
        XCTAssertEqual(loadedState?.directionStableCount, 3)
        XCTAssertEqual(loadedState?.normalizedPositions.count, 2)
    }
    
    func testLoadStateForNonExistentUser() {
        let state = ADMPersistenceManager.loadState(for: "nonExistentUser")
        XCTAssertNil(state)
    }
    
    func testClearState() {
        // First save some state
        let testState = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .stable,
            directionStableCount: 0,
            normalizedPositions: [:],
            domPerformanceProfiles: nil
        )
        
        ADMPersistenceManager.saveState(testState, for: actualUserId)
        
        // Verify it was saved
        XCTAssertNotNil(ADMPersistenceManager.loadState(for: actualUserId))
        
        // Clear the state
        ADMPersistenceManager.clearState(for: actualUserId)
        
        // Verify it was cleared
        XCTAssertNil(ADMPersistenceManager.loadState(for: actualUserId))
    }
    
    func testMultipleUsers() {
        let user1 = "user1"
        let user2 = "user2"
        
        let state1 = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .increasing,
            directionStableCount: 1,
            normalizedPositions: [.targetCount: 0.3],
            domPerformanceProfiles: nil
        )
        
        let state2 = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .decreasing,
            directionStableCount: 2,
            normalizedPositions: [.targetCount: 0.7],
            domPerformanceProfiles: nil
        )
        
        // Save states for different users
        ADMPersistenceManager.saveState(state1, for: user1)
        ADMPersistenceManager.saveState(state2, for: user2)
        
        // Load and verify each user's state
        let loaded1 = ADMPersistenceManager.loadState(for: user1)
        let loaded2 = ADMPersistenceManager.loadState(for: user2)
        
        XCTAssertEqual(loaded1?.lastAdaptationDirection, .increasing)
        XCTAssertEqual(loaded1?.directionStableCount, 1)
        
        XCTAssertEqual(loaded2?.lastAdaptationDirection, .decreasing)
        XCTAssertEqual(loaded2?.directionStableCount, 2)
        
        // Clean up
        ADMPersistenceManager.clearState(for: user1)
        ADMPersistenceManager.clearState(for: user2)
    }
    
    // MARK: - Codable Tests
    
    func testPerformanceHistoryEntryCodable() {
        let entry = PerformanceHistoryEntry(
            timestamp: 1234567890.0,
            overallScore: 0.85,
            normalizedKPIs: [.taskSuccess: 1.0, .reactionTime: 0.7, .tapAccuracy: 0.9],
            arousalLevel: 0.65,
            currentDOMValues: [.discriminatoryLoad: 0.4, .meanBallSpeed: 200.0],
            sessionContext: "challenge_phase"
        )
        
        // Encode
        let encoder = JSONEncoder()
        let data = try? encoder.encode(entry)
        XCTAssertNotNil(data)
        
        // Decode
        let decoder = JSONDecoder()
        let decodedEntry = try? decoder.decode(PerformanceHistoryEntry.self, from: data!)
        
        XCTAssertNotNil(decodedEntry)
        XCTAssertEqual(decodedEntry?.timestamp, entry.timestamp)
        XCTAssertEqual(decodedEntry?.overallScore, entry.overallScore)
        XCTAssertEqual(decodedEntry?.arousalLevel, entry.arousalLevel)
        XCTAssertEqual(decodedEntry?.sessionContext, entry.sessionContext)
        XCTAssertEqual(decodedEntry?.normalizedKPIs.count, 3)
        XCTAssertEqual(decodedEntry?.currentDOMValues.count, 2)
    }
    
    func testPersistedADMStateCodable() {
        let history = [
            PerformanceHistoryEntry(
                timestamp: CACurrentMediaTime(),
                overallScore: 0.6,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            )
        ]
        
        let state = PersistedADMState(
            performanceHistory: history,
            lastAdaptationDirection: .stable,
            directionStableCount: 5,
            normalizedPositions: [.targetCount: 0.4, .ballSpeedSD: 0.6],
            domPerformanceProfiles: nil
        )
        
        // Encode
        let encoder = JSONEncoder()
        let data = try? encoder.encode(state)
        XCTAssertNotNil(data)
        
        // Decode
        let decoder = JSONDecoder()
        let decodedState = try? decoder.decode(PersistedADMState.self, from: data!)
        
        XCTAssertNotNil(decodedState)
        XCTAssertEqual(decodedState?.performanceHistory.count, 1)
        XCTAssertEqual(decodedState?.lastAdaptationDirection, .stable)
        XCTAssertEqual(decodedState?.directionStableCount, 5)
        XCTAssertEqual(decodedState?.normalizedPositions.count, 2)
        XCTAssertEqual(decodedState?.version, 2)
    }
    
    // MARK: - ADM Integration Tests
    
    func testADMLoadsPersistentStateOnInit() {
        // First, save some state using the actual userId that ADM will use
        let testHistory = [
            PerformanceHistoryEntry(
                timestamp: CACurrentMediaTime() - 3600, // 1 hour ago
                overallScore: 0.7,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            )
        ]
        
        let testState = PersistedADMState(
            performanceHistory: testHistory,
            lastAdaptationDirection: .increasing,
            directionStableCount: 2,
            normalizedPositions: [.targetCount: 0.6, .meanBallSpeed: 0.7],
            domPerformanceProfiles: nil
        )
        
        // Save state using the actual userId that ADM will use
        ADMPersistenceManager.saveState(testState, for: actualUserId)
        
        // Create ADM with clearPastSessionData = false
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = false
        testConfig.enableSessionPhases = false // Disable warmup phase to prevent modification of loaded state
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        
        // Check that state was loaded
        XCTAssertEqual(adm.performanceHistory.count, 1)
        XCTAssertEqual(adm.lastAdaptationDirection, .increasing)
        XCTAssertEqual(adm.directionStableCount, 2)
        XCTAssertEqual(adm.normalizedPositions[.targetCount], 0.6)
        XCTAssertEqual(adm.normalizedPositions[.meanBallSpeed], 0.7)
    }
    
    func testADMClearsPersistentStateWhenFlagSet() {
        // First, save some state using the actual userId
        let testState = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .decreasing,
            directionStableCount: 1,
            normalizedPositions: [.targetCount: 0.8],
            domPerformanceProfiles: nil
        )
        
        ADMPersistenceManager.saveState(testState, for: actualUserId)
        
        // Create ADM with clearPastSessionData = true
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        
        // Verify state was cleared and ADM starts fresh
        XCTAssertEqual(adm.performanceHistory.count, 0)
        XCTAssertEqual(adm.lastAdaptationDirection, .stable)
        XCTAssertEqual(adm.directionStableCount, 0)
        
        // Verify persistent state was actually cleared
        XCTAssertNil(ADMPersistenceManager.loadState(for: actualUserId))
    }
    
    func testADMSaveState() {
        // Create ADM and modify its state
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.6, sessionDuration: 600)
        
        // Add some performance history
        adm.recordIdentificationPerformance(
            taskSuccess: true,
            tfTtfRatio: 0.8,
            reactionTime: 1.5,
            responseDuration: 3.0,
            averageTapAccuracy: 50.0,
            actualTargetsToFindInRound: 3
        )
        
        // Save state
        adm.saveState()
        
        // Load and verify using the ADM's actual userId
        let savedState = ADMPersistenceManager.loadState(for: adm.userId)
        XCTAssertNotNil(savedState)
        XCTAssertEqual(savedState?.performanceHistory.count, 1)
        XCTAssertEqual(savedState?.normalizedPositions.count, adm.normalizedPositions.count)
    }
    
    func testRecencyWeighting() {
        // Create history with old entries
        let oldTimestamp = CACurrentMediaTime() - (86400 * 3) // 3 days ago
        let testHistory = [
            PerformanceHistoryEntry(
                timestamp: oldTimestamp,
                overallScore: 0.5,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            )
        ]
        
        let testState = PersistedADMState(
            performanceHistory: testHistory,
            lastAdaptationDirection: .stable,
            directionStableCount: 0,
            normalizedPositions: [:],
            domPerformanceProfiles: nil
        )
        
        // Save state using the actual userId
        ADMPersistenceManager.saveState(testState, for: actualUserId)
        
        // Create ADM which should load and apply recency weighting
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = false
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        
        // Verify history was loaded
        XCTAssertEqual(adm.performanceHistory.count, 1)
        
        // The actual recency weighting would be applied in confidence calculations
        // We can test that the old data doesn't heavily influence new adaptations
        let confidence = adm.calculateAdaptationConfidence()
        XCTAssertLessThan(confidence.history, 0.5) // Old data should reduce history confidence
    }
    
    // MARK: - Notification Tests
    
    func testSaveNotificationTriggersADMSave() {
        // Create a mock ADM
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
        
        // Add some test data
        adm.recordIdentificationPerformance(
            taskSuccess: false,
            tfTtfRatio: 0.5,
            reactionTime: 2.0,
            responseDuration: 4.0,
            averageTapAccuracy: 75.0,
            actualTargetsToFindInRound: 4
        )
        
        // Clear any existing saved state
        ADMPersistenceManager.clearState(for: adm.userId)
        
        // Create expectation for async save
        let expectation = XCTestExpectation(description: "ADM state saved")
        
        // Create a test scene that mimics the notification handling
        class TestScene {
            let adm: AdaptiveDifficultyManager
            
            init(adm: AdaptiveDifficultyManager) {
                self.adm = adm
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(saveADMState),
                    name: Notification.Name("SaveADMState"),
                    object: nil
                )
            }
            
            @objc func saveADMState() {
                adm.saveState()
            }
            
            deinit {
                NotificationCenter.default.removeObserver(self)
            }
        }
        
        let testScene = TestScene(adm: adm)
        
        // Post the notification
        NotificationCenter.default.post(name: Notification.Name("SaveADMState"), object: nil)
        
        // Wait a moment for the save to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Verify state was saved using the adm's userId
            let savedState = ADMPersistenceManager.loadState(for: self.adm.userId)
            XCTAssertNotNil(savedState)
            XCTAssertEqual(savedState?.performanceHistory.count, 1)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Edge Cases
    
    func testHandlesEmptyPerformanceHistory() {
        let state = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .stable,
            directionStableCount: 0,
            normalizedPositions: [:],
            domPerformanceProfiles: nil
        )
        
        ADMPersistenceManager.saveState(state, for: actualUserId)
        let loaded = ADMPersistenceManager.loadState(for: actualUserId)
        
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.performanceHistory.count, 0)
    }
    
    func testHistoryTrimming() {
        // Create history that exceeds max size
        var largeHistory: [PerformanceHistoryEntry] = []
        for i in 0..<20 { // Assuming max history size is 10
            largeHistory.append(PerformanceHistoryEntry(
                timestamp: CACurrentMediaTime() + Double(i),
                overallScore: 0.5,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            ))
        }
        
        let state = PersistedADMState(
            performanceHistory: largeHistory,
            lastAdaptationDirection: .stable,
            directionStableCount: 0,
            normalizedPositions: [:],
            domPerformanceProfiles: nil
        )
        
        // Save state using the actual userId
        ADMPersistenceManager.saveState(state, for: actualUserId)
        
        // Create ADM which should trim history on load
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = false
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        
        // Verify history was trimmed to max size
        XCTAssertLessThanOrEqual(adm.performanceHistory.count, config.performanceHistoryWindowSize)
    }
    
    // MARK: - UserIDManager Independence Tests
    
    func testUserIDManagerIndependence() {
        // Get current user ID
        let currentUserId = UserIDManager.getUserId()
        
        // Save ADM state for this user
        let testState = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .increasing,
            directionStableCount: 2,
            normalizedPositions: [.targetCount: 0.6],
            domPerformanceProfiles: nil
        )
        ADMPersistenceManager.saveState(testState, for: currentUserId)
        
        // Create ADM with clearPastSessionData = true
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true
        testConfig.enableSessionPhases = false // Disable warmup phase for this test
        let adm1 = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        
        // Verify ADM state was cleared
        XCTAssertNil(ADMPersistenceManager.loadState(for: currentUserId))
        
        // Verify UserIDManager still returns the same user ID
        let userIdAfterClear = UserIDManager.getUserId()
        XCTAssertEqual(currentUserId, userIdAfterClear, "UserIDManager should maintain user ID independently of ADM clear flag")
        
        // Save new state and verify it persists
        let newState = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .decreasing,
            directionStableCount: 1,
            normalizedPositions: [.targetCount: 0.3],
            domPerformanceProfiles: nil
        )
        ADMPersistenceManager.saveState(newState, for: currentUserId)
        
        // Create another ADM without clearing
        testConfig.clearPastSessionData = false
        testConfig.enableSessionPhases = false // Keep warmup disabled
        let adm2 = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        
        // Verify it loaded the new state
        XCTAssertEqual(adm2.lastAdaptationDirection, .decreasing)
        XCTAssertEqual(adm2.normalizedPositions[.targetCount], 0.3)
    }
    
    // MARK: - Full Lifecycle Integration Test
    
    func testFullLifecycleWithAgedData() {
        // PHASE 1: Initial session
        print("=== PHASE 1: Initial Session ===")
        
        // Create ADM for first session
        var config1 = GameConfiguration()
        config1.clearPastSessionData = true // Start fresh
        let adm1 = AdaptiveDifficultyManager(configuration: config1, initialArousal: 0.7, sessionDuration: 600)
        
        // Simulate several identification rounds with good performance
        for i in 0..<5 {
            adm1.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 0.9 - (Double(i) * 0.05), // Gradually declining
                reactionTime: 1.0 + (Double(i) * 0.1), // Getting slower
                responseDuration: 2.0 + (Double(i) * 0.2),
                averageTapAccuracy: 30.0 + (Double(i) * 5.0),
                actualTargetsToFindInRound: 3
            )
        }
        
        // Check final state of first session
        XCTAssertEqual(adm1.performanceHistory.count, 5)
        let finalPositions1 = adm1.normalizedPositions
        print("Final positions after session 1:")
        for (dom, pos) in finalPositions1 {
            print("  \(dom): \(String(format: "%.3f", pos))")
        }
        
        // Save state (simulating app backgrounding)
        adm1.saveState()
        
        // PHASE 2: Return after 25 hours (data should be aged)
        print("\n=== PHASE 2: Return After 25 Hours ===")
        
        // Manually age the saved data by modifying timestamps
        if var savedState = ADMPersistenceManager.loadState(for: adm1.userId) {
            // Age all history entries by 25 hours
            let ageOffset = 25.0 * 3600.0 // 25 hours in seconds
            let agedHistory = savedState.performanceHistory.map { entry in
                PerformanceHistoryEntry(
                    timestamp: entry.timestamp - ageOffset,
                    overallScore: entry.overallScore,
                    normalizedKPIs: entry.normalizedKPIs,
                    arousalLevel: entry.arousalLevel,
                    currentDOMValues: entry.currentDOMValues,
                    sessionContext: entry.sessionContext
                )
            }
            
            let agedState = PersistedADMState(
                performanceHistory: agedHistory,
                lastAdaptationDirection: savedState.lastAdaptationDirection,
                directionStableCount: savedState.directionStableCount,
                normalizedPositions: savedState.normalizedPositions,
                domPerformanceProfiles: savedState.domPerformanceProfiles
            )
            
            // Save the aged state
            ADMPersistenceManager.saveState(agedState, for: adm1.userId)
        }
        
        // Create new ADM instance (simulating app launch)
        var config2 = GameConfiguration()
        config2.clearPastSessionData = false // Keep old data
        let adm2 = AdaptiveDifficultyManager(configuration: config2, initialArousal: 0.5, sessionDuration: 600)
        
        // Verify aged data was loaded
        XCTAssertEqual(adm2.performanceHistory.count, 5)
        
        // Check confidence is reduced due to aged data
        let confidence = adm2.calculateAdaptationConfidence()
        print("Confidence with aged data:")
        print("  Total: \(String(format: "%.3f", confidence.total))")
        print("  History: \(String(format: "%.3f", confidence.history))")
        XCTAssertLessThan(confidence.history, 0.5, "History confidence should be reduced due to aged data")
        
        // Simulate a performance round with different performance
        adm2.recordIdentificationPerformance(
            taskSuccess: false,
            tfTtfRatio: 0.4,
            reactionTime: 3.0,
            responseDuration: 6.0,
            averageTapAccuracy: 100.0,
            actualTargetsToFindInRound: 5
        )
        
        // Check that adaptation is more cautious due to low confidence
        let positions2 = adm2.normalizedPositions
        print("\nPositions after poor performance with aged data:")
        for (dom, pos) in positions2 {
            let change = pos - (finalPositions1[dom] ?? 0.5)
            print("  \(dom): \(String(format: "%.3f", pos)) (change: \(String(format: "%+.3f", change)))")
        }
        
        // PHASE 3: Continue with more rounds to rebuild confidence
        print("\n=== PHASE 3: Rebuilding Confidence ===")
        
        // Add more recent performance data
        for i in 0..<3 {
            adm2.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 0.6,
                reactionTime: 2.0,
                responseDuration: 4.0,
                averageTapAccuracy: 60.0,
                actualTargetsToFindInRound: 4
            )
        }
        
        // Check confidence has improved with fresh data
        let newConfidence = adm2.calculateAdaptationConfidence()
        print("Confidence after new data:")
        print("  Total: \(String(format: "%.3f", newConfidence.total))")
        print("  History: \(String(format: "%.3f", newConfidence.history))")
        XCTAssertGreaterThan(newConfidence.total, confidence.total, "Confidence should improve with fresh data")
        
        // Verify history contains both old and new entries
        XCTAssertEqual(adm2.performanceHistory.count, 9) // 5 old + 1 + 3 new
        
        // Check that recent entries have more influence
        let recentScores = adm2.performanceHistory.suffix(4).map { $0.overallScore }
        let averageRecentScore = recentScores.reduce(0.0, +) / CGFloat(recentScores.count)
        print("\nAverage of recent 4 scores: \(String(format: "%.3f", averageRecentScore))")
    }
}
