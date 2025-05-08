import XCTest
import SpriteKit
import GameplayKit
import CoreHaptics
import AVFoundation

// MARK: - Mock Classes

class MockSKView: SKView {
    var lastScene: SKScene?
    override func presentScene(_ scene: SKScene?) {
        lastScene = scene
        super.presentScene(scene)
    }
}

class MockSKScene: SKScene {
    var updateCalled = false
    var lastUpdateTime: TimeInterval = 0
    
    override func update(_ currentTime: TimeInterval) {
        updateCalled = true
        lastUpdateTime = currentTime
        super.update(currentTime)
    }
}

// Note: We can't actually override CHHapticEngine methods as they're not marked as overridable
class MockHapticEngine {
    var isStarted = false
    var isStopped = false
    
    func start() throws {
        isStarted = true
    }
    
    func stop() {
        isStopped = true
    }
}

// Note: We can't actually override AVAudioEngine methods as they're not marked as overridable
class MockAudioEngine {
    var isStarted = false
    var isStopped = false
    
    func start() throws {
        isStarted = true
    }
    
    func stop() {
        isStopped = true
    }
}

// MARK: - Test Utilities

extension XCTestCase {
    func waitForCondition(timeout: TimeInterval = 1.0, condition: () -> Bool) {
        let startTime = Date()
        while !condition() {
            if Date().timeIntervalSince(startTime) > timeout {
                XCTFail("Condition not met within timeout")
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }
    
    func simulateTouch(at point: CGPoint) -> UITouch {
        let mockTouch = MockUITouch(point: point)
        return mockTouch
    }
}

// MARK: - Mock Touch

class MockUITouch: UITouch {
    private var mockLocation: CGPoint
    
    init(point: CGPoint) {
        self.mockLocation = point
        super.init()
    }
    
    override func location(in view: UIView?) -> CGPoint {
        return mockLocation
    }
}

// MARK: - Test Constants

enum TestConstants {
    static let screenSize = CGSize(width: 1024, height: 768)
    static let testFrame = CGRect(origin: .zero, size: screenSize)
    static let testView = MockSKView(frame: testFrame)
} 