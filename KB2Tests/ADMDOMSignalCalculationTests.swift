//
//  ADMDOMSignalCalculationTests.swift
//  KB2Tests
//
//  Tests for the DOM-specific adaptation signal calculation logic
//

import XCTest
@testable import KB2
import CoreGraphics

class ADMDOMSignalCalculationTests: XCTestCase {
    
    var testConfig: GameConfiguration!
    var adm: AdaptiveDifficultyManager!
    
    override func setUp() {
        super.setUp()
        
        // Create a config that clears past session data to ensure clean state
        testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true
        testConfig.enableDomSpecificProfiling = true  // Enable the feature
        testConfig.enableSessionPhases = false  // Disable warmup phase to start in standard phase
        
        adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Re-initialize DOM profiles to ensure they're empty
        for domType in DOMTargetType.allCases {
            adm.domPerformanceProfiles[domType] = DOMPerformanceProfile(domType: domType)
        }
    }
    
    override func tearDown() {
        // Clean up test user state
        if let testUserId = adm?.userId {
            ADMPersistenceManager.clearState(for: testUserId)
        }
        testConfig = nil
        adm = nil
        super.tearDown()
    }
    
    // MARK: - Helper Function Tests
    
    func testCalculateStandardDeviation() {
        // Test with empty array
        let emptyResult = adm.calculateStandardDeviation(values: [])
        XCTAssertEqual(emptyResult, 0.0, "Standard deviation of empty array should be 0")
        
        // Test with single value
        let singleResult = adm.calculateStandardDeviation(values: [5.0])
        XCTAssertEqual(singleResult, 0.0, "Standard deviation of single value should be 0")
        
        // Test with identical values
        let identicalResult = adm.calculateStandardDeviation(values: [2.0, 2.0, 2.0, 2.0])
        XCTAssertEqual(identicalResult, 0.0, accuracy: 0.0001, "Standard deviation of identical values should be 0")
        
        // Test with known values
        let knownValues: [CGFloat] = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
        let knownResult = adm.calculateStandardDeviation(values: knownValues)
        XCTAssertEqual(knownResult, 2.0, accuracy: 0.01, "Standard deviation should match expected value")
    }
    
