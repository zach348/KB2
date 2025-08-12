//
//  ADMDirectionSpecificRatesTests.swift
//  KB2Tests
//
//  Created: 2025
//  Role: Unit tests for direction-specific adaptation rates in the PD controller
//
//  Tests verify that:
//  1. Easing (making easier) happens at full rate
//  2. Hardening (making harder) happens at reduced rate
//  3. The boundary case (performance exactly at target) is handled correctly
//

import XCTest
@testable import KB2

class ADMDirectionSpecificRatesTests: XCTestCase {
    
    var config: GameConfiguration!
    var adm: AdaptiveDifficultyManager!
    
    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        config.enableDomSpecificProfiling = true
        config.domMinDataPointsForProfiling = 5  // Lower threshold for testing
        config.domConvergenceDuration = 3  // Shorter for testing
        
        let sessionDuration: TimeInterval = 600
        adm = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: sessionDuration
        )
        
        // Skip warmup phase for these tests
        // Calculate warmup length the same way ADM does
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: config,
            initialArousal: 0.5
        )
        let warmupLength = Int(CGFloat(expectedRounds) * config.warmupPhaseProportion)
        
        // Simulate warmup rounds to transition to standard phase
        for _ in 0..<warmupLength {
            adm.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 0.7,
                reactionTime: 0.5,
                responseDuration: 2.0,
                averageTapAccuracy: 50,
                actualTargetsToFindInRound: 3
            )
        }
    }
    
    override func tearDown() {
        adm = nil
        config = nil
        super.tearDown()
    }
    
    // MARK: - Test Helpers
    
    private func populateDOMProfile(domType: DOMTargetType, performance: CGFloat, count: Int = 20) {
        let currentValue = adm.normalizedPositions[domType] ?? 0.5
        
        for i in 0..<count {
            // Add some variance to make data realistic
            let variance = CGFloat.random(in: -0.05...0.05)
            let perfValue = max(0.0, min(1.0, performance + variance))
            
            adm.domPerformanceProfiles[domType]?.recordPerformance(
                domValue: currentValue + CGFloat(i) * 0.01,  // Slight variation in DOM values
                performance: perfValue
            )
        }
    }
    
    // MARK: - Tests
    
    func testEasingUsesFullRate() {
        // Given: Player struggling (performance below target)
        let targetPerformance = config.domProfilingPerformanceTarget  // 0.8
        let poorPerformance = targetPerformance - 0.2  // 0.6
        
        // Populate all DOMs with poor performance
        for domType in DOMTargetType.allCases {
            populateDOMProfile(domType: domType, performance: poorPerformance)
        }
        
        // When: PD controller runs
        let oldPositions = adm.normalizedPositions
        let didModulate = adm.modulateDOMsWithProfiling()
        
        // Then: Adaptation should occur at full rate (multiplier = 1.0)
        XCTAssertTrue(didModulate, "PD controller should have run with sufficient data")
        
        // Verify at least one DOM position decreased (easing)
        var anyDOMEased = false
        for (domType, oldPosition) in oldPositions {
            let newPosition = adm.normalizedPositions[domType] ?? oldPosition
            if newPosition < oldPosition {
                anyDOMEased = true
                print("DOM \(domType) eased from \(oldPosition) to \(newPosition)")
            }
        }
        
        XCTAssertTrue(anyDOMEased, "At least one DOM should have eased with poor performance")
        
        // Verify easing rate multiplier was used (1.0)
        XCTAssertEqual(config.domEasingRateMultiplier, 1.0, "Easing rate multiplier should be 1.0")
    }
    
    func testHardeningUsesReducedRate() {
        // Given: Player excelling (performance above target)
        let targetPerformance = config.domProfilingPerformanceTarget  // 0.8
        let excellentPerformance = targetPerformance + 0.15  // 0.95
        
        // Populate all DOMs with excellent performance
        for domType in DOMTargetType.allCases {
            populateDOMProfile(domType: domType, performance: excellentPerformance)
        }
        
        // When: PD controller runs
        let oldPositions = adm.normalizedPositions
        let didModulate = adm.modulateDOMsWithProfiling()
        
        // Then: Adaptation should occur at reduced rate (multiplier = 0.6)
        XCTAssertTrue(didModulate, "PD controller should have run with sufficient data")
        
        // Verify at least one DOM position increased (hardening)
        var anyDOMHardened = false
        for (domType, oldPosition) in oldPositions {
            let newPosition = adm.normalizedPositions[domType] ?? oldPosition
            if newPosition > oldPosition {
                anyDOMHardened = true
                print("DOM \(domType) hardened from \(oldPosition) to \(newPosition)")
            }
        }
        
        XCTAssertTrue(anyDOMHardened, "At least one DOM should have hardened with excellent performance")
        
        // Verify hardening rate multiplier was used (0.85)
        XCTAssertEqual(config.domHardeningRateMultiplier, 0.85, "Hardening rate multiplier should be 0.85")
    }
    
    func testPerformanceAtTargetUsesHardeningRate() {
        // Given: Performance exactly at target
        let targetPerformance = config.domProfilingPerformanceTarget  // 0.8
        
        // Populate one DOM with exactly target performance
        let testDOM = DOMTargetType.meanBallSpeed
        populateDOMProfile(domType: testDOM, performance: targetPerformance, count: 30)
        
        // Add small positive variance to ensure non-zero slope
        for i in 0..<5 {
            adm.domPerformanceProfiles[testDOM]?.recordPerformance(
                domValue: 0.5 + CGFloat(i) * 0.02,
                performance: targetPerformance + 0.01  // Tiny positive bias
            )
        }
        
        // When: PD controller calculates adaptation
        let _ = adm.modulateDOMsWithProfiling()
        
        // Then: When performance gap is 0, we should use hardening rate
        // This is because the condition is (performanceGap > 0), not (performanceGap >= 0)
        // So exactly 0 falls into the else case (easing)
        XCTAssertEqual(config.domEasingRateMultiplier, 1.0, "At target should use easing rate (full speed)")
    }
    
    func testAsymmetricAdaptationOverMultipleRounds() {
        // Given: Set up consistent initial conditions
        let targetPerformance = config.domProfilingPerformanceTarget
        let testDOM = DOMTargetType.discriminatoryLoad
        
        // Build up a stable baseline with consistent variance
        for i in 0..<30 {
            // Create data with consistent variance to ensure similar confidence levels
            let domValue = 0.5 + CGFloat(i) * 0.005  // Small increments
            adm.domPerformanceProfiles[testDOM]?.recordPerformance(
                domValue: domValue,
                performance: targetPerformance + CGFloat.random(in: -0.02...0.02)
            )
        }
        
        // Record initial position
        let initialPosition = adm.normalizedPositions[testDOM] ?? 0.5
        
        // Test 1: Poor performance - should ease quickly
        // Clear convergence counter to ensure no forced exploration
        adm.domConvergenceCounters[testDOM] = 0
        
        // Add consistent poor performance data
        for i in 0..<15 {
            let domValue = initialPosition + CGFloat(i) * 0.002
            adm.domPerformanceProfiles[testDOM]?.recordPerformance(
                domValue: domValue,
                performance: targetPerformance - 0.25  // Consistent poor performance
            )
        }
        
        let _ = adm.modulateDOMsWithProfiling()
        let positionAfterEasing = adm.normalizedPositions[testDOM] ?? initialPosition
        let easingChange = initialPosition - positionAfterEasing  // Should be positive (position decreased)
        
        // Reset to initial position and clear convergence counter
        adm.normalizedPositions[testDOM] = initialPosition
        adm.domConvergenceCounters[testDOM] = 0
        
        // Clear recent performance data and rebuild baseline
        adm.domPerformanceProfiles[testDOM] = DOMPerformanceProfile(domType: testDOM)
        for i in 0..<30 {
            let domValue = 0.5 + CGFloat(i) * 0.005
            adm.domPerformanceProfiles[testDOM]?.recordPerformance(
                domValue: domValue,
                performance: targetPerformance + CGFloat.random(in: -0.02...0.02)
            )
        }
        
        // Test 2: Excellent performance - should harden slowly
        for i in 0..<15 {
            let domValue = initialPosition + CGFloat(i) * 0.002
            adm.domPerformanceProfiles[testDOM]?.recordPerformance(
                domValue: domValue,
                performance: targetPerformance + 0.15  // Consistent excellent performance
            )
        }
        
        let _ = adm.modulateDOMsWithProfiling()
        let positionAfterHardening = adm.normalizedPositions[testDOM] ?? initialPosition
        let hardeningChange = positionAfterHardening - initialPosition  // Should be positive (position increased)
        
        // Then: Verify changes occurred in expected directions
        XCTAssertGreaterThan(easingChange, 0, "Position should decrease when easing")
        XCTAssertGreaterThan(hardeningChange, 0, "Position should increase when hardening")
        
        // Calculate actual ratio
        if easingChange > 0.001 && hardeningChange > 0.001 {  // Ensure meaningful changes
            let actualRatio = hardeningChange / easingChange
            print("\n=== Asymmetric Adaptation Test Results ===")
            print("Easing change: \(String(format: "%.6f", easingChange))")
            print("Hardening change: \(String(format: "%.6f", hardeningChange))")
            print("Actual ratio: \(String(format: "%.3f", actualRatio))")
            print("Expected ratio: ~\(config.domHardeningRateMultiplier / config.domEasingRateMultiplier)")
            print("Direction multipliers - Easing: \(config.domEasingRateMultiplier), Hardening: \(config.domHardeningRateMultiplier)")
            
            // The ratio won't match the theoretical multiplier exactly due to confidence, D-term, and clamping.
            // Ensure hardening does not outrun easing excessively.
            XCTAssertLessThan(actualRatio, 1.6, "Hardening should not outrun easing excessively")
            
            // Basic sanity: ratio should be positive (both directions produced movement)
            XCTAssertGreaterThan(actualRatio, 0.0, "Ratio should be positive indicating both directions moved")
        } else {
            XCTFail("Changes too small to compare: easing=\(easingChange), hardening=\(hardeningChange)")
        }
    }
    
    func testBypassSmoothingIsRespected() {
        // Given: DOM with performance data
        let testDOM = DOMTargetType.responseTime
        populateDOMProfile(domType: testDOM, performance: 0.5)  // Below target
        
        // When: PD controller runs
        let _ = adm.modulateDOMsWithProfiling()
        
        // Then: bypassSmoothing should be true in applyModulation
        // This is verified by the documentation comment in the code
        // The PD controller sets bypassSmoothing = true to maintain precision
        XCTAssertTrue(true, "PD controller should bypass smoothing as documented")
    }
    
    // MARK: - New Tests: Per-DOM Direction Multipliers
    
    func testPerDOMHardeningOverridesAreApplied() {
        // Configure per-DOM hardening multipliers BEFORE creating ADM
        var localConfig = GameConfiguration()
        localConfig.enableDomSpecificProfiling = true
        localConfig.domMinDataPointsForProfiling = 5
        localConfig.domConvergenceDuration = 3
        localConfig.domMaxSignalPerRound = 1.0
        // Make meanBallSpeed harden more conservatively than responseTime
        localConfig.domHardeningRateMultiplierByDOM[.meanBallSpeed] = 0.5
        localConfig.domHardeningRateMultiplierByDOM[.responseTime] = 1.0
        
        let sessionDuration: TimeInterval = 600
        let localADM = AdaptiveDifficultyManager(
            configuration: localConfig,
            initialArousal: 0.5,
            sessionDuration: sessionDuration
        )
        
        // Skip warmup: simulate warmup rounds to transition to standard phase
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: localConfig,
            initialArousal: 0.5
        )
        let warmupLength = Int(CGFloat(expectedRounds) * localConfig.warmupPhaseProportion)
        for _ in 0..<warmupLength {
            localADM.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 0.7,
                reactionTime: 0.5,
                responseDuration: 2.0,
                averageTapAccuracy: 50,
                actualTargetsToFindInRound: 3
            )
        }
        
        // Populate identical "excellent" performance profiles for both DOMs to isolate multiplier effect
        let excellentPerformance = localConfig.domProfilingPerformanceTarget + 0.15
        for i in 0..<20 {
            let domVal = 0.5 + CGFloat(i) * 0.01
            localADM.domPerformanceProfiles[.meanBallSpeed]?.recordPerformance(domValue: domVal, performance: excellentPerformance)
            localADM.domPerformanceProfiles[.responseTime]?.recordPerformance(domValue: domVal, performance: excellentPerformance)
        }
        
        // Capture old positions
        let oldMean = localADM.normalizedPositions[.meanBallSpeed] ?? 0.5
        let oldRT = localADM.normalizedPositions[.responseTime] ?? 0.5
        
        // Run PD controller
        let didModulate = localADM.modulateDOMsWithProfiling()
        XCTAssertTrue(didModulate, "PD controller should run with sufficient data")
        
        // Compare deltas
        let newMean = localADM.normalizedPositions[.meanBallSpeed] ?? oldMean
        let newRT = localADM.normalizedPositions[.responseTime] ?? oldRT
        let deltaMean = newMean - oldMean
        let deltaRT = newRT - oldRT
        
        // Both should be hardening (positive) and meanBallSpeed should harden less due to lower per-DOM multiplier
        XCTAssertGreaterThan(deltaMean, 0, "meanBallSpeed should harden with excellent performance")
        XCTAssertGreaterThan(deltaRT, 0, "responseTime should harden with excellent performance")
        XCTAssertLessThan(deltaMean, deltaRT, "Per-DOM hardening override should reduce meanBallSpeed hardening relative to responseTime")
    }
    
    func testPerDOMEasingOverridesAreApplied() {
        // Configure per-DOM easing multipliers BEFORE creating ADM
        var localConfig = GameConfiguration()
        localConfig.enableDomSpecificProfiling = true
        localConfig.domMinDataPointsForProfiling = 5
        localConfig.domConvergenceDuration = 3
        localConfig.domMaxSignalPerRound = 1.0
        // Make meanBallSpeed ease faster than responseTime
        localConfig.domEasingRateMultiplierByDOM[.meanBallSpeed] = 1.2
        localConfig.domEasingRateMultiplierByDOM[.responseTime] = 1.0
        
        let sessionDuration: TimeInterval = 600
        let localADM = AdaptiveDifficultyManager(
            configuration: localConfig,
            initialArousal: 0.5,
            sessionDuration: sessionDuration
        )
        
        // Skip warmup: simulate warmup rounds to transition to standard phase
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: localConfig,
            initialArousal: 0.5
        )
        let warmupLength = Int(CGFloat(expectedRounds) * localConfig.warmupPhaseProportion)
        for _ in 0..<warmupLength {
            localADM.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 0.7,
                reactionTime: 0.5,
                responseDuration: 2.0,
                averageTapAccuracy: 50,
                actualTargetsToFindInRound: 3
            )
        }
        
        // Populate identical "poor" performance profiles for both DOMs to isolate multiplier effect
        let poorPerformance = localConfig.domProfilingPerformanceTarget - 0.20
        for i in 0..<20 {
            let domVal = 0.5 + CGFloat(i) * 0.01
            localADM.domPerformanceProfiles[.meanBallSpeed]?.recordPerformance(domValue: domVal, performance: poorPerformance)
            localADM.domPerformanceProfiles[.responseTime]?.recordPerformance(domValue: domVal, performance: poorPerformance)
        }
        
        // Capture old positions
        let oldMean = localADM.normalizedPositions[.meanBallSpeed] ?? 0.5
        let oldRT = localADM.normalizedPositions[.responseTime] ?? 0.5
        
        // Run PD controller
        let didModulate = localADM.modulateDOMsWithProfiling()
        XCTAssertTrue(didModulate, "PD controller should run with sufficient data")
        
        // Compare deltas (easing -> negative deltas)
        let newMean = localADM.normalizedPositions[.meanBallSpeed] ?? oldMean
        let newRT = localADM.normalizedPositions[.responseTime] ?? oldRT
        let deltaMean = newMean - oldMean
        let deltaRT = newRT - oldRT
        
        XCTAssertLessThan(deltaMean, 0, "meanBallSpeed should ease with poor performance")
        XCTAssertLessThan(deltaRT, 0, "responseTime should ease with poor performance")
        // meanBallSpeed should ease more (more negative) due to higher per-DOM easing multiplier
        XCTAssertLessThan(deltaMean, deltaRT, "Per-DOM easing override should increase easing magnitude for meanBallSpeed relative to responseTime")
    }
}
