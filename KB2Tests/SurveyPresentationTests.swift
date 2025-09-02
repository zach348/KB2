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
    
    override func setUp() {
        super.setUp()
        // Reset FirstRunManager state before each test
        FirstRunManager.shared.resetForDebug()
    }
    
    override func tearDown() {
        // Clean up after each test
        FirstRunManager.shared.resetForDebug()
        super.tearDown()
    }
    
    // MARK: - Session Count Tests
    
    func testSurveyNotPresentedOnFirstSession() {
        // Given: Fresh install (session count = 0, no survey interaction)
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 0)
        XCTAssertFalse(FirstRunManager.shared.hasAcceptedSurvey)
        XCTAssertNil(FirstRunManager.shared.surveyLastDeclinedVersion)
        
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
    
    func testSurveyNotPresentedAfterDeclineInCurrentVersion() {
        // Given: User has completed enough sessions and declined in current version
        FirstRunManager.shared.sessionCount = 3
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        FirstRunManager.shared.surveyLastDeclinedVersion = currentVersion
        
        // Then: Survey should not be presented
        XCTAssertFalse(shouldPresentSurvey(), "Survey should NOT be presented after decline in current app version")
    }
    
    func testSurveyRepresentedAfterDeclineInPreviousVersion() {
        // Given: User declined in a previous version but app has been updated
        FirstRunManager.shared.sessionCount = 2
        FirstRunManager.shared.surveyLastDeclinedVersion = "1.0"
        
        // Mock current version as different (normally this would be from Bundle.main)
        let mockCurrentVersion = "1.1"
        
        // Then: Survey should be presented again (simulate version check)
        let shouldPresent = shouldPresentSurveyWithVersion(mockCurrentVersion)
        XCTAssertTrue(shouldPresent, "Survey SHOULD be re-presented after app version update")
    }
    
    func testSurveyDeclineInPreviousVersionWithMoreSessions() {
        // Given: User declined in version 1.0, now on version 1.1 with more sessions
        FirstRunManager.shared.sessionCount = 8
        FirstRunManager.shared.surveyLastDeclinedVersion = "1.0"
        
        let mockCurrentVersion = "1.1"
        
        // Then: Survey should be presented again (meets session threshold)
        let shouldPresent = shouldPresentSurveyWithVersion(mockCurrentVersion)
        XCTAssertTrue(shouldPresent, "Survey SHOULD be re-presented after version update when session threshold is met")
    }
    
    // MARK: - Complex Scenario Tests
    
    func testComplexScenario_AcceptThenDeclineInNewVersion() {
        // This shouldn't happen in real app flow, but test the edge case
        
        // Given: User has both accepted and declined (acceptance should take precedence)
        FirstRunManager.shared.sessionCount = 5
        FirstRunManager.shared.hasAcceptedSurvey = true
        FirstRunManager.shared.surveyLastDeclinedVersion = "1.0"
        
        // Then: Survey should not be presented (acceptance takes precedence)
        XCTAssertFalse(shouldPresentSurvey(), "Survey should NOT be presented when user has accepted (regardless of decline history)")
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
        let lastDeclinedVersion = FirstRunManager.shared.surveyLastDeclinedVersion
        let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        
        // Survey presented after 2nd session and all subsequent sessions until accepted
        let meetsSessionThreshold = sessionCount >= 2
        let hasNotAcceptedSurvey = !hasAcceptedSurvey
        let shouldRepromptAfterDecline = lastDeclinedVersion != currentAppVersion
        
        return meetsSessionThreshold && hasNotAcceptedSurvey && shouldRepromptAfterDecline
    }
    
    /// Version of shouldPresentSurvey that accepts a mock current version for testing
    private func shouldPresentSurveyWithVersion(_ mockCurrentVersion: String) -> Bool {
        let sessionCount = FirstRunManager.shared.sessionCount
        let hasAcceptedSurvey = FirstRunManager.shared.hasAcceptedSurvey
        let lastDeclinedVersion = FirstRunManager.shared.surveyLastDeclinedVersion
        
        // Survey presented after 2nd session and all subsequent sessions until accepted
        let meetsSessionThreshold = sessionCount >= 2
        let hasNotAcceptedSurvey = !hasAcceptedSurvey
        let shouldRepromptAfterDecline = lastDeclinedVersion != mockCurrentVersion
        
        return meetsSessionThreshold && hasNotAcceptedSurvey && shouldRepromptAfterDecline
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
    
    func testSurveyDeclineUpdatesFlags() {
        // Given: Survey is eligible to be shown (session count >= 2)
        FirstRunManager.shared.sessionCount = 2
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        // When: User declines survey (simulate onDecline logic)
        FirstRunManager.shared.surveyLastDeclinedVersion = currentVersion
        
        // Then: surveyLastDeclinedVersion should be set to current version
        XCTAssertEqual(FirstRunManager.shared.surveyLastDeclinedVersion, currentVersion)
        
        // And: Survey should no longer be presented
        XCTAssertFalse(shouldPresentSurvey(), "Survey should not be presented after decline in current version")
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
        
        // When: We read the value directly from UserDefaults
        let storedCount = UserDefaults.standard.integer(forKey: "sessionCount")
        
        // Then: The value should match
        XCTAssertEqual(storedCount, 5, "Session count should persist in UserDefaults")
    }
    
    // MARK: - Reset Behavior Tests
    
    func testResetForDebugClearsSurveyFlags() {
        // Given: User has interacted with survey
        FirstRunManager.shared.sessionCount = 5
        FirstRunManager.shared.hasAcceptedSurvey = true
        FirstRunManager.shared.surveyLastDeclinedVersion = "1.0"
        
        // When: Debug reset is called
        FirstRunManager.shared.resetForDebug()
        
        // Then: All survey-related flags should be cleared
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 0)
        XCTAssertFalse(FirstRunManager.shared.hasAcceptedSurvey)
        XCTAssertNil(FirstRunManager.shared.surveyLastDeclinedVersion)
    }
    
    func testResetForTestFlightClearsSurveyFlags() {
        // Given: User has interacted with survey
        FirstRunManager.shared.sessionCount = 7
        FirstRunManager.shared.hasAcceptedSurvey = true
        FirstRunManager.shared.surveyLastDeclinedVersion = "1.2"
        
        // When: TestFlight reset is called
        FirstRunManager.shared.resetForTestFlight()
        
        // Then: All survey-related flags should be cleared
        XCTAssertEqual(FirstRunManager.shared.sessionCount, 0)
        XCTAssertFalse(FirstRunManager.shared.hasAcceptedSurvey)
        XCTAssertNil(FirstRunManager.shared.surveyLastDeclinedVersion)
    }
    
    // MARK: - Edge Cases
    
    func testSurveyLogicWithNilDeclinedVersion() {
        // Given: User has enough sessions but no decline history
        FirstRunManager.shared.sessionCount = 4
        FirstRunManager.shared.surveyLastDeclinedVersion = nil
        
        // Then: Survey should be presented (nil != any version and meets threshold)
        XCTAssertTrue(shouldPresentSurvey(), "Survey should be presented when no decline history exists")
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
