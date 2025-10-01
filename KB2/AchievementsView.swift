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
//  AchievementsView.swift
//  KB2
//
//  Created by Achievement System
//

import SwiftUI

struct AchievementsView: View {
    @ObservedObject private var achievementManager = AchievementManager.shared
    @State private var selectedAchievement: Achievement?
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.sizeCategory) private var sizeCategory
    
    // Responsive sizing
    private var progressSectionPadding: CGFloat {
        if hSize == .compact {
            return 6
        }
        return 8
    }
    
    private var iconFont: Font {
        if sizeCategory.isAccessibilityCategory {
            return .title
        } else if hSize == .compact {
            return .title3
        }
        return .title2
    }
    
    private var headlineFont: Font {
        if sizeCategory.isAccessibilityCategory {
            return .title2
        } else if hSize == .compact {
            return .subheadline
        }
        return .headline
    }
    
    private var percentageFont: Font {
        if sizeCategory.isAccessibilityCategory {
            return .title
        } else if hSize == .compact {
            return .title3
        }
        return .title2
    }
    
    var body: some View {
        NavigationView {
            List {
                // Overall progress section
                Section {
                    VStack(spacing: hSize == .compact ? 10 : 12) {
                        let progress = achievementManager.getUnlockedAchievementsCount()
                        let total = achievementManager.getTotalAchievementsCount()
                        
                        HStack(alignment: .center, spacing: hSize == .compact ? 8 : 12) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.yellow)
                                .font(iconFont)
                                .frame(width: hSize == .compact ? 20 : 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Overall Progress")
                                    .font(headlineFont)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(progress) of \(total) achievements unlocked")
                                    .font(sizeCategory.isAccessibilityCategory ? .body : .caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Spacer(minLength: 4)
                            
                            Text("\(Int((Double(progress) / Double(total)) * 100))%")
                                .font(percentageFont)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .minimumScaleFactor(0.8)
                        }
                        
                        ProgressView(value: Double(progress), total: Double(total))
                            .tint(.yellow)
                            .scaleEffect(hSize == .compact ? 0.9 : 1.0)
                    }
                    .padding(.vertical, progressSectionPadding)
                }
                
                // Achievement categories
                ForEach(AchievementCategory.allCases, id: \.self) { category in
                    Section(header: categoryHeader(for: category)) {
                        let achievements = achievementManager.getAchievementsByCategory(category)
                        ForEach(achievements) { achievement in
                            AchievementRow(achievement: achievement)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAchievement = achievement
                                }
                        }
                    }
                }
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .sheet(item: $selectedAchievement) { achievement in
                AchievementDetailView(achievement: achievement)
            }
        }
    }
    
    @ViewBuilder
    private func categoryHeader(for category: AchievementCategory) -> some View {
        HStack {
            Text(category.rawValue)
            Spacer()
            let progress = achievementManager.getProgressForCategory(category)
            Text("\(progress.unlocked)/\(progress.total)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct AchievementRow: View {
    let achievement: Achievement
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.sizeCategory) private var sizeCategory
    
    // Responsive sizing
    private var iconSize: CGFloat {
        if sizeCategory.isAccessibilityCategory {
            return 50
        } else if hSize == .compact {
            return 35
        }
        return 40
    }
    
    private var spacing: CGFloat {
        if hSize == .compact {
            return 12
        }
        return 16
    }
    
    private var titleFont: Font {
        if sizeCategory.isAccessibilityCategory {
            return .title3
        } else if hSize == .compact {
            return .subheadline
        }
        return .headline
    }
    
    private var descriptionFont: Font {
        if sizeCategory.isAccessibilityCategory {
            return .body
        } else if hSize == .compact {
            return .footnote
        }
        return .subheadline
    }
    
    private var statusIconFont: Font {
        if sizeCategory.isAccessibilityCategory {
            return .title2
        } else if hSize == .compact {
            return .body
        }
        return .title3
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            // Achievement icon
            Image(systemName: achievement.sfSymbolName)
                .font(.system(size: iconSize * 0.6))
                .foregroundColor(achievement.isUnlocked ? .yellow : .gray)
                .frame(width: iconSize, height: iconSize)
                .background(
                    Circle()
                        .fill(achievement.isUnlocked ? .yellow.opacity(0.1) : .gray.opacity(0.1))
                )
                .scaleEffect(achievement.isUnlocked ? 1.0 : 0.9)
            
            // Achievement info
            VStack(alignment: .leading, spacing: hSize == .compact ? 2 : 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(achievement.title)
                        .font(titleFont)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                    
                    if let tier = achievement.tier {
                        Text("Tier \(tier)")
                            .font(sizeCategory.isAccessibilityCategory ? .caption : .caption2)
                            .padding(.horizontal, hSize == .compact ? 4 : 6)
                            .padding(.vertical, hSize == .compact ? 1 : 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                            .fixedSize()
                    }
                }
                
                Text(achievement.description)
                    .font(descriptionFont)
                    .foregroundColor(.secondary)
                    .lineLimit(sizeCategory.isAccessibilityCategory ? 4 : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 4)
            
            // Status indicator
            VStack(spacing: 4) {
                if achievement.isUnlocked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(statusIconFont)
                    
                    if let date = achievement.unlockedDate, !sizeCategory.isAccessibilityCategory {
                        Text(date, style: .date)
                            .font(hSize == .compact ? .caption2 : .caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .font(statusIconFont)
                }
            }
            .frame(minWidth: hSize == .compact ? 30 : 40)
        }
        .padding(.vertical, hSize == .compact ? 6 : 8)
        .opacity(achievement.isUnlocked ? 1.0 : 0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title), \(achievement.description), \(achievement.isUnlocked ? "Unlocked" : "Locked")")
    }
}

#Preview {
    AchievementsView()
}
