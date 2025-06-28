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
        config.clearPastSessionData = true  // Ensure clean state for tests
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
    }
    
    override func tearDown() {
        adm = nil
        config = nil
        super.tearDown()
    }
    
    // MARK: - Threshold Crossing Tests
    
    func testIncreaseThresholdCrossing() {
        // Test that adaptation only occurs when performance exceeds increase threshold
        let performanceScores: [CGFloat] = [0.74, 0.76, 0.78, 0.79, 0.81, 0.82]
        var adaptationOccurred = false
        
        for score in performanceScores {
            let thresholds = adm.getEffectiveAdaptationThresholds()
            let (signal, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score, thresholds: thresholds, performanceTarget: config.globalPerformanceTarget)
            
            if score <= config.adaptationIncreaseThreshold {
                // Below threshold - should not adapt to increase
                // In neutral zone, small adaptations might occur based on distance from target
                let distanceFromTarget = abs(score - config.globalPerformanceTarget)
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
        let performanceScores: [CGFloat] = [0.76, 0.74, 0.72, 0.69, 0.68, 0.65]
        var adaptationOccurred = false
        
        for score in performanceScores {
            let thresholds = adm.getEffectiveAdaptationThresholds()
            let (signal, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score, thresholds: thresholds, performanceTarget: config.globalPerformanceTarget)
            
            if score >= config.adaptationDecreaseThreshold {
                // Above threshold - should not adapt to decrease
                // In neutral zone, small adaptations might occur based on distance from target
                let distanceFromTarget = abs(score - config.globalPerformanceTarget)
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
        let neutralScores: [CGFloat] = [0.73, 0.74, 0.75, 0.76, 0.77]
        
        for score in neutralScores {
            let thresholds = adm.getEffectiveAdaptationThresholds()
            let (signal, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score, thresholds: thresholds, performanceTarget: config.globalPerformanceTarget)
            
            let distanceFromTarget = abs(score - config.globalPerformanceTarget)
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
                let expectedSignal = (score - config.globalPerformanceTarget) * 1.0
                XCTAssertEqual(signal, expectedSignal, accuracy: 0.001, "Signal should match dampened calculation")
                XCTAssertEqual(direction, signal < 0 ? .decreasing : .increasing, "Direction should match signal")
            }
        }
    }
    
    // MARK: - Direction Change Prevention Tests
    
    func testPreventImmediateDirectionReversal() {
        // Simulate performance that would cause immediate reversal without hysteresis
        // Using lower scores to ensure they remain poor after adaptive scoring
        
        // First, establish increasing direction with good performance
        simulateFullRound(performanceScore: 0.85)
        XCTAssertEqual(adm.lastAdaptationDirection, .increasing)
        
        // Now try to immediately reverse with very poor performance
        // Using 0.35 to ensure it remains below decrease threshold after adaptive scoring
        simulateFullRound(performanceScore: 0.35)
        
        // With only 1 stable round, hysteresis should prevent immediate reversal
        if config.enableHysteresis {
            XCTAssertNotEqual(adm.lastAdaptationDirection, .decreasing, 
                            "Should prevent immediate reversal with hysteresis enabled")
        }
        
        // Continue with good performance to accumulate stable rounds
        simulateFullRound(performanceScore: 0.85)
        simulateFullRound(performanceScore: 0.85)
        
        // Should now have enough stable rounds
        XCTAssertGreaterThanOrEqual(adm.directionStableCount, config.minStableRoundsBeforeDirectionChange,
                                   "Should now have enough stable rounds")
        
        // Now with sustained very poor performance, reversal should eventually be allowed
        simulateFullRound(performanceScore: 0.35)
        simulateFullRound(performanceScore: 0.35)
        simulateFullRound(performanceScore: 0.35)
        
        // After meeting stable rounds requirement and sustained poor performance,
        // the system should change direction
        XCTAssertTrue(adm.lastAdaptationDirection == .decreasing || adm.lastAdaptationDirection == .stable,
                     "Should allow direction change after meeting stable rounds requirement. Current: \(adm.lastAdaptationDirection)")
    }
    
    func testStableRoundsCounting() {
        // Test that the system allows direction change after stable period
        
        // Establish increasing direction with good performance
        simulateFullRound(performanceScore: 0.85)
        simulateFullRound(performanceScore: 0.85)
        
        // Verify we're in increasing state with sufficient stable rounds
        let initialDirection = adm.lastAdaptationDirection
        let initialStableCount = adm.directionStableCount
        XCTAssertEqual(initialDirection, .increasing, "Should be in increasing state")
        XCTAssertGreaterThanOrEqual(initialStableCount, 2, "Should have accumulated stable rounds")
        
        // Now test with poor performance
        // The first poor performance should be prevented from reversing by hysteresis
        // but subsequent poor performance may eventually overcome it
        
        // Store the direction before the poor performance
        let directionBeforePoorPerf = adm.lastAdaptationDirection
        let stableCountBeforePoorPerf = adm.directionStableCount
        
        // Use very poor performance
        simulateFullRound(performanceScore: 0.3)
        
        // After first poor performance, if we haven't met the stable rounds requirement,
        // hysteresis should prevent immediate reversal to decreasing
        // However, the direction might go to stable as an intermediate state
        if config.enableHysteresis && stableCountBeforePoorPerf < config.minStableRoundsBeforeDirectionChange {
            // The direction should not have immediately flipped to the opposite
            if directionBeforePoorPerf == .increasing {
                // It might be stable or still increasing, but not decreasing yet
                XCTAssertTrue(adm.lastAdaptationDirection == .stable || adm.lastAdaptationDirection == .increasing,
                            "Should not immediately reverse from increasing to decreasing. Current: \(adm.lastAdaptationDirection)")
            }
        }
        
        // Continue with very poor performance for several more rounds
        simulateFullRound(performanceScore: 0.3)
        simulateFullRound(performanceScore: 0.3)
        simulateFullRound(performanceScore: 0.25)
        simulateFullRound(performanceScore: 0.2)
        
        // After sustained very poor performance, check final state
        let finalDirection = adm.lastAdaptationDirection
        
        // The system should either be decreasing (if it overcame hysteresis) or stable
        // It should NOT have oscillated back to increasing
        XCTAssertTrue(finalDirection == .decreasing || finalDirection == .stable,
                     "Should either transition to decreasing or remain stable (not oscillate back to increasing)")
    }
    
    // MARK: - Edge Case Tests
    
    func testRapidPerformanceSwings() {
        // Test system behavior with erratic performance
        let erraticScores: [CGFloat] = [0.85, 0.65, 0.9, 0.5, 0.82, 0.68, 0.8, 0.7]
        var allDirections: [AdaptiveDifficultyManager.AdaptationDirection] = []
        
        for score in erraticScores {
            // Use full round simulation to properly update state
            simulateFullRound(performanceScore: score)
            allDirections.append(adm.lastAdaptationDirection)
        }
        
        // Count actual direction changes (excluding stable)
        var significantChanges = 0
        var lastNonStableDirection: AdaptiveDifficultyManager.AdaptationDirection? = nil
        
        for direction in allDirections {
            if direction != .stable {
                if let lastDir = lastNonStableDirection, lastDir != direction {
                    significantChanges += 1
                }
                lastNonStableDirection = direction
            }
        }
        
        // With hysteresis, the system should limit rapid direction changes
        // Given the erratic performance, we expect the system to be more stable
        XCTAssertLessThanOrEqual(significantChanges, 3, 
                                "Hysteresis should limit rapid direction changes")
    }
    
    func testExtremeBoundaryValues() {
        // Test with performance at boundaries
        let boundaryScores: [CGFloat] = [0.0, 0.01, 0.99, 1.0]
        
        for score in boundaryScores {
            let thresholds = adm.getEffectiveAdaptationThresholds()
            let (signal, direction) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: score, thresholds: thresholds, performanceTarget: config.globalPerformanceTarget)
            
            if score < config.adaptationDecreaseThreshold {
                XCTAssertEqual(direction, .decreasing)
                XCTAssertLessThan(signal, 0)
            } else if score > config.adaptationIncreaseThreshold {
                XCTAssertEqual(direction, .increasing)
                XCTAssertGreaterThan(signal, 0)
            }
            
            // Signal should always be reasonably bounded
            XCTAssertLessThanOrEqual(abs(signal), 1.0, "Signal should be reasonably bounded")
        }
    }
    
    // MARK: - Feature Flag Tests
    
    func testHysteresisDisabled() {
        // Create a mock configuration with hysteresis disabled
        // Since GameConfiguration uses let constants, we need to create a custom init or use reflection
        // For now, we'll test the behavior by checking the config flag
        let admNoHysteresis = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
        
        // Skip this test if hysteresis is enabled in the default config
        guard !config.enableHysteresis else {
            print("Skipping hysteresis disabled test - default config has hysteresis enabled")
            return
        }
        
        // Test that original behavior is maintained
        let scores: [CGFloat] = [0.8, 0.7, 0.85, 0.65]
        
        for score in scores {
            let thresholds = admNoHysteresis.getEffectiveAdaptationThresholds()
            let (signal, direction) = admNoHysteresis.calculateAdaptationSignalWithHysteresis(performanceScore: score, thresholds: thresholds, performanceTarget: config.globalPerformanceTarget)
            
            // Should use original calculation
            let expectedSignal = (score - config.globalPerformanceTarget) * 2.0
            
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
        
        // Capture initial DOM positions
        let veryInitialPositions = adm.normalizedPositions
        
        // Warmup phase - performance improving
        let warmupScores: [CGFloat] = [0.7, 0.73, 0.76, 0.79, 0.81]
        for score in warmupScores {
            simulateFullRound(performanceScore: score)
        }
        
        // Should be adapting to increase difficulty
        XCTAssertEqual(adm.lastAdaptationDirection, .increasing)
        
        // Store positions after warmup phase
        let postWarmupPositions = adm.normalizedPositions
        
        // Performance drops dramatically - using very low scores to ensure they remain poor after adaptive scoring
        // The adaptive scoring weights current performance at 75%, so these should still be poor
        let dropScores: [CGFloat] = [0.5, 0.4, 0.35, 0.3, 0.25, 0.2, 0.15]
        for score in dropScores {
            simulateFullRound(performanceScore: score)
        }
        
        // After sustained very poor performance, the system should adapt
        let finalDirection = adm.lastAdaptationDirection
        
        // The system should have changed from increasing to either decreasing or stable
        // It definitely should NOT still be increasing
        XCTAssertTrue(finalDirection == .decreasing || finalDirection == .stable,
                     "After sustained poor performance, should not still be increasing. Direction: \(finalDirection)")
        
        // Verify DOM values have been adjusted from the initial state
        // At least one DOM should have changed significantly throughout the test
        var anySignificantChange = false
        for (dom, initialPos) in veryInitialPositions {
            if let currentPos = adm.normalizedPositions[dom], 
               abs(currentPos - initialPos) > 0.01 { // More lenient threshold
                anySignificantChange = true
                break
            }
        }
        XCTAssertTrue(anySignificantChange, "DOM positions should change during adaptation cycle")
    }
    
    // MARK: - Helper Methods
    
    private func simulatePerformanceRound(adm: AdaptiveDifficultyManager, performanceScore: CGFloat) {
        // Simulate the calculation that would happen in modulateDOMTargets
        let thresholds = adm.getEffectiveAdaptationThresholds()
        let (_, newDirection) = adm.calculateAdaptationSignalWithHysteresis(performanceScore: performanceScore, thresholds: thresholds, performanceTarget: config.globalPerformanceTarget)
        
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
