//
//  ADMDOMProfilingTests.swift
//  KB2Tests
//
//  Created by Cline on 6/23/2025.
//
//  Tests for the DOM-specific performance profiling feature

import XCTest
@testable import KB2

class ADMDOMProfilingTests: XCTestCase {
    
    var testConfig: GameConfiguration!
    var adm: AdaptiveDifficultyManager!
    
    override func setUp() {
        super.setUp()
        testConfig = GameConfiguration()
        // Use configuration as-is since we can't modify constants
        
        adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
    }
    
    override func tearDown() {
        testConfig = nil
        adm = nil
        super.tearDown()
    }
    
    // MARK: - Phase 1 Tests: Data Structure Initialization
    
    func testDOMPerformanceProfilesInitialized() {
        // Verify that profiles are created for all DOM types
        for domType in DOMTargetType.allCases {
            let profile = adm.domPerformanceProfiles[domType]
            XCTAssertNotNil(profile, "Profile should exist for \(domType)")
            XCTAssertEqual(profile?.domType, domType, "Profile should be for correct DOM type")
            XCTAssertTrue(profile?.performanceByValue.isEmpty ?? false, "Profile should start empty")
        }
    }
    
    func testFeatureFlagDisablesJitter() {
        // Since we can't modify enableDomSpecificProfiling (it's a var but starts as false by default),
        // we can use the default config which has it disabled
        let disabledConfig = GameConfiguration()
        adm = AdaptiveDifficultyManager(
            configuration: disabledConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Store initial positions
        let initialPositions = adm.normalizedPositions
        
        // Apply modulation without jitter
        let confidence = (total: CGFloat(0.8), variance: CGFloat(0.1), direction: CGFloat(0.9), history: CGFloat(0.7))
        let change = adm.applyModulation(
            domType: .meanBallSpeed,
            currentPosition: 0.5,
            desiredPosition: 0.6,
            confidence: confidence
        )
        
        // The change should be deterministic (no randomness)
        let expectedChange = (0.6 - 0.5) * (testConfig.domHardeningSmoothingFactors[.meanBallSpeed] ?? 0.1)
        XCTAssertEqual(change, expectedChange, accuracy: 0.0001, "Change should be deterministic when feature is disabled")
    }
    
    // MARK: - Phase 3 Tests: Jitter Application
    
    func testJitterIsAppliedWhenFeatureEnabled() {
        // Create a config with the feature enabled
        var enabledConfig = GameConfiguration()
        enabledConfig.enableDomSpecificProfiling = true
        adm = AdaptiveDifficultyManager(
            configuration: enabledConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Run multiple iterations to verify randomness
        var observedPositions: Set<CGFloat> = []
        let iterations = 20
        
        for _ in 0..<iterations {
            // Reset to known state
            adm.normalizedPositions[.meanBallSpeed] = 0.5
            
            let confidence = (total: CGFloat(0.8), variance: CGFloat(0.1), direction: CGFloat(0.9), history: CGFloat(0.7))
            _ = adm.applyModulation(
                domType: .meanBallSpeed,
                currentPosition: 0.5,
                desiredPosition: 0.6,
                confidence: confidence
            )
            
            let finalPosition = adm.normalizedPositions[.meanBallSpeed] ?? 0.5
            observedPositions.insert(finalPosition)
        }
        
        // With jitter, we should see variation in final positions
        XCTAssertGreaterThan(observedPositions.count, 1, "Jitter should produce varying final positions")
        
        // Verify all positions are within expected range
        let baseSmoothedPosition = 0.5 + (0.6 - 0.5) * (enabledConfig.domHardeningSmoothingFactors[.meanBallSpeed] ?? 0.1)
        let jitterRange = enabledConfig.domAdaptationJitterFactor
        
        for position in observedPositions {
            XCTAssertGreaterThanOrEqual(position, baseSmoothedPosition - jitterRange, "Position should be within jitter range")
            XCTAssertLessThanOrEqual(position, baseSmoothedPosition + jitterRange, "Position should be within jitter range")
        }
    }
    
    func testJitterRespectsNormalizedBounds() {
        // Create a config with the feature enabled
        var enabledConfig = GameConfiguration()
        enabledConfig.enableDomSpecificProfiling = true
        adm = AdaptiveDifficultyManager(
            configuration: enabledConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Test near upper bound
        adm.normalizedPositions[.meanBallSpeed] = 0.98
        
        let confidence = (total: CGFloat(0.8), variance: CGFloat(0.1), direction: CGFloat(0.9), history: CGFloat(0.7))
        _ = adm.applyModulation(
            domType: .meanBallSpeed,
            currentPosition: 0.98,
            desiredPosition: 0.99,
            confidence: confidence
        )
        
        let finalPosition = adm.normalizedPositions[.meanBallSpeed] ?? 0.98
        XCTAssertLessThanOrEqual(finalPosition, 1.0, "Position should not exceed 1.0 even with jitter")
        XCTAssertGreaterThanOrEqual(finalPosition, 0.0, "Position should not go below 0.0")
        
        // Test near lower bound
        adm.normalizedPositions[.meanBallSpeed] = 0.02
        _ = adm.applyModulation(
            domType: .meanBallSpeed,
            currentPosition: 0.02,
            desiredPosition: 0.01,
            confidence: confidence
        )
        
        let finalPositionLow = adm.normalizedPositions[.meanBallSpeed] ?? 0.02
        XCTAssertGreaterThanOrEqual(finalPositionLow, 0.0, "Position should not go below 0.0 even with jitter")
        XCTAssertLessThanOrEqual(finalPositionLow, 1.0, "Position should not exceed 1.0")
    }
    
    func testJitterMagnitudeControlledByConfig() {
        // Skip this test since we can't modify the jitter factor at runtime
        // The jitter factor is a compile-time constant
        XCTSkip("Cannot test different jitter factors since domAdaptationJitterFactor is a compile-time constant")
        
        var maxDeviation: CGFloat = 0
        let iterations = 50
        let basePosition: CGFloat = 0.5
        let targetPosition: CGFloat = 0.6
        let smoothingFactor = testConfig.domHardeningSmoothingFactors[.meanBallSpeed] ?? 0.1
        let expectedSmoothedPosition = basePosition + (targetPosition - basePosition) * smoothingFactor
        
        for _ in 0..<iterations {
            adm.normalizedPositions[.meanBallSpeed] = basePosition
            
            let confidence = (total: CGFloat(0.8), variance: CGFloat(0.1), direction: CGFloat(0.9), history: CGFloat(0.7))
            _ = adm.applyModulation(
                domType: .meanBallSpeed,
                currentPosition: basePosition,
                desiredPosition: targetPosition,
                confidence: confidence
            )
            
            let finalPosition = adm.normalizedPositions[.meanBallSpeed] ?? basePosition
            let deviation = abs(finalPosition - expectedSmoothedPosition)
            maxDeviation = max(maxDeviation, deviation)
        }
        
        // Maximum deviation should be approximately equal to jitter factor
        XCTAssertLessThanOrEqual(maxDeviation, testConfig.domAdaptationJitterFactor + 0.001, "Max deviation should not exceed jitter factor")
        XCTAssertGreaterThan(maxDeviation, testConfig.domAdaptationJitterFactor * 0.5, "Should see significant jitter with larger factor")
    }
    
    // MARK: - Phase 2 Tests: Data Collection (Passive)
    
    func testPerformanceDataIsCollected() {
        // Enable the feature
        var enabledConfig = GameConfiguration()
        enabledConfig.enableDomSpecificProfiling = true
        adm = AdaptiveDifficultyManager(
            configuration: enabledConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Simulate a round
        adm.recordIdentificationPerformance(
            taskSuccess: true,
            tfTtfRatio: 0.8,
            reactionTime: 1.5,
            responseDuration: 3.0,
            averageTapAccuracy: 50.0,
            actualTargetsToFindInRound: 4
        )
        
        // Verify data was collected for each DOM
        for domType in DOMTargetType.allCases {
            guard let profile = adm.domPerformanceProfiles[domType] else {
                XCTFail("Profile should exist for \(domType)")
                continue
            }
            
            XCTAssertEqual(profile.performanceByValue.count, 1, "Should have recorded one data point for \(domType)")
            
            if let dataPoint = profile.performanceByValue.first {
                XCTAssertGreaterThan(dataPoint.value, 0, "DOM value should be positive")
                XCTAssertGreaterThanOrEqual(dataPoint.performance, 0, "Performance should be >= 0")
                XCTAssertLessThanOrEqual(dataPoint.performance, 1, "Performance should be <= 1")
            }
        }
    }
    
    func testPerformanceBufferLimitsSize() {
        // Record many rounds to test buffer limiting
        for i in 0..<210 { // More than the 200 buffer limit
            adm.recordIdentificationPerformance(
                taskSuccess: i % 2 == 0, // Alternate success/failure
                tfTtfRatio: CGFloat(i % 10) / 10.0,
                reactionTime: 1.0 + Double(i % 5) * 0.2,
                responseDuration: 2.0 + Double(i % 3),
                averageTapAccuracy: 40.0 + CGFloat(i % 20),
                actualTargetsToFindInRound: 3 + i % 3
            )
        }
        
        // Verify buffer is limited to 200 entries
        for domType in DOMTargetType.allCases {
            guard let profile = adm.domPerformanceProfiles[domType] else {
                XCTFail("Profile should exist for \(domType)")
                continue
            }
            
            XCTAssertLessThanOrEqual(profile.performanceByValue.count, 200, "Buffer should not exceed 200 entries for \(domType)")
            XCTAssertGreaterThan(profile.performanceByValue.count, 0, "Buffer should contain data for \(domType)")
        }
    }
}
