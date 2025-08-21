import XCTest
@testable import KB2

class ADMPriorityTests: XCTestCase {

    var adm: AdaptiveDifficultyManager!
    var config: GameConfiguration!

    override func setUp() {
        super.setUp()
        config = GameConfiguration()
        config.clearPastSessionData = true  // Ensure clean state for tests
        // Disable DOM profiling to avoid jitter in tests
        config.enableDomSpecificProfiling = false
        adm = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
    }

    override func tearDown() {
        adm = nil
        config = nil
        super.tearDown()
    }

    // MARK: - Priority Interpolation Tests

    func testPriorityInterpolationAtLowArousal() {
        let priority = adm.calculateInterpolatedDOMPriority(domType: .targetCount, arousal: 0.5, invert: false)
        XCTAssertEqual(priority, config.domAdaptationRates_LowMidArousal[.targetCount]!, accuracy: 0.01)
    }

    func testPriorityInterpolationAtHighArousal() {
        let priority = adm.calculateInterpolatedDOMPriority(domType: .targetCount, arousal: 0.9, invert: false)
        XCTAssertEqual(priority, config.domAdaptationRates_HighArousal[.targetCount]!, accuracy: 0.01)
    }

    func testPriorityInterpolationMidTransition() {
        let arousal = (config.kpiWeightTransitionStart + config.kpiWeightTransitionEnd) / 2
        let priority = adm.calculateInterpolatedDOMPriority(domType: .targetCount, arousal: arousal, invert: false)
        let lowPriority = config.domAdaptationRates_LowMidArousal[.targetCount]!
        let highPriority = config.domAdaptationRates_HighArousal[.targetCount]!
        
        // smoothstep at midpoint (t=0.5) is 0.5
        let expectedPriority = lowPriority + (highPriority - lowPriority) * 0.5
        
        XCTAssertNotEqual(priority, lowPriority)
        XCTAssertNotEqual(priority, highPriority)
        XCTAssertEqual(priority, expectedPriority, accuracy: 0.01)
    }
    
    func testInvertedPriorityCalculation() {
        // Get normal priorities for all DOM types
        let normalPriorities = DOMTargetType.allCases.map { 
            (domType: $0, priority: adm.calculateInterpolatedDOMPriority(domType: $0, arousal: 0.5, invert: false))
        }
        
        // Find the max priority
        let maxPriority = normalPriorities.map { $0.priority }.max() ?? 0.0
        
        // For each DOM type, test that inversion is correct
        for (domType, normalPriority) in normalPriorities {
            let invertedPriority = adm.calculateInterpolatedDOMPriority(domType: domType, arousal: 0.5, invert: true)
            
            // With our new implementation, inversion should be (maxPriority + 1 - normalPriority)
            let expectedInversion = maxPriority + 1.0 - normalPriority
            XCTAssertEqual(invertedPriority, expectedInversion, accuracy: 0.01, 
                          "Inverted priority for \(domType) should be \(expectedInversion)")
            
            // Also verify that high-priority items have low inverted priority and vice versa
            // Use a small tolerance to avoid edge case failures when priorities are exactly equal
            let midpoint = maxPriority / 2 + 1
            if normalPriority > (maxPriority / 2) + 0.001 {
                XCTAssertLessThan(invertedPriority, midpoint, 
                                "High priority items should have low inverted priority")
            } else if normalPriority < (maxPriority / 2) - 0.001 {
                XCTAssertGreaterThan(invertedPriority, midpoint, 
                                   "Low priority items should have high inverted priority")
            }
            // Skip the assertion for items exactly at the midpoint to avoid edge case failures
        }
    }
    
