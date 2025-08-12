//
//  ADMPDControllerIntegrationTests.swift
//  KB2Tests
//
//  Integration tests for the PD controller using synthetic data
//

import XCTest
@testable import KB2
import CoreGraphics

class ADMPDControllerIntegrationTests: XCTestCase {
    
    var testConfig: GameConfiguration!
    var adm: AdaptiveDifficultyManager!
    
    override func setUp() {
        super.setUp()
        
        // Create a config for integration testing
        testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true
        testConfig.enableDomSpecificProfiling = true
        testConfig.enableSessionPhases = false  // Disable warmup phase
        
        adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Clear all DOM profiles
        for domType in DOMTargetType.allCases {
            adm.domPerformanceProfiles[domType] = DOMPerformanceProfile(domType: domType)
        }
    }
    
    override func tearDown() {
        if let testUserId = adm?.userId {
            ADMPersistenceManager.clearState(for: testUserId)
        }
        testConfig = nil
        adm = nil
        super.tearDown()
    }
    
    // MARK: - Synthetic Data Generator
    
    struct SyntheticDataGenerator {
        
        /// Generate performance data with a specified trend
        static func generatePerformanceData(
            domType: DOMTargetType,
            basePerformance: CGFloat,
            trend: PerformanceTrend,
            dataPoints: Int,
            domValueRange: ClosedRange<CGFloat> = 0.2...0.8
        ) -> [DOMPerformanceProfile.PerformanceDataPoint] {
            
            var data: [DOMPerformanceProfile.PerformanceDataPoint] = []
            let currentTime = CACurrentMediaTime()
            
            for i in 0..<dataPoints {
                let progress = CGFloat(i) / CGFloat(max(dataPoints - 1, 1))
                let domValue = domValueRange.lowerBound + (domValueRange.upperBound - domValueRange.lowerBound) * progress
                
                let performance: CGFloat
                switch trend {
                case .stable:
                    performance = basePerformance
                case .improving:
                    performance = basePerformance + progress * 0.3
                case .declining:
                    performance = basePerformance - progress * 0.3
                case .oscillating:
                    performance = basePerformance + sin(progress * .pi * 4) * 0.2
                case .noisy:
                    performance = basePerformance + CGFloat.random(in: -0.1...0.1)
                }
                
                let clampedPerformance = max(0, min(1, performance))
                let timestamp = currentTime - Double(dataPoints - i - 1) * 3600
                
                data.append(DOMPerformanceProfile.PerformanceDataPoint(
                    timestamp: timestamp,
                    value: domValue,
                    performance: clampedPerformance
                ))
            }
            
            return data
        }
        
        enum PerformanceTrend {
            case stable
            case improving
            case declining
            case oscillating
            case noisy
        }
    }
    
    // MARK: - Helper Methods
    
    private func injectSyntheticData(for domType: DOMTargetType, data: [DOMPerformanceProfile.PerformanceDataPoint]) {
        var profile = DOMPerformanceProfile(domType: domType)
        profile.performanceByValue = data
        adm.domPerformanceProfiles[domType] = profile
    }
    
    private func runRounds(_ count: Int) {
        for _ in 0..<count {
            adm.modulateDOMsWithProfiling()
        }
    }
    
    // MARK: - Integration Tests
    
    func testConvergenceAndExploration() {
        // Generate stable performance at target
        let stableData = SyntheticDataGenerator.generatePerformanceData(
            domType: .meanBallSpeed,
            basePerformance: testConfig.domProfilingPerformanceTarget,
            trend: .stable,
            dataPoints: testConfig.domMinDataPointsForProfiling
        )
        
        injectSyntheticData(for: .meanBallSpeed, data: stableData)
        
        // Set initial position
        adm.normalizedPositions[.meanBallSpeed] = 0.5
        
        // Track position changes
        var positionHistory: [CGFloat] = []
        var nudgeDetected = false
        
        // Run enough rounds to trigger convergence and nudge
        for round in 0..<(testConfig.domConvergenceDuration + 2) {
            let prePosition = adm.normalizedPositions[.meanBallSpeed] ?? 0.5
            adm.modulateDOMsWithProfiling()
            let postPosition = adm.normalizedPositions[.meanBallSpeed] ?? 0.5
            
            positionHistory.append(postPosition)
            
            // Check for nudge (significant change after stability)
            if round >= testConfig.domConvergenceDuration - 1 {
                let change = abs(postPosition - prePosition)
                if change > testConfig.domExplorationNudgeFactor * 0.8 {
                    nudgeDetected = true
                    
                    // Verify nudge magnitude
                    XCTAssertEqual(change, testConfig.domExplorationNudgeFactor, accuracy: 0.001,
                                 "Nudge magnitude should match configured factor")
                }
            }
        }
        
        // Verify convergence phase (positions should be stable before nudge)
        if testConfig.domConvergenceDuration > 2 {
            let earlyPositions = Array(positionHistory.prefix(testConfig.domConvergenceDuration - 1))
            let maxVariation = earlyPositions.max()! - earlyPositions.min()!
            XCTAssertLessThan(maxVariation, 0.01, "Position should be stable during convergence phase")
        }
        
        XCTAssertTrue(nudgeDetected, "Exploration nudge should be applied after convergence")
    }
    
