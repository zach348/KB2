//
//  AchievementDetailView.swift
//  KB2
//
//  Created by Achievement System
//

import SwiftUI

struct AchievementDetailView: View {
    let achievement: Achievement
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.sizeCategory) private var sizeCategory
    
    // Responsive sizing
    private var iconSize: CGFloat {
        if sizeCategory.isAccessibilityCategory {
            return 120
        } else if hSize == .compact {
            return 70
        }
        return 90
    }
    
    private var titleFont: Font {
        if sizeCategory.isAccessibilityCategory {
            return .title
        } else if hSize == .compact {
            return .title2
        }
        return .largeTitle
    }
    
    private var horizontalPadding: CGFloat {
        if hSize == .compact {
            return 16
        }
        return 30
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 25) {
                    // Large achievement icon
                    Image(systemName: achievement.sfSymbolName)
                        .font(.system(size: iconSize))
                        .foregroundColor(achievement.isUnlocked ? .yellow : .gray)
                        .padding(.top, 20)
                        .scaleEffect(achievement.isUnlocked ? 1.0 : 0.8)
                        .animation(.easeInOut(duration: 0.3), value: achievement.isUnlocked)
                    
                    // Achievement title
                    Text(achievement.title)
                        .font(titleFont)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .padding(.horizontal, horizontalPadding)
                        .minimumScaleFactor(0.8)
                    
                    // Category badge
                    Text(achievement.category.rawValue)
                        .font(sizeCategory.isAccessibilityCategory ? .body : .caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, hSize == .compact ? 10 : 12)
                        .padding(.vertical, hSize == .compact ? 4 : 6)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(12)
                        .foregroundColor(.secondary)
                    
                    // Achievement description
                    Text(achievement.description)
                        .font(sizeCategory.isAccessibilityCategory ? .title3 : .body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, horizontalPadding)
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Unlock status
                    VStack(spacing: 12) {
                        if achievement.isUnlocked {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Unlocked")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                            .font(sizeCategory.isAccessibilityCategory ? .title2 : .title3)
                            
                            if let date = achievement.unlockedDate {
                                Text("Achieved on \(date, formatter: itemFormatter)")
                                    .font(sizeCategory.isAccessibilityCategory ? .body : .caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, horizontalPadding)
                            }
                        } else {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.gray)
                                Text("Not Yet Unlocked")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gray)
                            }
                            .font(sizeCategory.isAccessibilityCategory ? .title2 : .title3)
                        }
                    }
                    .padding(.top, 10)
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Ensures proper display on all devices
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .short
    return formatter
}()

#Preview {
    AchievementDetailView(achievement: Achievement.allAchievements[0])
}
