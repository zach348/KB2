// Copyright 2025 Training State, LLC. All rights reserved.
//
//  AchievementManager.swift
//  KB2
//
//  Created by Achievement System
//

import Foundation
import QuartzCore

// MARK: - Achievement Manager

class AchievementManager: ObservableObject {
    
    // MARK: - Singleton
    static var shared = AchievementManager()
    
    // MARK: - Published Properties
    @Published var achievements: [Achievement] = []
    @Published var newlyUnlockedAchievements: [Achievement] = []
    
    // MARK: - Dependencies
    private let userDefaults: UserDefaults
    private let timeProvider: TimeProvider
    
    // MARK: - UserDefaults Keys
    private let achievementsKey = "com.kb2.achievements"
    private let sessionCountKey = "com.kb2.sessionCount"
    private let consecutiveDaysKey = "com.kb2.consecutiveDays"
    private let lastSessionDateKey = "com.kb2.lastSessionDate"
    
    // MARK: - Session Tracking Properties
    private var currentSessionPerfectStreakCount = 0
    private var currentSessionTotalRounds = 0
    private var currentSessionSuccessfulRounds = 0
    private var currentSessionBreathingTime: TimeInterval = 0
    private var breathingStartTime: TimeInterval?
    
    // MARK: - Notification Names
    static let achievementUnlockedNotification = Notification.Name("AchievementUnlocked")
    
    // MARK: - Initialization
    init(userDefaults: UserDefaults = .standard, timeProvider: TimeProvider = SystemTimeProvider()) {
        self.userDefaults = userDefaults
        self.timeProvider = timeProvider
        loadAchievements()
    }
    
    // MARK: - Achievement Loading/Saving
    
    private func loadAchievements() {
        if let data = userDefaults.data(forKey: achievementsKey),
           let savedAchievements = try? JSONDecoder().decode([Achievement].self, from: data) {
            // Create a dictionary of saved achievements for quick lookup
            let savedDict = Dictionary(uniqueKeysWithValues: savedAchievements.map { ($0.id, $0) })
            
            // Update the master list with saved states
            achievements = Achievement.allAchievements.map { achievement in
                var updatedAchievement = achievement
                if let savedAchievement = savedDict[achievement.id] {
                    updatedAchievement.isUnlocked = savedAchievement.isUnlocked
                    updatedAchievement.unlockedDate = savedAchievement.unlockedDate
                }
                return updatedAchievement
            }
        } else {
            // First time setup
            achievements = Achievement.allAchievements
        }
    }
    
    private func saveAchievements() {
        if let data = try? JSONEncoder().encode(achievements) {
            userDefaults.set(data, forKey: achievementsKey)
        }
    }
    
    // MARK: - Achievement Unlocking
    
    private func unlockAchievement(withId id: String) {
        guard let index = achievements.firstIndex(where: { $0.id == id }),
              !achievements[index].isUnlocked else {
            return // Already unlocked
        }
        
        achievements[index].isUnlocked = true
        achievements[index].unlockedDate = Date()
        
        // Track newly unlocked achievement for post-session display
        newlyUnlockedAchievements.append(achievements[index])
        
        // Save to persistence
        saveAchievements()
        
        // Post notification
        NotificationCenter.default.post(
            name: Self.achievementUnlockedNotification,
            object: achievements[index]
        )
        
        print("🏆 Achievement Unlocked: \(achievements[index].title)")
    }
    
    // MARK: - Session Management
    
    func startSession() {
        // Reset session tracking
        currentSessionPerfectStreakCount = 0
        currentSessionTotalRounds = 0
        currentSessionSuccessfulRounds = 0
        currentSessionBreathingTime = 0
        breathingStartTime = nil
        newlyUnlockedAchievements.removeAll()
    }
    
