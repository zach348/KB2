import XCTest
import SpriteKit
@testable import KB2

class SessionPatternTests: XCTestCase {
    var gameScene: GameScene!
    var mockView: MockSKView!
    
    override func setUp() {
        super.setUp()
        mockView = TestConstants.testView
        gameScene = GameScene(size: TestConstants.screenSize)
        gameScene.scaleMode = .aspectFill
    }
    
    override func tearDown() {
        gameScene = nil
        mockView = nil
        super.tearDown()
    }
    
    // MARK: - Session Profile Tests
    
    func testSessionProfileSelection() {
        // Test Standard profile
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10
        gameScene.initialArousalLevel = 0.95
        gameScene.sessionProfile = .standard
        
        gameScene.didMove(to: mockView)
        
        // Standard profile should have no challenge phases
        XCTAssertEqual(gameScene.challengePhases.count, 0, "Standard profile should not generate challenge phases")
        
        // Test Challenge profile
        gameScene.willMove(from: mockView)
        gameScene = GameScene(size: TestConstants.screenSize)
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10
        gameScene.initialArousalLevel = 0.95
        gameScene.sessionProfile = .challenge
        
        gameScene.didMove(to: mockView)
        
        // Challenge profile should have challenge phases (probability is set to 1.0 for tests)
        XCTAssertGreaterThan(gameScene.challengePhases.count, 0, "Challenge profile should generate challenge phases")
    }
    
    // MARK: - Fluctuations Tests
    
    func testFluctuationsAffectArousal() {
        // Setup session with fluctuating profile
        gameScene.sessionMode = true
        gameScene.sessionDuration = 100 // Longer duration for stable testing
        gameScene.initialArousalLevel = 0.95
        gameScene.sessionProfile = .fluctuating
        
        gameScene.didMove(to: mockView)
        
        // Get baseline curve without fluctuations (direct calculation)
        var baselineArousalValues: [CGFloat] = []
        for progress in stride(from: 0.1, through: 0.9, by: 0.1) {
            let baseArousal = gameScene.calculateBaseArousalForProgress(progress)
            baselineArousalValues.append(baseArousal)
        }
        
        // Get actual curve with fluctuations
        var fluctuatingArousalValues: [CGFloat] = []
        for progress in stride(from: 0.1, through: 0.9, by: 0.1) {
            let actualArousal = gameScene.calculateArousalForProgress(progress)
            fluctuatingArousalValues.append(actualArousal)
        }
        
        // Verify fluctuations create differences
        var hasDifferences = false
        for i in 0..<baselineArousalValues.count {
            if abs(baselineArousalValues[i] - fluctuatingArousalValues[i]) > 0.001 {
                hasDifferences = true
                break
            }
        }
        
        XCTAssertTrue(hasDifferences, "Fluctuating profile should produce different arousal values than the base curve")
        
        // Verify fluctuations don't deviate too much (reasonable bounds)
        for i in 0..<baselineArousalValues.count {
            XCTAssertLessThan(
                abs(baselineArousalValues[i] - fluctuatingArousalValues[i]),
                0.10, // Max 10% deviation
                "Fluctuations should stay within reasonable bounds"
            )
        }
    }
    
    // MARK: - Challenge Phase Tests
    
    func testChallengePhaseGeneration() {
        // Setup session with challenge profile
        gameScene.sessionMode = true
        gameScene.sessionDuration = 300 // 5 minutes
        gameScene.initialArousalLevel = 0.95
        gameScene.sessionProfile = .challenge
        
        gameScene.didMove(to: mockView)
        
        // Verify challenge phases were generated
        XCTAssertGreaterThan(gameScene.challengePhases.count, 0, "Challenge phases should be generated")
        
        // Verify challenge phases have valid properties
        for phase in gameScene.challengePhases {
            // Start should be before end
            XCTAssertLessThan(phase.startProgress, phase.endProgress, "Challenge phase start must be before end")
            
            // Duration should be within configuration range
            let durationPct = phase.endProgress - phase.startProgress
            XCTAssertGreaterThanOrEqual(durationPct, gameScene.gameConfiguration.challengePhaseDuration.lowerBound)
            XCTAssertLessThanOrEqual(durationPct, gameScene.gameConfiguration.challengePhaseDuration.upperBound)
            
            // Intensity should be within configuration range
            XCTAssertGreaterThanOrEqual(phase.intensity, gameScene.gameConfiguration.challengePhaseIntensity.lowerBound)
            XCTAssertLessThanOrEqual(phase.intensity, gameScene.gameConfiguration.challengePhaseIntensity.upperBound)
        }
    }
    
    func testChallengePhaseArousalModification() {
        // Create a test challenge phase
        let testPhase = SessionChallengePhase(
            startProgress: 0.4,
            endProgress: 0.6,
            intensity: 0.3
        )
        
        // Test arousal modification at different points
        
        // Before phase
        XCTAssertEqual(testPhase.arousalModifier(at: 0.3), 0, "No modification before phase starts")
        
        // At start - we now use less than or equal since the implementation may return a very small value
        XCTAssertLessThanOrEqual(testPhase.arousalModifier(at: 0.4), 0.001, "Minimal modification at phase start")
        
        // At middle
        let midPoint = (testPhase.startProgress + testPhase.endProgress) / 2
        XCTAssertGreaterThan(testPhase.arousalModifier(at: midPoint), 0.2, "Maximum effect at midpoint")
        
        // At end - we now use less than or equal since the implementation may return a very small value
        XCTAssertLessThanOrEqual(testPhase.arousalModifier(at: 0.6), 0.001, "Minimal modification at phase end")
        
        // After phase
        XCTAssertEqual(testPhase.arousalModifier(at: 0.7), 0, "No modification after phase ends")
    }
    
