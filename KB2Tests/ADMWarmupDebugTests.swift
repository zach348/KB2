import XCTest
@testable import KB2

class ADMWarmupDebugTests: XCTestCase {
    
    func testDebugWarmupTransition() {
        var testConfig = GameConfiguration()
        testConfig.enableSessionPhases = true
        testConfig.performanceHistoryWindowSize = 10
        
        let sessionDuration: TimeInterval = 15 * 60
        let adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.7,
            sessionDuration: sessionDuration
        )
        
        // Calculate expected warmup length
        let expectedRounds = SessionAnalytics.estimateExpectedRounds(
            forSessionDuration: sessionDuration,
            config: testConfig,
            initialArousal: 0.7
        )
        let calculatedWarmupLength = Int(CGFloat(expectedRounds) * testConfig.warmupPhaseProportion)
        let warmupLength = (testConfig.enableSessionPhases && expectedRounds > 0) ? max(1, calculatedWarmupLength) : calculatedWarmupLength
        
        print("=== DEBUG WARMUP TRANSITION ===")
        print("Session duration: \(sessionDuration) seconds")
        print("Expected total rounds: \(expectedRounds)")
        print("Warmup length: \(warmupLength)")
        print("Initial positions: \(adm.normalizedPositions)")
        
        // Track positions through warmup
        var roundPositions: [[DOMTargetType: CGFloat]] = []
        
        // Simulate rounds
        for round in 0..<(warmupLength + 3) {
            print("\n--- Round \(round + 1) ---")
            
            let positionsBefore = adm.normalizedPositions
            
            let expectation = XCTestExpectation(description: "Record performance round \(round + 1)")
            adm.recordIdentificationPerformanceAsync(
                taskSuccess: true,
                tfTtfRatio: 0.65,
                reactionTime: 0.5,
                responseDuration: 2.0,
                averageTapAccuracy: 50.0,
                actualTargetsToFindInRound: 3
            ) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
            
            roundPositions.append(adm.normalizedPositions)
            
            // Check if any positions changed
            var changes: [String] = []
            for (dom, posBefore) in positionsBefore {
                if let posAfter = adm.normalizedPositions[dom] {
                    let change = posAfter - posBefore
                    if abs(change) > 0.001 {
                        changes.append("\(dom): \(String(format: "%.3f", posBefore)) → \(String(format: "%.3f", posAfter)) (Δ: \(String(format: "%+.3f", change)))")
                    }
                }
            }
            
            if !changes.isEmpty {
                print("Position changes:")
                changes.forEach { print("  - \($0)") }
            } else {
                print("No position changes")
            }
        }
        
        print("\n=== FINAL ANALYSIS ===")
        print("Total rounds simulated: \(roundPositions.count)")
        print("Expected warmup rounds: \(warmupLength)")
        
        // Check positions at key points
        if warmupLength > 0 && roundPositions.count > warmupLength {
            let beforeTransition = roundPositions[warmupLength - 1]
            let afterTransition = roundPositions[warmupLength]
            
            print("\nPositions before transition (round \(warmupLength)):")
            for (dom, pos) in beforeTransition.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                print("  - \(dom): \(String(format: "%.3f", pos))")
            }
            
            print("\nPositions after transition (round \(warmupLength + 1)):")
            for (dom, pos) in afterTransition.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                print("  - \(dom): \(String(format: "%.3f", pos))")
            }
            
            // Check for reset
            var anyReset = false
            for (dom, beforePos) in beforeTransition {
                if let afterPos = afterTransition[dom] {
                    let jump = abs(afterPos - beforePos)
                    if jump > 0.15 { // Significant jump might indicate reset
                        print("\nWARNING: Possible reset detected for \(dom): \(String(format: "%.3f", beforePos)) → \(String(format: "%.3f", afterPos))")
                        anyReset = true
                    }
                }
            }
            
            if anyReset {
                XCTFail("Positions appear to have reset after warmup transition")
            }
        }
    }
    
    func testDebugShortSession() {
        var testConfig = GameConfiguration()
        testConfig.enableSessionPhases = true
        
        let sessionDuration: TimeInterval = 2 * 60 // 2 minutes
        
        print("=== DEBUG SHORT SESSION ===")
        print("Session duration: \(sessionDuration) seconds")
        
        // Test with different arousal levels
        for arousal in [0.5, 0.7, 1.0] {
            print("\nTesting with arousal: \(arousal)")
            
            let expectedRounds = SessionAnalytics.estimateExpectedRounds(
                forSessionDuration: sessionDuration,
                config: testConfig,
                initialArousal: arousal
            )
            
            let calculatedWarmupLength = Int(CGFloat(expectedRounds) * testConfig.warmupPhaseProportion)
            let warmupLength = (testConfig.enableSessionPhases && expectedRounds > 0) ? max(1, calculatedWarmupLength) : calculatedWarmupLength
            
            print("  Expected rounds: \(expectedRounds)")
            print("  Warmup rounds: \(warmupLength)")
            print("  Warmup percentage: \(warmupLength > 0 ? String(format: "%.1f%%", (CGFloat(warmupLength) / CGFloat(expectedRounds)) * 100) : "0%")")
            
            // Create ADM to verify initialization
            let adm = AdaptiveDifficultyManager(
                configuration: testConfig,
                initialArousal: arousal,
                sessionDuration: sessionDuration
            )
            
            print("  ADM initialized successfully")
            print("  Initial positions: \(adm.normalizedPositions.map { "\($0.key): \(String(format: "%.3f", $0.value))" }.joined(separator: ", "))")
            
            XCTAssertGreaterThan(expectedRounds, 0, "Should have at least 1 round even in short session")
            if expectedRounds > 0 {
                XCTAssertGreaterThan(warmupLength, 0, "Should have at least 1 warmup round")
                XCTAssertLessThanOrEqual(warmupLength, expectedRounds, "Warmup should not exceed total rounds")
            }
        }
    }
}
