//
//  ADMPersistenceIntegrationTests.swift
//  KB2Tests
//
//  Created by Cline on 6/21/25.
//

import XCTest
@testable import KB2

class ADMPersistenceIntegrationTests: XCTestCase {
    
    var adm: AdaptiveDifficultyManager!
    var config: GameConfiguration!
    let testUserId = "test_user_integration"
    
    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        config.clearPastSessionData = true // Start fresh
        config.persistDomPerformanceProfilesInState = false // Speed-oriented: exclude large DOM profiles for these perf-focused tests
        adm = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600,
            userId: testUserId
        )
    }
    
    override func tearDown() {
        ADMPersistenceManager.clearState(for: testUserId)
        adm = nil
        config = nil
        super.tearDown()
    }
    
    // MARK: - Multi-Day Session Tests
    
    func testMultiDaySessionContinuity() {
        // GIVEN: A simulated multi-day usage pattern
        let currentTime = CACurrentMediaTime()
        var performanceHistory: [PerformanceHistoryEntry] = []
        
        // Day 1: Morning session (72 hours ago)
        for i in 0..<3 {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - (72 * 3600) - Double(i * 300), // 5 min apart
                overallScore: 0.4 + Double(i) * 0.05, // Improving performance
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: "day1_morning"
            )
            performanceHistory.append(entry)
        }
        
        // Day 2: Evening session (48 hours ago)
        for i in 0..<3 {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - (48 * 3600) - Double(i * 300),
                overallScore: 0.5 + Double(i) * 0.05, // Better performance
                normalizedKPIs: [:],
                arousalLevel: 0.6,
                currentDOMValues: [:],
                sessionContext: "day2_evening"
            )
            performanceHistory.append(entry)
        }
        
        // Day 3: Morning session (24 hours ago)
        for i in 0..<4 {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - (24 * 3600) - Double(i * 300),
                overallScore: 0.6 + Double(i) * 0.03, // Consistent good performance
                normalizedKPIs: [:],
                arousalLevel: 0.7,
                currentDOMValues: [:],
                sessionContext: "day3_morning"
            )
            performanceHistory.append(entry)
        }
        
        // Set up ADM with this history
        adm.performanceHistory = performanceHistory
        adm.lastAdaptationDirection = .increasing
        adm.directionStableCount = 3
        adm.normalizedPositions[.discriminatoryLoad] = 0.7
        adm.normalizedPositions[.meanBallSpeed] = 0.65
        
        // WHEN: Saving and loading state
        adm.saveState()
        
        // Create new ADM instance
        config.clearPastSessionData = false
        config.enableSessionPhases = false // Disable warmup for this test
        let newADM = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600,
            userId: testUserId
        )
        
        // THEN: History should be loaded with proper recency weighting
        XCTAssertEqual(newADM.performanceHistory.count, 10, "All history should be loaded")
        
        // Calculate confidence to verify recency weighting is applied
        let confidence = newADM.calculateAdaptationConfidence()
        
        // With aged data, confidence should be lower than if all data was recent
        XCTAssertLessThan(confidence.history, 0.7, "History confidence should reflect aged data")
        XCTAssertGreaterThan(confidence.history, 0.3, "History confidence should still have some value")
        
        // DOM positions should be preserved
        XCTAssertEqual(Double(newADM.normalizedPositions[.discriminatoryLoad] ?? 0), 0.7, accuracy: 0.001)
        XCTAssertEqual(Double(newADM.normalizedPositions[.meanBallSpeed] ?? 0), 0.65, accuracy: 0.001)
    }
    
    func testPerformanceWithMaxHistorySize() {
        // GIVEN: Maximum history entries
        var performanceHistory: [PerformanceHistoryEntry] = []
        let currentTime = CACurrentMediaTime()
        
        for i in 0..<config.performanceHistoryWindowSize {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - Double(i * 60), // 1 minute apart
                overallScore: 0.5 + sin(Double(i) * 0.5) * 0.3, // Oscillating performance
                normalizedKPIs: [
                    .taskSuccess: i % 2 == 0 ? 1.0 : 0.0,
                    .tfTtfRatio: 0.7 + Double(i % 3) * 0.1,
                    .reactionTime: 0.6,
                    .responseDuration: 0.5,
                    .tapAccuracy: 0.8
                ],
                arousalLevel: 0.5 + Double(i) * 0.05,
                currentDOMValues: [
                    .discriminatoryLoad: 0.5,
                    .meanBallSpeed: 100.0,
                    .ballSpeedSD: 20.0,
                    .responseTime: 3.0,
                    .targetCount: 4.0
                ],
                sessionContext: "max_history_test"
            )
            performanceHistory.append(entry)
        }
        
        adm.performanceHistory = performanceHistory
        
        // WHEN: Saving and loading
        let startTime = CFAbsoluteTimeGetCurrent()
        adm.saveState()
        let saveTime = CFAbsoluteTimeGetCurrent() - startTime
        
        config.clearPastSessionData = false
        config.enableSessionPhases = false // Disable warmup for this test
        let loadStartTime = CFAbsoluteTimeGetCurrent()
        let newADM = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600,
            userId: testUserId
        )
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStartTime
        
        // THEN: Performance should be acceptable
        XCTAssertLessThan(saveTime, 0.1, "Save should complete in under 100ms")
        XCTAssertLessThan(loadTime, 0.1, "Load should complete in under 100ms")
        XCTAssertEqual(newADM.performanceHistory.count, config.performanceHistoryWindowSize)
        
        // Verify data integrity
        for i in 0..<newADM.performanceHistory.count {
            XCTAssertEqual(newADM.performanceHistory[i].sessionContext, "max_history_test")
        }
    }
    
    func testVeryOldDataHandling() {
        // GIVEN: Very old data (>1 week)
        let currentTime = CACurrentMediaTime()
        let veryOldEntry = PerformanceHistoryEntry(
            timestamp: currentTime - (7 * 24 * 3600), // 1 week old
            overallScore: 0.9, // High score but very old
            normalizedKPIs: [:],
            arousalLevel: 0.5,
            currentDOMValues: [:],
            sessionContext: "ancient_session"
        )
        
        let recentEntry = PerformanceHistoryEntry(
            timestamp: currentTime - 300, // 5 minutes ago
            overallScore: 0.5, // Moderate score but recent
            normalizedKPIs: [:],
            arousalLevel: 0.5,
            currentDOMValues: [:],
            sessionContext: "recent_session"
        )
        
        adm.performanceHistory = [veryOldEntry, recentEntry]
        
        // WHEN: Calculating confidence
        let confidence = adm.calculateAdaptationConfidence()
        
        // THEN: Very old data should have minimal impact
        // The weight of 1-week-old data should be approximately e^(-7*24/24) = e^(-7) ≈ 0.0009
        let expectedOldWeight = exp(-7.0)
        XCTAssertLessThan(expectedOldWeight, 0.001, "Week-old data should have <0.1% weight")
        
        // The effective history size should be close to 1 (just the recent entry)
        let effectiveSize = 1.0 + expectedOldWeight
        // Use the baseline of 10 entries for full confidence instead of window size
        let historyConfidenceBaseline: CGFloat = 10.0
        let expectedHistoryConfidence = effectiveSize / historyConfidenceBaseline
        XCTAssertLessThan(abs(confidence.history - expectedHistoryConfidence), 0.05, 
                         "History confidence should reflect minimal contribution from old data")
    }
    
    func testRealWorldUsagePattern() {
        // GIVEN: A realistic usage pattern over several days
        let currentTime = CACurrentMediaTime()
        let sessions: [(startHoursAgo: Double, duration: Int, performance: ClosedRange<CGFloat>)] = [
            (72, 5, 0.3...0.5),   // 3 days ago: 5 rounds, struggling
            (48, 8, 0.4...0.6),   // 2 days ago: 8 rounds, improving
            (24, 10, 0.5...0.7),  // 1 day ago: 10 rounds, good performance
            (2, 6, 0.6...0.8),    // 2 hours ago: 6 rounds, very good
        ]
        
        var performanceHistory: [PerformanceHistoryEntry] = []
        
        for session in sessions {
            for round in 0..<session.duration {
                let progress = CGFloat(round) / CGFloat(session.duration)
                let score = session.performance.lowerBound + 
                           (session.performance.upperBound - session.performance.lowerBound) * progress
                
                let entry = PerformanceHistoryEntry(
                    timestamp: currentTime - (session.startHoursAgo * 3600) + Double(round * 60),
                    overallScore: score,
                    normalizedKPIs: [:],
                    arousalLevel: 0.5,
                    currentDOMValues: [:],
                    sessionContext: "session_\(Int(session.startHoursAgo))h_ago"
                )
                performanceHistory.append(entry)
            }
        }
        
        // Only keep the most recent entries up to window size
        if performanceHistory.count > config.performanceHistoryWindowSize {
            performanceHistory = Array(performanceHistory.suffix(config.performanceHistoryWindowSize))
        }
        
        adm.performanceHistory = performanceHistory
        adm.lastAdaptationDirection = .increasing
        adm.directionStableCount = 5
        
        // WHEN: Calculating metrics and saving
        let (average, trend, variance) = adm.getPerformanceMetrics()
        let confidence = adm.calculateAdaptationConfidence()
        
        adm.saveState()
        
        // THEN: Metrics should reflect the improving pattern
        XCTAssertGreaterThan(trend, 0, "Trend should be positive for improving performance")
        XCTAssertGreaterThan(average, 0.5, "Average should reflect recent good performance")
        XCTAssertLessThan(variance, 0.1, "Variance should be relatively low for consistent improvement")
        XCTAssertGreaterThan(confidence.total, 0.6, "Confidence should be reasonably high")
        
        // Verify persistence
        config.clearPastSessionData = false
        config.enableSessionPhases = false // Disable warmup for this test
        let newADM = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600,
            userId: testUserId
        )
        
        let (newAverage, newTrend, newVariance) = newADM.getPerformanceMetrics()
        XCTAssertEqual(newAverage, average, accuracy: 0.001, "Metrics should be preserved")
        XCTAssertEqual(newTrend, trend, accuracy: 0.001, "Trend should be preserved")
        XCTAssertEqual(newVariance, variance, accuracy: 0.001, "Variance should be preserved")
    }
    
    func testAppLifecycleSimulation() {
        // GIVEN: ADM with some performance history
        adm.performanceHistory = TestHelpers.createPerformanceHistory(scores: [0.5, 0.6, 0.7])
        adm.normalizedPositions[.discriminatoryLoad] = 0.65
        
        // Simulate GameScene's saveADMState being called
        let saveExpectation = expectation(description: "ADM state saved")
        
        // WHEN: Simulating app going to background
        DispatchQueue.main.async {
            // This simulates what GameScene does when receiving the notification
            self.adm.saveState()
            saveExpectation.fulfill()
        }
        
        wait(for: [saveExpectation], timeout: 1.0)
        
        // THEN: State should be persisted
        let savedState = ADMPersistenceManager.loadState(for: testUserId)
        XCTAssertNotNil(savedState, "State should be persisted after save")
        XCTAssertEqual(savedState?.performanceHistory.count, 3)
        XCTAssertEqual(Double(savedState?.normalizedPositions[.discriminatoryLoad] ?? 0), 0.65, accuracy: 0.001)
        
        // Simulate app relaunch
        config.clearPastSessionData = false
        config.enableSessionPhases = false // Disable warmup for this test
        let newADM = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600,
            userId: testUserId
        )
        
        XCTAssertEqual(newADM.performanceHistory.count, 3, "History should be restored")
        XCTAssertEqual(Double(newADM.normalizedPositions[.discriminatoryLoad] ?? 0), 0.65, accuracy: 0.001)
    }
}
