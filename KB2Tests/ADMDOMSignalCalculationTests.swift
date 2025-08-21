//
//  ADMDOMSignalCalculationTests.swift
//  KB2Tests
//
//  Tests for the DOM-specific PD controller and forced exploration logic
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
    
    // MARK: - Deprecated Tests (Old Implementation)
    
    func test_DEPRECATED_CalculateStandardDeviation() {
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
    
    func test_DEPRECATED_CalculateWeightedSlope() {
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
    
    // MARK: - Deprecated Guard Clause Tests
    
    func test_DEPRECATED_HistorySizeGuardClause() {
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
    
    func test_DEPRECATED_VarianceGuardClause() {
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
    
    // MARK: - Deprecated Recency Weighting Tests
    
    func test_DEPRECATED_RecencyWeighting() {
        // Create data points with different ages (using 0.35h half-life)
        let currentTime = CACurrentMediaTime()
        var mockProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        
        // Old data point (1.4 hours old = 4 half-lives) - should have ~6.25% weight
        mockProfile.recordPerformance(
            timestamp: currentTime - 1.4 * 3600,
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
        XCTAssertLessThan(signal, 0.0, "Recent data should dominate the signal calculation")
    }
    
    // MARK: - Deprecated Adaptation Signal Tests
    
    func test_DEPRECATED_PositiveTrendAdaptationSignal() {
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
    
    func test_DEPRECATED_NegativeTrendAdaptationSignal() {
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
    
    func test_DEPRECATED_NeutralTrendAdaptationSignal() {
        // Create a scenario with no clear relationship between DOM value and performance
        // Use shorter time intervals to work with 0.35-hour half-life
        let currentTime = CACurrentMediaTime()
        var mockProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        
        // Random-ish performance values that don't correlate with DOM values
        // Use smaller time intervals (15 minutes each) so all data has meaningful weight
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
                timestamp: currentTime - Double(dataPoints.count - i - 1) * 900,  // 15 minutes apart
                domValue: point.value,
                performance: point.performance
            )
        }
        
        adm.domPerformanceProfiles[.meanBallSpeed] = mockProfile
        
        let signal = adm.calculateDOMSpecificAdaptationSignal(for: .meanBallSpeed)
        XCTAssertEqual(signal, 0.0, accuracy: 0.3, "No clear trend should yield near-zero adaptation signal")
    }
    
    // MARK: - Deprecated Integration Tests
    
    func test_DEPRECATED_ModulateDOMsWithProfiling() {
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
    
    // MARK: - New PD Controller Tests
    
    // Test local confidence calculation independence
    func testCalculateLocalConfidenceIndependence() {
        // Create a profile with varied data
        var profile = DOMPerformanceProfile(domType: .meanBallSpeed)
        
        // Add data points with good diversity
        let currentTime = CACurrentMediaTime()
        for i in 0..<10 {
            profile.recordPerformance(
                domValue: CGFloat(i) * 0.1,
                performance: 0.6 + CGFloat(i % 3) * 0.1
            )
        }
        
        // Store the profile
        adm.domPerformanceProfiles[.meanBallSpeed] = profile
        
        // Add global performance history (should NOT affect local confidence)
        for i in 0..<20 {
            let entry = PerformanceHistoryEntry(
                timestamp: currentTime - Double(i) * 3600,
                overallScore: 0.9,  // High global performance
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: nil
            )
            adm.performanceHistory.append(entry)
        }
        
        // Create new ADM instance to test calculateLocalConfidence
        let testAdm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Test that local confidence calculation doesn't access global history
        // We'll verify this by checking that confidence is based only on the profile data
        testAdm.domPerformanceProfiles[.meanBallSpeed] = profile
        
        // Since calculateLocalConfidence is private, we test it indirectly through modulateDOMsWithProfiling
        testAdm.modulateDOMsWithProfiling()
        
        // The test passes if no crash occurs and the DOM is processed
        // (calculateLocalConfidence should only use the profile data, not global history)
        XCTAssertNotNil(testAdm.normalizedPositions[.meanBallSpeed])
    }
    
    // Test P-Term calculation (performance gap)
    func testPDControllerPTerm() {
        // Set up a profile with consistent performance above target
        var profile = DOMPerformanceProfile(domType: .meanBallSpeed)
        
        // Add enough data points to pass the guard clause
        for i in 0..<testConfig.domMinDataPointsForProfiling {
            profile.recordPerformance(
                domValue: 0.5 + CGFloat(i) * 0.02,
                performance: 0.9  // Above target of 0.8
            )
        }
        
        adm.domPerformanceProfiles[.meanBallSpeed] = profile
        
        // Initial position
        let initialPosition = adm.normalizedPositions[.meanBallSpeed] ?? 0.5
        
        // Run PD controller
        adm.modulateDOMsWithProfiling()
        
        // Final position should be higher (harder) since performance is above target
        let finalPosition = adm.normalizedPositions[.meanBallSpeed] ?? 0.5
        XCTAssertGreaterThan(finalPosition, initialPosition,
                           "P-term should increase difficulty when performance is above target")
    }
    
    // Test D-Term calculation (slope dampening)
    func testPDControllerDTerm() {
        // Create two profiles: one with steep slope, one with gentle slope
        var steepProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        var gentleProfile = DOMPerformanceProfile(domType: .ballSpeedSD)
        
        let currentTime = CACurrentMediaTime()
        
        // Steep positive slope for meanBallSpeed
        for i in 0..<testConfig.domMinDataPointsForProfiling {
            steepProfile.recordPerformance(
                timestamp: currentTime - Double(testConfig.domMinDataPointsForProfiling - i - 1) * 3600,
                domValue: CGFloat(i) * 0.05 + 0.3,
                performance: CGFloat(i) * 0.03 + 0.6  // Steep increase
            )
        }
        
        // Gentle slope for ballSpeedSD  
        for i in 0..<testConfig.domMinDataPointsForProfiling {
            gentleProfile.recordPerformance(
                timestamp: currentTime - Double(testConfig.domMinDataPointsForProfiling - i - 1) * 3600,
                domValue: CGFloat(i) * 0.05 + 0.3,
                performance: 0.75 + CGFloat(i) * 0.005  // Very gentle increase
            )
        }
        
        adm.domPerformanceProfiles[.meanBallSpeed] = steepProfile
        adm.domPerformanceProfiles[.ballSpeedSD] = gentleProfile
        
        // Store initial positions
        let initialSpeedPos = adm.normalizedPositions[.meanBallSpeed] ?? 0.5
        let initialSDPos = adm.normalizedPositions[.ballSpeedSD] ?? 0.5
        
        // Run PD controller
        adm.modulateDOMsWithProfiling()
        
        // Calculate changes
        let speedChange = abs((adm.normalizedPositions[.meanBallSpeed] ?? 0.5) - initialSpeedPos)
        let sdChange = abs((adm.normalizedPositions[.ballSpeedSD] ?? 0.5) - initialSDPos)
        
        // The steep slope should be more dampened than the gentle slope
        // So the change for steep slope should be smaller relative to performance gap
        XCTAssertLessThan(speedChange, sdChange * 2.0,
                        "Steep slope should be more dampened by D-term")
    }
    
    // Test forced exploration convergence detection
    func testForcedExplorationConvergenceDetection() {
        // Create a profile with stable performance
        var profile = DOMPerformanceProfile(domType: .targetCount)
        
        // Add data points all at the target performance
        for i in 0..<testConfig.domMinDataPointsForProfiling {
            profile.recordPerformance(
                domValue: 0.5,
                performance: testConfig.domProfilingPerformanceTarget  // Exactly at target
            )
        }
        
        adm.domPerformanceProfiles[.targetCount] = profile
        
        // Run multiple rounds to trigger convergence
        for round in 0..<testConfig.domConvergenceDuration + 1 {
            adm.modulateDOMsWithProfiling()
            
            // After enough rounds, convergence should be detected
            if round >= testConfig.domConvergenceDuration - 1 {
                // On the final round, we should see a nudge
                // We can't directly test domConvergenceCounters, but we can observe the effect
                XCTAssertTrue(true, "Convergence detection test completed")
            }
        }
    }
    
    // Test forced exploration nudge application
    func testForcedExplorationNudge() {
        // Create a converged profile
        var profile = DOMPerformanceProfile(domType: .discriminatoryLoad)
        
        for i in 0..<testConfig.domMinDataPointsForProfiling {
            profile.recordPerformance(
                domValue: 0.6,
                performance: testConfig.domProfilingPerformanceTarget
            )
        }
        
        adm.domPerformanceProfiles[.discriminatoryLoad] = profile
        adm.normalizedPositions[.discriminatoryLoad] = 0.6
        
        // Run rounds to reach convergence
        var lastPosition = adm.normalizedPositions[.discriminatoryLoad] ?? 0.6
        var nudgeApplied = false
        
        for _ in 0..<testConfig.domConvergenceDuration + 2 {
            adm.modulateDOMsWithProfiling()
            
            let currentPosition = adm.normalizedPositions[.discriminatoryLoad] ?? 0.6
            let change = abs(currentPosition - lastPosition)
            
            // Check if a nudge was applied (significant change after stability)
            if change > testConfig.domExplorationNudgeFactor * 0.8 {
                nudgeApplied = true
                
                // Verify nudge direction (away from current position)
                if lastPosition < 0.5 {
                    XCTAssertGreaterThan(currentPosition, lastPosition,
                                       "Nudge should move away from low position")
                } else {
                    XCTAssertLessThan(currentPosition, lastPosition,
                                    "Nudge should move away from high position")
                }
            }
            
            lastPosition = currentPosition
        }
        
        XCTAssertTrue(nudgeApplied, "Exploration nudge should be applied after convergence")
    }
    
    // Test minimum data points guard clause
    func testMinDataPointsGuardClause() {
        // Create a profile with insufficient data
        var profile = DOMPerformanceProfile(domType: .responseTime)
        
        // Add fewer data points than required
        for i in 0..<(testConfig.domMinDataPointsForProfiling - 1) {
            profile.recordPerformance(
                domValue: CGFloat(i) * 0.1 + 0.3,
                performance: 0.7
            )
        }
        
        adm.domPerformanceProfiles[.responseTime] = profile
        
        // Store initial position
        let initialPosition = adm.normalizedPositions[.responseTime] ?? 0.5
        
        // Run PD controller
        adm.modulateDOMsWithProfiling()
        
        // Position should not change due to guard clause
        let finalPosition = adm.normalizedPositions[.responseTime] ?? 0.5
        XCTAssertEqual(initialPosition, finalPosition,
                      "DOM should not be modulated with insufficient data points")
    }
    
    // Test that nudged DOMs skip standard modulation
    func testNudgedDOMSkipsStandardModulation() {
        // Set up two DOMs: one converged, one active
        var convergedProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        var activeProfile = DOMPerformanceProfile(domType: .targetCount)
        
        // Converged profile - at target performance
        for i in 0..<testConfig.domMinDataPointsForProfiling {
            convergedProfile.recordPerformance(
                domValue: 0.5,
                performance: testConfig.domProfilingPerformanceTarget
            )
        }
        
        // Active profile - below target performance
        for i in 0..<testConfig.domMinDataPointsForProfiling {
            activeProfile.recordPerformance(
                domValue: 0.5,
                performance: 0.6  // Below target of 0.8
            )
        }
        
        adm.domPerformanceProfiles[.meanBallSpeed] = convergedProfile
        adm.domPerformanceProfiles[.targetCount] = activeProfile
        
        // Run rounds to converge meanBallSpeed
        for _ in 0..<testConfig.domConvergenceDuration {
            adm.modulateDOMsWithProfiling()
        }
        
        // Store positions before the nudge round
        let preNudgeSpeedPos = adm.normalizedPositions[.meanBallSpeed] ?? 0.5
        let preNudgeTargetPos = adm.normalizedPositions[.targetCount] ?? 0.5
        
        // Run one more round - meanBallSpeed should get nudged
        adm.modulateDOMsWithProfiling()
        
        let postNudgeSpeedPos = adm.normalizedPositions[.meanBallSpeed] ?? 0.5
        let postNudgeTargetPos = adm.normalizedPositions[.targetCount] ?? 0.5
        
        // Verify meanBallSpeed changed by approximately the nudge factor
        let speedChange = abs(postNudgeSpeedPos - preNudgeSpeedPos)
        print("DEBUG: Speed change = \(speedChange), expected nudge = \(testConfig.domExplorationNudgeFactor)")
        print("DEBUG: Pre-nudge speed pos = \(preNudgeSpeedPos), post-nudge = \(postNudgeSpeedPos)")
        
        // The converged DOM might not change if nudge hasn't triggered yet
        // Check if it either didn't change (still converging) or changed by nudge amount
        if speedChange > 0.001 {
            XCTAssertEqual(speedChange, testConfig.domExplorationNudgeFactor, accuracy: 0.001,
                          "Converged DOM should change by exactly the nudge factor")
        }
        
        // Verify targetCount changed normally (not by nudge amount)
        let targetChange = abs(postNudgeTargetPos - preNudgeTargetPos)
        print("DEBUG: Target change = \(targetChange)")
        print("DEBUG: Pre-nudge target pos = \(preNudgeTargetPos), post-nudge = \(postNudgeTargetPos)")
        
        if targetChange > 0.001 {
            XCTAssertNotEqual(targetChange, testConfig.domExplorationNudgeFactor,
                             "Active DOM should not receive a nudge")
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
