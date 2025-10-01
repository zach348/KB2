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
// KB2/OnboardingView.swift
import SwiftUI
import UIKit

struct OnboardingView: View {
    let onFinish: () -> Void
    
    @State private var index: Int = 0
    @State private var contentOpacity: Double = 0.0
    
    // Brand Colors (matching PaywallViewController and StartScreen)
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0) // #77FDC7
    private let secondaryColor = Color(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0) // #A09EA1
    private let darkColor = Color(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0) // #242424
    
    private func createPages(for sizeCategory: ContentSizeCategory, vSizeClass: UserInterfaceSizeClass?) -> [(text: AttributedString, icon: String)] {
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
        
        // Beta Page
        var betaPage = AttributedString("Greetings! Thank you for beta testing Kalibrate! Note that the trial limitation is diabled in this version. After you complete your second session, you'll be prompted to take a brief survey. We'd be grateful if you could take a moment to share your thoughts  - your feedback will directly shape the future of Kalibrate.")
        betaPage.font = baseFont
        if let range1 = betaPage.range(of: "Thank you for beta testing Kalibrate!") {
            betaPage[range1].font = boldFont
        }

        // Page 1
        var page1 = AttributedString("Welcome to Kalibrate! Here's a cool secret: what you do changes how you feel. And how you feel changes what you're ready to do.")
        page1.font = baseFont
        if let range1 = page1.range(of: "what you do changes how you feel") {
            page1[range1].font = boldFont
        }
        if let range2 = page1.range(of: "how you feel changes what you're ready to do") {
            page1[range2].font = boldFont
        }
        
        // Page 2
        var page2 = AttributedString("Feeling stressed or unfocused? Kalibrate helps guide your mind to a calmer, clearer place.")
        page2.font = baseFont
        if let range1 = page2.range(of: "stressed or unfocused") {
            page2[range1].font = boldFont
        }
        if let range2 = page2.range(of: "calmer, clearer place") {
            page2[range2].font = boldFont
        }
        
        // Page 3
        var page3 = AttributedString("We use pulses of light, sound, and vibration to help you focus and then relax. For the best experience, try using headphones.")
        page3.font = baseFont
        if let range1 = page3.range(of: "pulses of light, sound, and vibration") {
            page3[range1].font = boldFont
        }
        if let range2 = page3.range(of: "try using headphones") {
            page3[range2].font = boldFont
        }
        
        // Page 4
        var page4 = AttributedString("Each session has two parts: a fun focus game to settle your mind, followed by simple breathing exercises to deepen your calm.")
        page4.font = baseFont
        if let range1 = page4.range(of: "focus game") {
            page4[range1].font = boldFont
        }
        if let range2 = page4.range(of: "breathing exercises") {
            page4[range2].font = boldFont
        }
        
        // Page 5
        var page5 = AttributedString("Your score isn't what's important—it's all about how you feel, and your focus quality will get better with practice. Just follow along and have fun. Ready to start?")
        page5.font = baseFont
        if let range1 = page5.range(of: "Your score isn't what's important") {
            page5[range1].font = boldFont
        }
        if let range2 = page5.range(of: "Ready to start?") {
            page5[range2].font = boldFont
        }
        
        return [
            (text: betaPage, icon: "ladybug.fill"),
            (text: page1, icon: "hand.wave.fill"),
            (text: page2, icon: "brain.head.profile"),
            (text: page3, icon: "headphones"),
            (text: page4, icon: "gamecontroller.fill"),
            (text: page5, icon: "face.smiling")
        ]
    }
    
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    
    private var horizontalPadding: CGFloat {
        hSizeClass == .compact ? 20 : 24
    }
    
    private var pages: [(text: AttributedString, icon: String)] {
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
                    VStack(spacing: 24) {
                        // Icon
                        Image(systemName: pages[index].icon)
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(primaryColor)
                            .frame(height: 80)
                            .opacity(contentOpacity)
                            .scaleEffect(contentOpacity)
                        
                        // Text content
                        Text(pages[index].text)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(contentOpacity)
                    }
                    .padding(.top, 8)
                }
                .onAppear {
                    withOptionalAnimation {
                        contentOpacity = 1.0
                    }
                }
                .onChange(of: index) { _ in
                    contentOpacity = 0.0
                    withAnimation(.easeInOut(duration: 0.4).delay(0.1)) {
                        contentOpacity = 1.0
                    }
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