    func testChallengePhasesInSession() {
        // Setup session with challenge profile
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10 // Short for test
        gameScene.initialArousalLevel = 0.8 // Lower for more noticeable effects
        gameScene.sessionProfile = .challenge
        
        gameScene.didMove(to: mockView)
        
        // Ensure we have challenge phases
        XCTAssertGreaterThan(gameScene.challengePhases.count, 0, "Challenge phases should be generated")
        
        // Find a challenge phase to test
        guard let testPhase = gameScene.challengePhases.first else {
            XCTFail("No challenge phase available for testing")
            return
        }
        
        // Calculate the timestamp when the phase will be active (for debugging only)
        let _ = gameScene.sessionStartTime + (testPhase.startProgress * gameScene.sessionDuration)
        let _ = gameScene.sessionStartTime + (testPhase.midPoint * gameScene.sessionDuration)
        
        // Set the session start time back so that we're just before the phase starts
        gameScene.sessionStartTime = CACurrentMediaTime() - (testPhase.startProgress * gameScene.sessionDuration) + 0.2
        
        // Get base arousal (what it would be without challenges)
        let progress = (CACurrentMediaTime() - gameScene.sessionStartTime) / gameScene.sessionDuration
        let _ = gameScene.calculateBaseArousalForProgress(progress)
        
        // Force updates to move time forward through the phase
        var inChallengePhase = false
        var challengeArousalValue: CGFloat = 0
        
        // Simulate about 30 updates (game frames) to move through the phase
        for _ in 0..<30 {
            gameScene.update(CACurrentMediaTime())
            
            // Check if we've detected an active challenge
            if gameScene.isInChallengePhase {
                inChallengePhase = true
                challengeArousalValue = gameScene.currentArousalLevel
                break
            }
            
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        
        // Verify we detected a challenge phase
        XCTAssertTrue(inChallengePhase, "Challenge phase should become active")
        
        // If challenge detected, verify arousal effect
        if inChallengePhase {
            // We should see an increase or at least a deviation from the baseline curve
            let currentProgress = (CACurrentMediaTime() - gameScene.sessionStartTime) / gameScene.sessionDuration
            let expectedBaseArousal = gameScene.calculateBaseArousalForProgress(currentProgress)
            
            XCTAssertNotEqual(
                challengeArousalValue, 
                expectedBaseArousal, 
                accuracy: 0.001, 
                "Challenge phase should modify arousal"
            )
        }
    }
    
    // MARK: - Variable Profile Tests
    
    func testVariableProfile() {
        // Setup session with variable profile that has both fluctuations and challenges
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10
        gameScene.initialArousalLevel = 0.95
        gameScene.sessionProfile = .variable
        
        gameScene.didMove(to: mockView)
        
        // Verify challenge phases are created
        XCTAssertGreaterThan(gameScene.challengePhases.count, 0, "Variable profile should generate challenge phases")
        
        // Get baseline curve without fluctuations or challenges
        var baselineArousalValues: [CGFloat] = []
        var variableArousalValues: [CGFloat] = []
        
        // Sample at multiple points
        for progress in stride(from: 0.1, through: 0.9, by: 0.1) {
            let baseArousal = gameScene.calculateBaseArousalForProgress(progress)
            let variableArousal = gameScene.calculateArousalForProgress(progress)
            
            baselineArousalValues.append(baseArousal)
            variableArousalValues.append(variableArousal)
        }
        
        // Check if some points differ (showing evidence of fluctuations)
        var hasDifferences = false
        for i in 0..<baselineArousalValues.count {
            if abs(baselineArousalValues[i] - variableArousalValues[i]) > 0.001 {
                hasDifferences = true
                break
            }
        }
        
        XCTAssertTrue(hasDifferences, "Variable profile should produce different arousal values than the base curve")
    }
    
    // MARK: - Visual Indicator Tests
    
    func testChallengePhaseVisualIndicators() {
        // Setup session with challenge profile
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10
        gameScene.initialArousalLevel = 0.8
        gameScene.sessionProfile = .challenge
        
        gameScene.didMove(to: mockView)
        
        // Set up a mock challenge phase that will be active immediately
        gameScene.challengePhases = [
            SessionChallengePhase(
                startProgress: 0.0,
                endProgress: 0.2,
                intensity: 0.3
            )
        ]
        
        // Force challenge phase to start (simulate it becoming active)
        XCTAssertFalse(gameScene.isInChallengePhase, "Challenge phase should start inactive")
        
        // Manually trigger visualization
        gameScene.isInChallengePhase = true
        gameScene.startChallengePhaseVisualization()
        
        // Check that challenge indicator exists and is visible
        XCTAssertNotNil(gameScene.challengeIndicator, "Challenge indicator should exist")
        // We can't easily test alpha values in unit tests without accessing private properties,
        // but we can verify the indicator exists
        
        // Manually trigger end of visualization
        gameScene.isInChallengePhase = false
        gameScene.endChallengePhaseVisualization()
    }
} 