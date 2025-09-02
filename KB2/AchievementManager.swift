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
    static let shared = AchievementManager()
    
    // MARK: - Published Properties
    @Published var achievements: [Achievement] = []
    @Published var newlyUnlockedAchievements: [Achievement] = []
    
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
    private init() {
        loadAchievements()
    }
    
    // MARK: - Achievement Loading/Saving
    
    private func loadAchievements() {
        if let data = UserDefaults.standard.data(forKey: achievementsKey),
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
            UserDefaults.standard.set(data, forKey: achievementsKey)
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
        let currentCount = UserDefaults.standard.integer(forKey: sessionCountKey)
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: sessionCountKey)
        
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
        let lastSessionDate = UserDefaults.standard.object(forKey: lastSessionDateKey) as? Date
        let lastSessionDayStart = lastSessionDate.map { Calendar.current.startOfDay(for: $0) }
        
        var consecutiveDays = UserDefaults.standard.integer(forKey: consecutiveDaysKey)
        
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
        UserDefaults.standard.set(consecutiveDays, forKey: consecutiveDaysKey)
        UserDefaults.standard.set(Date(), forKey: lastSessionDateKey)
        
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
    }
    
    private func checkMasteryAchievements(preSessionEMA: EMAResponse?, postSessionEMA: EMAResponse?) {
        // Zen Master - 4+ minutes in breathing state
        if currentSessionBreathingTime >= 240.0 { // 4 minutes
            unlockAchievement(withId: "zen_master")
        }
        
        // Comeback Kid - significant stress reduction
        if let preEMA = preSessionEMA,
           let postEMA = postSessionEMA {
            let stressReduction = preEMA.stressLevel - postEMA.stressLevel
            let jitteryReduction = preEMA.calmJitteryLevel - postEMA.calmJitteryLevel
            
            // Significant reduction: at least 20 points on either scale, or 15 points on both
            if stressReduction >= 20.0 || jitteryReduction >= 20.0 || 
               (stressReduction >= 15.0 && jitteryReduction >= 15.0) {
                unlockAchievement(withId: "comeback_kid")
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
        } else {
            // Streak broken
            currentSessionPerfectStreakCount = 0
        }
    }
    
    func recordBreathingStateEntered() {
        breathingStartTime = CACurrentMediaTime()
    }
    
    func recordBreathingStateExited() {
        if let startTime = breathingStartTime {
            let duration = CACurrentMediaTime() - startTime
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
        UserDefaults.standard.removeObject(forKey: achievementsKey)
        UserDefaults.standard.removeObject(forKey: sessionCountKey)
        UserDefaults.standard.removeObject(forKey: consecutiveDaysKey)
        UserDefaults.standard.removeObject(forKey: lastSessionDateKey)
        
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
