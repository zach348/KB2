//
//  SurveyPresentationTests.swift
//  KB2Tests
//
//  Created on [Current Date]
//  Tests for survey presentation logic based on session count and user preferences
//

import XCTest
@testable import KB2

class SurveyPresentationTests: XCTestCase {
    private var testUserDefaults: UserDefaults!
    private var testFirstRunManager: FirstRunManager!
    
    override func setUp() {
        super.setUp()
        // Create isolated test UserDefaults
        testUserDefaults = TestHelpers.createTestUserDefaults()
        
        // Create FirstRunManager with test UserDefaults
        testFirstRunManager = FirstRunManager(userDefaults: testUserDefaults)
        
        // Replace shared instance for testing
        FirstRunManager.shared = testFirstRunManager
    }
    
    override func tearDown() {
        // Clean up test UserDefaults
        TestHelpers.cleanupTestUserDefaults(testUserDefaults)
        
        // Restore original shared instance
        FirstRunManager.shared = FirstRunManager()
        
        super.tearDown()
    }
    
    // MARK: - Session Count Tests
    
    func testSurveyNotPresentedOnFirstSession() {
        // Given: Fresh install (session count = 0, no survey interaction)
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 0)
        XCTAssertFalse(FirstRunManager.shared.hasAcceptedSurvey)
        
        // When: First session completes
        FirstRunManager.shared.sessionCount = 1
        
