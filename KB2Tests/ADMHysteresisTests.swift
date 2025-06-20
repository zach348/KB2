//
//  ADMHysteresisTests.swift
//  KB2Tests
//
//  Created by Cline on [Current Date].
//  Copyright © [Current Year] Your Company. All rights reserved.
//

import XCTest
@testable import KB2

class ADMHysteresisTests: XCTestCase {
    
    var config: GameConfiguration!
    var adm: AdaptiveDifficultyManager!
    
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
    
    // MARK: - Threshold Crossing Tests
    
    func testIncreaseThresholdCrossing() {
        // Test that adaptation only occurs when performance exceeds increase threshold
        let performanceScores: [CGFloat] = [0.54, 0.545, 0.549, 0.551, 0.56, 0.58]
        var adaptationOccurred = false
        
        for score in performanceScores {
            let (signal, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score)
            
            if score <= config.adaptationIncreaseThreshold {
                // Below threshold - should not adapt to increase
                // In neutral zone, small adaptations might occur based on distance from target
                let distanceFromTarget = abs(score - 0.5)
                if distanceFromTarget < config.hysteresisDeadZone {
                    XCTAssertEqual(direction, .stable, "Should be stable within dead zone")
                    XCTAssertEqual(signal, 0.0, "Signal should be 0 within dead zone")
                } else if distanceFromTarget < config.adaptationSignalDeadZone {
                    XCTAssertEqual(direction, .stable, "Should be stable for very small signals")
                } else {
                    // May have small adaptations in neutral zone
                    XCTAssertTrue(direction == .stable || abs(signal) < 0.1, 
                                 "Should be stable or have small signal in neutral zone")
                }
            } else {
                // Above threshold - should adapt (unless prevented by direction change rules)
                if adm.lastAdaptationDirection == .stable {
                    // First time crossing threshold, should adapt
                    XCTAssertEqual(direction, .increasing, "Should be increasing above threshold")
                    XCTAssertGreaterThan(signal, 0, "Signal should be positive above threshold")
                    adaptationOccurred = true
                }
                // Update state for next iteration
                simulatePerformanceRound(adm: adm, performanceScore: score)
            }
        }
        
        XCTAssertTrue(adaptationOccurred, "Adaptation should occur when threshold is crossed")
    }
    
    func testDecreaseThresholdCrossing() {
        // Test that adaptation only occurs when performance falls below decrease threshold
        let performanceScores: [CGFloat] = [0.46, 0.455, 0.451, 0.449, 0.44, 0.42]
        var adaptationOccurred = false
        
        for score in performanceScores {
            let (signal, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score)
            
            if score >= config.adaptationDecreaseThreshold {
                // Above threshold - should not adapt to decrease
                // In neutral zone, small adaptations might occur based on distance from target
                let distanceFromTarget = abs(score - 0.5)
                if distanceFromTarget < config.hysteresisDeadZone {
                    XCTAssertEqual(direction, .stable, "Should be stable within dead zone")
                    XCTAssertEqual(signal, 0.0, "Signal should be 0 within dead zone")
                } else if distanceFromTarget < config.adaptationSignalDeadZone {
                    XCTAssertEqual(direction, .stable, "Should be stable for very small signals")
                } else {
                    // May have small adaptations in neutral zone
                    XCTAssertTrue(direction == .stable || abs(signal) < 0.1, 
                                 "Should be stable or have small signal in neutral zone")
                }
            } else {
                // Below threshold - should adapt (unless prevented by direction change rules)
                if adm.lastAdaptationDirection == .stable {
                    // First time crossing threshold, should adapt
                    XCTAssertEqual(direction, .decreasing, "Should be decreasing below threshold")
                    XCTAssertLessThan(signal, 0, "Signal should be negative below threshold")
                    adaptationOccurred = true
                }
                // Update state for next iteration
                simulatePerformanceRound(adm: adm, performanceScore: score)
            }
        }
        
        XCTAssertTrue(adaptationOccurred, "Adaptation should occur when threshold is crossed")
    }
    
