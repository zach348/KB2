import XCTest
@testable import KB2

class ADMKPIWeightTests: XCTestCase {

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

        // Get the interpolated weights directly
        let interpolatedWeights = adm.getInterpolatedKPIWeights(arousal: arousal)

        let lowWeights = config.kpiWeights_LowMidArousal
        let highWeights = config.kpiWeights_HighArousal

        // Test taskSuccess (Low: 0.5 -> High: 0.3) - should decrease
        XCTAssertLessThan(interpolatedWeights.taskSuccess, lowWeights.taskSuccess)
        XCTAssertGreaterThan(interpolatedWeights.taskSuccess, highWeights.taskSuccess)

        // Test tfTtfRatio (Low: 0.2 -> High: 0.15) - should decrease
        XCTAssertLessThan(interpolatedWeights.tfTtfRatio, lowWeights.tfTtfRatio)
        XCTAssertGreaterThan(interpolatedWeights.tfTtfRatio, highWeights.tfTtfRatio)

        // Test reactionTime (Low: 0.1 -> High: 0.3) - should increase
        XCTAssertGreaterThan(interpolatedWeights.reactionTime, lowWeights.reactionTime)
        XCTAssertLessThan(interpolatedWeights.reactionTime, highWeights.reactionTime)

        // Test responseDuration (Low: 0.1 -> High: 0.2) - should increase
        XCTAssertGreaterThan(interpolatedWeights.responseDuration, lowWeights.responseDuration)
        XCTAssertLessThan(interpolatedWeights.responseDuration, highWeights.responseDuration)

        // Test tapAccuracy (Low: 0.1 -> High: 0.05) - should decrease
        XCTAssertLessThan(interpolatedWeights.tapAccuracy, lowWeights.tapAccuracy)
        XCTAssertGreaterThan(interpolatedWeights.tapAccuracy, highWeights.tapAccuracy)
    }

    func testKPIWeightsWithInterpolationDisabled() {
        var testConfig = GameConfiguration()
        testConfig.useKPIWeightInterpolation = false
        adm = AdaptiveDifficultyManager(configuration: testConfig, initialArousal: 0.5)
        
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
