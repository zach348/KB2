import XCTest
import SpriteKit
@testable import KB2

class MotionControllerTests: XCTestCase {
    var motionController: MotionController!
    var gameScene: GameScene!
    var balls: [Ball]!
    var motionSettings: MotionSettings!
    
    override func setUp() {
        super.setUp()
        motionController = MotionController()
        gameScene = GameScene(size: TestConstants.screenSize)
        motionSettings = MotionSettings()
        
        // Create test balls
        balls = []
        for i in 0..<5 {
            let ball = Ball(isTarget: false, position: CGPoint(x: 100 + CGFloat(i) * 50, y: 100))
            balls.append(ball)
        }
    }
    
    override func tearDown() {
        motionController = nil
        gameScene = nil
        balls = nil
        motionSettings = nil
        super.tearDown()
    }
    
    // MARK: - Stats Calculation Tests
    
    func testCalculateStats() {
        // Set up balls with known velocities
        for (index, ball) in balls.enumerated() {
            let velocity = CGVector(dx: CGFloat(index + 1) * 10, dy: CGFloat(index + 1) * 10)
            ball.physicsBody?.velocity = velocity
        }
        
        let stats = MotionController.calculateStats(balls: balls)
        
        // Calculate expected values
        let square1 = CGFloat(10 * 10)
        let square2 = CGFloat(20 * 20)
        let square3 = CGFloat(30 * 30)
        let square4 = CGFloat(40 * 40)
        let square5 = CGFloat(50 * 50)
        
        let sumOfSquares = square1 + square2 + square3 + square4 + square5
        let meanOfSquares = sumOfSquares / 5
        let twoTimesMean = 2 * meanOfSquares
        let expectedMeanSpeed = sqrt(twoTimesMean)
        let expectedSD = calculateExpectedSD(balls: balls, meanSpeed: expectedMeanSpeed)
        
        XCTAssertEqual(stats.meanSpeed, expectedMeanSpeed, accuracy: 0.1)
        XCTAssertEqual(stats.speedSD, expectedSD, accuracy: 0.1)
    }
    
    private func calculateExpectedSD(balls: [Ball], meanSpeed: CGFloat) -> CGFloat {
        let squaredDifferences = balls.map { ball in
            let speed = sqrt(ball.physicsBody!.velocity.dx * ball.physicsBody!.velocity.dx +
                           ball.physicsBody!.velocity.dy * ball.physicsBody!.velocity.dy)
            return (speed - meanSpeed) * (speed - meanSpeed)
        }
        let meanSquaredDifference = squaredDifferences.reduce(0, +) / CGFloat(balls.count)
        return sqrt(meanSquaredDifference)
    }
    
    // MARK: - Motion Correction Tests
    
    func testApplyCorrections() {
        // Set up motion settings
        motionSettings.targetMeanSpeed = 100
        motionSettings.targetSpeedSD = 20
        
        // Apply corrections
        MotionController.applyCorrections(balls: balls, settings: motionSettings, scene: gameScene)
        
        // Verify velocities were adjusted
        let stats = MotionController.calculateStats(balls: balls)
        XCTAssertEqual(stats.meanSpeed, motionSettings.targetMeanSpeed, accuracy: 10)
        XCTAssertEqual(stats.speedSD, motionSettings.targetSpeedSD, accuracy: 5)
    }
    
    func testApplyCorrectionsWithZeroTargetSpeed() {
        // Set up motion settings
        motionSettings.targetMeanSpeed = 0
        motionSettings.targetSpeedSD = 0
        
        // Apply corrections
        MotionController.applyCorrections(balls: balls, settings: motionSettings, scene: gameScene)
        
        // Verify all balls stopped
        for ball in balls {
            XCTAssertEqual(Double(ball.physicsBody?.velocity.dx ?? 0), 0, accuracy: 0.1)
            XCTAssertEqual(Double(ball.physicsBody?.velocity.dy ?? 0), 0, accuracy: 0.1)
        }
    }
    
    // MARK: - Circle Points Tests
    
    func testCirclePoints() {
        let center = CGPoint(x: 100, y: 100)
        let radius: CGFloat = 50
        let numPoints = 4
        
        let points = MotionController.circlePoints(numPoints: numPoints, center: center, radius: radius)
        
        XCTAssertEqual(points.count, numPoints)
        
        // Verify points are on circle
        for point in points {
            let distance = sqrt(pow(point.x - center.x, 2) + pow(point.y - center.y, 2))
            XCTAssertEqual(distance, radius, accuracy: 0.1)
        }
        
        // Verify points are evenly spaced
        let expectedAngleStep = 2 * .pi / CGFloat(numPoints)
        for i in 0..<points.count {
            let angle = atan2(points[i].y - center.y, points[i].x - center.x)
            let expectedAngle = expectedAngleStep * CGFloat(i)
            XCTAssertEqual(angle, expectedAngle, accuracy: 0.1)
        }
    }
} 