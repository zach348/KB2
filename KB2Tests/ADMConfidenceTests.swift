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
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5)
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
        let confidence = adm.calculateAdaptationConfidence().total
        
        // THEN: History component of confidence should be low
        let historyConfidence = min(CGFloat(adm.performanceHistory.count) / CGFloat(config.performanceHistoryWindowSize), 1.0)
        XCTAssertEqual(historyConfidence, 0.1, "History confidence should be low with few entries")
        XCTAssertLessThan(confidence, 0.5, "Overall confidence should be modest with insufficient history")
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
}
