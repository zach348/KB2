// KB2/OnboardingView.swift
import SwiftUI
import UIKit

struct OnboardingView: View {
    let onFinish: () -> Void
    
    @State private var index: Int = 0
    
    // Brand Colors (matching PaywallViewController and StartScreen)
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0) // #77FDC7
    private let secondaryColor = Color(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0) // #A09EA1
    private let darkColor = Color(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0) // #242424
    
    private let pages: [String] = [
        "Welcome to Kalibrate. Quick spoiler: what you do affects how you feel — and how you feel affects what you’re ready to do.",
        "Kalibrate captures a stressed or anxious mind and guides it toward a calmer, more focused state.",
        "Using attention neuroscience, Kalibrate helps you settle and focus by changing what your brain is asked to do over a short session.",
        "All that’s required is a few minutes of focused play. Try it as a warm-up before meditation — or anytime you want to reset."
    ]
    
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    
    private var horizontalPadding: CGFloat {
        hSizeClass == .compact ? 20 : 24
    }
    
    private var contentFont: Font {
        if vSizeClass == .compact || sizeCategory.isAccessibilityCategory {
            return .title3.weight(.semibold)
        } else {
            return .title2.weight(.semibold)
        }
    }
    
    var body: some View {
        ZStack {
            darkColor.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 24) {
                // Top bar: progress
                HStack {
                    Spacer()
                    Text("\(index + 1) / \(pages.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(secondaryColor)
                        .monospacedDigit()
                }
                .padding(.top, 16)
                
                // Content
                ScrollView {
                    Text(pages[index])
                        .font(contentFont)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .animation(.easeInOut(duration: 0.2), value: index)
                }
                
                // Primary action using brand colors
                Button(action: advance) {
                    Text(index == pages.count - 1 ? "Start" : "Next")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primaryColor)
                        .foregroundColor(darkColor)
                        .cornerRadius(14)
                }
                .accessibilityIdentifier("onboarding_primary_button")
                .padding(.bottom, 24)
            }
            .padding(.horizontal, horizontalPadding)
        }
        .preferredColorScheme(.dark)
    }
    
    private func advance() {
        if index < pages.count - 1 {
            withOptionalAnimation {
                index += 1
            }
        } else {
            onFinish()
        }
    }
    
    private func withOptionalAnimation(_ action: () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            action()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        }
    }
}

// Preview for development
#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView { }
            .previewDevice("iPhone 16")
    }
}
#endif
