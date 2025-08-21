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
    
    private func createPages(for sizeCategory: ContentSizeCategory, vSizeClass: UserInterfaceSizeClass?) -> [AttributedString] {
        let baseFont: Font = {
            if vSizeClass == .compact || sizeCategory.isAccessibilityCategory {
                return .title3.weight(.regular)
            } else {
                return .title2.weight(.regular)
            }
        }()
        
        let boldFont: Font = {
            if vSizeClass == .compact || sizeCategory.isAccessibilityCategory {
                return .title3.weight(.bold)
            } else {
                return .title2.weight(.bold)
            }
        }()
        
        var page1 = AttributedString("Welcome to Kalibrate. Quick spoiler: what you do affects how you feel — and how you feel affects what you're ready to do.")
        page1.font = baseFont
        if let range1 = page1.range(of: "what you do affects how you feel") {
            page1[range1].font = boldFont
        }
        if let range2 = page1.range(of: "how you feel affects what you're ready to do") {
            page1[range2].font = boldFont
        }
        
        var page2 = AttributedString("Kalibrate captures a stressed or anxious mind and guides it toward a calmer, more focused state.")
        page2.font = baseFont
        if let range1 = page2.range(of: "stressed or anxious mind") {
            page2[range1].font = boldFont
        }
        if let range2 = page2.range(of: "calmer, more focused state") {
            page2[range2].font = boldFont
        }
        
        var page3 = AttributedString("To do this, Kalibrate uses synchronized pulses of light, sound, and vibration to gently guide your brain's rhythm.")
        page3.font = baseFont
        if let range = page3.range(of: "light, sound, and vibration") {
            page3[range].font = boldFont
        }
        
        var page4 = AttributedString("Each session has two parts: a focus task to first engage and then settle your mind, followed by guided breathing to deepen your calm.")
        page4.font = baseFont
        if let range1 = page4.range(of: "focus task") {
            page4[range1].font = boldFont
        }
        if let range2 = page4.range(of: "guided breathing") {
            page4[range2].font = boldFont
        }
        
        var page5 = AttributedString("The focus task involves tracking targets. It starts off challenging, but stick with it—the goal is to prepare you for the breathing exercise.")
        page5.font = baseFont
        if let range = page5.range(of: "stick with it") {
            page5[range].font = boldFont
        }
        
        var page6 = AttributedString("Don't worry about your score. The real measure of success is completing the full session and noticing how you feel afterward.")
        page6.font = baseFont
        if let range1 = page6.range(of: "Don't worry about your score.") {
            page6[range1].font = boldFont
        }
        if let range2 = page6.range(of: "completing the full session") {
            page6[range2].font = boldFont
        }
        
        var page7 = AttributedString("Like any skill, the benefits of Kalibrate grow stronger with practice. Your first few sessions help you learn the experience—the real magic happens as it becomes familiar.")
        page7.font = baseFont
        if let range1 = page7.range(of: "benefits of Kalibrate grow stronger with practice") {
            page7[range1].font = boldFont
        }
        if let range2 = page7.range(of: "real magic happens as it becomes familiar") {
            page7[range2].font = boldFont
        }
        
        var page8 = AttributedString("A few minutes is all it takes to complete a session. Ready to begin?")
        page8.font = baseFont
        if let range = page8.range(of: "Ready to begin?") {
            page8[range].font = boldFont
        }
        
        return [page1, page2, page3, page4, page5, page6, page7, page8]
    }
    
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    
    private var horizontalPadding: CGFloat {
        hSizeClass == .compact ? 20 : 24
    }
    
    private var pages: [AttributedString] {
        createPages(for: sizeCategory, vSizeClass: vSizeClass)
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
