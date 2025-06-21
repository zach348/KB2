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
            normalizedPositions: [.targetCount: 0.5, .meanBallSpeed: 0.6]
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
            normalizedPositions: [:]
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
            normalizedPositions: [.targetCount: 0.3]
        )
        
        let state2 = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .decreasing,
            directionStableCount: 2,
            normalizedPositions: [.targetCount: 0.7]
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
            normalizedPositions: [.targetCount: 0.4, .ballSpeedSD: 0.6]
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
        XCTAssertEqual(decodedState?.version, 1)
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
            normalizedPositions: [.targetCount: 0.6, .meanBallSpeed: 0.7]
        )
        
        // Save state using the actual userId that ADM will use
        ADMPersistenceManager.saveState(testState, for: actualUserId)
        
        // Create ADM with clearPastSessionData = false
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = false
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5)
        
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
            normalizedPositions: [.targetCount: 0.8]
        )
        
        ADMPersistenceManager.saveState(testState, for: actualUserId)
        
        // Create ADM with clearPastSessionData = true
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5)
        
        // Verify state was cleared and ADM starts fresh
        XCTAssertEqual(adm.performanceHistory.count, 0)
        XCTAssertEqual(adm.lastAdaptationDirection, .stable)
        XCTAssertEqual(adm.directionStableCount, 0)
        
        // Verify persistent state was actually cleared
        XCTAssertNil(ADMPersistenceManager.loadState(for: actualUserId))
    }
    
    func testADMSaveState() {
        // Create ADM and modify its state
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.6)
        
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
            normalizedPositions: [:]
        )
        
        // Save state using the actual userId
        ADMPersistenceManager.saveState(testState, for: actualUserId)
        
        // Create ADM which should load and apply recency weighting
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = false
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5)
        
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
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5)
        
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
            normalizedPositions: [:]
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
            normalizedPositions: [:]
        )
        
        // Save state using the actual userId
        ADMPersistenceManager.saveState(state, for: actualUserId)
        
        // Create ADM which should trim history on load
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = false
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5)
        
        // Verify history was trimmed to max size
        XCTAssertLessThanOrEqual(adm.performanceHistory.count, config.performanceHistoryWindowSize)
    }
}
