//
//  AchievementTests.swift
//  KB2Tests
//
//  Created by Testing System
//

import XCTest
@testable import KB2

class AchievementTests: XCTestCase {

    var achievementManager: AchievementManager!
    var testUserDefaults: UserDefaults!
    var mockTimeProvider: MockTimeProvider!

    override func setUp() {
        super.setUp()
        // Create isolated test UserDefaults
        testUserDefaults = TestHelpers.createTestUserDefaults()
        
        // Create mock time provider for deterministic testing
        mockTimeProvider = MockTimeProvider()
        
        // Create test AchievementManager with isolated UserDefaults and mock time provider
        achievementManager = AchievementManager(userDefaults: testUserDefaults, timeProvider: mockTimeProvider)
        
        // Replace the shared instance for this test
        AchievementManager.shared = achievementManager
    }

    override func tearDown() {
        // Clean up test UserDefaults
        TestHelpers.cleanupTestUserDefaults(testUserDefaults)
        
        // Reset shared instance to normal (for integration with other parts of the app during testing)
        AchievementManager.shared = AchievementManager()
        
        achievementManager = nil
        testUserDefaults = nil
        mockTimeProvider = nil
        super.tearDown()
    }

    // MARK: - Helper Methods
    
    private func assertAchievementUnlocked(id: String, expectInNewlyUnlocked: Bool = true, file: StaticString = #file, line: UInt = #line) {
        let achievement = achievementManager.achievements.first { $0.id == id }
        XCTAssertNotNil(achievement, "Achievement with id \(id) should exist", file: file, line: line)
        XCTAssertTrue(achievement?.isUnlocked ?? false, "Achievement '\(achievement?.title ?? "")' should be unlocked", file: file, line: line)
        
        if expectInNewlyUnlocked {
            XCTAssertTrue(achievementManager.newlyUnlockedAchievements.contains(where: { $0.id == id }), "Achievement should be in newly unlocked list", file: file, line: line)
        }
    }
    
    private func assertAchievementLocked(id: String, file: StaticString = #file, line: UInt = #line) {
        let achievement = achievementManager.achievements.first { $0.id == id }
        XCTAssertNotNil(achievement, "Achievement with id \(id) should exist", file: file, line: line)
        XCTAssertFalse(achievement?.isUnlocked ?? true, "Achievement '\(achievement?.title ?? "")' should be locked", file: file, line: line)
    }

    // MARK: - Individual Achievement Tests

    func testFirstStepsAchievement() {
        // Act
        achievementManager.recordTutorialCompletion()
        
        // Assert
        assertAchievementUnlocked(id: "first_steps")
        XCTAssertEqual(achievementManager.newlyUnlockedAchievements.count, 1)
    }

    func testSessionStarterAchievement() {
        // Act
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementUnlocked(id: "session_starter")
    }
    
    func testDedicatedUserTier1Achievement() {
        // Act - Complete 10 sessions
        for _ in 1...10 {
            achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        }
        
        // Assert
        assertAchievementUnlocked(id: "dedicated_user_10")
        XCTAssertEqual(testUserDefaults.integer(forKey: "com.kb2.sessionCount"), 10)
    }
    
    func testDedicatedUserTier2Achievement() {
        // Arrange - Set session count to 49
        testUserDefaults.set(49, forKey: "com.kb2.sessionCount")
        
        // Act - Complete one more session to reach 50
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementUnlocked(id: "dedicated_user_50")
        XCTAssertEqual(testUserDefaults.integer(forKey: "com.kb2.sessionCount"), 50)
    }
    
    func testDedicatedUserTier3Achievement() {
        // Arrange - Set session count to 99
        testUserDefaults.set(99, forKey: "com.kb2.sessionCount")
        
        // Act - Complete one more session to reach 100
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementUnlocked(id: "dedicated_user_100")
        XCTAssertEqual(testUserDefaults.integer(forKey: "com.kb2.sessionCount"), 100)
    }
    
