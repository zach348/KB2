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
        
        // THEN: Confidence should be high due to low variance
        XCTAssertGreaterThan(confidence, 0.7, "Confidence should be high for low variance performance")
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
        // GIVEN: A stable adaptation direction
        adm.directionStableCount = 5 // Max stability
        adm.lastAdaptationDirection = .increasing
        adm.performanceHistory = TestHelpers.createPerformanceHistory(scores: [0.6, 0.65, 0.7])
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence().total
        
        // THEN: Confidence should be high
        XCTAssertGreaterThan(confidence, 0.7, "Confidence should be high for stable adaptation direction")
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
        // GIVEN: High confidence state
        adm.performanceHistory = TestHelpers.createPerformanceHistory(scores: [0.5, 0.51, 0.52, 0.53, 0.54, 0.55, 0.56, 0.57, 0.58, 0.59]) // Full history, low variance
        adm.directionStableCount = 5
        
        // WHEN: Effective thresholds are calculated
        let thresholds = adm.getEffectiveAdaptationThresholds()
        
        // THEN: Thresholds should be close to the base configuration
        XCTAssertEqual(thresholds.increaseThreshold, config.adaptationIncreaseThreshold, accuracy: 0.01, "Increase threshold should not widen much with high confidence")
        XCTAssertEqual(thresholds.decreaseThreshold, config.adaptationDecreaseThreshold, accuracy: 0.01, "Decrease threshold should not widen much with high confidence")
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
        // GIVEN: Performance history with old data (24 hours = half-life)
        let currentTime = CACurrentMediaTime()
        let oldEntry = PerformanceHistoryEntry(
            timestamp: currentTime - (24 * 3600), // 24 hours ago
            overallScore: 0.7,
            normalizedKPIs: [:],
            arousalLevel: 0.5,
            currentDOMValues: [:],
            sessionContext: nil
        )
        adm.performanceHistory = [oldEntry]
        
        // WHEN: Confidence is calculated
        let confidence = adm.calculateAdaptationConfidence()
        
        // THEN: Old data should have approximately half weight (0.5)
        // The effective history size should be around 0.5, making history confidence around 0.05
        XCTAssertLessThan(confidence.history, 0.06, "24-hour old data should contribute ~50% weight")
        XCTAssertGreaterThan(confidence.history, 0.04, "24-hour old data should contribute ~50% weight")
    }
    
    func testRecencyWeighting_MixedAgeData() {
        // GIVEN: Performance history with mixed age data
        let currentTime = CACurrentMediaTime()
        var history: [PerformanceHistoryEntry] = []
        
        // Add entries at different ages
        for hoursAgo in [0.1, 1.0, 6.0, 12.0, 24.0] {
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
        // due to older entries having less weight
        // Expected weights: ~1.0, ~0.97, ~0.75, ~0.59, ~0.5 = ~3.81 effective size
        // With the baseline of 10 entries for full confidence:
        let expectedEffectiveSize = 3.81 / 10.0  // Using baseline instead of window size
        XCTAssertLessThan(confidence.history, expectedEffectiveSize + 0.1, "Mixed age data should have reduced effective history size")
        XCTAssertGreaterThan(confidence.history, expectedEffectiveSize - 0.1, "Mixed age data should have predictable effective history size")
    }
    
    func testRecencyWeighting_VarianceCalculation() {
        // GIVEN: Performance history with consistent scores but different ages
        let currentTime = CACurrentMediaTime()
        var history: [PerformanceHistoryEntry] = []
        
        // Add alternating scores: old entries have extreme values, recent ones are moderate
        let ages = [48.0, 36.0, 24.0, 12.0, 1.0] // hours ago
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
        // GIVEN: Stable direction count but with old data
        let currentTime = CACurrentMediaTime()
        let oldEntry = PerformanceHistoryEntry(
            timestamp: currentTime - (48 * 3600), // 48 hours ago
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
        // 48 hours = 2 half-lives, so weight ≈ 0.25
        let expectedWeight = 0.25
        let expectedDirectionConfidence = 1.0 * expectedWeight // max direction confidence * weight
        XCTAssertLessThan(confidence.direction, expectedDirectionConfidence + 0.1, "Direction confidence should be weighted by data recency")
        XCTAssertGreaterThan(confidence.direction, expectedDirectionConfidence - 0.1, "Direction confidence should be predictably weighted")
    }
}