    func testCalculateWeightedSlope() {
        // Create mock data points with known trend
        let currentTime = CACurrentMediaTime()
        
        // Test positive trend (performance increases with DOM value)
        let positiveData = [
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 3600, value: 0.3, performance: 0.4),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 2400, value: 0.4, performance: 0.5),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 1200, value: 0.5, performance: 0.6),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 600, value: 0.6, performance: 0.7),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime, value: 0.7, performance: 0.8)
        ]
        
        let weights = positiveData.map { entry in
            let ageInHours = (currentTime - entry.timestamp) / 3600.0
            return CGFloat(exp(-ageInHours * log(2.0) / 24.0))
        }
        
        let positiveSlope = adm.calculateWeightedSlope(data: positiveData, weights: weights)
        XCTAssertGreaterThan(positiveSlope, 0, "Positive trend should yield positive slope")
        
        // Test negative trend (performance decreases with DOM value)
        let negativeData = [
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 3600, value: 0.3, performance: 0.8),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 2400, value: 0.4, performance: 0.7),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 1200, value: 0.5, performance: 0.6),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 600, value: 0.6, performance: 0.5),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime, value: 0.7, performance: 0.4)
        ]
        
        let negativeWeights = negativeData.map { entry in
            let ageInHours = (currentTime - entry.timestamp) / 3600.0
            return CGFloat(exp(-ageInHours * log(2.0) / 24.0))
        }
        
        let negativeSlope = adm.calculateWeightedSlope(data: negativeData, weights: negativeWeights)
        XCTAssertLessThan(negativeSlope, 0, "Negative trend should yield negative slope")
        
        // Test no trend (flat performance)
        let flatData = [
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 3600, value: 0.3, performance: 0.6),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 2400, value: 0.4, performance: 0.6),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 1200, value: 0.5, performance: 0.6),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime - 600, value: 0.6, performance: 0.6),
            DOMPerformanceProfile.PerformanceDataPoint(timestamp: currentTime, value: 0.7, performance: 0.6)
        ]
        
        let flatWeights = flatData.map { entry in
            let ageInHours = (currentTime - entry.timestamp) / 3600.0
            return CGFloat(exp(-ageInHours * log(2.0) / 24.0))
        }
        
        let flatSlope = adm.calculateWeightedSlope(data: flatData, weights: flatWeights)
        XCTAssertEqual(flatSlope, 0.0, accuracy: 0.001, "Flat trend should yield near-zero slope")
    }
    
    // MARK: - Guard Clause Tests
    
    func testHistorySizeGuardClause() {
        // Add fewer than 7 data points
        var mockProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        for i in 0..<6 {
            mockProfile.recordPerformance(
                timestamp: CACurrentMediaTime() - Double(i) * 3600,
                domValue: CGFloat(i) * 0.1 + 0.3,
                performance: CGFloat(i) * 0.1 + 0.5
            )
        }
        adm.domPerformanceProfiles[.meanBallSpeed] = mockProfile
        
        let signal = adm.calculateDOMSpecificAdaptationSignal(for: .meanBallSpeed)
        XCTAssertEqual(signal, 0.0, "Should return neutral signal with fewer than 7 data points")
    }
    
    func testVarianceGuardClause() {
        // Add data points with very low variance in DOM values
        var mockProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        let baseValue: CGFloat = 0.5
        
        for i in 0..<10 {
            // All DOM values are nearly identical
            let domValue = baseValue + CGFloat(i % 2) * 0.001  // Tiny variation
            mockProfile.recordPerformance(
                timestamp: CACurrentMediaTime() - Double(i) * 3600,
                domValue: domValue,
                performance: CGFloat(i) * 0.05 + 0.5
            )
        }
        adm.domPerformanceProfiles[.meanBallSpeed] = mockProfile
        
        let signal = adm.calculateDOMSpecificAdaptationSignal(for: .meanBallSpeed)
        XCTAssertEqual(signal, 0.0, "Should return neutral signal with insufficient DOM variance")
    }
    
    // MARK: - Recency Weighting Tests
    
    func testRecencyWeighting() {
        // Create data points with different ages
        let currentTime = CACurrentMediaTime()
        var mockProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        
        // Old data point (48 hours old) - should have ~25% weight
        mockProfile.recordPerformance(
            timestamp: currentTime - 48 * 3600,
            domValue: 0.3,
            performance: 0.9  // High performance at low difficulty
        )
        
        // Recent data points - should have nearly full weight
        for i in 0..<8 {
            mockProfile.recordPerformance(
                timestamp: currentTime - Double(i) * 600,  // Last 80 minutes
                domValue: 0.7,
                performance: 0.4  // Low performance at high difficulty
            )
        }
        
        adm.domPerformanceProfiles[.meanBallSpeed] = mockProfile
        
        let signal = adm.calculateDOMSpecificAdaptationSignal(for: .meanBallSpeed)
        
        // The signal should be negative (recent data shows poor performance at high difficulty)
        // despite the old data point showing good performance at low difficulty
        XCTAssertLessThan(signal, 0, "Recent data should dominate the signal calculation")
    }
    
    // MARK: - Adaptation Signal Tests
    
    func testPositiveTrendAdaptationSignal() {
        // Create a scenario where performance improves as DOM value increases
        // This suggests the player can handle harder difficulty
        let currentTime = CACurrentMediaTime()
        var mockProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        
        let dataPoints = [
            (value: 0.2, performance: 0.3),
            (value: 0.3, performance: 0.4),
            (value: 0.4, performance: 0.5),
            (value: 0.5, performance: 0.6),
            (value: 0.6, performance: 0.7),
            (value: 0.7, performance: 0.8),
            (value: 0.8, performance: 0.85),
            (value: 0.9, performance: 0.9)
        ]
        
        for (i, point) in dataPoints.enumerated() {
            mockProfile.recordPerformance(
                timestamp: currentTime - Double(dataPoints.count - i - 1) * 3600,
                domValue: point.value,
                performance: point.performance
            )
        }
        
        adm.domPerformanceProfiles[.meanBallSpeed] = mockProfile
        
        let signal = adm.calculateDOMSpecificAdaptationSignal(for: .meanBallSpeed)
        XCTAssertGreaterThan(signal, 0, "Positive performance trend should yield positive adaptation signal")
    }
    
    func testNegativeTrendAdaptationSignal() {
        // Create a scenario where performance degrades as DOM value increases
        // This suggests the player is struggling with harder difficulty
        let currentTime = CACurrentMediaTime()
        var mockProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        
        let dataPoints = [
            (value: 0.2, performance: 0.9),
            (value: 0.3, performance: 0.85),
            (value: 0.4, performance: 0.75),
            (value: 0.5, performance: 0.65),
            (value: 0.6, performance: 0.55),
            (value: 0.7, performance: 0.45),
            (value: 0.8, performance: 0.35),
            (value: 0.9, performance: 0.25)
        ]
        
        for (i, point) in dataPoints.enumerated() {
            mockProfile.recordPerformance(
                timestamp: currentTime - Double(dataPoints.count - i - 1) * 3600,
                domValue: point.value,
                performance: point.performance
            )
        }
        
        adm.domPerformanceProfiles[.meanBallSpeed] = mockProfile
        
        let signal = adm.calculateDOMSpecificAdaptationSignal(for: .meanBallSpeed)
        XCTAssertLessThan(signal, 0, "Negative performance trend should yield negative adaptation signal")
    }
    
    func testNeutralTrendAdaptationSignal() {
        // Create a scenario with no clear relationship between DOM value and performance
        let currentTime = CACurrentMediaTime()
        var mockProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        
        // Random-ish performance values that don't correlate with DOM values
        let dataPoints = [
            (value: 0.2, performance: 0.6),
            (value: 0.3, performance: 0.5),
            (value: 0.4, performance: 0.7),
            (value: 0.5, performance: 0.4),
            (value: 0.6, performance: 0.6),
            (value: 0.7, performance: 0.5),
            (value: 0.8, performance: 0.65),
            (value: 0.9, performance: 0.55)
        ]
        
        for (i, point) in dataPoints.enumerated() {
            mockProfile.recordPerformance(
                timestamp: currentTime - Double(dataPoints.count - i - 1) * 3600,
                domValue: point.value,
                performance: point.performance
            )
        }
        
        adm.domPerformanceProfiles[.meanBallSpeed] = mockProfile
        
        let signal = adm.calculateDOMSpecificAdaptationSignal(for: .meanBallSpeed)
        XCTAssertEqual(signal, 0.0, accuracy: 0.1, "No clear trend should yield near-zero adaptation signal")
    }
    
    // MARK: - Integration Tests
    
    func testModulateDOMsWithProfiling() {
        // Set up profiles with different trends for each DOM
        let currentTime = CACurrentMediaTime()
        
        // Positive trend for meanBallSpeed
        var speedProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        for i in 0..<8 {
            let value = CGFloat(i) * 0.1 + 0.2
            let performance = CGFloat(i) * 0.08 + 0.4
            speedProfile.recordPerformance(
                timestamp: currentTime - Double(7 - i) * 3600,
                domValue: value,
                performance: performance
            )
        }
        adm.domPerformanceProfiles[.meanBallSpeed] = speedProfile
        
        // Negative trend for responseTime
        var responseProfile = DOMPerformanceProfile(domType: .responseTime)
        for i in 0..<8 {
            let value = CGFloat(i) * 0.1 + 0.2
            let performance = 0.8 - CGFloat(i) * 0.08
            responseProfile.recordPerformance(
                timestamp: currentTime - Double(7 - i) * 3600,
                domValue: value,
                performance: performance
            )
        }
        adm.domPerformanceProfiles[.responseTime] = responseProfile
        
        // Neutral trend for targetCount
        var targetProfile = DOMPerformanceProfile(domType: .targetCount)
        for i in 0..<8 {
            let value = CGFloat(i) * 0.1 + 0.2
            let performance = 0.5 + (i % 2 == 0 ? 0.1 : -0.1)
            targetProfile.recordPerformance(
                timestamp: currentTime - Double(7 - i) * 3600,
                domValue: value,
                performance: performance
            )
        }
        adm.domPerformanceProfiles[.targetCount] = targetProfile
        
        // Store initial positions
        let initialPositions = adm.normalizedPositions
        
        print("DEBUG: Initial positions:")
        for (dom, pos) in initialPositions {
            print("  \(dom): \(pos)")
        }
        
        // Call modulateDOMsWithProfiling
        adm.modulateDOMsWithProfiling()
        
        print("DEBUG: Final positions:")
        for (dom, pos) in adm.normalizedPositions {
            print("  \(dom): \(pos)")
        }
        
        // Verify that positions changed appropriately
        // meanBallSpeed should increase (positive trend)
        if let initialSpeed = initialPositions[.meanBallSpeed],
           let finalSpeed = adm.normalizedPositions[.meanBallSpeed] {
            print("DEBUG: meanBallSpeed: \(initialSpeed) -> \(finalSpeed)")
            XCTAssertGreaterThan(finalSpeed, initialSpeed, "Mean ball speed should increase with positive trend")
        }
        
        // responseTime should decrease (negative trend)
        if let initialResponse = initialPositions[.responseTime],
           let finalResponse = adm.normalizedPositions[.responseTime] {
            print("DEBUG: responseTime: \(initialResponse) -> \(finalResponse)")
            XCTAssertLessThan(finalResponse, initialResponse, "Response time should decrease with negative trend")
        }
        
        // targetCount should remain relatively stable (neutral trend)
        if let initialTarget = initialPositions[.targetCount],
           let finalTarget = adm.normalizedPositions[.targetCount] {
            print("DEBUG: targetCount: \(initialTarget) -> \(finalTarget)")
            XCTAssertEqual(finalTarget, initialTarget, accuracy: 0.05, "Target count should remain stable with neutral trend")
        }
    }
}

// MARK: - Test Extensions

extension DOMPerformanceProfile {
    // Helper method for tests to record performance with timestamp
    mutating func recordPerformance(timestamp: TimeInterval, domValue: CGFloat, performance: CGFloat) {
        performanceByValue.append(PerformanceDataPoint(
            timestamp: timestamp,
            value: domValue,
            performance: performance
        ))
        
        // Maintain buffer size
        if performanceByValue.count > 200 {
            performanceByValue.removeFirst()
        }
    }
}

// MARK: - Test Extensions

// No need for extensions anymore since methods are internal