    func endSession(duration: TimeInterval, preSessionEMA: EMAResponse?, postSessionEMA: EMAResponse?) {
        // Update session count
        let currentCount = userDefaults.integer(forKey: sessionCountKey)
        let newCount = currentCount + 1
        userDefaults.set(newCount, forKey: sessionCountKey)
        
        // Check progression achievements
        checkProgressionAchievements(sessionCount: newCount, sessionDuration: duration)
        
        // Check daily habit achievements
        checkDailyHabitAchievements()
        
        // Check performance achievements (session level)
        checkSessionPerformanceAchievements()
        
        // Check mastery achievements
        checkMasteryAchievements(preSessionEMA: preSessionEMA, postSessionEMA: postSessionEMA)
        
        print("AchievementManager: Session completed - \(newlyUnlockedAchievements.count) new achievements unlocked")
    }
    
    // MARK: - Individual Achievement Checks
    
    private func checkProgressionAchievements(sessionCount: Int, sessionDuration: TimeInterval) {
        // Session Starter
        if sessionCount == 1 {
            unlockAchievement(withId: "session_starter")
        }
        
        // Dedicated User tiers
        if sessionCount >= 10 {
            unlockAchievement(withId: "dedicated_user_10")
        }
        if sessionCount >= 50 {
            unlockAchievement(withId: "dedicated_user_50")
        }
        if sessionCount >= 100 {
            unlockAchievement(withId: "dedicated_user_100")
        }
        
        // Marathon achievements
        let durationMinutes = sessionDuration / 60.0
        if durationMinutes >= 15.0 {
            unlockAchievement(withId: "marathon")
        }
        if durationMinutes >= 25.0 {
            unlockAchievement(withId: "super_marathon")
        }
    }
    
    private func checkDailyHabitAchievements() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastSessionDate = userDefaults.object(forKey: lastSessionDateKey) as? Date
        let lastSessionDayStart = lastSessionDate.map { Calendar.current.startOfDay(for: $0) }
        
        var consecutiveDays = userDefaults.integer(forKey: consecutiveDaysKey)
        
        if let lastSessionDayStart = lastSessionDayStart {
            let daysDifference = Calendar.current.dateComponents([.day], from: lastSessionDayStart, to: today).day ?? 0
            
            if daysDifference == 1 {
                // Consecutive day
                consecutiveDays += 1
            } else if daysDifference == 0 {
                // Same day, don't increment
            } else {
                // Streak broken
                consecutiveDays = 1
            }
        } else {
            // First session ever
            consecutiveDays = 1
        }
        
        // Save updated values
        userDefaults.set(consecutiveDays, forKey: consecutiveDaysKey)
        userDefaults.set(Date(), forKey: lastSessionDateKey)
        
