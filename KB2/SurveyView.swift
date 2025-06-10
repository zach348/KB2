import SwiftUI
import UIKit

struct SurveyView: View {
    let onConfirm: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        ZStack {
            // Dark background to match the app theme
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                // Heading
                Text("We'd love to know what you think! Would you help Kalibrate improve by filling out a short survey?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                
                Spacer()
                
                // Blue button - "I'll help!"
                Button(action: onConfirm) {
                    Text("I'll help!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color.blue)
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
                .padding(.bottom, 30)
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