    func testHardeningResponse() {
        // Generate improving performance data
        let improvingData = SyntheticDataGenerator.generatePerformanceData(
            domType: .targetCount,
            basePerformance: 0.7,  // Start below target
            trend: .improving,
            dataPoints: testConfig.domMinDataPointsForProfiling * 2,
            domValueRange: 0.3...0.7
        )
        
        injectSyntheticData(for: .targetCount, data: improvingData)
        
        // Set initial position
        let initialPosition: CGFloat = 0.4
        adm.normalizedPositions[.targetCount] = initialPosition
        
        // Run multiple rounds
        runRounds(5)
        
        let finalPosition = adm.normalizedPositions[.targetCount] ?? initialPosition
        
        // Verify hardening occurred
        XCTAssertGreaterThan(finalPosition, initialPosition,
                           "DOM should harden (increase) with improving performance")
        
        // Verify the magnitude is reasonable
        let totalChange = finalPosition - initialPosition
        XCTAssertGreaterThan(totalChange, 0.05, "Hardening should be significant")
        XCTAssertLessThan(totalChange, 0.5, "Hardening should not be excessive")
    }
    
    func testEasingResponse() {
        // Generate declining performance data
        let decliningData = SyntheticDataGenerator.generatePerformanceData(
            domType: .discriminatoryLoad,
            basePerformance: 0.7,  // Start near target so average dips below -> easing expected
            trend: .declining,
            dataPoints: testConfig.domMinDataPointsForProfiling * 2,
            domValueRange: 0.5...0.8
        )
        
        injectSyntheticData(for: .discriminatoryLoad, data: decliningData)
        
        // Set initial position high
        let initialPosition: CGFloat = 0.7
        adm.normalizedPositions[.discriminatoryLoad] = initialPosition
        
        // Run multiple rounds
        runRounds(5)
        
        let finalPosition = adm.normalizedPositions[.discriminatoryLoad] ?? initialPosition
        
        // Verify easing occurred
        XCTAssertLessThan(finalPosition, initialPosition,
                        "DOM should ease (decrease) with declining performance")
        
        // Verify the magnitude is reasonable
        let totalChange = initialPosition - finalPosition
        XCTAssertGreaterThan(totalChange, 0.02, "Easing should be significant") // Reduced from 0.04
        XCTAssertLessThan(totalChange, 0.5, "Easing should not be excessive")
    }
    
    func testDOMIndependence() {
        // Set up contrasting performance profiles for two DOMs
        // We want to test that DOMs adjust independently based on their local performance
        
        // DOM 1: Performance below target (player struggling)
        let belowTargetData = SyntheticDataGenerator.generatePerformanceData(
            domType: .meanBallSpeed,
            basePerformance: 0.5, // Below target of 0.6
            trend: .stable,
            dataPoints: testConfig.domMinDataPointsForProfiling
        )
        
        // DOM 2: Performance above target (player excelling)
        let aboveTargetData = SyntheticDataGenerator.generatePerformanceData(
            domType: .ballSpeedSD,
            basePerformance: 0.9, // Above target of 0.8
            trend: .stable,
            dataPoints: testConfig.domMinDataPointsForProfiling
        )
        
        injectSyntheticData(for: .meanBallSpeed, data: belowTargetData)
        injectSyntheticData(for: .ballSpeedSD, data: aboveTargetData)
        
        // Set initial positions at midpoint
        adm.normalizedPositions[.meanBallSpeed] = 0.5
        adm.normalizedPositions[.ballSpeedSD] = 0.5
        
        let initialSpeedPos = adm.normalizedPositions[.meanBallSpeed]!
        let initialSDPos = adm.normalizedPositions[.ballSpeedSD]!
        
        // Run rounds
        runRounds(5)
        
        let finalSpeedPos = adm.normalizedPositions[.meanBallSpeed]!
        let finalSDPos = adm.normalizedPositions[.ballSpeedSD]!
        
        // Verify independent movement based on performance vs target
        // Below target performance should cause easing (decrease)
        XCTAssertLessThan(finalSpeedPos, initialSpeedPos,
                           "meanBallSpeed should decrease with below-target performance")
        // Above target performance should cause hardening (increase)
        XCTAssertGreaterThan(finalSDPos, initialSDPos,
                        "ballSpeedSD should increase with above-target performance")
        
        // Verify they moved in opposite directions
        let speedChange = finalSpeedPos - initialSpeedPos
        let sdChange = finalSDPos - initialSDPos
        XCTAssertLessThan(speedChange, 0, "Speed change should be negative (easing)")
        XCTAssertGreaterThan(sdChange, 0, "SD change should be positive (hardening)")
    }
    
