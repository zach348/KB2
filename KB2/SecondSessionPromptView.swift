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