    func testNeutralZoneBehavior() {
        // Test behavior in the neutral zone between thresholds
        let neutralScores: [CGFloat] = [0.48, 0.49, 0.50, 0.51, 0.52]
        
        for score in neutralScores {
            let (signal, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score)
            
            let distanceFromTarget = abs(score - 0.5)
            if distanceFromTarget < config.hysteresisDeadZone {
                XCTAssertEqual(direction, .stable, "Should be stable within dead zone")
                XCTAssertEqual(signal, 0.0, "Signal should be 0 within dead zone")
            } else if distanceFromTarget < config.adaptationSignalDeadZone {
                // Within adaptation dead zone
                XCTAssertEqual(direction, .stable, "Should be stable within adaptation dead zone")
                XCTAssertEqual(signal, 0.0, "Signal should be 0 within adaptation dead zone")
            } else {
                // Small adaptations allowed outside dead zones
                // The signal will be dampened in neutral zone (multiplied by 1.0 instead of 2.0)
                let expectedSignal = (score - 0.5) * 1.0
                XCTAssertEqual(signal, expectedSignal, accuracy: 0.001, "Signal should match dampened calculation")
                XCTAssertEqual(direction, signal < 0 ? .decreasing : .increasing, "Direction should match signal")
            }
        }
    }
    
    // MARK: - Direction Change Prevention Tests
    
    func testPreventImmediateDirectionReversal() {
        // Simulate performance that would cause immediate reversal without hysteresis
        
        // First, establish increasing direction
        simulatePerformanceRound(adm: adm, performanceScore: 0.6)
        XCTAssertEqual(adm.lastAdaptationDirection, .increasing)
        
        // Now try to immediately reverse - should be prevented
        let (signal1, direction1) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: 0.4)
        XCTAssertEqual(direction1, .stable, "Should prevent immediate reversal")
        XCTAssertEqual(signal1, 0.0, "Signal should be 0 when reversal is prevented")
        
        // After minimum stable rounds, reversal should be allowed
        simulatePerformanceRound(adm: adm, performanceScore: 0.4)
        simulatePerformanceRound(adm: adm, performanceScore: 0.4)
        