        // Check achievements
        if consecutiveDays >= 3 {
            unlockAchievement(withId: "daily_habit_3")
        }
        if consecutiveDays >= 7 {
            unlockAchievement(withId: "daily_habit_7")
        }
        if consecutiveDays >= 14 {
            unlockAchievement(withId: "daily_habit_14")
        }
    }
    
    private func checkSessionPerformanceAchievements() {
        // Flawless Session - all rounds successful (only if there were actually rounds played)
        if currentSessionTotalRounds > 0 && currentSessionSuccessfulRounds == currentSessionTotalRounds {
            unlockAchievement(withId: "flawless_session")
        }
        
        // Perfect Streak achievements
        if currentSessionPerfectStreakCount >= 5 {
            unlockAchievement(withId: "perfect_streak_5")
        }
        if currentSessionPerfectStreakCount >= 10 {
            unlockAchievement(withId: "perfect_streak_10")
        }
        if currentSessionPerfectStreakCount >= 15 {
            unlockAchievement(withId: "perfect_streak_15")
        }
    }
    
    private func checkMasteryAchievements(preSessionEMA: EMAResponse?, postSessionEMA: EMAResponse?) {
        // Breathing achievements - 3 tiers
        if currentSessionBreathingTime >= 180.0 { // 3 minutes
            unlockAchievement(withId: "beginner_zen")
        }
        if currentSessionBreathingTime >= 300.0 { // 5 minutes
            unlockAchievement(withId: "zen_apprentice")
        }
        if currentSessionBreathingTime >= 420.0 { // 7 minutes
            unlockAchievement(withId: "zen_master")
        }
        
        // EMA recovery achievements - 2 tiers
        if let preEMA = preSessionEMA,
           let postEMA = postSessionEMA {
            let stressReduction = preEMA.stressLevel - postEMA.stressLevel
            let jitteryReduction = preEMA.calmJitteryLevel - postEMA.calmJitteryLevel
            
            // Resilient Rebound (Tier 1): at least 20 points on either scale, or 15 points on both
            if stressReduction >= 20.0 || jitteryReduction >= 20.0 || 
               (stressReduction >= 15.0 && jitteryReduction >= 15.0) {
                unlockAchievement(withId: "resilient_rebound")
            }
            
            // Recovery Rockstar (Tier 2): at least 35 points on either scale, or 25 points on both
            if stressReduction >= 35.0 || jitteryReduction >= 35.0 || 
               (stressReduction >= 25.0 && jitteryReduction >= 25.0) {
                unlockAchievement(withId: "recovery_rockstar")
            }
        }
    }
    
    // MARK: - Event Tracking Methods (called by GameScene)
    
    func recordTutorialCompletion() {
        unlockAchievement(withId: "first_steps")
    }
    
    func recordIdentificationRoundStart() {
        currentSessionTotalRounds += 1
    }
    
    func recordIdentificationRoundEnd(success: Bool) {
        if success {
            currentSessionSuccessfulRounds += 1
            currentSessionPerfectStreakCount += 1
            
            // Check for Perfect Round achievement
            unlockAchievement(withId: "perfect_round")
            
            // Check streak achievements during session
            if currentSessionPerfectStreakCount >= 5 {
                unlockAchievement(withId: "perfect_streak_5")
            }
            if currentSessionPerfectStreakCount >= 10 {
                unlockAchievement(withId: "perfect_streak_10")
            }
            if currentSessionPerfectStreakCount >= 15 {
                unlockAchievement(withId: "perfect_streak_15")
            }
        } else {
            // Streak broken
            currentSessionPerfectStreakCount = 0
        }
    }
    
    func recordBreathingStateEntered() {
        breathingStartTime = timeProvider.currentTime()
    }
    
    func recordBreathingStateExited() {
        if let startTime = breathingStartTime {
            let duration = timeProvider.currentTime() - startTime
            currentSessionBreathingTime += duration
            breathingStartTime = nil
        }
    }
    
    // MARK: - Utility Methods
    
    func getNewlyUnlockedAchievements() -> [Achievement] {
        return newlyUnlockedAchievements
    }
    
    func clearNewlyUnlockedAchievements() {
        newlyUnlockedAchievements.removeAll()
    }
    
    func getAchievementsByCategory(_ category: AchievementCategory) -> [Achievement] {
        return achievements.filter { $0.category == category }
    }
    
    func getUnlockedAchievementsCount() -> Int {
        return achievements.filter { $0.isUnlocked }.count
    }
    
    func getTotalAchievementsCount() -> Int {
        return achievements.count
    }
    
    func getProgressForCategory(_ category: AchievementCategory) -> (unlocked: Int, total: Int) {
        let categoryAchievements = getAchievementsByCategory(category)
        let unlockedCount = categoryAchievements.filter { $0.isUnlocked }.count
        return (unlocked: unlockedCount, total: categoryAchievements.count)
    }
    
    // MARK: - Data Reset
    
    func resetAchievements() {
        // Reset all achievements to their initial state
        achievements = Achievement.allAchievements.map { achievement in
            var newAchievement = achievement
            newAchievement.isUnlocked = false
            newAchievement.unlockedDate = nil
            return newAchievement
        }
        
        // Clear related UserDefaults data
        userDefaults.removeObject(forKey: achievementsKey)
        userDefaults.removeObject(forKey: sessionCountKey)
        userDefaults.removeObject(forKey: consecutiveDaysKey)
        userDefaults.removeObject(forKey: lastSessionDateKey)
        
        // Clear newly unlocked achievements array
        newlyUnlockedAchievements.removeAll()
        
        // Reset session tracking properties
        currentSessionPerfectStreakCount = 0
        currentSessionTotalRounds = 0
        currentSessionSuccessfulRounds = 0
        currentSessionBreathingTime = 0
        breathingStartTime = nil
        
        // Save the cleared state
        saveAchievements()
        
        print("Achievements have been reset.")
    }
}
