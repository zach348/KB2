import XCTest
@testable import KB2

class ADMAdaptationGapTests: XCTestCase {
    var config: GameConfiguration!
    
    override func setUp() {
        super.setUp()
        config = GameConfiguration()
    }
    
    func testAdaptationGap_WhenPDControllerIsNotReady_SystemUsesGlobalAdaptation() throws {
        // Configure short warmup and high data requirements
        config.enableSessionPhases = true
        config.warmupPhaseProportion = 0.1  // Very short warmup (10%)
        config.enableDomSpecificProfiling = true
        config.domMinDataPointsForProfiling = 20  // High requirement to ensure PD controller won't have enough data
        
        // Create ADM with 10-minute session (expect ~10 rounds)
        let adm = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600
        )
        
        // Skip warmup phase by recording 2 rounds (assuming ~10 total rounds, 10% = 1 round)
        for _ in 0..<2 {
            adm.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 0.8,
                reactionTime: 1.5,
                responseDuration: 4.0,
                averageTapAccuracy: 30.0,
                actualTargetsToFindInRound: 3
            )
        }
        
        // Now in standard phase, but not enough data for PD controller
        // Record initial positions
        let initialPositions = Dictionary(uniqueKeysWithValues: 
            DOMTargetType.allCases.map { ($0, adm.normalizedPositions[$0] ?? 0.5) }
        )
        
        // Simulate poor performance to trigger adaptation
        for _ in 0..<5 {
            adm.recordIdentificationPerformance(
                taskSuccess: false,
                tfTtfRatio: 0.3,
                reactionTime: 3.0,
                responseDuration: 8.0,
                averageTapAccuracy: 50.0,
                actualTargetsToFindInRound: 3
            )
        }
        
        // Verify that positions changed (global adaptation occurred)
        var anyPositionChanged = false
        for domType in DOMTargetType.allCases {
            let currentPosition = adm.normalizedPositions[domType] ?? 0.5
            if abs(currentPosition - initialPositions[domType]!) > 0.001 {
                anyPositionChanged = true
                print("DOM \(domType) changed from \(String(format: "%.3f", initialPositions[domType]!)) to \(String(format: "%.3f", currentPosition))")
            }
        }
        
        XCTAssertTrue(anyPositionChanged, 
            "DOM positions should have changed through global adaptation when PD controller lacks data")
    }
    
    func testAdaptationGap_WhenPDControllerHasSufficientData_UsesPDControl() throws {
        // Configure to allow PD controller to run
        config.enableSessionPhases = true
        config.warmupPhaseProportion = 0.1
        config.enableDomSpecificProfiling = true
        config.domMinDataPointsForProfiling = 5  // Low requirement
        
        // Create ADM
        let adm = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600
        )
        
        // Skip warmup and provide enough data for PD controller
        for i in 0..<10 {
            // Vary performance to create diverse data
            let performance = CGFloat(i) / 10.0
            adm.recordIdentificationPerformance(
                taskSuccess: performance > 0.5,
                tfTtfRatio: performance,
                reactionTime: 2.0 - Double(performance),
                responseDuration: 5.0 - Double(performance * 2),
                averageTapAccuracy: 40.0 - (performance * 20),
                actualTargetsToFindInRound: 3
            )
        }
        
        // Verify PD controller has sufficient data
        var allDomsHaveSufficientData = true
        for domType in DOMTargetType.allCases {
            if let profile = adm.domPerformanceProfiles[domType] {
                let dataCount = profile.performanceByValue.count
                print("DOM \(domType) has \(dataCount) data points")
                if dataCount < config.domMinDataPointsForProfiling {
                    allDomsHaveSufficientData = false
                }
            }
        }
        
        XCTAssertTrue(allDomsHaveSufficientData,
            "All DOMs should have sufficient data for PD controller to run")
    }
    
    func testAdaptationGap_TransitionFromGlobalToPDControl() throws {
        // Test the transition when PD controller gains sufficient data
        config.enableSessionPhases = true
        config.warmupPhaseProportion = 0.1
        config.enableDomSpecificProfiling = true
        config.domMinDataPointsForProfiling = 8
        
        let adm = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 600
        )
        
        // Skip warmup
        for _ in 0..<2 {
            adm.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 0.7,
                reactionTime: 1.5,
                responseDuration: 4.0,
                averageTapAccuracy: 30.0,
                actualTargetsToFindInRound: 3
            )
        }
        
        var transitionOccurred = false
        var roundsUsingGlobalAdaptation = 0
        var roundsUsingPDController = 0
        
        // Gradually accumulate data
        for round in 0..<15 {
            // Check data count before recording
            let dataCountBefore = adm.domPerformanceProfiles[.discriminatoryLoad]?.performanceByValue.count ?? 0
            
            adm.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 0.6,
                reactionTime: 2.0,
                responseDuration: 5.0,
                averageTapAccuracy: 35.0,
                actualTargetsToFindInRound: 3
            )
            
            let dataCountAfter = adm.domPerformanceProfiles[.discriminatoryLoad]?.performanceByValue.count ?? 0
            
            // Determine which adaptation method was likely used
            if dataCountAfter < config.domMinDataPointsForProfiling {
                roundsUsingGlobalAdaptation += 1
            } else {
                if roundsUsingGlobalAdaptation > 0 && roundsUsingPDController == 0 {
                    transitionOccurred = true
                }
                roundsUsingPDController += 1
            }
            
            print("Round \(round + 3): Data count = \(dataCountAfter), Using \(dataCountAfter >= config.domMinDataPointsForProfiling ? "PD Controller" : "Global Adaptation")")
        }
        
        XCTAssertTrue(transitionOccurred,
            "Should transition from global adaptation to PD controller when sufficient data is accumulated")
        XCTAssertGreaterThan(roundsUsingGlobalAdaptation, 0,
            "Should have used global adaptation initially")
        XCTAssertGreaterThan(roundsUsingPDController, 0,
            "Should have used PD controller after accumulating data")
    }
}