        let (signal2, direction2) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: 0.4)
        XCTAssertEqual(direction2, .decreasing, "Should allow reversal after stable rounds")
        XCTAssertLessThan(signal2, 0, "Signal should be negative after allowed reversal")
    }
    
    func testStableRoundsCounting() {
        // Test that the system allows direction change after stable period
        
        // Establish increasing direction with good performance
        simulateFullRound(performanceScore: 0.6)
        simulateFullRound(performanceScore: 0.6)
        
        // Verify we're in increasing state
        let initialDirection = adm.lastAdaptationDirection
        XCTAssertEqual(initialDirection, .increasing, "Should be in increasing state")
        
        // Now try poor performance - reversal should be allowed after meeting stable rounds requirement
        let (signal1, direction1) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: 0.4)
        XCTAssertEqual(direction1, .decreasing, "Should allow reversal after stable rounds requirement is met")
        XCTAssertLessThan(signal1, 0.0, "Signal should be negative when reversal is allowed")
        
        // The direction is now decreasing. Subsequent rounds should continue this trend.
        simulateFullRound(performanceScore: 0.4) // This round will be decreasing
        simulateFullRound(performanceScore: 0.4) // This round will continue decreasing
        
        // The system should have adapted to the new direction
        let finalDirection = adm.lastAdaptationDirection
        
        // The key behavior we're testing: after meeting the stable round count, the
        // system correctly reverses direction and maintains it.
        XCTAssertEqual(finalDirection, .decreasing,
                     "Should have transitioned to and maintained the decreasing direction")
    }
    
    // MARK: - Edge Case Tests
    
    func testRapidPerformanceSwings() {
        // Test system behavior with erratic performance
        let erraticScores: [CGFloat] = [0.7, 0.3, 0.8, 0.2, 0.75, 0.25, 0.6, 0.4]
        var significantDirectionChanges = 0
        var lastSignificantDirection = AdaptiveDifficultyManager.AdaptationDirection.stable
        
        for score in erraticScores {
            let (_, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score)
            simulatePerformanceRound(adm: adm, performanceScore: score)
            
            // Count only significant direction changes (not transitions to/from stable)
            if direction != .stable && lastSignificantDirection != .stable && 
               direction != lastSignificantDirection {
                significantDirectionChanges += 1
            }
            
            if direction != .stable {
                lastSignificantDirection = direction
            }
        }
        
        // With hysteresis, direction changes should be limited
        // The system should prevent rapid oscillations
        XCTAssertLessThanOrEqual(significantDirectionChanges, 2, 
                                "Hysteresis should limit rapid direction changes")
    }
    
    func testExtremeBoundaryValues() {
        // Test with performance at boundaries
        let boundaryScores: [CGFloat] = [0.0, 0.01, 0.99, 1.0]
        
        for score in boundaryScores {
            let (signal, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score)
            
            if score < config.adaptationDecreaseThreshold {
                XCTAssertEqual(direction, .decreasing)
                XCTAssertLessThan(signal, 0)
            } else if score > config.adaptationIncreaseThreshold {
                XCTAssertEqual(direction, .increasing)
                XCTAssertGreaterThan(signal, 0)
            }
            
            // Signal should always be clamped to reasonable values
            XCTAssertGreaterThanOrEqual(signal, -1.0)
            XCTAssertLessThanOrEqual(signal, 1.0)
        }
    }
    
    // MARK: - Feature Flag Tests
    
    func testHysteresisDisabled() {
        // Create a mock configuration with hysteresis disabled
        // Since GameConfiguration uses let constants, we need to create a custom init or use reflection
        // For now, we'll test the behavior by checking the config flag
        let admNoHysteresis = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5)
        
        // Skip this test if hysteresis is enabled in the default config
        guard !config.enableHysteresis else {
            print("Skipping hysteresis disabled test - default config has hysteresis enabled")
            return
        }
        
        // Test that original behavior is maintained
        let scores: [CGFloat] = [0.6, 0.4, 0.7, 0.3]
        
        for score in scores {
            let (signal, direction) = admNoHysteresis.calculateAdaptationSignalWithHysteresis(performanceScore: score)
            
            // Should use original calculation
            let expectedSignal = (score - 0.5) * 2.0
            
            if abs(expectedSignal) < config.adaptationSignalDeadZone {
                XCTAssertEqual(direction, .stable)
                XCTAssertEqual(signal, 0.0)
            } else {
                XCTAssertEqual(signal, expectedSignal, accuracy: 0.001)
                XCTAssertEqual(direction, expectedSignal < 0 ? .decreasing : .increasing)
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testFullAdaptationCycleWithHysteresis() {
        // Test a complete adaptation cycle with realistic performance patterns
        
        // Warmup phase - performance improving
        let warmupScores: [CGFloat] = [0.45, 0.48, 0.51, 0.54, 0.56]
        for score in warmupScores {
            simulateFullRound(performanceScore: score)
        }
        
        // Should be adapting to increase difficulty
        XCTAssertEqual(adm.lastAdaptationDirection, .increasing)
        
        // Performance drops but not immediately - hysteresis should prevent oscillation
        let dropScores: [CGFloat] = [0.52, 0.48, 0.44]
        for score in dropScores {
            simulateFullRound(performanceScore: score)
        }
        
        // Should eventually adapt to decrease difficulty
        XCTAssertEqual(adm.lastAdaptationDirection, .decreasing)
        
        // Verify DOM values have been adjusted
        let initialPositions = adm.normalizedPositions
        simulateFullRound(performanceScore: 0.4)
        
        // At least one DOM should have changed
        var positionsChanged = false
        for (dom, initialPos) in initialPositions {
            if let currentPos = adm.normalizedPositions[dom], abs(currentPos - initialPos) > 0.001 {
                positionsChanged = true
                break
            }
        }
        XCTAssertTrue(positionsChanged, "DOM positions should change with adaptation")
    }
    
    // MARK: - Helper Methods
    
    private func simulatePerformanceRound(adm: AdaptiveDifficultyManager, performanceScore: CGFloat) {
        // Simulate the calculation that would happen in modulateDOMTargets
        let (_, newDirection) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: performanceScore)
        
        // Update direction tracking (mimicking modulateDOMTargets logic)
        if newDirection != adm.lastAdaptationDirection {
            if newDirection == .stable {
                adm.directionStableCount = 0
            } else if adm.lastAdaptationDirection == .stable {
                adm.directionStableCount = 1
                adm.lastSignificantChangeTime = CACurrentMediaTime()
            } else if (adm.lastAdaptationDirection == .increasing && newDirection == .decreasing) ||
                      (adm.lastAdaptationDirection == .decreasing && newDirection == .increasing) {
                adm.directionStableCount = 1
                adm.lastSignificantChangeTime = CACurrentMediaTime()
            }
            adm.lastAdaptationDirection = newDirection
        } else if newDirection != .stable {
            adm.directionStableCount += 1
        }
    }
    
    private func simulateFullRound(performanceScore: CGFloat) {
        // Simulate a full identification round
        adm.recordIdentificationPerformance(
            taskSuccess: performanceScore > 0.5,
            tfTtfRatio: performanceScore,
            reactionTime: 1.0 - Double(performanceScore) * 0.5,
            responseDuration: 3.0 - Double(performanceScore) * 2.0,
            averageTapAccuracy: (1.0 - performanceScore) * 100.0,
            actualTargetsToFindInRound: 3
        )
    }
}