    func testMarathonAchievement() {
        // Act - 15 minute session
        achievementManager.endSession(duration: 15 * 60, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementUnlocked(id: "marathon")
    }
    
    func testSuperMarathonAchievement() {
        // Act - 25 minute session
        achievementManager.endSession(duration: 25 * 60, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementUnlocked(id: "super_marathon")
        // Marathon should also be unlocked
        assertAchievementUnlocked(id: "marathon")
    }
    
    func testPerfectRoundAchievement() {
        // Act
        achievementManager.recordIdentificationRoundEnd(success: true)
        
        // Assert
        assertAchievementUnlocked(id: "perfect_round")
    }
    
    func testPerfectStreak5Achievement() {
        // Arrange
        achievementManager.startSession()
        
        // Act - Record 5 successful rounds
        for _ in 1...5 {
            achievementManager.recordIdentificationRoundEnd(success: true)
        }
        
        // Assert - Check achievement is unlocked during session
        assertAchievementUnlocked(id: "perfect_streak_5")
    }
    
    func testPerfectStreak10Achievement() {
        // Arrange
        achievementManager.startSession()
        
        // Act - Record 10 successful rounds
        for _ in 1...10 {
            achievementManager.recordIdentificationRoundEnd(success: true)
        }
        
        // Assert - Both streak achievements should be unlocked
        assertAchievementUnlocked(id: "perfect_streak_5")
        assertAchievementUnlocked(id: "perfect_streak_10")
    }
    
    func testPerfectStreak15Achievement() {
        // Arrange
        achievementManager.startSession()
        
        // Act - Record 15 successful rounds
        for _ in 1...15 {
            achievementManager.recordIdentificationRoundEnd(success: true)
        }
        
        // Assert - All three streak achievements should be unlocked
        assertAchievementUnlocked(id: "perfect_streak_5")
        assertAchievementUnlocked(id: "perfect_streak_10")
        assertAchievementUnlocked(id: "perfect_streak_15")
    }
    
    func testPerfectStreakBrokenAchievement() {
        // Arrange
        achievementManager.startSession()
        
        // Act - Record successful rounds, then fail one, then succeed again
        for _ in 1...3 {
            achievementManager.recordIdentificationRoundEnd(success: true)
        }
        achievementManager.recordIdentificationRoundEnd(success: false) // Break streak
        for _ in 1...5 {
            achievementManager.recordIdentificationRoundEnd(success: true)
        }
        
        // Assert - Should have perfect_streak_5 from the second streak, but not from broken first streak
        assertAchievementUnlocked(id: "perfect_streak_5")
        // Should not have 10 streak since it was broken
        assertAchievementLocked(id: "perfect_streak_10")
    }
    
    func testFlawlessSessionAchievement() {
        // Arrange
        achievementManager.startSession()
        
        // Act - Record some rounds, all successful
        achievementManager.recordIdentificationRoundStart()
        achievementManager.recordIdentificationRoundEnd(success: true)
        achievementManager.recordIdentificationRoundStart()
        achievementManager.recordIdentificationRoundEnd(success: true)
        achievementManager.recordIdentificationRoundStart()
        achievementManager.recordIdentificationRoundEnd(success: true)
        
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementUnlocked(id: "flawless_session")
    }
    
    func testFlawlessSessionNotAchievedWithFailure() {
        // Arrange
        achievementManager.startSession()
        
        // Act - Record some rounds with one failure
        achievementManager.recordIdentificationRoundStart()
        achievementManager.recordIdentificationRoundEnd(success: true)
        achievementManager.recordIdentificationRoundStart()
        achievementManager.recordIdentificationRoundEnd(success: false) // This should prevent flawless
        achievementManager.recordIdentificationRoundStart()
        achievementManager.recordIdentificationRoundEnd(success: true)
        
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementLocked(id: "flawless_session")
    }
    
    // MARK: - Breathing Achievement Tests
    
    func testBeginnerZenAchievement() {
        // Arrange
        achievementManager.startSession()
        mockTimeProvider.setCurrentTime(0)
        
        // Act - Simulate breathing session with mock time to reach 180+ seconds
        // Single long breathing session
        achievementManager.recordBreathingStateEntered()
        mockTimeProvider.advanceTime(by: 180.0) // Advance exactly 3 minutes
        achievementManager.recordBreathingStateExited()
        
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementUnlocked(id: "beginner_zen")
    }
    
    func testZenApprenticeAchievement() {
        // Arrange
        achievementManager.startSession()
        mockTimeProvider.setCurrentTime(0)
        
        // Act - Simulate breathing session with mock time to reach 300+ seconds
        // Multiple breathing segments totaling over 5 minutes
        achievementManager.recordBreathingStateEntered()
        mockTimeProvider.advanceTime(by: 200.0) // 3 minutes 20 seconds
        achievementManager.recordBreathingStateExited()
        
        achievementManager.recordBreathingStateEntered()
        mockTimeProvider.advanceTime(by: 100.0) // Additional 1 minute 40 seconds (total: 5 minutes)
        achievementManager.recordBreathingStateExited()
        
        achievementManager.endSession(duration: 600, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert - Should unlock both beginner_zen and zen_apprentice
        assertAchievementUnlocked(id: "beginner_zen")
        assertAchievementUnlocked(id: "zen_apprentice")
    }
    
    func testZenMasterAchievement() {
        // Arrange
        achievementManager.startSession()
        mockTimeProvider.setCurrentTime(0)
        
        // Act - Simulate breathing session with mock time to reach 420+ seconds
        // Single long breathing session over 7 minutes
        achievementManager.recordBreathingStateEntered()
        mockTimeProvider.advanceTime(by: 420.0) // Advance exactly 7 minutes
        achievementManager.recordBreathingStateExited()
        
        achievementManager.endSession(duration: 800, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert - Should unlock all three breathing achievements
        assertAchievementUnlocked(id: "beginner_zen")
        assertAchievementUnlocked(id: "zen_apprentice")
        assertAchievementUnlocked(id: "zen_master")
    }
    
    // MARK: - EMA Recovery Achievement Tests
    
    func testResilientReboundAchievement() {
        // Arrange - Create EMA responses with significant stress reduction
        let preEMA = EMAResponse(
            stressLevel: 80,
            calmJitteryLevel: 70,
            completionTime: 30,
            emaType: .preSession
        )
        let postEMA = EMAResponse(
            stressLevel: 50, // 30 point reduction (>20 required)
            calmJitteryLevel: 50, // 20 point reduction (meets threshold)
            completionTime: 30,
            emaType: .postSession
        )
        
        // Act
        achievementManager.endSession(duration: 300, preSessionEMA: preEMA, postSessionEMA: postEMA)
        
        // Assert
        assertAchievementUnlocked(id: "resilient_rebound")
    }
    
    func testResilientReboundAchievementWithJitteryReduction() {
        // Arrange - Test with jittery reduction meeting threshold
        let preEMA = EMAResponse(
            stressLevel: 60,
            calmJitteryLevel: 80,
            completionTime: 30,
            emaType: .preSession
        )
        let postEMA = EMAResponse(
            stressLevel: 55, // Only 5 point reduction
            calmJitteryLevel: 55, // 25 point reduction (>20 required)
            completionTime: 30,
            emaType: .postSession
        )
        
        // Act
        achievementManager.endSession(duration: 300, preSessionEMA: preEMA, postSessionEMA: postEMA)
        
        // Assert
        assertAchievementUnlocked(id: "resilient_rebound")
    }
    
    func testRecoveryRockstarAchievement() {
        // Arrange - Create EMA responses with exceptional stress reduction
        let preEMA = EMAResponse(
            stressLevel: 90,
            calmJitteryLevel: 85,
            completionTime: 30,
            emaType: .preSession
        )
        let postEMA = EMAResponse(
            stressLevel: 50, // 40 point reduction (>35 required)
            calmJitteryLevel: 55, // 30 point reduction (>25 required for both)
            completionTime: 30,
            emaType: .postSession
        )
        
        // Act
        achievementManager.endSession(duration: 300, preSessionEMA: preEMA, postSessionEMA: postEMA)
        
        // Assert - Should unlock both resilient_rebound and recovery_rockstar
        assertAchievementUnlocked(id: "resilient_rebound")
        assertAchievementUnlocked(id: "recovery_rockstar")
    }
    
    func testResilientReboundAchievementNotUnlockedWithSmallReduction() {
        // Arrange - Create EMA responses with insufficient stress reduction
        let preEMA = EMAResponse(
            stressLevel: 60,
            calmJitteryLevel: 60,
            completionTime: 30,
            emaType: .preSession
        )
        let postEMA = EMAResponse(
            stressLevel: 50, // 10 point reduction (insufficient)
            calmJitteryLevel: 50, // 10 point reduction (insufficient)
            completionTime: 30,
            emaType: .postSession
        )
        
        // Act
        achievementManager.endSession(duration: 300, preSessionEMA: preEMA, postSessionEMA: postEMA)
        
        // Assert
        assertAchievementLocked(id: "resilient_rebound")
        assertAchievementLocked(id: "recovery_rockstar")
    }

    func testDailyHabit3Achievement() {
        // Arrange - Set up consecutive days
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        
        // Simulate session on day 1
        testUserDefaults.set(twoDaysAgo, forKey: "com.kb2.lastSessionDate")
        testUserDefaults.set(1, forKey: "com.kb2.consecutiveDays")
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Simulate session on day 2
        testUserDefaults.set(yesterday, forKey: "com.kb2.lastSessionDate")
        testUserDefaults.set(2, forKey: "com.kb2.consecutiveDays")
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Act - Session on day 3 (today)
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert
        assertAchievementUnlocked(id: "daily_habit_3")
        XCTAssertEqual(testUserDefaults.integer(forKey: "com.kb2.consecutiveDays"), 3)
    }

    // MARK: - Edge Case and Integration Tests

    func testMultipleAchievementsUnlockedInSingleSession() {
        // Arrange - Set up conditions for multiple achievements
        achievementManager.startSession()
        
        // Act - Create conditions that should unlock multiple achievements
        // 1. First session + perfect rounds + marathon duration
        for _ in 1...5 {
            achievementManager.recordIdentificationRoundStart()
            achievementManager.recordIdentificationRoundEnd(success: true)
        }
        
        // End a long session (first session + marathon + flawless + streaks)
        achievementManager.endSession(duration: 16 * 60, preSessionEMA: nil, postSessionEMA: nil)
        
        // Assert - Multiple achievements should be unlocked
        assertAchievementUnlocked(id: "session_starter") // First session
        assertAchievementUnlocked(id: "marathon") // 16 minute session
        assertAchievementUnlocked(id: "perfect_round") // At least one perfect round
        assertAchievementUnlocked(id: "perfect_streak_5") // 5 successful rounds
        assertAchievementUnlocked(id: "flawless_session") // All rounds successful
        
        // Should have 5 newly unlocked achievements
        XCTAssertEqual(achievementManager.newlyUnlockedAchievements.count, 5)
    }

    func testAchievementsDoNotReUnlock() {
        // Arrange - Unlock an achievement
        achievementManager.recordTutorialCompletion()
        assertAchievementUnlocked(id: "first_steps")
        XCTAssertEqual(achievementManager.newlyUnlockedAchievements.count, 1)
        
        // Act - Clear newly unlocked and try to unlock again
        achievementManager.clearNewlyUnlockedAchievements()
        achievementManager.recordTutorialCompletion()
        
        // Assert - Should remain unlocked but not be in newly unlocked list
        assertAchievementUnlocked(id: "first_steps", expectInNewlyUnlocked: false)
        XCTAssertEqual(achievementManager.newlyUnlockedAchievements.count, 0, "Already unlocked achievements should not be added to the newly unlocked list again.")
    }
    
    func testAchievementDoesNotUnlockPrematurely() {
        // Test Marathon threshold (15 minutes)
        achievementManager.endSession(duration: 14 * 60 + 59, preSessionEMA: nil, postSessionEMA: nil) // 14:59
        assertAchievementLocked(id: "marathon")
        
        // Test Super Marathon threshold (25 minutes)
        achievementManager.endSession(duration: 24 * 60 + 59, preSessionEMA: nil, postSessionEMA: nil) // 24:59
        assertAchievementLocked(id: "super_marathon")
        
        // Test insufficient stress reduction for Resilient Rebound
        let preEMA = EMAResponse(stressLevel: 60, calmJitteryLevel: 60, completionTime: 30, emaType: .preSession)
        let postEMA = EMAResponse(stressLevel: 45, calmJitteryLevel: 46, completionTime: 30, emaType: .postSession) // 15 & 14 point reductions
        achievementManager.endSession(duration: 300, preSessionEMA: preEMA, postSessionEMA: postEMA)
        assertAchievementLocked(id: "resilient_rebound")
    }
    
    func testResetAchievements() {
        // Arrange - Unlock some achievements
        achievementManager.recordTutorialCompletion()
        achievementManager.endSession(duration: 300, preSessionEMA: nil, postSessionEMA: nil)
        XCTAssertEqual(achievementManager.getUnlockedAchievementsCount(), 2)
        
        // Verify some UserDefaults were set
        XCTAssertEqual(testUserDefaults.integer(forKey: "com.kb2.sessionCount"), 1)
        
        // Act
        achievementManager.resetAchievements()
        
        // Assert
        XCTAssertEqual(achievementManager.getUnlockedAchievementsCount(), 0, "All achievements should be locked after reset.")
        XCTAssertEqual(achievementManager.newlyUnlockedAchievements.count, 0, "Newly unlocked achievements should be cleared.")
        assertAchievementLocked(id: "first_steps")
        assertAchievementLocked(id: "session_starter")
        
        // Verify UserDefaults were cleared
        XCTAssertEqual(testUserDefaults.integer(forKey: "com.kb2.sessionCount"), 0)
        XCTAssertNil(testUserDefaults.object(forKey: "com.kb2.lastSessionDate"))
        XCTAssertEqual(testUserDefaults.integer(forKey: "com.kb2.consecutiveDays"), 0)
    }
    
    func testAchievementPersistence() {
        // Arrange - Unlock an achievement
        achievementManager.recordTutorialCompletion()
        assertAchievementUnlocked(id: "first_steps")
        
        // Act - Simulate app restart by creating a new AchievementManager instance
        let newManager = AchievementManager.shared
        
        // Assert - Achievement should still be unlocked
        let achievement = newManager.achievements.first { $0.id == "first_steps" }
        XCTAssertTrue(achievement?.isUnlocked ?? false, "Achievement should persist across app launches")
        XCTAssertNotNil(achievement?.unlockedDate, "Unlocked date should be preserved")
    }
    
    func testGetAchievementsByCategory() {
        // Act
        let progressionAchievements = achievementManager.getAchievementsByCategory(.progression)
        let performanceAchievements = achievementManager.getAchievementsByCategory(.performance)
        let masteryAchievements = achievementManager.getAchievementsByCategory(.mastery)
        
        // Assert
        XCTAssertTrue(progressionAchievements.count > 0, "Should have progression achievements")
        XCTAssertTrue(performanceAchievements.count > 0, "Should have performance achievements")
        XCTAssertTrue(masteryAchievements.count > 0, "Should have mastery achievements")
        
        // Verify categories are correct
        XCTAssertTrue(progressionAchievements.allSatisfy { $0.category == .progression })
        XCTAssertTrue(performanceAchievements.allSatisfy { $0.category == .performance })
        XCTAssertTrue(masteryAchievements.allSatisfy { $0.category == .mastery })
    }
    
    func testGetProgressForCategory() {
        // Arrange - Unlock one achievement in progression category
        achievementManager.recordTutorialCompletion() // "first_steps" is progression
        
        // Act
        let progressionProgress = achievementManager.getProgressForCategory(.progression)
        let performanceProgress = achievementManager.getProgressForCategory(.performance)
        let masteryProgress = achievementManager.getProgressForCategory(.mastery)
        
        // Assert
        XCTAssertEqual(progressionProgress.unlocked, 1, "Should have 1 unlocked progression achievement")
        XCTAssertTrue(progressionProgress.total > 1, "Should have multiple progression achievements total")
        XCTAssertEqual(performanceProgress.unlocked, 0, "Should have 0 unlocked performance achievements")
        XCTAssertEqual(masteryProgress.unlocked, 0, "Should have 0 unlocked mastery achievements")
    }
}
