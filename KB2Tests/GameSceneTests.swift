import XCTest
import SpriteKit
@testable import KB2

class GameSceneTests: XCTestCase {
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
    
    // MARK: - Initialization Tests
    
    func testSceneInitialization() {
        XCTAssertNotNil(gameScene)
        XCTAssertEqual(gameScene.size, TestConstants.screenSize)
        XCTAssertEqual(gameScene.scaleMode, .aspectFill)
    }
    
    func testSceneDidMoveToView() {
        gameScene.didMove(to: mockView)
        
        // Verify physics world setup
        XCTAssertEqual(gameScene.physicsWorld.gravity.dx, 0)
        XCTAssertEqual(gameScene.physicsWorld.gravity.dy, 0)
        
        // Verify initial state
        XCTAssertEqual(gameScene.currentState, .tracking)
        XCTAssertEqual(gameScene.currentArousalLevel, 0.75, accuracy: 0.01)
    }
    
    // MARK: - State Transition Tests
    
    func testStateTransitionToBreathing() {
        gameScene.didMove(to: mockView)
        
        // Set arousal level below threshold
        gameScene.currentArousalLevel = 0.3
        
        // Verify state transition
        XCTAssertEqual(gameScene.currentState, .breathing)
    }
    
    func testStateTransitionToTracking() {
        gameScene.didMove(to: mockView)
        gameScene.currentState = .breathing
        gameScene.currentArousalLevel = 0.2 // below threshold
        gameScene.currentArousalLevel = 0.4 // above threshold, should trigger transition
        XCTAssertEqual(gameScene.currentState, .tracking)
    }
    
    // MARK: - Touch Handling Tests
    
    func testTwoFingerTapTopHalf() {
        gameScene.didMove(to: mockView)
        let initialArousal = gameScene.currentArousalLevel
        
        // Simulate two-finger tap in top half
        let touch1 = simulateTouch(at: CGPoint(x: 100, y: 600))
        let touch2 = simulateTouch(at: CGPoint(x: 200, y: 600))
        let touches = Set([touch1, touch2])
        
        gameScene.touchesBegan(touches, with: nil)
        
        // Verify arousal increased
        XCTAssertGreaterThan(gameScene.currentArousalLevel, initialArousal)
    }
    
    func testTwoFingerTapBottomHalf() {
        gameScene.didMove(to: mockView)
        let initialArousal = gameScene.currentArousalLevel
        
        // Simulate two-finger tap in bottom half
        let touch1 = simulateTouch(at: CGPoint(x: 100, y: 200))
        let touch2 = simulateTouch(at: CGPoint(x: 200, y: 200))
        let touches = Set([touch1, touch2])
        
        gameScene.touchesBegan(touches, with: nil)
        
        // Verify arousal decreased
        XCTAssertLessThan(gameScene.currentArousalLevel, initialArousal)
    }
    
    // MARK: - Ball Management Tests
    
    func testBallCreation() {
        gameScene.didMove(to: mockView)
        
        // Verify balls were created
        XCTAssertFalse(gameScene.balls.isEmpty)
        XCTAssertEqual(gameScene.balls.count, gameScene.gameConfiguration.numberOfBalls)
    }
    
    func testTargetAssignment() {
        gameScene.didMove(to: mockView)
        
        // Count initial targets
        let initialTargetCount = gameScene.balls.filter { $0.isTarget }.count
        
        // Assign new targets
        gameScene.assignNewTargets(flashNewTargets: false)
        
        // Verify target count matches current setting
        let newTargetCount = gameScene.balls.filter { $0.isTarget }.count
        XCTAssertEqual(newTargetCount, gameScene.currentTargetCount)
    }
} 