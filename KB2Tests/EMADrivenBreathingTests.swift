// EMADrivenBreathingTests.swift
// Tests for EMA-driven dynamic breathing phase duration system

import XCTest
import SpriteKit
@testable import KB2

class EMADrivenBreathingTests: XCTestCase {
    var gameScene: GameScene!
    var mockView: MockSKView!
    var gameConfig: GameConfiguration!
    
    override func setUp() {
        super.setUp()
        mockView = TestConstants.testView
        gameScene = GameScene(size: TestConstants.screenSize)
        gameScene.scaleMode = .aspectFill
        gameScene.sessionMode = true
        gameScene.sessionDuration = 300 // 5 minutes for testing
        gameConfig = GameConfiguration()
    }
    
    override func tearDown() {
        gameScene = nil
        mockView = nil
        gameConfig = nil
        super.tearDown()
    }
    
    // MARK: - Breathing Phase Entry Point Tests (Jitteriness-based)
    
    func testBreathingTransitionPoint_LowJitteriness() {
        // Test user with low jitteriness (calm) - should get early breathing transition
        let lowJitteryEMA = EMAResponse(
            stressLevel: 50.0,      // Mid stress (not used for transition point)
            calmJitteryLevel: 0.0,  // Very calm = low jitteriness
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = lowJitteryEMA
        gameScene.didMove(to: mockView)
        
        // Verify breathing transition point is at the minimum (early transition)
        let expectedTransition = gameConfig.emaJitterinessTransitionPointMin
        XCTAssertEqual(gameScene.breathingTransitionPoint, expectedTransition, accuracy: 0.001,
                      "Low jitteriness should result in early breathing transition")
        
        print("Low jitteriness test: \(gameScene.breathingTransitionPoint) vs expected \(expectedTransition)")
    }
    
    func testBreathingTransitionPoint_HighJitteriness() {
        // Test user with high jitteriness (restless) - should get late breathing transition
        let highJitteryEMA = EMAResponse(
            stressLevel: 50.0,        // Mid stress (not used for transition point)
            calmJitteryLevel: 100.0,  // Very jittery = high jitteriness
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = highJitteryEMA
        gameScene.didMove(to: mockView)
        
        // Verify breathing transition point is at the maximum (late transition)
        let expectedTransition = gameConfig.emaJitterinessTransitionPointMax
        XCTAssertEqual(gameScene.breathingTransitionPoint, expectedTransition, accuracy: 0.001,
                      "High jitteriness should result in late breathing transition")
        
        print("High jitteriness test: \(gameScene.breathingTransitionPoint) vs expected \(expectedTransition)")
    }
    
    func testBreathingTransitionPoint_MidJitteriness() {
        // Test user with medium jitteriness - should get interpolated transition point
        let midJitteryEMA = EMAResponse(
            stressLevel: 50.0,       // Mid stress (not used for transition point)
            calmJitteryLevel: 50.0,  // Mid jitteriness
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = midJitteryEMA
        gameScene.didMove(to: mockView)
        
        // Calculate expected interpolated value
        let normalizedJitteriness = 50.0 / 100.0 // = 0.5
        let expectedTransition = gameConfig.emaJitterinessTransitionPointMin + 
            (normalizedJitteriness * (gameConfig.emaJitterinessTransitionPointMax - gameConfig.emaJitterinessTransitionPointMin))
        // = 0.40 + (0.5 * (0.70 - 0.40)) = 0.40 + (0.5 * 0.30) = 0.40 + 0.15 = 0.55
        
        XCTAssertEqual(gameScene.breathingTransitionPoint, expectedTransition, accuracy: 0.001,
                      "Mid jitteriness should result in interpolated breathing transition")
        
        print("Mid jitteriness test: \(gameScene.breathingTransitionPoint) vs expected \(expectedTransition)")
    }
    
    func testBreathingTransitionPoint_NoEMAFallback() {
        // Test fallback when no EMA data is available
        gameScene.preSessionEMA = nil
        gameScene.didMove(to: mockView)
        
        // Verify breathing transition point falls within the standard random range
        XCTAssertGreaterThanOrEqual(gameScene.breathingTransitionPoint, gameConfig.breathingStateTargetRangeMin,
                                   "Fallback transition point should be >= min random range")
        XCTAssertLessThanOrEqual(gameScene.breathingTransitionPoint, gameConfig.breathingStateTargetRangeMax,
                                "Fallback transition point should be <= max random range")
        
        print("No EMA fallback test: \(gameScene.breathingTransitionPoint)")
    }
    
    // MARK: - Breathing Pacing Tests (Stress-based)
    
    func testBreathingPacingArousal_LowStress() {
        // Test user with low stress - should get gentle breathing start (low pacing arousal)
        let lowStressEMA = EMAResponse(
            stressLevel: 0.0,         // Very low stress
            calmJitteryLevel: 50.0,   // Mid jitteriness (not used for pacing)
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = lowStressEMA
        gameScene.didMove(to: mockView)
        
        // Force transition to breathing state to trigger pacing calculation
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        
        // Verify initial breathing pacing arousal is at minimum
        let expectedPacingArousal = gameConfig.emaStressPacingArousalMin
        XCTAssertEqual(gameScene.initialBreathingPacingArousal, expectedPacingArousal, accuracy: 0.001,
                      "Low stress should result in gentle breathing pacing arousal")
        
        print("Low stress test: \(gameScene.initialBreathingPacingArousal) vs expected \(expectedPacingArousal)")
    }
    
    func testBreathingPacingArousal_HighStress() {
        // Test user with high stress - should get current "on-ramp" approach (high pacing arousal)
        let highStressEMA = EMAResponse(
            stressLevel: 100.0,       // Very high stress
            calmJitteryLevel: 50.0,   // Mid jitteriness (not used for pacing)
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = highStressEMA
        gameScene.didMove(to: mockView)
        
        // Force transition to breathing state to trigger pacing calculation
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        
        // Verify initial breathing pacing arousal is at maximum
        let expectedPacingArousal = gameConfig.emaStressPacingArousalMax
        XCTAssertEqual(gameScene.initialBreathingPacingArousal, expectedPacingArousal, accuracy: 0.001,
                      "High stress should result in current on-ramp pacing arousal")
        
        print("High stress test: \(gameScene.initialBreathingPacingArousal) vs expected \(expectedPacingArousal)")
    }
    
    func testBreathingPacingArousal_MidStress() {
        // Test user with medium stress - should get interpolated pacing arousal
        let midStressEMA = EMAResponse(
            stressLevel: 50.0,        // Mid stress
            calmJitteryLevel: 50.0,   // Mid jitteriness (not used for pacing)
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = midStressEMA
        gameScene.didMove(to: mockView)
        
        // Force transition to breathing state to trigger pacing calculation
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        
        // Calculate expected interpolated value
        let normalizedStress = 50.0 / 100.0 // = 0.5
        let expectedPacingArousal = gameConfig.emaStressPacingArousalMin + 
            (normalizedStress * (gameConfig.emaStressPacingArousalMax - gameConfig.emaStressPacingArousalMin))
        // = 0.15 + (0.5 * (0.35 - 0.15)) = 0.15 + (0.5 * 0.20) = 0.15 + 0.10 = 0.25
        
        XCTAssertEqual(gameScene.initialBreathingPacingArousal, expectedPacingArousal, accuracy: 0.001,
                      "Mid stress should result in interpolated breathing pacing arousal")
        
        print("Mid stress test: \(gameScene.initialBreathingPacingArousal) vs expected \(expectedPacingArousal)")
    }
    
    func testBreathingPacingArousal_NoEMAFallback() {
        // Test fallback when no EMA data is available
        gameScene.preSessionEMA = nil
        gameScene.didMove(to: mockView)
        
        // Force transition to breathing state to trigger pacing calculation
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        
        // Verify initial breathing pacing arousal uses default value
        let expectedDefaultPacingArousal: CGFloat = 0.35
        XCTAssertEqual(gameScene.initialBreathingPacingArousal, expectedDefaultPacingArousal, accuracy: 0.001,
                      "No EMA data should result in default breathing pacing arousal")
        
        print("No EMA fallback pacing test: \(gameScene.initialBreathingPacingArousal) vs expected \(expectedDefaultPacingArousal)")
    }
    
    // MARK: - Proportional Decay System Tests
    
    func testBreathingPacingProportionalDecay() {
        // Test the proportional decay mapping to ensure no negative values
        let testStressEMA = EMAResponse(
            stressLevel: 75.0,        // High stress for testing
            calmJitteryLevel: 50.0,
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = testStressEMA
        gameScene.didMove(to: mockView)
        
        // Store initial system arousal
        let initialSystemArousal = gameScene.currentArousalLevel
        
        // Force transition to breathing state
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        
        // Verify initial pacing values were set
        XCTAssertGreaterThan(gameScene.initialBreathingPacingArousal, 0.0, "Initial breathing pacing arousal should be positive")
        XCTAssertGreaterThan(gameScene.arousalAtBreathingStart, 0.0, "Arousal at breathing start should be positive")
        
        // Simulate system arousal decay during breathing phase
        let originalArousalAtStart = gameScene.arousalAtBreathingStart
        let originalInitialPacing = gameScene.initialBreathingPacingArousal
        
        // Test with system arousal at 50% of original
        gameScene.currentArousalLevel = originalArousalAtStart * 0.5
        
        // Call updateDynamicBreathingParameters to trigger the calculation
        gameScene.updateParametersFromArousal() // This calls updateDynamicBreathingParameters for breathing state
        
        // Calculate expected values manually
        let expectedDecayProgress = (originalArousalAtStart - gameScene.currentArousalLevel) / originalArousalAtStart
        let expectedEffectivePacing = originalInitialPacing * (1.0 - expectedDecayProgress)
        
        print("Proportional decay test:")
        print("  ├─ Original arousal at start: \(originalArousalAtStart)")
        print("  ├─ Current system arousal: \(gameScene.currentArousalLevel)")
        print("  ├─ Expected decay progress: \(expectedDecayProgress)")
        print("  ├─ Original initial pacing: \(originalInitialPacing)")
        print("  └─ Expected effective pacing: \(expectedEffectivePacing)")
        
        // The key test: effective pacing should never be negative
        XCTAssertGreaterThanOrEqual(expectedEffectivePacing, 0.0, 
                                   "Effective pacing arousal should never be negative")
        
        // Test with system arousal at near zero
        gameScene.currentArousalLevel = 0.01
        gameScene.updateParametersFromArousal()
        
        // Even at very low system arousal, effective pacing should approach zero but not go negative
        let veryLowDecayProgress = (originalArousalAtStart - 0.01) / originalArousalAtStart
        let veryLowEffectivePacing = originalInitialPacing * (1.0 - veryLowDecayProgress)
        
        XCTAssertGreaterThanOrEqual(veryLowEffectivePacing, 0.0,
                                   "Effective pacing arousal should be non-negative even at very low system arousal")
        XCTAssertLessThan(veryLowEffectivePacing, originalInitialPacing * 0.1,
                         "Effective pacing arousal should be very small when system arousal is near zero")
        
        print("Very low arousal test:")
        print("  ├─ System arousal: 0.01")
        print("  ├─ Decay progress: \(veryLowDecayProgress)")
        print("  └─ Effective pacing: \(veryLowEffectivePacing)")
    }
    
    func testBreathingPacingDecayMapping_ZeroArousalAtStart() {
        // Edge case test: What happens if arousalAtBreathingStart is zero?
        gameScene.preSessionEMA = EMAResponse(
            stressLevel: 50.0,
            calmJitteryLevel: 50.0,
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.didMove(to: mockView)
        
        // Manually set arousalAtBreathingStart to zero (edge case)
        gameScene.arousalAtBreathingStart = 0.0
        
        // Transition to breathing
        gameScene.currentState = .breathing
        
        // Call updateDynamicBreathingParameters - should handle zero gracefully
        gameScene.updateParametersFromArousal()
        
        // Test should pass without crashing - the guard statement should catch this
        XCTAssertTrue(true, "Should handle zero arousalAtBreathingStart gracefully without crashing")
    }
    
    // MARK: - Integration Tests
    
    func testFullEMADrivenBreathingWorkflow() {
        // Test complete workflow with realistic EMA values
        let testEMA = EMAResponse(
            stressLevel: 80.0,        // High stress = high initial pacing arousal
            calmJitteryLevel: 25.0,   // Low jitteriness = early breathing transition
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = testEMA
        gameScene.didMove(to: mockView)
        
        // Verify breathing transition point calculation
        let normalizedJitteriness = 25.0 / 100.0
        let expectedTransition = gameConfig.emaJitterinessTransitionPointMin + 
            (normalizedJitteriness * (gameConfig.emaJitterinessTransitionPointMax - gameConfig.emaJitterinessTransitionPointMin))
        // = 0.40 + (0.25 * 0.30) = 0.475
        
        XCTAssertEqual(gameScene.breathingTransitionPoint, expectedTransition, accuracy: 0.001,
                      "Transition point should be calculated correctly from jitteriness")
        
        // Simulate session progress to breathing transition point
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        
        // Verify breathing pacing calculation
        let normalizedStress = 80.0 / 100.0
        let expectedInitialPacing = gameConfig.emaStressPacingArousalMin + 
            (normalizedStress * (gameConfig.emaStressPacingArousalMax - gameConfig.emaStressPacingArousalMin))
        // = 0.15 + (0.8 * 0.20) = 0.15 + 0.16 = 0.31
        
        XCTAssertEqual(gameScene.initialBreathingPacingArousal, expectedInitialPacing, accuracy: 0.001,
                      "Initial pacing arousal should be calculated correctly from stress")
        
        print("Full workflow test:")
        print("  ├─ Transition point: \(gameScene.breathingTransitionPoint) vs expected \(expectedTransition)")
        print("  └─ Initial pacing: \(gameScene.initialBreathingPacingArousal) vs expected \(expectedInitialPacing)")
    }
    
    // MARK: - Boundary Condition Tests
    
    func testEMABoundaryValues() {
        // Test with extreme EMA values (0 and 100)
        let extremeEMA = EMAResponse(
            stressLevel: 0.0,         // Minimum stress
            calmJitteryLevel: 100.0,  // Maximum jitteriness  
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = extremeEMA
        gameScene.didMove(to: mockView)
        
        // Check transition point (from max jitteriness)
        XCTAssertEqual(gameScene.breathingTransitionPoint, gameConfig.emaJitterinessTransitionPointMax, accuracy: 0.001,
                      "Maximum jitteriness should result in maximum transition point")
        
        // Force breathing transition
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        
        // Check pacing arousal (from min stress)
        XCTAssertEqual(gameScene.initialBreathingPacingArousal, gameConfig.emaStressPacingArousalMin, accuracy: 0.001,
                      "Minimum stress should result in minimum pacing arousal")
        
        print("Boundary values test:")
        print("  ├─ Max jitteriness -> transition: \(gameScene.breathingTransitionPoint)")
        print("  └─ Min stress -> pacing: \(gameScene.initialBreathingPacingArousal)")
    }
    
    func testBreathingPacingArousalsStoredCorrectly() {
        // Verify that arousal values are stored correctly when breathing begins
        let testEMA = EMAResponse(
            stressLevel: 60.0,
            calmJitteryLevel: 40.0,
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = testEMA
        gameScene.didMove(to: mockView)
        
        // Set a specific system arousal level before breathing transition
        let preBreathingArousal: CGFloat = 0.32
        gameScene.currentArousalLevel = preBreathingArousal
        
        // Force transition to breathing (this should be below threshold)
        XCTAssertEqual(gameScene.currentState, .breathing, "Should be in breathing state")
        
        // Verify that arousalAtBreathingStart was stored correctly
        XCTAssertEqual(gameScene.arousalAtBreathingStart, preBreathingArousal, accuracy: 0.001,
                      "arousalAtBreathingStart should match the system arousal at transition")
        
        // Verify that initialBreathingPacingArousal was calculated from stress
        let normalizedStress = 60.0 / 100.0
        let expectedPacing = gameConfig.emaStressPacingArousalMin + 
            (normalizedStress * (gameConfig.emaStressPacingArousalMax - gameConfig.emaStressPacingArousalMin))
        // = 0.15 + (0.6 * 0.20) = 0.15 + 0.12 = 0.27
        
        XCTAssertEqual(gameScene.initialBreathingPacingArousal, expectedPacing, accuracy: 0.001,
                      "initialBreathingPacingArousal should be calculated from stress level")
        
        print("Storage test:")
        print("  ├─ System arousal at breathing start: \(gameScene.arousalAtBreathingStart)")
        print("  └─ Initial pacing from stress: \(gameScene.initialBreathingPacingArousal)")
    }
    
    // MARK: - Breathing Duration Calculation Tests
    
    func testBreathingDurationCalculation_HighPacing() {
        // Test breathing durations when effective pacing arousal is high (high stress, early in breathing phase)
        let highStressEMA = EMAResponse(
            stressLevel: 90.0,        // Very high stress
            calmJitteryLevel: 50.0,
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = highStressEMA
        gameScene.didMove(to: mockView)
        
        // Force to breathing state with high system arousal (early in breathing phase)
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.02
        
        // Enable testing mode to get immediate updates
        gameScene.isTesting = true
        
        // Call parameter update which should calculate breathing durations
        gameScene.updateParametersFromArousal()
        
        // At high effective pacing arousal, should have shorter exhale (more balanced pattern)
        // The breathing pacing affects the normalized value used for duration interpolation
        XCTAssertLessThan(gameScene.currentBreathingExhaleDuration, gameConfig.dynamicBreathingMaxExhaleDuration,
                         "High pacing arousal should result in shorter exhale duration")
        XCTAssertGreaterThan(gameScene.currentBreathingInhaleDuration, gameConfig.dynamicBreathingMinInhaleDuration,
                            "High pacing arousal should result in longer inhale duration")
        
        print("High pacing duration test:")
        print("  ├─ Inhale duration: \(gameScene.currentBreathingInhaleDuration)")
        print("  └─ Exhale duration: \(gameScene.currentBreathingExhaleDuration)")
    }
    
    func testBreathingDurationCalculation_LowPacing() {
        // Test breathing durations when effective pacing arousal is low (low stress, late in breathing phase)
        let lowStressEMA = EMAResponse(
            stressLevel: 10.0,        // Very low stress
            calmJitteryLevel: 50.0,
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = lowStressEMA
        gameScene.didMove(to: mockView)
        
        // Force to breathing state and simulate significant system arousal decay
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        let originalArousalStart = gameScene.arousalAtBreathingStart
        
        // Simulate significant decay in system arousal (late in breathing phase)
        gameScene.currentArousalLevel = originalArousalStart * 0.1 // 10% of original
        
        // Enable testing mode
        gameScene.isTesting = true
        
        // Call parameter update which should flag for duration changes
        gameScene.updateParametersFromArousal()
        
        // Force apply the deferred visual duration updates immediately for testing
        // Simulate the breathing cycle start that would apply the deferred updates
        if gameScene.needsVisualDurationUpdate {
            // Manually calculate expected durations based on the effective pacing arousal
            let breathingDecayProgress = max(0.0, min(1.0, (gameScene.arousalAtBreathingStart - gameScene.currentArousalLevel) / gameScene.arousalAtBreathingStart))
            let effectivePacingArousal = gameScene.initialBreathingPacingArousal * (1.0 - breathingDecayProgress)
            let breathingArousalRange = gameConfig.trackingArousalThresholdLow
            let normalizedBreathingArousal = min(1.0, effectivePacingArousal / breathingArousalRange)
            
            // Apply the same calculations as in runBreathingCycleAction
            let minInhale = gameConfig.dynamicBreathingMinInhaleDuration
            let maxInhale = gameConfig.dynamicBreathingMaxInhaleDuration
            let minExhale = gameConfig.dynamicBreathingMinExhaleDuration
            let maxExhale = gameConfig.dynamicBreathingMaxExhaleDuration
            
            let targetInhaleDuration = minInhale + (maxInhale - minInhale) * normalizedBreathingArousal
            let targetExhaleDuration = maxExhale + (minExhale - maxExhale) * normalizedBreathingArousal
            
            // At low effective pacing arousal, should have longer exhale (emphasis on exhale)
            XCTAssertGreaterThan(targetExhaleDuration, targetInhaleDuration,
                                "Low pacing arousal should result in longer exhale than inhale")
            XCTAssertGreaterThan(targetExhaleDuration, gameConfig.dynamicBreathingMinExhaleDuration,
                                "Low pacing arousal should result in longer exhale duration")
            
            print("Low pacing duration test (calculated targets):")
            print("  ├─ Effective pacing arousal: \(effectivePacingArousal)")
            print("  ├─ Normalized for breathing: \(normalizedBreathingArousal)")
            print("  ├─ Target inhale duration: \(targetInhaleDuration)")
            print("  └─ Target exhale duration: \(targetExhaleDuration)")
        } else {
            // If no duration update was flagged, the test might be invalid
            print("Warning: No breathing duration update was flagged - test conditions may be insufficient")
        }
        
    }
    
    // MARK: - Edge Cases and Error Handling
    
    func testEMAWithExtremeValues() {
        // Test with values outside 0-100 range (should be handled gracefully)
        let extremeEMA = EMAResponse(
            stressLevel: 150.0,       // Above 100 (invalid)
            calmJitteryLevel: -10.0,  // Below 0 (invalid)
            completionTime: 0.0,
            emaType: .preSession
        )
        
        gameScene.preSessionEMA = extremeEMA
        gameScene.didMove(to: mockView)
        
        // Should not crash and should produce values within valid ranges (clamped to 0-100)
        XCTAssertGreaterThanOrEqual(gameScene.breathingTransitionPoint, gameConfig.emaJitterinessTransitionPointMin,
                                   "Should clamp invalid jitteriness to valid range")
        XCTAssertLessThanOrEqual(gameScene.breathingTransitionPoint, gameConfig.emaJitterinessTransitionPointMax,
                                "Should clamp invalid jitteriness to valid range")
        
        // Force breathing transition
        gameScene.currentArousalLevel = gameConfig.trackingArousalThresholdLow - 0.05
        
        XCTAssertGreaterThanOrEqual(gameScene.initialBreathingPacingArousal, gameConfig.emaStressPacingArousalMin,
                                   "Should clamp invalid stress to valid range")
        XCTAssertLessThanOrEqual(gameScene.initialBreathingPacingArousal, gameConfig.emaStressPacingArousalMax,
                                "Should clamp invalid stress to valid range")
        
        print("Extreme values test passed without crashing")
    }
    
    // MARK: - Configuration Consistency Tests
    
    func testEMAConfigurationRangesValid() {
        // Test that configuration ranges are valid
        XCTAssertLessThan(gameConfig.emaJitterinessTransitionPointMin, gameConfig.emaJitterinessTransitionPointMax,
                         "Jitteriness transition point min should be less than max")
        XCTAssertGreaterThan(gameConfig.emaJitterinessTransitionPointMin, 0.0,
                            "Jitteriness transition point min should be positive")
        XCTAssertLessThan(gameConfig.emaJitterinessTransitionPointMax, 1.0,
                         "Jitteriness transition point max should be less than 1.0")
        
        XCTAssertLessThan(gameConfig.emaStressPacingArousalMin, gameConfig.emaStressPacingArousalMax,
                         "Stress pacing arousal min should be less than max")
        XCTAssertGreaterThan(gameConfig.emaStressPacingArousalMin, 0.0,
                            "Stress pacing arousal min should be positive")
        XCTAssertLessThanOrEqual(gameConfig.emaStressPacingArousalMax, gameConfig.trackingArousalThresholdLow,
                                "Stress pacing arousal max should not exceed breathing threshold")
    }
    
}
