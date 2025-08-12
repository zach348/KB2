import XCTest
@testable import KB2

class ADMBoundaryRecoveryTests: XCTestCase {
    
    private var config: GameConfiguration!
    private var adm: AdaptiveDifficultyManager!
    
    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        config.enableDomSpecificProfiling = true
        config.domMinDataPointsForProfiling = 5 // Lower for testing
        
        adm = AdaptiveDifficultyManager(
            configuration: config,
            initialArousal: 0.5,
            sessionDuration: 900
        )
    }
    
    func testBoundaryRecoveryFromFloor() {
        // 1. Force a DOM to its floor
        adm.normalizedPositions[.meanBallSpeed] = 0.05
        
        // 2. Simulate consistently good performance
        for _ in 0..<10 {
            adm.recordIdentificationPerformance(
                taskSuccess: true,
                tfTtfRatio: 1.0,
                reactionTime: 0.2,
                responseDuration: 0.5,
                averageTapAccuracy: 10,
                actualTargetsToFindInRound: 3
            )
        }
        
        // 3. Check that the DOM position has increased
        let finalPosition = adm.normalizedPositions[.meanBallSpeed] ?? 0.05
        XCTAssertGreaterThan(finalPosition, 0.05, "DOM should have recovered from the floor")
    }
}
