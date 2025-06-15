import Foundation
import XCTest
@testable import KB2

// MARK: - Mock DataLogger

import SpriteKit

// MARK: - Mock SKView
class MockSKView: SKView {
    // Override methods if needed to track calls or provide mock behavior
}

// MARK: - Test Constants
struct TestConstants {
    static let screenSize = CGSize(width: 375, height: 812) // iPhone X size
    static var testView: MockSKView {
        return MockSKView(frame: CGRect(origin: .zero, size: screenSize))
    }
}

class MockDataLogger: DataLogger {
    // Capture calls
    var loggedEvents: [(eventType: String, data: [String: Any]?)] = []
    var loggedAdaptiveDifficultySteps: [(arousal: CGFloat, performance: CGFloat)] = []
    
    // Expectation for async testing
    var logEventExpectation: XCTestExpectation?

    override func logCustomEvent(eventType: String, data: [String : Any]? = nil, description: String) {
        loggedEvents.append((eventType, data))
        logEventExpectation?.fulfill()
    }
    
    override func logAdaptiveDifficultyStep(arousalLevel: CGFloat, performanceScore: CGFloat, normalizedKPIs: [KPIType : CGFloat], domValues: [DOMTargetType : CGFloat]) {
        loggedAdaptiveDifficultySteps.append((arousal: arousalLevel, performance: performanceScore))
    }
    
    func clearLogs() {
        loggedEvents.removeAll()
        loggedAdaptiveDifficultySteps.removeAll()
    }
}

// MARK: - Test Configuration Helper

func createTestConfiguration() -> GameConfiguration {
    // Return a standard GameConfiguration instance for tests
    return GameConfiguration()
}

// MARK: - Touch Simulation

func simulateTouch(at point: CGPoint) -> UITouch {
    let touch = MockUITouch(location: point)
    return touch
}

class MockUITouch: UITouch {
    private var locationInView: CGPoint
    
    init(location: CGPoint) {
        self.locationInView = location
        super.init()
    }
    
    override func location(in view: UIView?) -> CGPoint {
        return locationInView
    }
}
