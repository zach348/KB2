// Copyright 2025 Training State, LLC. All rights reserved.
// KB2/SurveyWallView.swift
import SwiftUI

struct SurveyWallView: View {
    let onTakeSurvey: () -> Void
    let onSkip: () -> Void
    let skipsRemaining: Int
    
    // Define the primary brand color matching StartScreen
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark background to match the app theme
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Heading
                    Text("We're thrilled to see you keep coming back! Please fill out the beta feedback survey to continue using Kalibrate. After providing feedback, you will be provided with instructions to disable survey prompts.")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, geometry.size.height * 0.05)
                    
                    Spacer()
                    
                    // Branded Icon - Heart with star (enthusiastic user)
                    Image(systemName: "heart.fill")
                        .font(.system(size: geometry.size.height * 0.2625, weight: .light))
                        .foregroundColor(primaryColor)
                        .padding(.vertical, 20)
                    
                    Spacer()
                    
                    // Skip counter message (only show if skips remain)
                    if skipsRemaining > 0 {
                        Text("You can skip this \(skipsRemaining) more time\(skipsRemaining == 1 ? "" : "s").")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.bottom, 10)
                    }
                    
                    // Action buttons
                    VStack(spacing: 20) {
                        // Primary brand color button - "Let's do it!"
                        Button(action: onTakeSurvey) {
                            Text("Let's do it!")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black) // Dark text for contrast against mint green
                                .frame(maxWidth: .infinity)
                                .frame(height: 55)
                                .background(primaryColor)
                                .cornerRadius(15)
                        }
                        .padding(.horizontal, 40)
                        
                        // Gray button - "Not right now"
                        Button(action: onSkip) {
                            Text("Not right now")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 55)
                                .background(Color.gray)
                                .cornerRadius(15)
                        }
                        .padding(.horizontal, 40)
                    }
                    .padding(.bottom, geometry.size.height * 0.05)
                }
            }
        }
    }
}

// Preview for SwiftUI Canvas
struct SurveyWallView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SurveyWallView(
                onTakeSurvey: { print("User chose to take survey") },
                onSkip: { print("User chose to skip") },
                skipsRemaining: 2
            )
            .previewDisplayName("With Skips Remaining")
            
            SurveyWallView(
                onTakeSurvey: { print("User chose to take survey") },
                onSkip: { print("User chose to skip") },
                skipsRemaining: 0
            )
            .previewDisplayName("No Skips Remaining")
        }
    }
}
