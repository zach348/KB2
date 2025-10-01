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
import SwiftUI

struct AchievementBannerView: View {
    let achievements: [Achievement]
    @State private var selectedAchievement: Achievement?
    
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.sizeCategory) private var sizeCategory
    
    // Brand Colors matching other views
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0) // #77FDC7
    private let goldColor = Color(red: 1.0, green: 0.84, blue: 0.0) // Gold for achievements
    
    // Dynamic sizing based on screen size and accessibility
    private var cardWidth: CGFloat {
        if hSize == .compact || sizeCategory.isAccessibilityCategory {
            return 140 // Narrower on small screens
        }
        return 160 // Wider on larger screens
    }
    
    private var cardHeight: CGFloat {
        if sizeCategory.isAccessibilityCategory {
            return 180 // Taller for large text
        }
        return 160
    }
    
    private var iconSize: CGFloat {
        if sizeCategory.isAccessibilityCategory {
            return 50 // Larger icons for accessibility
        } else if hSize == .compact {
            return 36 // Smaller on compact screens
        }
        return 44
    }
    
    private var titleFontSize: Font {
        if sizeCategory.isAccessibilityCategory {
            return .title3
        } else if hSize == .compact {
            return .caption
        }
        return .subheadline
    }
    
    private var descriptionFontSize: Font {
        if sizeCategory.isAccessibilityCategory {
            return .body
        }
        return .caption2
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(goldColor)
                    .font(.title2)
                
                Text("Achievements Earned")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                // Achievement count badge
                Text("\(achievements.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(goldColor)
                    .cornerRadius(12)
            }
            
            // Scrollable achievement cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(achievements) { achievement in
                        Button(action: {
                            selectedAchievement = achievement
                        }) {
                            AchievementCard(
                                achievement: achievement,
                                width: cardWidth,
                                height: cardHeight,
                                iconSize: iconSize,
                                titleFont: titleFontSize,
                                descriptionFont: descriptionFontSize
                            )
                        }
                        .buttonStyle(PlainButtonStyle()) // Preserve the card's appearance
                    }
                }
                .padding(.horizontal, 4) // Small padding to ensure cards aren't clipped
                .padding(.vertical, 2)
            }
            .scrollContentBackground(.hidden) // Ensure transparent background
            .sheet(item: $selectedAchievement) { achievement in
                AchievementDetailView(achievement: achievement)
            }
        }
    }
}

private struct AchievementCard: View {
    let achievement: Achievement
    let width: CGFloat
    let height: CGFloat
    let iconSize: CGFloat
    let titleFont: Font
    let descriptionFont: Font
    
    private let goldColor = Color(red: 1.0, green: 0.84, blue: 0.0)
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0)
    
    var body: some View {
        VStack(spacing: 8) {
            // Achievement icon with glow effect
            ZStack {
                Circle()
                    .fill(goldColor.opacity(0.2))
                    .frame(width: iconSize + 16, height: iconSize + 16)
                
                Circle()
                    .stroke(goldColor, lineWidth: 2)
                    .frame(width: iconSize + 12, height: iconSize + 12)
                
                Image(systemName: achievement.sfSymbolName)
                    .font(.system(size: iconSize * 0.6, weight: .bold))
                    .foregroundColor(goldColor)
            }
            .shadow(color: goldColor.opacity(0.3), radius: 4, x: 0, y: 2)
            
            // Achievement title
            Text(achievement.title)
                .font(titleFont)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            // Achievement description
            Text(achievement.description)
                .font(descriptionFont)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
            
            Spacer()
            
            // Category badge
            Text(categoryDisplayName(achievement.category))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(primaryColor.opacity(0.8))
                .cornerRadius(8)
        }
        .padding(12)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(goldColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private func categoryDisplayName(_ category: AchievementCategory) -> String {
        switch category {
        case .progression:
            return "Progress"
        case .performance:
            return "Skill"
        case .mastery:
            return "Mastery"
        }
    }
}

// MARK: - Empty State

struct EmptyAchievementBannerView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy")
                .font(.title2)
                .foregroundColor(.gray)
            
            Text("No new achievements this session")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Text("Keep training to unlock badges!")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

struct AchievementBannerView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleAchievements = [
            Achievement(
                id: "first_steps",
                title: "First Steps",
                description: "Complete the tutorial",
                sfSymbolName: "figure.walk.arrival",
                category: .progression
            ),
            Achievement(
                id: "perfect_round",
                title: "Perfect Round",
                description: "Achieve 100% focus quality in a single round",
                sfSymbolName: "checkmark.seal.fill",
                category: .performance
            ),
            Achievement(
                id: "zen_master",
                title: "Zen Master",
                description: "Spend over 4 minutes in breathing state",
                sfSymbolName: "lungs.fill",
                category: .mastery
            )
        ]
        
        return Group {
            // With achievements
            VStack {
                AchievementBannerView(achievements: sampleAchievements)
                Spacer()
            }
            .padding()
            .background(Color(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0))
            .preferredColorScheme(.dark)
            .previewDisplayName("With Achievements")
            
            // Empty state
            VStack {
                EmptyAchievementBannerView()
                Spacer()
            }
            .padding()
            .background(Color(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0))
            .preferredColorScheme(.dark)
            .previewDisplayName("Empty State")
            
            // Compact width
            VStack {
                AchievementBannerView(achievements: Array(sampleAchievements.prefix(2)))
                Spacer()
            }
            .padding()
            .background(Color(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0))
            .preferredColorScheme(.dark)
            .previewDevice("iPhone SE (3rd generation)")
            .previewDisplayName("Compact Width")
        }
    }
}