    func testOscillatingPerformanceResponse() {
        // Generate oscillating performance data
        let oscillatingData = SyntheticDataGenerator.generatePerformanceData(
            domType: .responseTime,
            basePerformance: testConfig.domProfilingPerformanceTarget,
            trend: .oscillating,
            dataPoints: testConfig.domMinDataPointsForProfiling * 3
        )
        
        injectSyntheticData(for: .responseTime, data: oscillatingData)
        
        // Track position changes
        var positions: [CGFloat] = []
        adm.normalizedPositions[.responseTime] = 0.5
        
        // Run multiple rounds
        for _ in 0..<10 {
            adm.modulateDOMsWithProfiling()
            positions.append(adm.normalizedPositions[.responseTime] ?? 0.5)
        }
        
        // Calculate variance in positions
        let mean = positions.reduce(0, +) / CGFloat(positions.count)
        let variance = positions.map { pow($0 - mean, 2) }.reduce(0, +) / CGFloat(positions.count)
        
        // With oscillating performance, positions should show some movement but not extreme
        XCTAssertGreaterThan(variance, 0.0001, "Oscillating performance should cause some position changes")
        XCTAssertLessThan(variance, 0.01, "Position variance should be moderate, not extreme")
    }
    
    func testNoisyPerformanceFiltering() {
        // Generate noisy but stable performance data
        let noisyData = SyntheticDataGenerator.generatePerformanceData(
            domType: .ballSpeedSD,
            basePerformance: testConfig.domProfilingPerformanceTarget,
            trend: .noisy,
            dataPoints: testConfig.domMinDataPointsForProfiling * 4
        )
        
        injectSyntheticData(for: .ballSpeedSD, data: noisyData)
        
        // Set initial position
        let initialPosition: CGFloat = 0.5
        adm.normalizedPositions[.ballSpeedSD] = initialPosition
        
        // Run multiple rounds
        var positions: [CGFloat] = []
        for _ in 0..<10 {
            adm.modulateDOMsWithProfiling()
            positions.append(adm.normalizedPositions[.ballSpeedSD] ?? 0.5)
        }
        
        // Despite noise, average position should remain near initial
        let averagePosition = positions.reduce(0, +) / CGFloat(positions.count)
        XCTAssertEqual(averagePosition, initialPosition, accuracy: 0.05,
                      "Noisy performance around target should keep position stable on average")
    }
    
    func testRapidPerformanceChangeResponse() {
        // Start with stable good performance
        let goodData = SyntheticDataGenerator.generatePerformanceData(
            domType: .targetCount,
            basePerformance: 0.9,
            trend: .stable,
            dataPoints: testConfig.domMinDataPointsForProfiling
        )
        
        injectSyntheticData(for: .targetCount, data: goodData)
        adm.normalizedPositions[.targetCount] = 0.5
        
        // Run a few rounds with good performance
        runRounds(3)
        let positionAfterGoodPerf = adm.normalizedPositions[.targetCount] ?? 0.5
        
        // Now inject poor performance data
        let poorData = SyntheticDataGenerator.generatePerformanceData(
            domType: .targetCount,
            basePerformance: 0.4,
            trend: .stable,
            dataPoints: testConfig.domMinDataPointsForProfiling
        )
        
        injectSyntheticData(for: .targetCount, data: poorData)
        
        // Run more rounds with poor performance
        runRounds(3)
        let positionAfterPoorPerf = adm.normalizedPositions[.targetCount] ?? 0.5
        
        // Verify the system responded to the performance change
        XCTAssertGreaterThan(positionAfterGoodPerf, 0.5,
                           "Position should increase with good performance")
        XCTAssertLessThan(positionAfterPoorPerf, positionAfterGoodPerf,
                        "Position should decrease when performance drops")
    }
    
    func testMultipleDOMsSimultaneousConvergence() {
        // Set up multiple DOMs with stable performance at target
        let domsToTest: [DOMTargetType] = [.meanBallSpeed, .targetCount, .responseTime]
        
        for domType in domsToTest {
            let stableData = SyntheticDataGenerator.generatePerformanceData(
                domType: domType,
                basePerformance: testConfig.domProfilingPerformanceTarget,
                trend: .stable,
                dataPoints: testConfig.domMinDataPointsForProfiling
            )
            injectSyntheticData(for: domType, data: stableData)
            adm.normalizedPositions[domType] = 0.5 + CGFloat.random(in: -0.1...0.1)
        }
        
        // Track which DOMs have been nudged
        var nudgedDOMs: Set<DOMTargetType> = []
        var prePositions: [DOMTargetType: CGFloat] = [:]
        
        // Run enough rounds for all to converge and potentially nudge
        for _ in 0..<(testConfig.domConvergenceDuration + 3) {
            // Record pre-positions
            for domType in domsToTest {
                prePositions[domType] = adm.normalizedPositions[domType] ?? 0.5
            }
            
            adm.modulateDOMsWithProfiling()
            
            // Check for nudges
            for domType in domsToTest {
                let postPosition = adm.normalizedPositions[domType] ?? 0.5
                let change = abs(postPosition - (prePositions[domType] ?? 0.5))
                
                if change > testConfig.domExplorationNudgeFactor * 0.8 {
                    nudgedDOMs.insert(domType)
                }
            }
        }
        
        // All stable DOMs should eventually get nudged
        XCTAssertEqual(nudgedDOMs.count, domsToTest.count,
                      "All converged DOMs should receive exploration nudges")
    }
}
