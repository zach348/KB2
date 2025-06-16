import XCTest
@testable import KB2

class ADMPriorityTests: XCTestCase {

    var adm: AdaptiveDifficultyManager!
    var config: GameConfiguration!

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

    // MARK: - Priority Interpolation Tests

    func testPriorityInterpolationAtLowArousal() {
        let priority = adm.calculateInterpolatedDOMPriority(domType: .targetCount, arousal: 0.5, invert: false)
        XCTAssertEqual(priority, config.domPriorities_LowMidArousal[.targetCount]!, accuracy: 0.01)
    }

    func testPriorityInterpolationAtHighArousal() {
        let priority = adm.calculateInterpolatedDOMPriority(domType: .targetCount, arousal: 0.9, invert: false)
        XCTAssertEqual(priority, config.domPriorities_HighArousal[.targetCount]!, accuracy: 0.01)
    }

    func testPriorityInterpolationMidTransition() {
        let arousal = (config.kpiWeightTransitionStart + config.kpiWeightTransitionEnd) / 2
        let priority = adm.calculateInterpolatedDOMPriority(domType: .targetCount, arousal: arousal, invert: false)
        let lowPriority = config.domPriorities_LowMidArousal[.targetCount]!
        let highPriority = config.domPriorities_HighArousal[.targetCount]!
        
        // smoothstep at midpoint (t=0.5) is 0.5
        let expectedPriority = lowPriority + (highPriority - lowPriority) * 0.5
        
        XCTAssertNotEqual(priority, lowPriority)
        XCTAssertNotEqual(priority, highPriority)
        XCTAssertEqual(priority, expectedPriority, accuracy: 0.01)
    }
    
    func testInvertedPriorityCalculation() {
        let normalPriority = adm.calculateInterpolatedDOMPriority(domType: .targetCount, arousal: 0.5, invert: false)
        let invertedPriority = adm.calculateInterpolatedDOMPriority(domType: .targetCount, arousal: 0.5, invert: true)
        
        // Assuming a 1-5 scale, 6 is the max+min
        XCTAssertEqual(normalPriority + invertedPriority, 6.0, accuracy: 0.01)
    }

    // MARK: - Budget Distribution Tests

    func testBudgetDistributionHardening() {
        let budget: CGFloat = 0.2
        let distributedBudget = adm.distributeAdaptationBudget(totalBudget: budget, arousal: 0.5, invertPriorities: false, subset: nil)
        
        let totalDistributed = distributedBudget.values.reduce(0, +)
        XCTAssertEqual(totalDistributed, budget, accuracy: 0.01)
        
        // Check that higher priority DOMs get more budget
        let targetCountBudget = distributedBudget[.targetCount]!
        let ballSpeedSDBudget = distributedBudget[.ballSpeedSD]!
        XCTAssertGreaterThan(targetCountBudget, ballSpeedSDBudget)
    }
    
    func testBudgetDistributionEasing() {
        // GIVEN: All DOMs are at the midpoint, so pass 1 is skipped
        for domType in DOMTargetType.allCases {
            adm.normalizedPositions[domType] = 0.5
        }
        
        let initialPositions = adm.normalizedPositions

        // WHEN: A negative budget is applied
        _ = adm.modulateDOMsWithWeightedBudget(totalBudget: -0.2, arousal: 0.5, invertPriorities: true)
        
        // THEN: All DOMs should be eased from their initial position
        for domType in DOMTargetType.allCases {
            XCTAssertLessThan(adm.normalizedPositions[domType]!, initialPositions[domType]!, "All DOMs should be eased when starting at the midpoint.")
        }
        
        // AND: The DOMs with higher inverted priority (originally lower priority) should have moved more
        let countChange = initialPositions[.targetCount]! - adm.normalizedPositions[.targetCount]!
        let speedChange = initialPositions[.ballSpeedSD]! - adm.normalizedPositions[.ballSpeedSD]!
        XCTAssertLessThan(countChange, speedChange, "DOMs with higher inverted priority should be eased more.")
    }
    
    // MARK: - Two-Pass Easing Logic Tests
    
    func testEasingPrioritizesOverHardenedDOMs() {
        // GIVEN: One DOM is over-hardened (>0.5), others are not
        adm.normalizedPositions[.meanBallSpeed] = 0.8
        adm.normalizedPositions[.targetCount] = 0.4
        
        // WHEN: A negative budget is applied
        let initialBudget: CGFloat = -0.2
        let finalBudget = adm.modulateDOMsWithWeightedBudget(totalBudget: initialBudget, arousal: 0.5, invertPriorities: true)
        
        // THEN: The over-hardened DOM should have been eased, and the other should not have changed
        XCTAssertLessThan(adm.normalizedPositions[.meanBallSpeed]!, 0.8, "Over-hardened DOM should be eased.")
        XCTAssertEqual(adm.normalizedPositions[.targetCount]!, 0.4, accuracy: 0.001, "DOM at/below midpoint should not be touched in pass 1.")
        XCTAssertGreaterThan(finalBudget, initialBudget, "Budget should have been spent.")
    }
    
    func testEasingPassTwoEngagesWhenAllDOMsAreAtMidpoint() {
        // GIVEN: All DOMs are at or below 0.5
        adm.normalizedPositions[.meanBallSpeed] = 0.5
        adm.normalizedPositions[.targetCount] = 0.4
        
        let initialSpeedPos = adm.normalizedPositions[.meanBallSpeed]!
        let initialCountPos = adm.normalizedPositions[.targetCount]!

        // WHEN: A negative budget is applied
        _ = adm.modulateDOMsWithWeightedBudget(totalBudget: -0.2, arousal: 0.5, invertPriorities: true)
        
        // THEN: Both DOMs should have been eased according to inverted priorities
        XCTAssertLessThan(adm.normalizedPositions[.meanBallSpeed]!, initialSpeedPos, "Speed (higher inverted priority) should be eased.")
        XCTAssertLessThan(adm.normalizedPositions[.targetCount]!, initialCountPos, "Count (lower inverted priority) should be eased.")
    }
}
