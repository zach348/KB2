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
// KB2/SecondSessionPromptView.swift
import SwiftUI

struct SecondSessionPromptView: View {
    let onContinue: () -> Void

    // Brand colors for consistency
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0)
    private let darkColor = Color(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0)

    var body: some View {
        ZStack {
            darkColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "hand.wave.fill")
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(primaryColor)
                            .frame(height: 80)

                        Text("Welcome back!")
                            .font(.title.weight(.bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Complete this session to unlock the feedback survey and share your insights.")
                            .font(.title3.weight(.regular))
                            .foregroundColor(.white)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primaryColor)
                        .foregroundColor(darkColor)
                        .cornerRadius(14)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }
}

// Preview for development
#if DEBUG
struct SecondSessionPromptView_Previews: PreviewProvider {
    static var previews: some View {
        SecondSessionPromptView { }
            .previewDevice("iPhone 16")
    }
}
#endif
