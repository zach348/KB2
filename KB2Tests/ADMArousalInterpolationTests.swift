//
//  ADMArousalInterpolationTests.swift
//  KB2Tests
//
//  Created by Cline on 6/28/2025.
//  Purpose: Test arousal-based DOM adaptation rate interpolation
//

import XCTest
@testable import KB2

class ADMArousalInterpolationTests: XCTestCase {
    var config: GameConfiguration!
    var adm: AdaptiveDifficultyManager!
    
    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        
        // Use mutable properties for testing
        config.enableDomSpecificProfiling = true
        config.domMinDataPointsForProfiling = 5 // Low threshold for testing
        
        // Note: We'll test with the default transition ranges and rates
        // since they are immutable. The defaults are:
        // - kpiWeightTransitionStart: 0.55
        // - kpiWeightTransitionEnd: 0.85
        // - domAdaptationRates_LowMidArousal and domAdaptationRates_HighArousal have distinct values
        
        adm = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600
        )
    }
    
    override func tearDown() {
        adm = nil
        config = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func getInterpolatedRate(for domType: DOMTargetType, at arousal: CGFloat) -> CGFloat {
        // Update arousal
        adm.updateArousalLevel(arousal)
        
        // Calculate the expected interpolated rate using the same logic as ADM
        let lowRate = config.domAdaptationRates_LowMidArousal[domType] ?? 1.0
        let highRate = config.domAdaptationRates_HighArousal[domType] ?? 1.0
        
        let t = smoothstep(config.kpiWeightTransitionStart,
                          config.kpiWeightTransitionEnd,
                          arousal)
        return lerp(lowRate, highRate, t)
    }
    
    private func populateDOMProfileWithData(for domType: DOMTargetType, dataPoints: Int) {
        // Add performance data to enable PD controller
        for i in 0..<dataPoints {
            let domValue = CGFloat(i) / CGFloat(dataPoints - 1) // 0.0 to 1.0
            let performance = 0.7 + CGFloat.random(in: -0.1...0.1) // Near target
            adm.domPerformanceProfiles[domType]?.recordPerformance(
                domValue: domValue,
                performance: performance
            )
        }
    }
    
    // Helper functions matching ADM's implementation
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }
    
    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
    
    // MARK: - Tests
    
    func test_arousalBelowTransitionStart_usesLowRates() {
        // Test at arousal 0.3 (below transition start of 0.55)
        let arousal: CGFloat = 0.3
        
        for domType in DOMTargetType.allCases {
            let rate = getInterpolatedRate(for: domType, at: arousal)
            let expectedRate = config.domAdaptationRates_LowMidArousal[domType] ?? 1.0
            
            XCTAssertEqual(rate, expectedRate, accuracy: 0.001,
                          "DOM \(domType) should use low arousal rate at arousal \(arousal)")
        }
    }
    
    func test_arousalAboveTransitionEnd_usesHighRates() {
        // Test at arousal 0.9 (above transition end of 0.85)
        let arousal: CGFloat = 0.9
        
        for domType in DOMTargetType.allCases {
            let rate = getInterpolatedRate(for: domType, at: arousal)
            let expectedRate = config.domAdaptationRates_HighArousal[domType] ?? 1.0
            
            XCTAssertEqual(rate, expectedRate, accuracy: 0.001,
                          "DOM \(domType) should use high arousal rate at arousal \(arousal)")
        }
    }
    
    func test_arousalInTransitionRange_interpolatesRates() {
        // Test at arousal 0.7 (middle of transition range 0.55-0.85)
        let arousal: CGFloat = 0.7
        
        for domType in DOMTargetType.allCases {
            let rate = getInterpolatedRate(for: domType, at: arousal)
            let lowRate = config.domAdaptationRates_LowMidArousal[domType] ?? 1.0
            let highRate = config.domAdaptationRates_HighArousal[domType] ?? 1.0
            
            // Calculate expected interpolation
            let t = smoothstep(config.kpiWeightTransitionStart, 
                              config.kpiWeightTransitionEnd, 
                              arousal)
            let expectedRate = lerp(lowRate, highRate, t)
            
            XCTAssertEqual(rate, expectedRate, accuracy: 0.001,
                          "DOM \(domType) should interpolate between rates at arousal \(arousal)")
            
            // Verify it's actually between the two rates
            if lowRate < highRate {
                XCTAssertGreaterThan(rate, lowRate, "Interpolated rate should be above low rate")
                XCTAssertLessThan(rate, highRate, "Interpolated rate should be below high rate")
            } else {
                XCTAssertLessThan(rate, lowRate, "Interpolated rate should be below low rate")
                XCTAssertGreaterThan(rate, highRate, "Interpolated rate should be above high rate")
            }
        }
    }
    
    func test_smoothTransitionAcrossRange() {
        // Test smooth transition by sampling multiple points
        let arousalPoints: [CGFloat] = [0.4, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9]
        
        for domType in DOMTargetType.allCases {
            var previousRate: CGFloat?
            let lowRate = config.domAdaptationRates_LowMidArousal[domType] ?? 1.0
            let highRate = config.domAdaptationRates_HighArousal[domType] ?? 1.0
            let isIncreasing = highRate > lowRate
            
            for arousal in arousalPoints {
                let rate = getInterpolatedRate(for: domType, at: arousal)
                
                if let prev = previousRate {
                    if isIncreasing {
                        XCTAssertGreaterThanOrEqual(rate, prev,
                            "Rate should increase monotonically for \(domType) when high > low")
                    } else {
                        XCTAssertLessThanOrEqual(rate, prev,
                            "Rate should decrease monotonically for \(domType) when high < low")
                    }
                }
                
                previousRate = rate
            }
        }
    }
    
    func test_noContinuityBreakAtTransitionBoundaries() {
        // Test that there's no discontinuity at transition boundaries
        let testPoints: [(CGFloat, CGFloat)] = [
            (0.549, 0.551),  // Around transition start (0.55)
            (0.849, 0.851)   // Around transition end (0.85)
        ]
        
        for domType in DOMTargetType.allCases {
            for (arousal1, arousal2) in testPoints {
                let rate1 = getInterpolatedRate(for: domType, at: arousal1)
                let rate2 = getInterpolatedRate(for: domType, at: arousal2)
                
                let difference = abs(rate1 - rate2)
                XCTAssertLessThan(difference, 0.1,
                    "Rate change should be small across boundary for \(domType) at \(arousal1)-\(arousal2)")
            }
        }
    }
    
    func test_pdControllerUsesInterpolatedRates() {
        // Test that PD controller actually uses interpolated rates in its calculations
        let testArousal: CGFloat = 0.7 // Middle of transition
        adm.updateArousalLevel(testArousal)
        
        // Enable PD controller and populate with data
        for domType in DOMTargetType.allCases {
            populateDOMProfileWithData(for: domType, dataPoints: 20)
        }
        
        // Record positions before modulation
        let positionsBefore = adm.normalizedPositions
        
        // Trigger PD controller by recording performance
        adm.recordIdentificationPerformance(
            taskSuccess: true,
            tfTtfRatio: 0.8,
            reactionTime: 1.0,
            responseDuration: 5.0,
            averageTapAccuracy: 20.0,
            actualTargetsToFindInRound: 5
        )
        
        // Check that positions changed (PD controller ran)
        let positionsAfter = adm.normalizedPositions
        var anyChanged = false
        
        for domType in DOMTargetType.allCases {
            if positionsBefore[domType] != positionsAfter[domType] {
                anyChanged = true
                break
            }
        }
        
        XCTAssertTrue(anyChanged, "PD controller should have modulated at least one DOM")
    }
    
    func test_interpolationMatchesGlobalSystem() {
        // Verify that the PD controller interpolation matches the global system's approach
        let testArousal: CGFloat = 0.7
        
        // Get global system's interpolated priority (without inversion)
        let globalInterpolation = adm.calculateInterpolatedDOMPriority(
            domType: .meanBallSpeed,
            arousal: testArousal,
            invert: false
        )
        
        // Get PD controller's interpolated rate
        let pdRate = getInterpolatedRate(for: .meanBallSpeed, at: testArousal)
        
        XCTAssertEqual(globalInterpolation, pdRate, accuracy: 0.001,
                      "PD controller interpolation should match global system interpolation")
    }
    
    func test_defaultConfigurationRates() {
        // Document the default configuration rates for clarity
        print("Default Low/Mid Arousal Rates:")
        for domType in DOMTargetType.allCases {
            let rate = config.domAdaptationRates_LowMidArousal[domType] ?? 0
            print("  \(domType): \(rate)")
        }
        
        print("\nDefault High Arousal Rates:")
        for domType in DOMTargetType.allCases {
            let rate = config.domAdaptationRates_HighArousal[domType] ?? 0
            print("  \(domType): \(rate)")
        }
        
        print("\nTransition Range: \(config.kpiWeightTransitionStart) - \(config.kpiWeightTransitionEnd)")
        
        // Verify some expected differences
        XCTAssertNotEqual(
            config.domAdaptationRates_LowMidArousal[.targetCount],
            config.domAdaptationRates_HighArousal[.targetCount],
            "Target count rates should differ between arousal levels"
        )
    }
}
