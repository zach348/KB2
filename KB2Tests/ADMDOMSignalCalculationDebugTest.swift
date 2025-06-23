import XCTest
@testable import KB2
import CoreGraphics

class ADMDOMSignalCalculationDebugTest: XCTestCase {
    
    var testConfig: GameConfiguration!
    var adm: AdaptiveDifficultyManager!
    
    override func setUp() {
        super.setUp()
        
        testConfig = GameConfiguration()
        testConfig.clearPastSessionData = true
        testConfig.enableDomSpecificProfiling = true
        
        adm = AdaptiveDifficultyManager(
            configuration: testConfig,
            initialArousal: 0.5,
            sessionDuration: 300
        )
        
        // Re-initialize DOM profiles
        for domType in DOMTargetType.allCases {
            adm.domPerformanceProfiles[domType] = DOMPerformanceProfile(domType: domType)
        }
    }
    
    func testDebugModulateDOMs() {
        let currentTime = CACurrentMediaTime()
        
        // Only set up one DOM with data
        var speedProfile = DOMPerformanceProfile(domType: .meanBallSpeed)
        for i in 0..<8 {
            let value = CGFloat(i) * 0.1 + 0.2
            let performance = CGFloat(i) * 0.08 + 0.4
            speedProfile.recordPerformance(
                timestamp: currentTime - Double(7 - i) * 3600,
                domValue: value,
                performance: performance
            )
        }
        adm.domPerformanceProfiles[.meanBallSpeed] = speedProfile
        
        print("Initial positions:")
        for (dom, pos) in adm.normalizedPositions {
            print("  \(dom): \(pos)")
        }
        
        // Call modulateDOMsWithProfiling
        adm.modulateDOMsWithProfiling()
        
        print("\nFinal positions:")
        for (dom, pos) in adm.normalizedPositions {
            print("  \(dom): \(pos)")
        }
        
        // The test should pass as long as no crash occurs
        XCTAssertTrue(true)
    }
}

// Extension for recordPerformance is already defined in ADMDOMSignalCalculationTests.swift
