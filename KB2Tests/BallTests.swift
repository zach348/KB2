import XCTest
import SpriteKit
@testable import KB2

class BallTests: XCTestCase {
    var ball: Ball!
    let testPosition = CGPoint(x: 100, y: 100)
    let testTargetColor = SKColor.red
    let testDistractorColor = SKColor.blue
    
    override func setUp() {
        super.setUp()
        ball = Ball(isTarget: false, position: testPosition)
    }
    
    override func tearDown() {
        ball = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testBallInitialization() {
        XCTAssertNotNil(ball)
        XCTAssertEqual(ball.position, testPosition)
        XCTAssertFalse(ball.isTarget)
        XCTAssertNotNil(ball.physicsBody)
    }
    
    func testBallPhysicsBody() {
        XCTAssertNotNil(ball.physicsBody)
        XCTAssertEqual(ball.physicsBody?.categoryBitMask, 1)
        XCTAssertEqual(ball.physicsBody?.collisionBitMask, 1)
        XCTAssertEqual(ball.physicsBody?.contactTestBitMask, 1)
        XCTAssertEqual(ball.physicsBody?.restitution, 1.0)
        XCTAssertEqual(ball.physicsBody?.friction, 0.0)
        XCTAssertEqual(ball.physicsBody?.linearDamping, 0.0)
        XCTAssertEqual(ball.physicsBody?.angularDamping, 0.0)
    }
    
    // MARK: - Appearance Tests
    
    func testUpdateAppearanceAsTarget() {
        ball.isTarget = true
        ball.updateAppearance(targetColor: testTargetColor, distractorColor: testDistractorColor)
        
        XCTAssertEqual(ball.fillColor, testTargetColor)
        XCTAssertEqual(ball.strokeColor, testTargetColor)
    }
    
    func testUpdateAppearanceAsDistractor() {
        ball.isTarget = false
        ball.updateAppearance(targetColor: testTargetColor, distractorColor: testDistractorColor)
        
        XCTAssertEqual(ball.fillColor, testDistractorColor)
        XCTAssertEqual(ball.strokeColor, testDistractorColor)
    }
    
    // MARK: - Identity Management Tests
    
    func testHideIdentity() {
        ball.hideIdentity(hiddenColor: testDistractorColor)
        XCTAssertEqual(ball.fillColor, testDistractorColor)
        XCTAssertEqual(ball.strokeColor, testDistractorColor)
    }
    
    func testRevealIdentity() {
        ball.isTarget = true
        ball.hideIdentity(hiddenColor: testDistractorColor)
        ball.revealIdentity(targetColor: testTargetColor, distractorColor: testDistractorColor)
        
        XCTAssertEqual(ball.fillColor, testTargetColor)
        XCTAssertEqual(ball.strokeColor, testTargetColor)
    }
    
    // MARK: - Physics Tests
    
    func testApplyRandomImpulse() {
        let initialVelocity = ball.physicsBody?.velocity ?? .zero
        ball.applyRandomImpulse()
        let newVelocity = ball.physicsBody?.velocity ?? .zero
        
        XCTAssertNotEqual(newVelocity, initialVelocity)
        XCTAssertGreaterThan(newVelocity.dx * newVelocity.dx + newVelocity.dy * newVelocity.dy, 0)
    }
    
    func testStoreAndRestoreVelocity() {
        let testVelocity = CGVector(dx: 100, dy: 100)
        ball.physicsBody?.velocity = testVelocity
        ball.storedVelocity = testVelocity
        
        XCTAssertEqual(ball.storedVelocity, testVelocity)
        
        ball.physicsBody?.velocity = .zero
        ball.physicsBody?.velocity = ball.storedVelocity ?? .zero
        
        XCTAssertEqual(ball.physicsBody?.velocity, testVelocity)
    }
} 