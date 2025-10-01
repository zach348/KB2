// Copyright 2025 Training State, LLC. All rights reserved.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
//  Achievement.swift
//  KB2
//
//  Created by Achievement System
//

import Foundation

// MARK: - Achievement Data Structure

struct Achievement: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let sfSymbolName: String
    let category: AchievementCategory
    var isUnlocked: Bool
    var unlockedDate: Date?
    
    // For multi-tier achievements (like Dedicated User or Perfect Streak)
    let tier: Int?
    let requiredValue: Int?
    
    init(id: String, title: String, description: String, sfSymbolName: String, category: AchievementCategory, tier: Int? = nil, requiredValue: Int? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.sfSymbolName = sfSymbolName
        self.category = category
        self.tier = tier
        self.requiredValue = requiredValue
        self.isUnlocked = false
        self.unlockedDate = nil
    }
}

// MARK: - Achievement Category

enum AchievementCategory: String, CaseIterable, Codable {
    case progression = "Progression & Consistency"
    case performance = "Performance & Skill"
    case mastery = "Mastery"
}

// MARK: - Achievement Definitions

extension Achievement {
    
    // MARK: - All Achievements
    static let allAchievements: [Achievement] = [
        // Progression & Consistency
        Achievement(
            id: "first_steps",
            title: "First Steps",
            description: "Complete the tutorial",
            sfSymbolName: "figure.walk.arrival",
            category: .progression
        ),
        
        Achievement(
            id: "session_starter",
            title: "Session Starter",
            description: "Complete your first session",
            sfSymbolName: "play.circle.fill",
            category: .progression
        ),
        
        Achievement(
            id: "dedicated_user_10",
            title: "Dedicated User",
            description: "Complete 10 sessions",
            sfSymbolName: "rosette",
            category: .progression,
            tier: 1,
            requiredValue: 10
        ),
        
        Achievement(
            id: "dedicated_user_50",
            title: "Super Dedicated",
            description: "Complete 50 sessions",
            sfSymbolName: "star.circle.fill",
            category: .progression,
            tier: 2,
            requiredValue: 50
        ),
        
        Achievement(
            id: "dedicated_user_100",
            title: "Elite User",
            description: "Complete 100 sessions",
            sfSymbolName: "crown.fill",
            category: .progression,
            tier: 3,
            requiredValue: 100
        ),
        
        Achievement(
            id: "daily_habit_3",
            title: "Getting Started",
            description: "Complete a session on 3 consecutive days",
            sfSymbolName: "flame.fill",
            category: .progression,
            tier: 1,
            requiredValue: 3
        ),
        
        Achievement(
            id: "daily_habit_7",
            title: "Week Warrior",
            description: "Complete a session on 7 consecutive days",
            sfSymbolName: "flame.fill",
            category: .progression,
            tier: 2,
            requiredValue: 7
        ),
        
        Achievement(
            id: "daily_habit_14",
            title: "Streak Master",
            description: "Complete a session on 14 consecutive days",
            sfSymbolName: "flame.fill",
            category: .progression,
            tier: 3,
            requiredValue: 14
        ),
        
        Achievement(
            id: "marathon",
            title: "Marathon",
            description: "Complete a session of 15 minutes or longer",
            sfSymbolName: "stopwatch.fill",
            category: .progression,
            tier: 1,
            requiredValue: 900
        ),
        
        Achievement(
            id: "super_marathon",
            title: "Super Marathon",
            description: "Complete a session of 25 minutes or longer",
            sfSymbolName: "timer",
            category: .progression,
            tier: 2,
            requiredValue: 1500
        ),
        
        // Performance & Skill (Focus Quality)
        Achievement(
            id: "perfect_round",
            title: "Perfect Round",
            description: "Achieve 100% focus quality in a single identification round",
            sfSymbolName: "checkmark.seal.fill",
            category: .performance
        ),
        
        Achievement(
            id: "perfect_streak_5",
            title: "Focus Streak",
            description: "Achieve 100% focus quality on 5 identification rounds in a row",
            sfSymbolName: "scope",
            category: .performance,
            tier: 1,
            requiredValue: 5
        ),
        
        Achievement(
            id: "perfect_streak_10",
            title: "Focus Master",
            description: "Achieve 100% focus quality on 10 identification rounds in a row",
            sfSymbolName: "target",
            category: .performance,
            tier: 2,
            requiredValue: 10
        ),
        
        Achievement(
            id: "perfect_streak_15",
            title: "Focus Prodigy",
            description: "Achieve 100% focus quality on 15 identification rounds in a row",
            sfSymbolName: "brain.head.profile",
            category: .performance,
            tier: 3,
            requiredValue: 15
        ),
        
        Achievement(
            id: "flawless_session",
            title: "Flawless Session",
            description: "Complete an entire session with 100% focus quality on all rounds",
            sfSymbolName: "star.fill",
            category: .performance
        ),
        
        // Mastery
        Achievement(
            id: "beginner_zen",
            title: "Beginner Zen",
            description: "Spend over 3 minutes in the breathing state during a single session",
            sfSymbolName: "lungs",
            category: .mastery,
            tier: 1,
            requiredValue: 180
        ),
        
        Achievement(
            id: "zen_apprentice",
            title: "Zen Apprentice",
            description: "Spend over 5 minutes in the breathing state during a single session",
            sfSymbolName: "lungs.fill",
            category: .mastery,
            tier: 2,
            requiredValue: 300
        ),
        
        Achievement(
            id: "zen_master",
            title: "Zen Master",
            description: "Spend over 7 minutes in the breathing state during a single session",
            sfSymbolName: "wind",
            category: .mastery,
            tier: 3,
            requiredValue: 420
        ),
        
        Achievement(
            id: "resilient_rebound",
            title: "Resilient Rebound",
            description: "Show significant stress reduction from pre to post session",
            sfSymbolName: "arrow.up.heart.fill",
            category: .mastery,
            tier: 1
        ),
        
        Achievement(
            id: "recovery_rockstar",
            title: "Recovery Rockstar",
            description: "Show exceptional stress reduction from pre to post session",
            sfSymbolName: "bolt.heart.fill",
            category: .mastery,
            tier: 2
        )
    ]
}
