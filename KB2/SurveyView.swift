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
import UIKit

struct SurveyView: View {
    let onConfirm: () -> Void
    let onDecline: () -> Void
    
    // Define the primary brand color matching StartScreen
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark background to match the app theme
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Heading
                    Text("We'd love to know what you think! Would you help Kalibrate improve by filling out a short survey?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, geometry.size.height * 0.05)
                    
                    Spacer()
                    
                    // Branded Icon - Survey clipboard graphic
                    Image(systemName: "list.clipboard")
                        .font(.system(size: geometry.size.height * 0.2625, weight: .light))
                        .foregroundColor(primaryColor)
                        .padding(.vertical, 20)
                    
                    Spacer()
                    
                    // Action buttons
                    VStack(spacing: 20) {
                        // Primary brand color button - "I'll help!"
                        Button(action: onConfirm) {
                            Text("I'll help!")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black) // Dark text for contrast against mint green
                                .frame(maxWidth: .infinity)
                                .frame(height: 55)
                                .background(primaryColor)
                                .cornerRadius(15)
                        }
                        .padding(.horizontal, 40)
                        
                        // Gray button - "No thanks"
                        Button(action: onDecline) {
                            Text("No thanks.")
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
struct SurveyView_Previews: PreviewProvider {
    static var previews: some View {
        SurveyView(
            onConfirm: { print("User confirmed") },
            onDecline: { print("User declined") }
        )
    }
}