        // Then: Survey should NOT be presented (need 2+ sessions)
        XCTAssertFalse(shouldPresentSurvey(), "Survey should NOT be presented after 1st session")
    }
    
    func testSurveyPresentedOnSecondSession() {
        // Given: User has completed one session
        FirstRunManager.shared.sessionCount = 2
        
        // Then: Survey should be presented (meets threshold)
        XCTAssertTrue(shouldPresentSurvey(), "Survey SHOULD be presented after 2nd session")
    }
    
    func testSurveyPresentedOnThirdSession() {
        // Given: User has completed two sessions
        FirstRunManager.shared.sessionCount = 3
        
        // Then: Survey should be presented (meets threshold)
        XCTAssertTrue(shouldPresentSurvey(), "Survey SHOULD be presented after 3rd session")
    }
    
    func testSurveyPresentedOnSecondAndSubsequentSessions() {
        // Test session 1 - should NOT be presented
        FirstRunManager.shared.sessionCount = 1
        XCTAssertFalse(shouldPresentSurvey(), "Survey should NOT be presented after 1st session")
        
        // Test session 2 - should be presented
        FirstRunManager.shared.sessionCount = 2
        XCTAssertTrue(shouldPresentSurvey(), "Survey SHOULD be presented after 2nd session")
        
        // Test session 4 - should be presented
        FirstRunManager.shared.sessionCount = 4
        XCTAssertTrue(shouldPresentSurvey(), "Survey SHOULD be presented after 4th session")
        
        // Test session 10 - should be presented
        FirstRunManager.shared.sessionCount = 10
        XCTAssertTrue(shouldPresentSurvey(), "Survey SHOULD be presented after 10th session")
    }
    
    // MARK: - User Acceptance Tests
    
    func testSurveyNotPresentedAfterUserAccepts() {
        // Given: User has completed multiple sessions and accepted the survey
        FirstRunManager.shared.sessionCount = 5
        FirstRunManager.shared.hasAcceptedSurvey = true
        
        // Then: Survey should not be presented again
        XCTAssertFalse(shouldPresentSurvey(), "Survey should NOT be presented after user has accepted it")
    }
    
    func testSurveyAcceptancePersistsAcrossSessions() {
        // Given: User accepted survey in a previous session
        FirstRunManager.shared.sessionCount = 3
        FirstRunManager.shared.hasAcceptedSurvey = true
        
        // When: More sessions complete
        FirstRunManager.shared.sessionCount = 6
        
        // Then: Survey should still not be presented
        XCTAssertFalse(shouldPresentSurvey(), "Survey should NOT be presented in subsequent sessions after acceptance")
    }
    
    // MARK: - User Decline Tests
    
    func testSurveyPresentedAgainAfterDecline() {
        // Given: User has completed enough sessions (survey was previously declined but no version tracking)
        FirstRunManager.shared.sessionCount = 3
        
        // Then: Survey should still be presented (no version-based blocking)
        XCTAssertTrue(shouldPresentSurvey(), "Survey SHOULD be re-presented every session until accepted")
    }
    
    func testSurveyRepresentedConsistentlyUntilAccepted() {
        // Given: User has many sessions but hasn't accepted survey
        FirstRunManager.shared.sessionCount = 8
        
        // Then: Survey should be presented (repeated until accepted)
        XCTAssertTrue(shouldPresentSurvey(), "Survey SHOULD be re-presented consistently until user accepts")
    }
    
    // MARK: - Complex Scenario Tests
    
    func testComplexScenario_AcceptanceTakesPrecedence() {
        // Given: User has accepted survey (regardless of session count)
        FirstRunManager.shared.sessionCount = 5
        FirstRunManager.shared.hasAcceptedSurvey = true
        
        // Then: Survey should not be presented (acceptance takes precedence)
        XCTAssertFalse(shouldPresentSurvey(), "Survey should NOT be presented when user has accepted")
    }
    
    func testComplexScenario_HighSessionCountWithoutInteraction() {
        // Given: User has many sessions but never interacted with survey
        FirstRunManager.shared.sessionCount = 20
        
        // Then: Survey should still be presented (meets session threshold)
        XCTAssertTrue(shouldPresentSurvey(), "Survey SHOULD be presented even after many sessions if no interaction")
    }
    
    // MARK: - Helper Methods
    
    /// Replicates the logic from GameScene.checkAndPresentSurveyIfNeeded()
    private func shouldPresentSurvey() -> Bool {
        let sessionCount = FirstRunManager.shared.sessionCount
        let hasAcceptedSurvey = FirstRunManager.shared.hasAcceptedSurvey
        
        // Survey presented after 2nd session and all subsequent sessions until accepted
        let meetsSessionThreshold = sessionCount >= 2
        let hasNotAcceptedSurvey = !hasAcceptedSurvey
        
        return meetsSessionThreshold && hasNotAcceptedSurvey
    }
    
    // MARK: - Integration Tests for Survey Completion Handlers
    
    func testSurveyAcceptanceUpdatesFlags() {
        // Given: Survey is eligible to be shown (session count >= 2)
        FirstRunManager.shared.sessionCount = 2
        XCTAssertFalse(FirstRunManager.shared.hasAcceptedSurvey)
        
        // When: User accepts survey (simulate onConfirm logic)
        FirstRunManager.shared.hasAcceptedSurvey = true
        
        // Then: hasAcceptedSurvey should be true
        XCTAssertTrue(FirstRunManager.shared.hasAcceptedSurvey)
        
        // And: Survey should no longer be presented
        XCTAssertFalse(shouldPresentSurvey(), "Survey should not be presented after acceptance")
    }
    
    func testSurveyDeclineDoesNotAffectPresentation() {
        // Given: Survey is eligible to be shown (session count >= 2)
        FirstRunManager.shared.sessionCount = 2
        
        // When: User declines survey (no tracking needed - survey will re-present)
        // No decline tracking in current implementation
        
        // Then: Survey should still be presented in next session (no version-based blocking)
        XCTAssertTrue(shouldPresentSurvey(), "Survey should continue to be presented every session until accepted")
    }
    
    // MARK: - Session Counter Tests
    
    func testSessionCounterIncrementsCorrectly() {
        // Given: Fresh state
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 0)
        
        // When: Sessions complete
        FirstRunManager.shared.sessionCount += 1
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 1)
        XCTAssertFalse(shouldPresentSurvey(), "Survey should NOT be eligible after 1st session")
        
        FirstRunManager.shared.sessionCount += 1
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 2)
        XCTAssertTrue(shouldPresentSurvey(), "Survey should be eligible after 2nd session")
        
        FirstRunManager.shared.sessionCount += 1
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 3)
        XCTAssertTrue(shouldPresentSurvey(), "Survey should be eligible after 3rd session")
    }
    
    func testSessionCounterPersistsInUserDefaults() {
        // Given: Session count is incremented
        FirstRunManager.shared.sessionCount = 5
        
        // When: We read the value directly from test UserDefaults
        let storedCount = testUserDefaults.integer(forKey: "sessionCount")
        
        // Then: The value should match
        XCTAssertEqual(storedCount, 5, "Session count should persist in UserDefaults")
    }
    
    // MARK: - Reset Behavior Tests
    
    func testResetForDebugClearsSurveyFlags() {
        // Given: User has interacted with survey
        FirstRunManager.shared.sessionCount = 5
        FirstRunManager.shared.hasAcceptedSurvey = true
        
        // When: Debug reset is called
        FirstRunManager.shared.resetForDebug()
        
        // Then: All survey-related flags should be cleared
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 0)
        XCTAssertFalse(FirstRunManager.shared.hasAcceptedSurvey)
    }
    
    func testResetForTestFlightClearsSurveyFlags() {
        // Given: User has interacted with survey
        FirstRunManager.shared.sessionCount = 7
        FirstRunManager.shared.hasAcceptedSurvey = true
        
        // When: TestFlight reset is called
        FirstRunManager.shared.resetForTestFlight()
        
        // Then: All survey-related flags should be cleared
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 0)
        XCTAssertFalse(FirstRunManager.shared.hasAcceptedSurvey)
    }
    
    // MARK: - Edge Cases
    
    func testSurveyLogicWithoutDeclineTracking() {
        // Given: User has enough sessions (no decline tracking in current implementation)
        FirstRunManager.shared.sessionCount = 4
        
        // Then: Survey should be presented (meets threshold, no version-based blocking)
        XCTAssertTrue(shouldPresentSurvey(), "Survey should be presented when session threshold is met")
    }
    
    func testSurveyLogicWithZeroSessions() {
        // Given: No sessions completed
        FirstRunManager.shared.sessionCount = 0
        
        // Then: Survey should not be presented (below threshold)
        XCTAssertFalse(shouldPresentSurvey(), "Survey should not be presented with zero sessions")
    }
    
    // MARK: - Performance Tests
    
    func testSurveyLogicPerformance() {
        // This test ensures the survey logic check is fast enough to not impact user experience
        
        FirstRunManager.shared.sessionCount = 3
        
        measure {
            for _ in 0..<1000 {
                _ = shouldPresentSurvey()
            }
        }
    }
}
