//
//  ADMDOMProfilingPersistenceTests.swift
//  KB2Tests
//
//  Created by Cline on 6/23/2025.
//
//  Tests for DOM profile persistence functionality

import XCTest
@testable import KB2

class ADMDOMProfilingPersistenceTests: XCTestCase {
    
    var testConfig: GameConfiguration!
    
    override func setUp() {
        super.setUp()
        testConfig = GameConfiguration()
        // Clear any existing persisted state for test user
        ADMPersistenceManager.clearState(for: "test_user_dom_profiles")
    }
    
    override func tearDown() {
        // Clean up test data
        ADMPersistenceManager.clearState(for: "test_user_dom_profiles")
        testConfig = nil
        super.tearDown()
    }
    
    func testDOMProfilesPersistAcrossSessions() {
        // Get the actual user ID that will be used
        let actualUserId = UserIDManager.getUserId()
        
        // Clear any existing state for this user
        ADMPersistenceManager.clearState(for: actualUserId)
        
        // Create first ADM instance with clearPastSessionData = true to start fresh
        var config1 = GameConfiguration()
        config1.clearPastSessionData = true
        config1.enableSessionPhases = false
        config1.persistDomPerformanceProfilesInState = true
        
        let adm1 = AdaptiveDifficultyManager(
            configuration: config1,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Record several rounds of performance data
        let testData: [(success: Bool, tfTtf: CGFloat, reaction: TimeInterval)] = [
            (true, 0.9, 1.2),
            (false, 0.5, 2.0),
            (true, 0.8, 1.5),
            (true, 0.95, 1.1),
            (false, 0.6, 1.8)
        ]
        
        for (i, (success, tfTtf, reaction)) in testData.enumerated() {
            let expectation1 = XCTestExpectation(description: "Record performance data \(i+1)")
            adm1.recordIdentificationPerformanceAsync(
                taskSuccess: success,
                tfTtfRatio: tfTtf,
                reactionTime: reaction,
                responseDuration: 3.0,
                averageTapAccuracy: 50.0,
                actualTargetsToFindInRound: 4
            ) {
                expectation1.fulfill()
            }
            wait(for: [expectation1], timeout: 5.0)
        }
        
        // Verify data was collected
        for domType in DOMTargetType.allCases {
            let profile = adm1.domPerformanceProfiles[domType]
            XCTAssertEqual(profile?.performanceByValue.count, testData.count, 
                          "Should have \(testData.count) data points for \(domType)")
        }
        
        // Save state
        adm1.saveState()
        
        // Create second ADM instance (simulating new session) with clearPastSessionData = false
        var config2 = GameConfiguration()
        config2.clearPastSessionData = false
        config2.enableSessionPhases = false
        config2.persistDomPerformanceProfilesInState = true
        
        let adm2 = AdaptiveDifficultyManager(
            configuration: config2,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Verify profiles were loaded
        for domType in DOMTargetType.allCases {
            guard let profile1 = adm1.domPerformanceProfiles[domType],
                  let profile2 = adm2.domPerformanceProfiles[domType] else {
                XCTFail("Profiles should exist for \(domType)")
                continue
            }
            
            // Check that the data was preserved
            XCTAssertEqual(profile2.performanceByValue.count, profile1.performanceByValue.count,
                          "Loaded profile should have same data count for \(domType)")
            
            // Verify actual data matches
            for i in 0..<profile1.performanceByValue.count {
                let dataPoint1 = profile1.performanceByValue[i]
                let dataPoint2 = profile2.performanceByValue[i]
                
                XCTAssertEqual(dataPoint2.value, dataPoint1.value, accuracy: 0.001,
                              "DOM value should match for \(domType) at index \(i)")
                XCTAssertEqual(dataPoint2.performance, dataPoint1.performance, accuracy: 0.001,
                              "Performance should match for \(domType) at index \(i)")
            }
        }
    }
    
    func testBackwardCompatibilityWithOldSavedState() {
        // Get the actual user ID that will be used
        let actualUserId = UserIDManager.getUserId()
        
        // Create an old-style persisted state without DOM profiles
        let oldState = PersistedADMState(
            performanceHistory: [],
            lastAdaptationDirection: .stable,
            directionStableCount: 0,
            normalizedPositions: [
                .meanBallSpeed: 0.5,
                .discriminatoryLoad: 0.5,
                .ballSpeedSD: 0.5,
                .responseTime: 0.5,
                .targetCount: 0.5
            ],
            domPerformanceProfiles: nil // Old format doesn't have this
        )
        
        // Save the old-style state
        ADMPersistenceManager.saveState(oldState, for: actualUserId)
        
        // Create new ADM instance with clearPastSessionData = false to load the old state
        var config = GameConfiguration()
        config.clearPastSessionData = false
        config.enableSessionPhases = false
        
        let adm = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Should not crash and should have fresh profiles
        for domType in DOMTargetType.allCases {
            let profile = adm.domPerformanceProfiles[domType]
            XCTAssertNotNil(profile, "Profile should exist for \(domType)")
            XCTAssertTrue(profile?.performanceByValue.isEmpty ?? false, 
                         "Profile should be empty when loading old format for \(domType)")
        }
    }
    
    func testLargeBufferPersistence() {
        // Get the actual user ID that will be used
        let actualUserId = UserIDManager.getUserId()
        
        // Clear any existing state for this user
        ADMPersistenceManager.clearState(for: actualUserId)
        
        // Test that a full 200-entry buffer persists correctly
        var config1 = GameConfiguration()
        config1.clearPastSessionData = true
        config1.enableSessionPhases = false
        config1.persistDomPerformanceProfilesInState = true
        
        let adm1 = AdaptiveDifficultyManager(
            configuration: config1,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Fill the buffer to capacity
        for i in 0..<200 {
            let expectation2 = XCTestExpectation(description: "Record large buffer data \(i+1)")
            adm1.recordIdentificationPerformanceAsync(
                taskSuccess: i % 3 != 0,
                tfTtfRatio: CGFloat(i % 10) / 10.0,
                reactionTime: 1.0 + Double(i % 5) * 0.2,
                responseDuration: 2.0 + Double(i % 4),
                averageTapAccuracy: 30.0 + CGFloat(i % 40),
                actualTargetsToFindInRound: 3 + i % 3
            ) {
                expectation2.fulfill()
            }
            wait(for: [expectation2], timeout: 5.0)
        }
        
        // Verify buffer is at capacity
        for domType in DOMTargetType.allCases {
            let profile = adm1.domPerformanceProfiles[domType]
            XCTAssertEqual(profile?.performanceByValue.count, 200,
                          "Buffer should be at full capacity for \(domType)")
        }
        
        // Save state
        adm1.saveState()
        
        // Load in new instance
        var config2 = GameConfiguration()
        config2.clearPastSessionData = false
        config2.enableSessionPhases = false
        config2.persistDomPerformanceProfilesInState = true
        
        let adm2 = AdaptiveDifficultyManager(
            configuration: config2,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Verify full buffer was restored
        for domType in DOMTargetType.allCases {
            let profile2 = adm2.domPerformanceProfiles[domType]
            XCTAssertEqual(profile2?.performanceByValue.count, 200,
                          "Full buffer should be restored for \(domType)")
        }
    }
    
    func testContinuityAcrossSessions() {
        // Get the actual user ID that will be used
        let actualUserId = UserIDManager.getUserId()
        
        // Clear any existing state for this user
        ADMPersistenceManager.clearState(for: actualUserId)
        
        // Test that new data appends correctly to persisted data
        var config1 = GameConfiguration()
        config1.clearPastSessionData = true
        config1.enableSessionPhases = false
        config1.persistDomPerformanceProfilesInState = true
        
        let adm1 = AdaptiveDifficultyManager(
            configuration: config1,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Record initial data
        for i in 0..<5 {
            let expectation3 = XCTestExpectation(description: "Record initial data \(i+1)")
            adm1.recordIdentificationPerformanceAsync(
                taskSuccess: true,
                tfTtfRatio: 0.8,
                reactionTime: 1.5,
                responseDuration: 3.0,
                averageTapAccuracy: 50.0,
                actualTargetsToFindInRound: 4
            ) {
                expectation3.fulfill()
            }
            wait(for: [expectation3], timeout: 5.0)
        }
        
        // Save state
        adm1.saveState()
        
        // New session
        var config2 = GameConfiguration()
        config2.clearPastSessionData = false
        config2.enableSessionPhases = false
        config2.persistDomPerformanceProfilesInState = true
        
        let adm2 = AdaptiveDifficultyManager(
            configuration: config2,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Record additional data
        for i in 0..<3 {
            let expectation4 = XCTestExpectation(description: "Record additional data \(i+1)")
            adm2.recordIdentificationPerformanceAsync(
                taskSuccess: false,
                tfTtfRatio: 0.5,
                reactionTime: 2.0,
                responseDuration: 4.0,
                averageTapAccuracy: 70.0,
                actualTargetsToFindInRound: 5
            ) {
                expectation4.fulfill()
            }
            wait(for: [expectation4], timeout: 5.0)
        }
        
        // Verify continuity
        for domType in DOMTargetType.allCases {
            let profile = adm2.domPerformanceProfiles[domType]
            XCTAssertEqual(profile?.performanceByValue.count, 8,
                          "Should have 5 old + 3 new data points for \(domType)")
            
            // Check that old data is preserved (first 5 entries)
            if let performanceData = profile?.performanceByValue {
                for i in 0..<5 {
                    XCTAssertGreaterThan(performanceData[i].performance, 0.5,
                                       "First 5 entries should have higher performance for \(domType)")
                }
                // Check that new data was appended (last 3 entries)
                for i in 5..<8 {
                    XCTAssertLessThan(performanceData[i].performance, 0.5,
                                    "Last 3 entries should have lower performance for \(domType)")
                }
            }
        }
    }
}
