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

// MARK: - ADM Test Helpers
class TestHelpers {
    static func createPerformanceHistory(scores: [CGFloat], hoursAgo: [Double]? = nil) -> [PerformanceHistoryEntry] {
        var history: [PerformanceHistoryEntry] = []
        let currentTime = CACurrentMediaTime()
        
        for (index, score) in scores.enumerated() {
            // Default to recent entries (5 minutes apart)
            let ageInHours = hoursAgo?[safe: index] ?? Double(index) * 0.0833 // 5 minutes = 0.0833 hours
            let timestamp = currentTime - (ageInHours * 3600)
            
            let entry = PerformanceHistoryEntry(
                timestamp: timestamp,
                overallScore: score,
                normalizedKPIs: [:], // Keep empty for simplicity in these tests
                arousalLevel: 0.5,
                currentDOMValues: [:],
                sessionContext: "test_session"
            )
            history.append(entry)
        }
        return history
    }
    
    // MARK: - UserDefaults Test Helpers
    
    /// Creates a test-specific UserDefaults instance with a unique suite name
    /// This ensures test isolation from the app's normal UserDefaults
    static func createTestUserDefaults() -> UserDefaults {
        let suiteName = "com.kb2.tests"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        
        // Clear any existing data from previous test runs
        testDefaults.removePersistentDomain(forName: suiteName)
        
        return testDefaults
    }
    
    /// Cleans up test UserDefaults after test completion
    static func cleanupTestUserDefaults(_ userDefaults: UserDefaults) {
        // Simple approach: just remove the test suite domain
        let testSuiteName = "com.kb2.tests"
        userDefaults.removePersistentDomain(forName: testSuiteName)
    }
}

// Safe array subscript extension
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
