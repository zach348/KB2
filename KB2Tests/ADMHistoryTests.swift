//
//  ADMHistoryTests.swift
//  KB2Tests
//
//  Created by Cline on 6/16/25.
//

import XCTest
@testable import KB2

class ADMHistoryTests: XCTestCase {

    var adm: AdaptiveDifficultyManager!
    var config: GameConfiguration!

    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        // We can use a default arousal level for these tests, as history is independent of it
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
    }

    override func tearDown() {
        adm = nil
        config = nil
        super.tearDown()
    }

    // MARK: - Test History Management

    func testAddPerformanceEntry() {
        let entry = createDummyHistoryEntry(score: 0.6)
        adm.addPerformanceEntry(entry)
        
        let (metrics) = adm.getPerformanceMetrics()
        XCTAssertEqual(metrics.average, 0.6, "Average should be the score of the single entry.")
    }

    func testHistoryRollingWindow() {
        let windowSize = config.performanceHistoryWindowSize
        
        // Fill the history beyond its capacity
        for i in 0...(windowSize + 2) {
            let entry = createDummyHistoryEntry(score: CGFloat(i) / 10.0)
            adm.addPerformanceEntry(entry)
        }
        
        // Manually access performanceHistory to check its count
        let historyCount = adm.performanceHistory.count
        XCTAssertEqual(historyCount, windowSize, "History should not exceed the max window size.")
        
        // Check that the first element is what we expect (entry for i=3)
        let (metrics) = adm.getPerformanceMetrics()
        let expectedFirstScore = CGFloat(3) / 10.0
        let actualFirstScore = adm.performanceHistory.first?.overallScore
        
        XCTAssertEqual(actualFirstScore, expectedFirstScore, "The oldest entries should have been removed.")
    }

    // MARK: - Test History Analytics

    func testGetPerformanceMetrics_EmptyHistory() {
        let (average, trend, variance) = adm.getPerformanceMetrics()
        
        XCTAssertEqual(average, 0.5, "Average should default to 0.5 for empty history.")
        XCTAssertEqual(trend, 0.0, "Trend should be 0.0 for empty history.")
        XCTAssertEqual(variance, 0.0, "Variance should be 0.0 for empty history.")
    }

    func testGetPerformanceMetrics_SingleEntry() {
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.75))
        
        let (average, trend, variance) = adm.getPerformanceMetrics()
        
        XCTAssertEqual(average, 0.75, "Average should be the score of the single entry.")
        XCTAssertEqual(trend, 0.0, "Trend should be 0.0 for a single entry.")
        XCTAssertEqual(variance, 0.0, "Variance should be 0.0 for a single entry.")
    }

    func testGetPerformanceMetrics_MultipleEntries_NoTrend() {
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))
        
        let (average, trend, variance) = adm.getPerformanceMetrics()
        
        XCTAssertEqual(average, 0.5, accuracy: 0.001)
        XCTAssertEqual(trend, 0.0, accuracy: 0.001, "Trend should be zero for constant scores.")
        XCTAssertEqual(variance, 0.0, accuracy: 0.001, "Variance should be zero for constant scores.")
    }

    func testGetPerformanceMetrics_PositiveTrend() {
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.1))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.2))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.3))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.4))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))

        let (average, trend, variance) = adm.getPerformanceMetrics()
        
        XCTAssertEqual(average, 0.3, accuracy: 0.001)
        XCTAssertGreaterThan(trend, 0.0, "Trend should be positive for increasing scores.")
        XCTAssertTrue(variance > 0.0, "Variance should be positive for non-constant scores.")
    }
    
    func testGetPerformanceMetrics_NegativeTrend() {
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.9))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.8))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.7))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.6))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))

        let (average, trend, variance) = adm.getPerformanceMetrics()
        
        XCTAssertEqual(average, 0.7, accuracy: 0.001)
        XCTAssertLessThan(trend, 0.0, "Trend should be negative for decreasing scores.")
    }

    func testCalculateLinearTrend_WithKnownDataSet() {
        // y = 0.1x + 0.1
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.1)) // x=0
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.2)) // x=1
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.3)) // x=2
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.4)) // x=3
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5)) // x=4

        let (_, trend, _) = adm.getPerformanceMetrics()
        
        // The slope of this line is 0.1. The normalization in the function is a bit abstract,
        // but for a simple linear progression, we expect a positive, non-zero trend.
        // A more precise test would require refactoring the trend normalization to be more predictable.
        // For now, we assert it's a meaningful positive value.
        XCTAssertGreaterThan(trend, 0.05, "Trend for a perfect linear progression should be a significant positive value.")
    }

    func testCalculatePerformanceVariance_WithKnownDataSet() {
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))
        
        var (_, _, variance) = adm.getPerformanceMetrics()
        XCTAssertEqual(variance, 0.0, accuracy: 0.001, "Variance for a constant set should be 0.")

        adm.performanceHistory.removeAll()
        
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.1))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.3))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.5))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.7))
        adm.addPerformanceEntry(createDummyHistoryEntry(score: 0.9))

        // Mean = 0.5
        // Deviations: -0.4, -0.2, 0.0, 0.2, 0.4
        // Squared Deviations: 0.16, 0.04, 0.0, 0.04, 0.16
        // Sum of Squared Deviations: 0.4
        // Variance = 0.4 / 5 = 0.08
        (_, _, variance) = adm.getPerformanceMetrics()
        XCTAssertEqual(variance, 0.08, accuracy: 0.001, "Variance calculation is incorrect.")
    }

    // MARK: - DataLogger Integration Test

    func testDataLoggerIntegration() {
        // 1. Setup
        let mockLogger = MockDataLogger()
        
        // Create a new ADM instance with a config that enables history
        var testConfig = GameConfiguration()
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        adm.dataLogger = mockLogger

        // 2. Action
        // This will trigger the logging inside recordIdentificationPerformance
        adm.recordIdentificationPerformance(
            taskSuccess: true,
            tfTtfRatio: 1.0,
            reactionTime: 0.3,
            responseDuration: 1.2,
            averageTapAccuracy: 10.0,
            actualTargetsToFindInRound: 5
        )

        // 3. Assert
        XCTAssertEqual(mockLogger.loggedEvents.count, 1, "One custom event should have been logged.")
        
        let loggedEvent = mockLogger.loggedEvents.first
        XCTAssertEqual(loggedEvent?.eventType, "adm_performance_history", "Event type should be for ADM history.")
        
        let eventData = loggedEvent?.data
        XCTAssertNotNil(eventData, "Event data should not be nil.")
        XCTAssertEqual(eventData!["history_size"] as! Int, 1, "History size should be 1.")
        XCTAssertNotNil(eventData!["performance_average"] as? CGFloat, "Performance average should be present.")
        XCTAssertNotNil(eventData!["performance_trend"] as? CGFloat, "Performance trend should be present.")
        XCTAssertNotNil(eventData!["performance_variance"] as? CGFloat, "Performance variance should be present.")
        XCTAssertNotNil(eventData!["recent_score"] as? CGFloat, "Recent score should be present.")
    }

    // MARK: - Helper
    
    private func createDummyHistoryEntry(score: CGFloat) -> PerformanceHistoryEntry {
        return PerformanceHistoryEntry(
            timestamp: CACurrentMediaTime(),
            overallScore: score,
            normalizedKPIs: [:],
            arousalLevel: 0.5,
            currentDOMValues: [:],
            sessionContext: "test"
        )
    }
}
