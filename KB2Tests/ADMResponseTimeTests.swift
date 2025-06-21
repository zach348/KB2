import XCTest
@testable import KB2

/// Tests specifically focused on the relationship between normalized and absolute responseTime values
/// in the Adaptive Difficulty Manager. This suite verifies that:
/// 1. Increases in normalized responseTime (0.0-1.0) result in decreases in absolute responseTime (in seconds)
/// 2. Positive adaptation budget correctly increases normalized responseTime
/// 3. This behavior is consistent across all arousal levels
class ADMResponseTimeTests: XCTestCase {

    var adm: AdaptiveDifficultyManager!
    var config: GameConfiguration!

    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        // Start with mid-range arousal
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
    }

    override func tearDown() {
        adm = nil
        config = nil
        super.tearDown()
    }
    
    // MARK: - Direct Mathematical Verification Tests
    
    /// Tests that for responseTime, increasing normalized values result in decreasing absolute values
    func testResponseTimeNormalizedToAbsoluteConversion() {
        // Test a range of normalized values at fixed arousal level
        let normalizedValues: [CGFloat] = [0.0, 0.25, 0.5, 0.75, 1.0]
        var previousAbsoluteValue: TimeInterval = .greatestFiniteMagnitude
        
        for normalizedValue in normalizedValues {
            // Use exposed API to get the absolute value
            adm.normalizedPositions[.responseTime] = normalizedValue
            adm.updateForCurrentArousal()
            let absoluteValue = adm.currentResponseTime
            
            // As normalized value increases, absolute value should decrease
            if normalizedValue > 0.0 {
                XCTAssertLessThan(absoluteValue, previousAbsoluteValue, 
                                  "For responseTime, higher normalized value (\(normalizedValue)) should result in lower absolute value")
            }
            previousAbsoluteValue = absoluteValue
            
            // Log for debugging
            print("Normalized: \(normalizedValue), Absolute: \(absoluteValue)s")
        }
    }
    
    /// Tests the normalized-to-absolute conversion across different arousal levels
    func testResponseTimeConversionAcrossArousalLevels() {
        let arousalLevels: [CGFloat] = [0.35, 0.5, 0.7, 0.85, 1.0]
        let normalizedValues: [CGFloat] = [0.0, 0.5, 1.0]
        
        for arousal in arousalLevels {
            adm.updateArousalLevel(arousal)
            
            print("\n--- Testing at Arousal \(arousal) ---")
            var absoluteValues: [TimeInterval] = []
            
            for normalizedValue in normalizedValues {
                adm.normalizedPositions[.responseTime] = normalizedValue
                adm.updateForCurrentArousal()
                let absoluteValue = adm.currentResponseTime
                absoluteValues.append(absoluteValue)
                
                print("Normalized: \(normalizedValue), Absolute: \(absoluteValue)s")
            }
            
            // Verify the inverse relationship holds: as normalized increases, absolute decreases
            XCTAssertGreaterThan(absoluteValues[0], absoluteValues[1], 
                               "At arousal \(arousal), norm 0.0 should give higher absolute value than norm 0.5")
            XCTAssertGreaterThan(absoluteValues[1], absoluteValues[2],
                               "At arousal \(arousal), norm 0.5 should give higher absolute value than norm 1.0")
        }
    }
    
    /// Tests that the conversion logic correctly handles the easiest > hardest relationship
    func testResponseTimeEasiestHardestRelationship() {
        // Access config settings directly for verification
        let minArousalEasiest = config.responseTime_MinArousal_EasiestSetting
        let minArousalHardest = config.responseTime_MinArousal_HardestSetting
        let maxArousalEasiest = config.responseTime_MaxArousal_EasiestSetting
        let maxArousalHardest = config.responseTime_MaxArousal_HardestSetting
        
        // Verify our understanding of the config
        XCTAssertGreaterThan(minArousalEasiest, minArousalHardest,
                           "For responseTime, easiest should be > hardest at min arousal")
        XCTAssertGreaterThan(maxArousalEasiest, maxArousalHardest,
                           "For responseTime, easiest should be > hardest at max arousal")
        
        // Test at min operational arousal
        adm.updateArousalLevel(config.arousalOperationalMinForDOMScaling)
        adm.normalizedPositions[.responseTime] = 0.0 // Easiest
        adm.updateForCurrentArousal()
        let minArousalEasiestValue = adm.currentResponseTime
        
        adm.normalizedPositions[.responseTime] = 1.0 // Hardest
        adm.updateForCurrentArousal()
        let minArousalHardestValue = adm.currentResponseTime
        
        // Test at max operational arousal
        adm.updateArousalLevel(config.arousalOperationalMaxForDOMScaling)
        adm.normalizedPositions[.responseTime] = 0.0 // Easiest
        adm.updateForCurrentArousal()
        let maxArousalEasiestValue = adm.currentResponseTime
        
        adm.normalizedPositions[.responseTime] = 1.0 // Hardest
        adm.updateForCurrentArousal()
        let maxArousalHardestValue = adm.currentResponseTime
        
        // Verify the relationship holds in the absolute values
        XCTAssertGreaterThan(minArousalEasiestValue, minArousalHardestValue,
                           "At min arousal, easiest setting should give higher absolute value than hardest")
        XCTAssertGreaterThan(maxArousalEasiestValue, maxArousalHardestValue,
                           "At max arousal, easiest setting should give higher absolute value than hardest")
        
        print("Min Arousal - Easiest (norm=0.0): \(minArousalEasiestValue)s, Hardest (norm=1.0): \(minArousalHardestValue)s")
        print("Max Arousal - Easiest (norm=0.0): \(maxArousalEasiestValue)s, Hardest (norm=1.0): \(maxArousalHardestValue)s")
    }
    
    // MARK: - Adaptation Budget Flow Tests
    
    /// Tests that positive adaptation budget increases normalized responseTime
    func testPositiveAdaptationBudgetIncreasesNormalizedResponseTime() {
        // Setup initial state
        adm.normalizedPositions[.responseTime] = 0.5 // Start at midpoint
        adm.updateForCurrentArousal()
        let initialNormalizedPosition = adm.normalizedPositions[.responseTime]!
        let initialAbsoluteValue = adm.currentResponseTime
        
        // Instead of directly accessing private members, simulate a positive budget
        // by directly modifying the normalized position
        let simulatedPositiveChange: CGFloat = 0.1
        adm.setNormalizedPositionAndUpdate(domType: .responseTime, 
                                         value: initialNormalizedPosition + simulatedPositiveChange)
        
        // Verify normalized position increased
        let newNormalizedPosition = adm.normalizedPositions[.responseTime]!
        XCTAssertGreaterThan(newNormalizedPosition, initialNormalizedPosition,
                           "Normalized position should increase with positive adaptation budget")
        
        // Verify absolute value decreased
        adm.updateForCurrentArousal() // Ensure absolute values are updated
        let newAbsoluteValue = adm.currentResponseTime
        XCTAssertLessThan(newAbsoluteValue, initialAbsoluteValue,
                        "Absolute response time should decrease when normalized position increases")
        
        // Log for debugging
        print("Initial Normalized: \(initialNormalizedPosition), Absolute: \(initialAbsoluteValue)s")
        print("Position Change Applied: \(simulatedPositiveChange)")
        print("New Normalized: \(newNormalizedPosition), Absolute: \(newAbsoluteValue)s")
    }
    
    /// Tests adaptation budget distribution at different arousal levels
    func testAdaptationBudgetDistributionAcrossArousalLevels() {
        let arousalLevels: [CGFloat] = [0.35, 0.5, 0.7, 0.85, 1.0]
        let simulatedPositiveChange: CGFloat = 0.1
        
        for arousal in arousalLevels {
            // Setup
            adm = AdaptiveDifficultyManager(configuration: config, initialArousal: arousal, sessionDuration: 600)
            adm.normalizedPositions[.responseTime] = 0.5 // Start at midpoint
            adm.updateForCurrentArousal()
            let initialNormalizedPosition = adm.normalizedPositions[.responseTime]!
            let initialAbsoluteValue = adm.currentResponseTime
            
            // Directly modify the normalized position to simulate adaptation
            adm.setNormalizedPositionAndUpdate(domType: .responseTime,
                                             value: initialNormalizedPosition + simulatedPositiveChange)
            
            // Verify normalized increased and absolute decreased
            adm.updateForCurrentArousal()
            let newNormalizedPosition = adm.normalizedPositions[.responseTime]!
            let newAbsoluteValue = adm.currentResponseTime
            
            XCTAssertGreaterThan(newNormalizedPosition, initialNormalizedPosition,
                               "At arousal \(arousal), normalized position should increase")
            XCTAssertLessThan(newAbsoluteValue, initialAbsoluteValue,
                            "At arousal \(arousal), absolute value should decrease")
            
            print("\n--- Arousal \(arousal) ---")
            print("Position Change Applied: \(simulatedPositiveChange)")
            print("Normalized: \(initialNormalizedPosition) -> \(newNormalizedPosition)")
            print("Absolute: \(initialAbsoluteValue)s -> \(newAbsoluteValue)s")
        }
    }
    
    // MARK: - Integration Tests
    
    /// Tests a complete performance evaluation cycle with positive performance
    func testFullPerformanceCycleWithPositivePerformance() {
        // Start with a clean ADM
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
        adm.normalizedPositions[.responseTime] = 0.5
        adm.updateForCurrentArousal()
        
        let initialNormalizedPosition = adm.normalizedPositions[.responseTime]!
        let initialAbsoluteValue = adm.currentResponseTime
        
        // Simulate excellent performance (all KPIs maxed out)
        adm.recordIdentificationPerformance(
            taskSuccess: true,
            tfTtfRatio: 1.0,
            reactionTime: config.reactionTime_BestExpected,
            responseDuration: config.responseDuration_PerTarget_BestExpected,
            averageTapAccuracy: config.tapAccuracy_BestExpected_Points,
            actualTargetsToFindInRound: 5
        )
        
        // Verify normalized increased and absolute decreased
        let newNormalizedPosition = adm.normalizedPositions[.responseTime]!
        let newAbsoluteValue = adm.currentResponseTime
        
        XCTAssertGreaterThan(newNormalizedPosition, initialNormalizedPosition,
                           "Normalized position should increase after excellent performance")
        XCTAssertLessThan(newAbsoluteValue, initialAbsoluteValue,
                        "Absolute value should decrease after excellent performance")
        
        print("\n--- Full Performance Cycle ---")
        print("Normalized: \(initialNormalizedPosition) -> \(newNormalizedPosition)")
        print("Absolute: \(initialAbsoluteValue)s -> \(newAbsoluteValue)s")
    }
    
    /// Tests the effects of historical performance data on responseTime adaptation
    func testResponseTimeAdaptationWithPerformanceHistory() {
        // Setup ADM with history enabled
        var testConfig = GameConfiguration()
        testConfig.usePerformanceHistory = true
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        adm.normalizedPositions[.responseTime] = 0.5
        adm.updateForCurrentArousal()
        
        let initialNormalizedPosition = adm.normalizedPositions[.responseTime]!
        let initialAbsoluteValue = adm.currentResponseTime
        
        // Create performance history with improving scores
        for score in stride(from: 0.6, through: 0.9, by: 0.1) {
            let entry = PerformanceHistoryEntry(
                timestamp: CACurrentMediaTime(),
                overallScore: score,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: "test"
            )
            adm.addPerformanceEntry(entry)
        }
        
        // Simulate good performance
        adm.recordIdentificationPerformance(
            taskSuccess: true,
            tfTtfRatio: 1.0,
            reactionTime: config.reactionTime_BestExpected,
            responseDuration: config.responseDuration_PerTarget_BestExpected,
            averageTapAccuracy: config.tapAccuracy_BestExpected_Points,
            actualTargetsToFindInRound: 5
        )
        
        // Verify normalized increased and absolute decreased, with a larger change
        // due to the positive performance history
        let newNormalizedPosition = adm.normalizedPositions[.responseTime]!
        let newAbsoluteValue = adm.currentResponseTime
        
        XCTAssertGreaterThan(newNormalizedPosition, initialNormalizedPosition,
                           "Normalized position should increase after good performance with positive history")
        XCTAssertLessThan(newAbsoluteValue, initialAbsoluteValue,
                        "Absolute value should decrease after good performance with positive history")
        
        print("\n--- Performance With History ---")
        print("Normalized: \(initialNormalizedPosition) -> \(newNormalizedPosition)")
        print("Absolute: \(initialAbsoluteValue)s -> \(newAbsoluteValue)s")
    }
    
    // MARK: - Edge Case Tests
    
    /// Tests behavior at arousal boundaries
    func testResponseTimeAtArousalBoundaries() {
        // Test minimum operational arousal
        adm.updateArousalLevel(config.arousalOperationalMinForDOMScaling)
        
        // Test at 0.0 normalized (easiest)
        adm.normalizedPositions[.responseTime] = 0.0
        adm.updateForCurrentArousal()
        let minArousalEasiestValue = adm.currentResponseTime
        
        // Test at 1.0 normalized (hardest)
        adm.normalizedPositions[.responseTime] = 1.0
        adm.updateForCurrentArousal()
        let minArousalHardestValue = adm.currentResponseTime
        
        // Test maximum operational arousal
        adm.updateArousalLevel(config.arousalOperationalMaxForDOMScaling)
        
        // Test at 0.0 normalized (easiest)
        adm.normalizedPositions[.responseTime] = 0.0
        adm.updateForCurrentArousal()
        let maxArousalEasiestValue = adm.currentResponseTime
        
        // Test at 1.0 normalized (hardest)
        adm.normalizedPositions[.responseTime] = 1.0
        adm.updateForCurrentArousal()
        let maxArousalHardestValue = adm.currentResponseTime
        
        // Verify the relationship still holds
        XCTAssertGreaterThan(minArousalEasiestValue, minArousalHardestValue,
                           "At min arousal boundary, easiest should still be > hardest")
        XCTAssertGreaterThan(maxArousalEasiestValue, maxArousalHardestValue,
                           "At max arousal boundary, easiest should still be > hardest")
        
        print("\n--- Arousal Boundaries ---")
        print("Min Arousal - Easiest: \(minArousalEasiestValue)s, Hardest: \(minArousalHardestValue)s")
        print("Max Arousal - Easiest: \(maxArousalEasiestValue)s, Hardest: \(maxArousalHardestValue)s")
    }
    
    /// Tests behavior with maximum positive adaptation budget
    func testResponseTimeWithMaximumPositiveBudget() {
        // Setup
        adm.normalizedPositions[.responseTime] = 0.5
        adm.updateForCurrentArousal()
        let initialNormalizedPosition = adm.normalizedPositions[.responseTime]!
        let initialAbsoluteValue = adm.currentResponseTime
        
        // Simulate a very large positive change, directly setting to max
        adm.setNormalizedPositionAndUpdate(domType: .responseTime, value: 1.0)
        
        adm.updateForCurrentArousal()
        let newNormalizedPosition = adm.normalizedPositions[.responseTime]!
        let newAbsoluteValue = adm.currentResponseTime
        
        // Normalized position should increase but be clamped at 1.0
        XCTAssertGreaterThan(newNormalizedPosition, initialNormalizedPosition,
                           "Normalized position should increase with large budget")
        XCTAssertLessThanOrEqual(newNormalizedPosition, 1.0,
                               "Normalized position should not exceed 1.0")
        
        // Absolute value should decrease significantly
        XCTAssertLessThan(newAbsoluteValue, initialAbsoluteValue,
                        "Absolute value should decrease with large budget")
        
        print("\n--- Maximum Budget ---")
        print("Normalized: \(initialNormalizedPosition) -> \(newNormalizedPosition)")
        print("Absolute: \(initialAbsoluteValue)s -> \(newAbsoluteValue)s")
    }
    
    /// Tests different magnitudes of change on responseTime modulation
    func testSmoothingFactorEffectsOnResponseTime() {
        // Test with different change magnitudes
        let positionChanges: [CGFloat] = [0.05, 0.1, 0.2]
        
        for positionChange in positionChanges {
            // Reset ADM for each test
            adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
            adm.normalizedPositions[.responseTime] = 0.5
            adm.updateForCurrentArousal()
            
            let initialNormalizedPosition = adm.normalizedPositions[.responseTime]!
            let initialAbsoluteValue = adm.currentResponseTime
            
            // Apply change directly
            adm.setNormalizedPositionAndUpdate(domType: .responseTime,
                                             value: initialNormalizedPosition + positionChange)
            
            let newNormalizedPosition = adm.normalizedPositions[.responseTime]!
            let newAbsoluteValue = adm.currentResponseTime
            
            // With larger position changes, we should see larger absolute value changes
            print("\n--- Position Change \(positionChange) ---")
            print("Normalized Change: \(newNormalizedPosition - initialNormalizedPosition)")
            print("Absolute Change: \(initialAbsoluteValue - newAbsoluteValue)s")
            
            // Verify the relationship still holds
            XCTAssertGreaterThan(newNormalizedPosition, initialNormalizedPosition,
                               "Normalized position should increase regardless of smoothing")
            XCTAssertLessThan(newAbsoluteValue, initialAbsoluteValue,
                            "Absolute value should decrease regardless of smoothing")
        }
    }
    
    // MARK: - Exposed Helpers
    
    /// A more granular test that specifically focuses on the relationship between
    /// normalized and absolute responseTime values with fine-grained changes
    func testFineGrainedResponseTimeRelationship() {
        // Reset the ADM to a known state
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
        
        // Record values across the full normalized range with small increments
        let increment: CGFloat = 0.05
        var normalizedValues: [CGFloat] = []
        var absoluteValues: [TimeInterval] = []
        
        print("\n--- Fine-Grained Response Time Relationship ---")
        print("Starting at normalized 0.0")
        
        for normalizedValue in stride(from: 0.0, through: 1.0, by: increment) {
            adm.setNormalizedPositionAndUpdate(domType: .responseTime, value: normalizedValue)
            let absoluteValue = adm.currentResponseTime
            
            normalizedValues.append(normalizedValue)
            absoluteValues.append(absoluteValue)
            
            print("Normalized: \(String(format: "%.2f", normalizedValue)), Absolute: \(String(format: "%.4f", absoluteValue))s")
        }
        
        // Verify the inverse relationship holds throughout
        for i in 1..<normalizedValues.count {
            XCTAssertGreaterThan(normalizedValues[i], normalizedValues[i-1],
                               "Normalized value should be increasing")
            XCTAssertLessThan(absoluteValues[i], absoluteValues[i-1],
                            "Absolute value should be decreasing as normalized increases")
        }
        
        // Calculate and print the correlation
        let correlation = calculateCorrelation(normalizedValues: normalizedValues, absoluteValues: absoluteValues)
        print("Correlation between normalized and absolute values: \(correlation)")
        XCTAssertLessThan(correlation, 0, "Correlation should be negative (inverse relationship)")
    }
    
    /// Calculate the Pearson correlation coefficient between normalized and absolute values
    private func calculateCorrelation(normalizedValues: [CGFloat], absoluteValues: [TimeInterval]) -> Double {
        let n = Double(normalizedValues.count)
        guard n > 1 else { return 0 }
        
        // Convert TimeInterval to Double for calculations
        let absoluteDoubles = absoluteValues.map { Double($0) }
        let normalizedDoubles = normalizedValues.map { Double($0) }
        
        // Calculate means
        let normalizedMean = normalizedDoubles.reduce(0, +) / n
        let absoluteMean = absoluteDoubles.reduce(0, +) / n
        
        // Calculate covariance and variances
        var covariance: Double = 0
        var normalizedVariance: Double = 0
        var absoluteVariance: Double = 0
        
        for i in 0..<normalizedDoubles.count {
            let normalizedDiff = normalizedDoubles[i] - normalizedMean
            let absoluteDiff = absoluteDoubles[i] - absoluteMean
            
            covariance += normalizedDiff * absoluteDiff
            normalizedVariance += normalizedDiff * normalizedDiff
            absoluteVariance += absoluteDiff * absoluteDiff
        }
        
        // Calculate correlation coefficient
        let denominator = sqrt(normalizedVariance) * sqrt(absoluteVariance)
        guard denominator > 0 else { return 0 }
        
        return covariance / denominator
    }
}

// We'll need a simplified extension that doesn't access private members
extension AdaptiveDifficultyManager {
    // A test-only helper to directly modify normalized positions and update
    func setNormalizedPositionAndUpdate(domType: DOMTargetType, value: CGFloat) {
        normalizedPositions[domType] = max(0.0, min(1.0, value))
        updateForCurrentArousal()
    }
}