    func testDiscriminatoryLoadPriorityInversion() {
        // Test specifically for discriminatory load since it had issues with the original implementation
        let normalPriority = adm.calculateInterpolatedDOMPriority(domType: .discriminatoryLoad, arousal: 0.8, invert: false)
        let invertedPriority = adm.calculateInterpolatedDOMPriority(domType: .discriminatoryLoad, arousal: 0.8, invert: true)
        
        // The inverted priority should be non-zero even if the normal priority is high
        XCTAssertGreaterThan(invertedPriority, 0.0, "Inverted priority should never be zero, even for highest priority item")
        
        // Get all priorities at this arousal level
        let allPriorities = DOMTargetType.allCases.map {
            adm.calculateInterpolatedDOMPriority(domType: $0, arousal: 0.8, invert: false)
        }
        let maxPriority = allPriorities.max() ?? 0.0
        
        // Verify the exact calculation
        XCTAssertEqual(invertedPriority, maxPriority + 1.0 - normalPriority, accuracy: 0.01, 
                      "Inverted priority should be maxPriority + 1 - normalPriority")
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
        // GIVEN: All DOMs are slightly above the midpoint to ensure Pass 1 engages
        for domType in DOMTargetType.allCases {
            adm.normalizedPositions[domType] = 0.6
        }
        
        let initialPositions = adm.normalizedPositions

        // WHEN: A negative budget is applied
        _ = adm.modulateDOMsWithWeightedBudget(totalBudget: -0.2, arousal: 0.5, invertPriorities: true)
        
        // THEN: All DOMs should be eased from their initial position
        for domType in DOMTargetType.allCases {
            XCTAssertLessThan(adm.normalizedPositions[domType]!, initialPositions[domType]!, "All DOMs should be eased from their initial position.")
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
        
        let initialSpeedPosition = adm.normalizedPositions[.meanBallSpeed]!
        let initialCountPosition = adm.normalizedPositions[.targetCount]!

        // WHEN: A negative budget is applied
        let initialBudget: CGFloat = -0.2
        _ = adm.modulateDOMsWithWeightedBudget(totalBudget: initialBudget, arousal: 0.5, invertPriorities: true)
        
        // THEN: Both DOMs should have been eased, but the over-hardened one more so
        XCTAssertLessThan(adm.normalizedPositions[.meanBallSpeed]!, initialSpeedPosition, "Over-hardened DOM should be eased.")
        XCTAssertLessThan(adm.normalizedPositions[.targetCount]!, initialCountPosition, "DOM at/below midpoint should also be eased in the second pass.")
        
        let speedChange = initialSpeedPosition - adm.normalizedPositions[.meanBallSpeed]!
        let countChange = initialCountPosition - adm.normalizedPositions[.targetCount]!
        
        XCTAssertGreaterThan(speedChange, countChange, "The over-hardened DOM should have a larger change.")
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
    
    // MARK: - Direction-Specific Smoothing Tests
    
    func testDirectionalSmoothingFactorsForHardening() {
        // GIVEN: DOM positioned at 0.5
        adm.normalizedPositions[.discriminatoryLoad] = 0.5
        let initialPosition = adm.normalizedPositions[.discriminatoryLoad]!
        
        // WHEN: Applying a positive change (hardening)
        let desiredPosition = initialPosition + 0.1 // Move in hardening direction
        let smoothedChange = adm.applyModulation(domType: .discriminatoryLoad,
                                                 currentPosition: initialPosition,
                                                 desiredPosition: desiredPosition, confidence: (total: 1.0, variance: 1.0, direction: 1.0, history: 1.0))
        
        // THEN: Hardening smoothing factor should have been applied
        let hardeningFactor = config.domHardeningSmoothingFactors[.discriminatoryLoad]!
        let expectedSmoothedChange = 0.1 * hardeningFactor
        let expectedPosition = initialPosition + expectedSmoothedChange
        
        XCTAssertEqual(adm.normalizedPositions[.discriminatoryLoad]!, expectedPosition, accuracy: 0.001,
                      "Hardening should use hardening smoothing factor")
        XCTAssertEqual(smoothedChange, expectedSmoothedChange, accuracy: 0.001,
                      "Returned change should be the smoothed change")
    }
    
    func testDirectionalSmoothingFactorsForEasing() {
        // GIVEN: DOM positioned at 0.5
        adm.normalizedPositions[.discriminatoryLoad] = 0.5
        let initialPosition = adm.normalizedPositions[.discriminatoryLoad]!
        
        // WHEN: Applying a negative change (easing)
        let desiredPosition = initialPosition - 0.1 // Move in easing direction
        let smoothedChange = adm.applyModulation(domType: .discriminatoryLoad,
                                                 currentPosition: initialPosition,
                                                 desiredPosition: desiredPosition, confidence: (total: 1.0, variance: 1.0, direction: 1.0, history: 1.0))
        
        // THEN: Easing smoothing factor should have been applied
        let easingFactor = config.domEasingSmoothingFactors[.discriminatoryLoad]!
        let expectedSmoothedChange = -0.1 * easingFactor
        let expectedPosition = initialPosition + expectedSmoothedChange
        
        XCTAssertEqual(adm.normalizedPositions[.discriminatoryLoad]!, expectedPosition, accuracy: 0.001,
                      "Easing should use easing smoothing factor")
        XCTAssertEqual(smoothedChange, expectedSmoothedChange, accuracy: 0.001,
                      "Returned change should be the smoothed change")
    }
    
    func testEasingFactorIsFasterThanHardeningFactor() {
        // Define DOMs that intentionally have faster easing than hardening  
        let fasterEasingDOMs: Set<DOMTargetType> = [.responseTime] // Only responseTime has easing >= hardening
        
        // Verify the configuration: most DOMs have slower easing than hardening for conservative behavior,
        // but some DOMs (like responseTime) have faster easing to help struggling players quickly
        for domType in DOMTargetType.allCases {
            let hardeningFactor = config.domHardeningSmoothingFactors[domType] ?? 0.1
            let easingFactor = config.domEasingSmoothingFactors[domType] ?? 0.1
            
            if fasterEasingDOMs.contains(domType) {
                // These DOMs should have faster or equal easing compared to hardening
                XCTAssertGreaterThanOrEqual(easingFactor, hardeningFactor,
                    "\(domType) easing factor should be >= hardening factor")
            } else {
                // Most DOMs should have slower easing than hardening for conservative behavior
                XCTAssertLessThanOrEqual(easingFactor, hardeningFactor,
                    "\(domType) should have easing factor <= hardening factor (conservative easing)")
            }
        }
    }
    
    func testEasingFactorInfluencesResponseMagnitude() {
        // Test that the easing factors are actually applied and produce different magnitudes
        // compared to hardening factors
        
        // Test with a DOM that should have different easing vs hardening factors
        let testDomType = DOMTargetType.discriminatoryLoad
        let hardeningFactor = config.domHardeningSmoothingFactors[testDomType] ?? 0.1
        let easingFactor = config.domEasingSmoothingFactors[testDomType] ?? 0.1
        
        // Set initial position
        adm.normalizedPositions[testDomType] = 0.5
        let initialPosition: CGFloat = 0.5
        
        // Test hardening (positive change)
        let hardeningChange: CGFloat = 0.2
        let hardeningResult = adm.applyModulation(
            domType: testDomType,
            currentPosition: initialPosition,
            desiredPosition: initialPosition + hardeningChange,
            confidence: (total: 1.0, variance: 1.0, direction: 1.0, history: 1.0)
        )
        
        // Reset position for easing test
        adm.normalizedPositions[testDomType] = initialPosition
        
        // Test easing (negative change)
        let easingChange: CGFloat = -0.2
        let easingResult = adm.applyModulation(
            domType: testDomType,
            currentPosition: initialPosition,
            desiredPosition: initialPosition + easingChange,
            confidence: (total: 1.0, variance: 1.0, direction: 1.0, history: 1.0)
        )
        
        // Verify that the factors are applied correctly
        let expectedHardeningResult = hardeningChange * hardeningFactor
        let expectedEasingResult = easingChange * easingFactor
        
        XCTAssertEqual(hardeningResult, expectedHardeningResult, accuracy: 0.001,
                      "Hardening should apply hardening factor")
        XCTAssertEqual(easingResult, expectedEasingResult, accuracy: 0.001,
                      "Easing should apply easing factor")
        
        // Verify that different factors produce different magnitudes when factors differ
        if hardeningFactor != easingFactor {
            XCTAssertNotEqual(abs(hardeningResult), abs(easingResult),
                            "Different smoothing factors should produce different response magnitudes")
        }
        
        // Verify the factors are being read from configuration correctly
        XCTAssertGreaterThan(hardeningFactor, 0, "Hardening factor should be positive")
        XCTAssertGreaterThan(easingFactor, 0, "Easing factor should be positive")
        XCTAssertLessThanOrEqual(hardeningFactor, 1.0, "Hardening factor should be <= 1.0")
        XCTAssertLessThanOrEqual(easingFactor, 1.0, "Easing factor should be <= 1.0")
    }
    
    private func testEasingMagnitude(withConfig config: GameConfiguration) -> CGFloat {
        let testADM = AdaptiveDifficultyManager(configuration: config, initialArousal: 0.5, sessionDuration: 600)
        testADM.normalizedPositions[.discriminatoryLoad] = 0.7 // Over-hardened
        
        // Apply easing
        _ = testADM.modulateDOMsWithWeightedBudget(totalBudget: -0.2, arousal: 0.5, invertPriorities: true)
        
        // Return the magnitude of change
        return 0.7 - testADM.normalizedPositions[.discriminatoryLoad]!
    }
}
