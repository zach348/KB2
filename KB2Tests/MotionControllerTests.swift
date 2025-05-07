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
        let speeds = balls.map { ball in
            let dx = ball.physicsBody?.velocity.dx ?? 0
            let dy = ball.physicsBody?.velocity.dy ?? 0
            return sqrt(dx * dx + dy * dy)
        }
        
        let meanSpeed = speeds.reduce(0, +) / CGFloat(speeds.count)
        let squaredDifferences = speeds.map { ($0 - meanSpeed) * ($0 - meanSpeed) }
        let meanSquaredDifference = squaredDifferences.reduce(0, +) / CGFloat(speeds.count)
        let expectedSD = sqrt(meanSquaredDifference)
        
        XCTAssertEqual(stats.meanSpeed, meanSpeed, accuracy: 5.0)
        XCTAssertEqual(stats.speedSD, expectedSD, accuracy: 5.0)
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
        
        // Initialize ball velocities
        for ball in balls {
            ball.physicsBody?.velocity = CGVector(dx: 50, dy: 50)
        }
        
        // Apply corrections
        MotionController.applyCorrections(balls: balls, settings: motionSettings, scene: gameScene)
        
        // Verify velocities were adjusted
        let stats = MotionController.calculateStats(balls: balls)
        XCTAssertEqual(stats.meanSpeed, motionSettings.targetMeanSpeed, accuracy: 50)
        XCTAssertEqual(stats.speedSD, motionSettings.targetSpeedSD, accuracy: 30)
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
        
        // Verify points are evenly spaced (compare sets of angles)
        let expectedAngleStep = 2 * .pi / CGFloat(numPoints)
        let calculatedAngles = points.map { atan2($0.y - center.y, $0.x - center.x) }
        let expectedAngles = (0..<numPoints).map { expectedAngleStep * CGFloat($0) }
        let normalizedCalculated = calculatedAngles.map { $0 < 0 ? $0 + 2 * .pi : $0 }
        let normalizedExpected = expectedAngles.map { $0 < 0 ? $0 + 2 * .pi : $0 }
        for angle in normalizedCalculated {
            let match = normalizedExpected.contains { abs($0 - angle) < 0.2 }
            XCTAssertTrue(match, "Angle \(angle) does not match any expected angle")
        }
    }
} 