// Copyright 2025 Training State, LLC. All rights reserved.
import SwiftUI

// Lightweight session summary for visualization
struct SessionSummary {
    let totalRounds: Int
    let correctRounds: Int
    let accuracy: Double // 0.0 - 1.0
    let avgReactionTime: TimeInterval? // optional
}

struct EMAScoreVisualizationView: View {
    let preEMA: EMAResponse?
    let postEMA: EMAResponse?
    let summary: SessionSummary
    let newlyUnlockedAchievements: [Achievement]
    let onDone: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.sizeCategory) private var sizeCategory
    
    // Brand Colors (matching other views)
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0) // #77FDC7
    private let secondaryColor = Color(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0) // #A09EA1
    private let darkColor = Color(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0) // #242424

    // Dynamic spacing that adapts for compact vs regular width and large text sizes
    private var sectionSpacing: CGFloat {
        if hSize == .compact || sizeCategory.isAccessibilityCategory { return 20 }
        return 28
    }

    var body: some View {
        ZStack {
            darkColor.ignoresSafeArea()

            VStack(spacing: sectionSpacing) {
                // Title
                Text("Session Summary")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 16)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                ScrollView {
                    VStack(alignment: .leading, spacing: sectionSpacing) {

                        // Section: How you felt
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How you felt")
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            MetricDeltaRow(
                                title: "Stress",
                                pre: preEMA?.stressLevel,
                                post: postEMA?.stressLevel,
                                improvementWhenDecreases: true,
                                preColor: .blue,
                                postColor: .green
                            )

                            MetricDeltaRow(
                                title: "Calm ↔ Jittery",
                                pre: preEMA?.calmJitteryLevel,
                                post: postEMA?.calmJitteryLevel,
                                improvementWhenDecreases: true,
                                preColor: .teal,
                                postColor: .green
                            )
                        }

                        // Section: How you performed
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How you performed")
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            AccuracyCard(accuracy: summary.accuracy,
                                         totalRounds: summary.totalRounds,
                                         correctRounds: summary.correctRounds,
                                         avgReactionTime: summary.avgReactionTime)
                        }

                        // Section: Achievements (only show if there are any)
                        if !newlyUnlockedAchievements.isEmpty {
                            AchievementBannerView(achievements: newlyUnlockedAchievements)
                        }

                        // Optional note if any EMA is missing
                        if preEMA == nil || postEMA == nil {
                            Text("Some EMA responses were not available.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100) // ensure content not hidden behind bottom button on small screens
                }

                // Done button moved to safeAreaInset(bottom:)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Done")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(darkColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background(primaryColor)
                    .cornerRadius(15)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Components

private struct MetricDeltaRow: View {
    let title: String
    let pre: Double?
    let post: Double?
    // true = lower is better; false = higher is better; nil = neutral (no green/red)
    let improvementWhenDecreases: Bool?
    let preColor: Color
    let postColor: Color

    var delta: Double? {
        guard let pre, let post else { return nil }
        return post - pre
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if let d = delta {
                    DeltaChip(delta: d, improvementWhenDecreases: improvementWhenDecreases)
                }
            }

            // Paired bars (0..100)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background rail
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.18))
                        .frame(height: 14)

                    // Pre bar
                    if let pre {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(preColor.opacity(0.8))
                            .frame(width: max(0, min(1, pre / 100.0)) * geo.size.width,
                                   height: 14)
                    }

                    // Post bar (overlay)
                    if let post {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(postColor)
                            .frame(width: max(0, min(1, post / 100.0)) * geo.size.width,
                                   height: 14)
                            .opacity(0.9)
                    }
                }
            }
            .frame(height: 14)

            // Value labels
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(preColor.opacity(0.8)).frame(width: 8, height: 8)
                    Text(preText)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(postColor).frame(width: 8, height: 8)
                    Text(postText)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var preText: String {
        if let pre {
            return "Pre: \(Int(pre))"
        } else {
            return "Pre: N/A"
        }
    }

    private var postText: String {
        if let post {
            return "Post: \(Int(post))"
        } else {
            return "Post: N/A"
        }
    }
}

private struct DeltaChip: View {
    let delta: Double
    let improvementWhenDecreases: Bool?

    var body: some View {
        let (label, bg, fg) = colorsAndLabel()
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(fg)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(bg)
            .cornerRadius(10)
    }

    private func colorsAndLabel() -> (String, Color, Color) {
        let sign = delta == 0 ? "" : (delta < 0 ? "−" : "+")
        let magnitude = Int(abs(delta).rounded())
        let label = "\(sign)\(magnitude)"

        // Neutral metric -> gray chip
        guard let improveWhenDown = improvementWhenDecreases else {
            return (label, Color(white: 0.25), .white)
        }

        // Improvement logic
        let isImprovement = (improveWhenDown && delta < 0) || (!improveWhenDown && delta > 0)
        let bg = isImprovement ? Color.green.opacity(0.3) : Color.red.opacity(0.3)
        let fg = isImprovement ? Color.green : Color.red
        return (label, bg, fg)
    }
}

private struct AccuracyCard: View {
    let accuracy: Double // 0..1
    let totalRounds: Int
    let correctRounds: Int
    let avgReactionTime: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Focus Quality")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int((accuracy * 100).rounded()))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(accuracyColor)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.18))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(accuracyColor)
                        .frame(width: max(0, min(1, accuracy)) * geo.size.width,
                               height: 14)
                }
            }
            .frame(height: 14)

            // Adaptive grid: wraps stats on narrow widths to avoid compression
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 8) {
                stat(label: "Rounds", value: "\(totalRounds)")
                stat(label: "Correct", value: "\(correctRounds)")
                if let rt = avgReactionTime {
                    stat(label: "Avg RT", value: String(format: "%.1fs", rt))
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12))
        .cornerRadius(12)
    }

    private var accuracyColor: Color {
        switch accuracy {
        case ..<0.34: return .red
        case ..<0.67: return .yellow
        default: return .green
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview

struct EMAScoreVisualizationView_Previews: PreviewProvider {
    static var previews: some View {
        let pre = EMAResponse(stressLevel: 62, calmJitteryLevel: 55, completionTime: 10, emaType: .preSession)
        let post = EMAResponse(stressLevel: 38, calmJitteryLevel: 30, completionTime: 8, emaType: .postSession)
        let summary = SessionSummary(totalRounds: 12, correctRounds: 8, accuracy: 8.0/12.0, avgReactionTime: 1.4)
        
        let sampleAchievements = [
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
            EMAScoreVisualizationView(preEMA: pre, postEMA: post, summary: summary, newlyUnlockedAchievements: sampleAchievements, onDone: {})
                .preferredColorScheme(.dark)
                .previewDisplayName("With Achievements")
            EMAScoreVisualizationView(preEMA: nil, postEMA: post, summary: summary, newlyUnlockedAchievements: [], onDone: {})
                .preferredColorScheme(.dark)
                .previewDisplayName("No Achievements")
        }
    }
}
