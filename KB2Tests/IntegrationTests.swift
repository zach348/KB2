import XCTest
import SpriteKit
@testable import KB2

class IntegrationTests: XCTestCase {
    var gameScene: GameScene!
    var mockView: MockSKView!
    
    override func setUp() {
        super.setUp()
        mockView = TestConstants.testView
        gameScene = GameScene(size: TestConstants.screenSize)
        gameScene.scaleMode = .aspectFill
        gameScene.didMove(to: mockView)
    }
    
    override func tearDown() {
        gameScene = nil
        mockView = nil
        super.tearDown()
    }
    
    // MARK: - Session Mode and Arousal Interaction
    
    func testSessionModeArousalAffectsTargets() {
        // Setup session mode
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10
        gameScene.initialArousalLevel = 1.0
        
        // Reset the scene
        gameScene.willMove(from: mockView)
        gameScene = GameScene(size: TestConstants.screenSize)
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10
        gameScene.initialArousalLevel = 1.0
        gameScene.didMove(to: mockView)
        
        // Record initial target count
        let initialTargetCount = gameScene.currentTargetCount
        
        // Manually set session start time to 5 seconds ago (halfway through)
        gameScene.sessionStartTime = CACurrentMediaTime() - 5.0
        
        // Force multiple updates to allow throttled arousal update
        for _ in 0..<20 {
            gameScene.update(CACurrentMediaTime())
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        
        // Verify arousal has decreased
        XCTAssertLessThan(gameScene.currentArousalLevel, 1.0)
        
        // Verify target count has increased as arousal decreases
        XCTAssertGreaterThanOrEqual(gameScene.currentTargetCount, initialTargetCount)
    }
    
    // MARK: - Identification Task Bug Fix Validation
    
    func testIdentificationTaskCompletionAfterTargetShift() {
        // Force a specific target count
        gameScene.currentTargetCount = 3
        
        // Set the target count directly without going through assignNewTargets
        // This avoids the potential timing issues with flash sequences
        gameScene.targetCountForNextIDRound = gameScene.currentTargetCount
        
        // Change target count before identification starts (simulating the bug condition)
        gameScene.currentTargetCount = 4
        
        // Start identification phase
        gameScene.startIdentificationPhase()
        
        // Verify that the targets to find matches the SNAPSHOTTED value (3) not the current value (4)
        XCTAssertEqual(gameScene.targetsToFind, 3)
        
        // Verify that the target count snapshot was reset
        XCTAssertNil(gameScene.targetCountForNextIDRound)
    }
    
    // MARK: - Breathing State and Audio/Haptic Interaction
    
    func testBreathingStateAffectsAudioParameters() {
        // Start in tracking state
        // gameScene.didMove(to: mockView) // REMOVED - setUp() already calls this.
        XCTAssertEqual(gameScene.currentState, .tracking)
        
        // Record initial frequency calculated by GameScene
        // Call updateParametersFromArousal to ensure lastCalculated is fresh before grabbing it
        // didMove(to:) in setUp calls updateParametersFromArousal, so this should be up-to-date initially.
        let initialFrequency = gameScene.lastCalculatedTargetAudioFrequencyForTests ?? 0
        
        // Transition to breathing state
        let breathingThreshold = gameScene.gameConfiguration.trackingArousalThresholdLow
        gameScene.currentArousalLevel = breathingThreshold - 0.05 // This setter calls updateParametersFromArousal
        
        // Verify state transition
        XCTAssertEqual(gameScene.currentState, .breathing)
        
        // The audio frequency should still update based on arousal even in breathing state
        let breathingStateFrequency = gameScene.lastCalculatedTargetAudioFrequencyForTests ?? 0
        XCTAssertNotEqual(breathingStateFrequency, initialFrequency, "Calculated target audio frequency should change after arousal change.")
        
        // Calculate expected frequency based on current arousal
        let audioFreqRange = gameScene.gameConfiguration.maxAudioFrequency - gameScene.gameConfiguration.minAudioFrequency
        let expectedFrequency = gameScene.gameConfiguration.minAudioFrequency + (audioFreqRange * Float(gameScene.currentArousalLevel))
        
        // Verify the frequency matches expectation
        XCTAssertEqual(breathingStateFrequency, expectedFrequency, accuracy: 1.0)
    }
    
    // MARK: - End-to-End Power Curve Test
    
    func testPowerCurveAffectsEntireSystem() {
        // Setup session mode with power curve
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10
        gameScene.initialArousalLevel = 1.0
        
        // Reset the scene to apply session mode and initialize AudioManager correctly
        gameScene.willMove(from: mockView) // Clean up old scene
        gameScene = GameScene(size: TestConstants.screenSize) // Create new instance
        gameScene.sessionMode = true
        gameScene.sessionDuration = 10
        gameScene.initialArousalLevel = 1.0
        gameScene.didMove(to: mockView) // Initialize new scene and its AudioManager
        
        // Record initial values
        let initialArousal = gameScene.currentArousalLevel
        // Ensure lastCalculated is fresh before grabbing it
        gameScene.updateParametersFromArousal() 
        let initialFrequency = gameScene.lastCalculatedTargetAudioFrequencyForTests ?? 0
        let initialTargetCount = gameScene.currentTargetCount
        
        // Advance session time to 75% completion
        gameScene.sessionStartTime = CACurrentMediaTime() - 7.5
        
        // Force multiple updates to allow arousal update
        for _ in 0..<20 {
            gameScene.update(CACurrentMediaTime())
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        
        // Verify arousal has decreased according to power curve shape
        XCTAssertLessThan(gameScene.currentArousalLevel, initialArousal)
        
        let expectedArousal = gameScene.calculateArousalForProgress(0.75)
        XCTAssertEqual(gameScene.currentArousalLevel, expectedArousal, accuracy: 0.8)
        
        // Verify downstream effects
        // 1. Audio frequency should decrease with arousal
        // Ensure lastCalculated is fresh after updates
        gameScene.updateParametersFromArousal()
        XCTAssertLessThan(gameScene.lastCalculatedTargetAudioFrequencyForTests ?? initialFrequency + 1, initialFrequency, "Calculated target audio frequency should decrease with arousal.")
        
        // 2. Target count should increase with decreased arousal
        XCTAssertGreaterThanOrEqual(gameScene.currentTargetCount, initialTargetCount)
        
        // 3. If arousal is low enough, state should transition to breathing
        if gameScene.currentArousalLevel < gameScene.gameConfiguration.trackingArousalThresholdLow {
            XCTAssertEqual(gameScene.currentState, .breathing)
        } else {
            XCTAssertEqual(gameScene.currentState, .tracking)
        }
    }
}
