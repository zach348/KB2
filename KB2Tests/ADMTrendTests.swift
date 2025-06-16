import XCTest
@testable import KB2

class ADMTrendTests: XCTestCase {

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

    // Helper to add a series of performance scores to the ADM history
    private func addPerformanceHistory(scores: [CGFloat]) {
        for score in scores {
            let entry = PerformanceHistoryEntry(
                timestamp: CACurrentMediaTime(),
                overallScore: score,
                normalizedKPIs: [:],
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: "test"
            )
            adm.addPerformanceEntry(entry)
        }
    }

    func testAdaptiveScoreWithStablePerformance() {
        // GIVEN: A stable performance history around 0.6
        addPerformanceHistory(scores: [0.6, 0.6, 0.6, 0.6, 0.6])
        let currentRawScore: CGFloat = 0.6

        // WHEN: The adaptive score is calculated
        let adaptiveScore = adm.calculateAdaptivePerformanceScore(currentScore: currentRawScore)

        // THEN: The adaptive score should be very close to the raw score, as the trend is neutral
        let (average, trend, _) = adm.getPerformanceMetrics()
        XCTAssertEqual(trend, 0.0, accuracy: 0.01, "Trend should be near zero for stable performance.")
        XCTAssertEqual(average, 0.6, accuracy: 0.01, "Average should be correct.")
        XCTAssertEqual(adaptiveScore, 0.6, accuracy: 0.01, "Adaptive score should be close to the raw score with a neutral trend.")
    }

    func testAdaptiveScoreWithImprovingPerformance() {
        // GIVEN: A clearly improving performance history
        addPerformanceHistory(scores: [0.4, 0.5, 0.6, 0.7, 0.8])
        let currentRawScore: CGFloat = 0.85 // Current performance continues the trend

        // WHEN: The adaptive score is calculated
        let adaptiveScore = adm.calculateAdaptivePerformanceScore(currentScore: currentRawScore)

        // THEN: The adaptive score should be higher than a simple weighted average, due to the positive trend
        let (average, trend, _) = adm.getPerformanceMetrics()
        let scoreWithoutTrend = (currentRawScore * config.currentPerformanceWeight) + (average * config.historyInfluenceWeight)
        
        XCTAssertGreaterThan(trend, 0.0, "Trend should be positive for improving performance.")
        XCTAssertEqual(average, 0.6, accuracy: 0.01, "Average should be correct.")
        XCTAssertGreaterThan(adaptiveScore, scoreWithoutTrend, "Adaptive score should be boosted by the positive trend.")
    }

    func testAdaptiveScoreWithDecliningPerformance() {
        // GIVEN: A clearly declining performance history
        addPerformanceHistory(scores: [0.8, 0.7, 0.6, 0.5, 0.4])
        let currentRawScore: CGFloat = 0.35 // Current performance continues the trend

        // WHEN: The adaptive score is calculated
        let adaptiveScore = adm.calculateAdaptivePerformanceScore(currentScore: currentRawScore)

        // THEN: The adaptive score should be lower than a simple weighted average, due to the negative trend
        let (average, trend, _) = adm.getPerformanceMetrics()
        let scoreWithoutTrend = (currentRawScore * config.currentPerformanceWeight) + (average * config.historyInfluenceWeight)

        XCTAssertLessThan(trend, 0.0, "Trend should be negative for declining performance.")
        XCTAssertEqual(average, 0.6, accuracy: 0.01, "Average should be correct.")
        XCTAssertLessThan(adaptiveScore, scoreWithoutTrend, "Adaptive score should be penalized by the negative trend.")
    }

    func testAdaptiveScoreFallsBackWithInsufficientHistory() {
        // GIVEN: A performance history with fewer samples than required for trend calculation
        addPerformanceHistory(scores: [0.5, 0.6]) // minimumHistoryForTrend is 3
        let currentRawScore: CGFloat = 0.7

        // WHEN: The adaptive score is calculated
        let adaptiveScore = adm.calculateAdaptivePerformanceScore(currentScore: currentRawScore)

        // THEN: The adaptive score should be identical to the raw score, as the trend logic is bypassed
        XCTAssertEqual(adaptiveScore, currentRawScore, "Adaptive score should fall back to raw score when history is insufficient.")
    }
    
    func testAdaptiveScoreWeighting() {
        // GIVEN: A mixed performance history
        addPerformanceHistory(scores: [0.9, 0.9, 0.4, 0.4])
        let currentRawScore: CGFloat = 0.4
        
        // WHEN: The adaptive score is calculated
        let adaptiveScore = adm.calculateAdaptivePerformanceScore(currentScore: currentRawScore)
        
        // THEN: The score should be a blend of the current score and the historical average, plus trend adjustment
        let (average, trend, _) = adm.getPerformanceMetrics() // avg = 0.65, trend is negative
        
        let expectedScore = (currentRawScore * config.currentPerformanceWeight) +
                            (average * config.historyInfluenceWeight) +
                            (trend * config.trendInfluenceWeight)
        
        XCTAssertEqual(adaptiveScore, max(0.0, min(1.0, expectedScore)), accuracy: 0.01, "Adaptive score should correctly blend current, average, and trend components.")
        XCTAssertLessThan(adaptiveScore, average, "Adaptive score should be pulled down by the recent poor performance and negative trend.")
    }
}
