//
//  ADMConfidenceTests.swift
//  KB2Tests
//
//  Created by Cline on 6/21/25.
//

import XCTest
@testable import KB2

class ADMConfidenceTests: XCTestCase {

    var adm: AdaptiveDifficultyManager!
    var config: GameConfiguration!

    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        config.clearPastSessionData = true  // Ensure clean state for tests
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
    }

    override func tearDown() {
        adm = nil
        config = nil
        super.tearDown()
    }

    // MARK: - Confidence Calculation Tests

    func testConfidence_InitialState() {
        // With no history, confidence should be 0.5
        let confidence = adm.calculateAdaptationConfidence().total
        XCTAssertEqual(confidence, 0.5, "Initial confidence should be 0.5")
    }

    func testConfidence_LowVariance() {
        // GIVEN: A history with very consistent performance
        adm.performanceHistory = TestHelpers.createPerformanceHistory(scores: [0.5, 0.51, 0.49])
        adm.directionStableCount = 5 // Max stability
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence().total
        
        // THEN: Confidence should be reasonably high due to low variance, but adjusted for aggressive recency weighting
        XCTAssertGreaterThan(confidence, 0.65, "Confidence should be reasonably high for low variance performance")
    }

    func testConfidence_HighVariance() {
        // GIVEN: A history with erratic performance
        adm.performanceHistory = TestHelpers.createPerformanceHistory(scores: [0.9, 0.1, 0.8])
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence().total
        
        // THEN: Confidence should be low
        XCTAssertLessThan(confidence, 0.4, "Confidence should be low for high variance performance")
    }

    func testConfidence_StableDirection() {
        // GIVEN: A stable adaptation direction with recent data for aggressive recency weighting
        adm.directionStableCount = 5 // Max stability
        adm.lastAdaptationDirection = .increasing
        
        // Create recent performance history (within last 0.35 hours to get full weight)
        let currentTime = CACurrentMediaTime()
        var recentHistory: [PerformanceHistoryEntry] = []
        for (index, score) in [0.6, 0.65, 0.7].enumerated() {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - Double(index * 300), // 5-minute intervals
                overallScore: score,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            )
            recentHistory.append(entry)
        }
        adm.performanceHistory = recentHistory
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence().total
        
        // THEN: Confidence should be reasonably high (adjusted for aggressive recency weighting)
        XCTAssertGreaterThan(confidence, 0.6, "Confidence should be reasonably high for stable adaptation direction with recent data")
    }
    
    func testConfidence_InsufficientHistory() {
        // GIVEN: Only one performance entry
        adm.performanceHistory = [TestHelpers.createPerformanceHistory(scores: [0.6]).first!]
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence()
        
        // THEN: History component of confidence should be low
        // With the new baseline of 10 entries for full confidence:
        // 1 entry / 10 baseline = 0.1
        XCTAssertEqual(confidence.history, 0.1, accuracy: 0.0001, "History confidence should be low with few entries")
        XCTAssertLessThan(confidence.total, 0.5, "Overall confidence should be modest with insufficient history")
    }

    // MARK: - Effective Threshold Tests

    func testEffectiveThresholds_HighConfidence() {
        // GIVEN: High confidence state with recent data for aggressive recency weighting
        let currentTime = CACurrentMediaTime()
        var recentHistory: [PerformanceHistoryEntry] = []
        
        // Create recent performance history with low variance (within last 10 minutes)
        for (index, score) in [0.5, 0.51, 0.52, 0.53, 0.54, 0.55, 0.56, 0.57, 0.58, 0.59].enumerated() {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - Double(index * 60), // 1-minute intervals for recent data
                overallScore: score,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            )
            recentHistory.append(entry)
        }
        adm.performanceHistory = recentHistory
        adm.directionStableCount = 5
        
        // WHEN: Effective thresholds are calculated
        let thresholds = adm.getEffectiveAdaptationThresholds()
        
        // THEN: Thresholds should be reasonably close to the base configuration (with some tolerance for aggressive recency weighting)
        XCTAssertEqual(thresholds.increaseThreshold, config.adaptationIncreaseThreshold, accuracy: 0.03, "Increase threshold should not widen much with high confidence from recent data")
        XCTAssertEqual(thresholds.decreaseThreshold, config.adaptationDecreaseThreshold, accuracy: 0.03, "Decrease threshold should not widen much with high confidence from recent data")
    }

    func testEffectiveThresholds_LowConfidence() {
        // GIVEN: Low confidence state
        adm.performanceHistory = TestHelpers.createPerformanceHistory(scores: [0.9, 0.1, 0.8]) // High variance
        adm.directionStableCount = 0 // No stable direction
        
        // WHEN: Effective thresholds are calculated
        let thresholds = adm.getEffectiveAdaptationThresholds()
        
        // THEN: Thresholds should be significantly wider than base
        XCTAssertGreaterThan(thresholds.increaseThreshold, config.adaptationIncreaseThreshold, "Increase threshold should widen with low confidence")
        XCTAssertLessThan(thresholds.decreaseThreshold, config.adaptationDecreaseThreshold, "Decrease threshold should widen with low confidence")
    }

    // MARK: - Adaptation Scaling Tests

    func testAdaptationSignal_ScaledByConfidence() {
        // GIVEN: A performance score that would generate a strong adaptation signal
        let performanceScore: CGFloat = 0.8
        let baseSignal = (performanceScore - 0.5) * 2.0 // Expected signal without scaling
        
        // AND: A low confidence state
        adm.performanceHistory = TestHelpers.createPerformanceHistory(scores: [0.9, 0.1, 0.8])
        let confidence = adm.calculateAdaptationConfidence().total
        XCTAssertLessThan(confidence, 0.5, "Precondition: confidence should be low")

        // WHEN: The DOM targets are modulated
        adm.modulateDOMTargets(overallPerformanceScore: performanceScore)
        
        // THEN: The actual adaptation should be dampened by the low confidence
        // This is an indirect test. We check the resulting normalized position.
        // We expect the change to be less than if confidence were 1.0
        let initialPosition = 0.5
        let finalPosition = adm.normalizedPositions[.discriminatoryLoad]!
        
        let expectedChangeWithFullConfidence = baseSignal * (config.domHardeningSmoothingFactors[.discriminatoryLoad] ?? 0.1)
        let actualChange = finalPosition - initialPosition
        
        XCTAssertLessThan(abs(actualChange), abs(expectedChangeWithFullConfidence), "Adaptation change should be dampened by low confidence")
    }
    
    // MARK: - Recency Weighting Tests
    
    func testRecencyWeighting_RecentDataHighWeight() {
        // GIVEN: Performance history with recent data
        let currentTime = CACurrentMediaTime()
        let recentEntry = PerformanceHistoryEntry(
            timestamp: currentTime - 60, // 1 minute ago
            overallScore: 0.7,
            normalizedKPIs: [:],
            arousalLevel: 0.5,
            currentDOMValues: [:],
            sessionContext: nil
        )
        adm.performanceHistory = [recentEntry]
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence()
        
        // THEN: Recent data should have nearly full weight (close to 1.0)
        // The effective history size should be close to 1.0
        XCTAssertGreaterThan(confidence.history, 0.09, "Recent data should contribute nearly full weight to history confidence")
    }
    
    func testRecencyWeighting_OldDataLowWeight() {
        // GIVEN: Performance history with old data (0.7 hours = 2 half-lives with 0.35h half-life)
        let currentTime = CACurrentMediaTime()
        let oldEntry = PerformanceHistoryEntry(
            timestamp: currentTime - (0.7 * 3600), // 0.7 hours ago (2 half-lives)
            overallScore: 0.7,
            normalizedKPIs: [:],
            arousalLevel: 0.5,
            currentDOMValues: [:],
            sessionContext: nil
        )
        adm.performanceHistory = [oldEntry]
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence()
        
        // THEN: Old data at 2 half-lives should have approximately 25% weight (0.25)
        // The effective history size should be around 0.25, making history confidence around 0.025
        XCTAssertLessThan(confidence.history, 0.035, "0.7-hour old data should contribute ~25% weight")
        XCTAssertGreaterThan(confidence.history, 0.015, "0.7-hour old data should contribute ~25% weight")
    }
    
    func testRecencyWeighting_MixedAgeData() {
        // GIVEN: Performance history with mixed age data (using 0.35h half-life)
        let currentTime = CACurrentMediaTime()
        var history: [PerformanceHistoryEntry] = []
        
        // Add entries at different ages - use shorter times for 0.35h half-life
        for hoursAgo in [0.1, 0.35, 0.7, 1.05, 1.4] {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - (hoursAgo * 3600),
                overallScore: 0.5,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            )
            history.append(entry)
        }
        adm.performanceHistory = history
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence()
        
        // THEN: The effective history size should be less than the actual count
        // Expected weights with 0.35h half-life: ~0.82, ~0.5, ~0.25, ~0.125, ~0.0625 ≈ 1.76 effective size
        // With the baseline of 10 entries for full confidence:
        let expectedEffectiveSize = 1.76 / 10.0  // Using baseline instead of window size
        XCTAssertLessThan(confidence.history, expectedEffectiveSize + 0.05, "Mixed age data should have reduced effective history size")
        XCTAssertGreaterThan(confidence.history, expectedEffectiveSize - 0.05, "Mixed age data should have predictable effective history size")
    }
    
    func testRecencyWeighting_VarianceCalculation() {
        // GIVEN: Performance history with consistent scores but different ages (using 0.35h half-life)
        let currentTime = CACurrentMediaTime()
        var history: [PerformanceHistoryEntry] = []
        
        // Add alternating scores: older entries have extreme values, recent ones are moderate
        let ages = [1.4, 1.05, 0.7, 0.35, 0.1] // hours ago - using shorter times for 0.35h half-life
        let scores = [0.9, 0.1, 0.9, 0.5, 0.5] // extreme values are older
        
        for (hoursAgo, score) in zip(ages, scores) {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - (hoursAgo * 3600),
                overallScore: score,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            )
            history.append(entry)
        }
        adm.performanceHistory = history
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence()
        
        // THEN: Variance confidence should be relatively high because recent data is consistent
        // The old extreme values should have less impact due to low weights
        XCTAssertGreaterThan(confidence.variance, 0.5, "Weighted variance should give less weight to old extreme values")
    }
    
    func testRecencyWeighting_DirectionConfidence() {
        // GIVEN: Stable direction count but with old data (using 0.35h half-life)
        let currentTime = CACurrentMediaTime()
        let oldEntry = PerformanceHistoryEntry(
            timestamp: currentTime - (1.4 * 3600), // 1.4 hours ago (4 half-lives with 0.35h half-life)
            overallScore: 0.7,
            normalizedKPIs: [:],
            arousalLevel: 0.5,
            currentDOMValues: [:],
            sessionContext: nil
        )
        adm.performanceHistory = [oldEntry]
        adm.directionStableCount = 5 // Max stability
        adm.lastAdaptationDirection = .increasing
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence()
        
        // THEN: Direction confidence should be reduced by the recency weight
        // 1.4 hours = 4 half-lives, so weight ≈ 0.0625 (6.25%)
        let expectedWeight = 0.0625
        let expectedDirectionConfidence = 1.0 * expectedWeight // max direction confidence * weight
        XCTAssertLessThan(confidence.direction, expectedDirectionConfidence + 0.05, "Direction confidence should be weighted by data recency")
        XCTAssertGreaterThan(confidence.direction, expectedDirectionConfidence - 0.05, "Direction confidence should be predictably weighted")
    }
}
