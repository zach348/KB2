import XCTest
@testable import KB2

class ADMKPIWeightTests: XCTestCase {

    var adm: AdaptiveDifficultyManager!
    var config: GameConfiguration!

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

    func testKPIWeightsAtLowArousal() {
        let arousal = config.kpiWeightTransitionStart - 0.1
        adm.updateArousalLevel(arousal)
        
        let score = adm.calculateOverallPerformanceScore(normalizedKPIs: [
            .taskSuccess: 1.0,
            .tfTtfRatio: 1.0,
            .reactionTime: 1.0,
            .responseDuration: 1.0,
            .tapAccuracy: 1.0
        ])
        
        let expectedScore = config.kpiWeights_LowMidArousal.taskSuccess +
                            config.kpiWeights_LowMidArousal.tfTtfRatio +
                            config.kpiWeights_LowMidArousal.reactionTime +
                            config.kpiWeights_LowMidArousal.responseDuration +
                            config.kpiWeights_LowMidArousal.tapAccuracy
        
        XCTAssertEqual(score, expectedScore, accuracy: 0.001, "Weights at low arousal are incorrect.")
    }

    func testKPIWeightsAtHighArousal() {
        let arousal = config.kpiWeightTransitionEnd + 0.1
        adm.updateArousalLevel(arousal)
        
        let score = adm.calculateOverallPerformanceScore(normalizedKPIs: [
            .taskSuccess: 1.0,
            .tfTtfRatio: 1.0,
            .reactionTime: 1.0,
            .responseDuration: 1.0,
            .tapAccuracy: 1.0
        ])
        
        let expectedScore = config.kpiWeights_HighArousal.taskSuccess +
                            config.kpiWeights_HighArousal.tfTtfRatio +
                            config.kpiWeights_HighArousal.reactionTime +
                            config.kpiWeights_HighArousal.responseDuration +
                            config.kpiWeights_HighArousal.tapAccuracy
        
        XCTAssertEqual(score, expectedScore, accuracy: 0.001, "Weights at high arousal are incorrect.")
    }

    func testKPIWeightsInTransitionZone() {
        let arousal = (config.kpiWeightTransitionStart + config.kpiWeightTransitionEnd) / 2.0
        adm.updateArousalLevel(arousal)

        let w = adm.getInterpolatedKPIWeights(arousal: arousal)
        let low = config.kpiWeights_LowMidArousal
        let high = config.kpiWeights_HighArousal

        // taskSuccess
        if low.taskSuccess == high.taskSuccess {
            XCTAssertEqual(w.taskSuccess, low.taskSuccess, accuracy: 0.0001)
        } else {
            // Expect interpolation to be strictly between low and high
            if low.taskSuccess < high.taskSuccess {
                XCTAssertGreaterThan(w.taskSuccess, low.taskSuccess)
                XCTAssertLessThan(w.taskSuccess, high.taskSuccess)
            } else {
                XCTAssertLessThan(w.taskSuccess, low.taskSuccess)
                XCTAssertGreaterThan(w.taskSuccess, high.taskSuccess)
            }
        }

        // tfTtfRatio
        if low.tfTtfRatio == high.tfTtfRatio {
            XCTAssertEqual(w.tfTtfRatio, low.tfTtfRatio, accuracy: 0.0001)
        } else {
            if low.tfTtfRatio < high.tfTtfRatio {
                XCTAssertGreaterThan(w.tfTtfRatio, low.tfTtfRatio)
                XCTAssertLessThan(w.tfTtfRatio, high.tfTtfRatio)
            } else {
                XCTAssertLessThan(w.tfTtfRatio, low.tfTtfRatio)
                XCTAssertGreaterThan(w.tfTtfRatio, high.tfTtfRatio)
            }
        }

        // reactionTime
        if low.reactionTime == high.reactionTime {
            XCTAssertEqual(w.reactionTime, low.reactionTime, accuracy: 0.0001)
        } else {
            if low.reactionTime < high.reactionTime {
                XCTAssertGreaterThan(w.reactionTime, low.reactionTime)
                XCTAssertLessThan(w.reactionTime, high.reactionTime)
            } else {
                XCTAssertLessThan(w.reactionTime, low.reactionTime)
                XCTAssertGreaterThan(w.reactionTime, high.reactionTime)
            }
        }

        // responseDuration
        if low.responseDuration == high.responseDuration {
            XCTAssertEqual(w.responseDuration, low.responseDuration, accuracy: 0.0001)
        } else {
            if low.responseDuration < high.responseDuration {
                XCTAssertGreaterThan(w.responseDuration, low.responseDuration)
                XCTAssertLessThan(w.responseDuration, high.responseDuration)
            } else {
                XCTAssertLessThan(w.responseDuration, low.responseDuration)
                XCTAssertGreaterThan(w.responseDuration, high.responseDuration)
            }
        }

        // tapAccuracy
        if low.tapAccuracy == high.tapAccuracy {
            XCTAssertEqual(w.tapAccuracy, low.tapAccuracy, accuracy: 0.0001)
        } else {
            if low.tapAccuracy < high.tapAccuracy {
                XCTAssertGreaterThan(w.tapAccuracy, low.tapAccuracy)
                XCTAssertLessThan(w.tapAccuracy, high.tapAccuracy)
            } else {
                XCTAssertLessThan(w.tapAccuracy, low.tapAccuracy)
                XCTAssertGreaterThan(w.tapAccuracy, high.tapAccuracy)
            }
        }
    }

    func testKPIWeightsWithInterpolationDisabled() {
        var testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true  // Ensure clean state for tests
        testConfig.useKPIWeightInterpolation = false
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5, sessionDuration: 600)
        
        let arousal = (config.kpiWeightTransitionStart + config.kpiWeightTransitionEnd) / 2.0
        adm.updateArousalLevel(arousal)
        
        let score = adm.calculateOverallPerformanceScore(normalizedKPIs: [
            .taskSuccess: 1.0,
            .tfTtfRatio: 1.0,
            .reactionTime: 1.0,
            .responseDuration: 1.0,
            .tapAccuracy: 1.0
        ])
        
        let expectedScore = config.kpiWeights_LowMidArousal.taskSuccess +
                            config.kpiWeights_LowMidArousal.tfTtfRatio +
                            config.kpiWeights_LowMidArousal.reactionTime +
                            config.kpiWeights_LowMidArousal.responseDuration +
                            config.kpiWeights_LowMidArousal.tapAccuracy
        
        XCTAssertEqual(score, expectedScore, accuracy: 0.001, "Weights should be low/mid when interpolation is disabled.")
    }
}
