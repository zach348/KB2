import SwiftUI
import Foundation

enum EMAType: String, CaseIterable {
    case preSession = "pre_session"
    case postSession = "post_session"
    
    var title: String {
        switch self {
        case .preSession:
            return "How are you feeling right now?"
        case .postSession:
            return "How are you feeling after the session?"
        }
    }
    
    var buttonText: String {
        switch self {
        case .preSession:
            return "Start Session"
        case .postSession:
            return "Complete"
        }
    }
}

struct EMAView: View {
    let emaType: EMAType
    let onCompletion: (EMAResponse) -> Void
    
    @State private var stressLevel: Double = 50
    @State private var calmAgitationLevel: Double = 50
    @State private var energyLevel: Double = 50
    @State private var startTime: Date = Date()
    
    var body: some View {
        ZStack {
            // Dark background to match the app theme
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                // Title
                VStack {
                    Text(emaType.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true) // Allow text to wrap
                    
                    Text("(Your responses are anonymous)")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Stress Level VAS
                VStack(spacing: 15) {
                    Text("How stressed do you feel right now?")
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 8) {
                        Slider(value: $stressLevel, in: 0...100, step: 1)
                            .accentColor(.blue)
                        
                        HStack {
                            Text("Not Stressed at All")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("Extremely Stressed")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Text("\(Int(stressLevel))")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                
                // Calm/Agitation Level VAS
                VStack(spacing: 15) {
                    Text("How calm or agitated do you feel right now?")
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 8) {
                        Slider(value: $calmAgitationLevel, in: 0...100, step: 1)
                            .accentColor(.green)
                        
                        HStack {
                            Text("Very Calm")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("Very Agitated")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Text("\(Int(calmAgitationLevel))")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                
                // Energy Level VAS
                VStack(spacing: 15) {
                    Text("How energetic or drained do you feel right now?")
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 8) {
                        Slider(value: $energyLevel, in: 0...100, step: 1)
                            .accentColor(.orange)
                        
                        HStack {
                            Text("Drained / Lethargic")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("Full of Energy / Vigorous")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Text("\(Int(energyLevel))")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Submit Button
                Button(action: submitEMA) {
                    Text(emaType.buttonText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(Color.blue)
                        .cornerRadius(15)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            startTime = Date()
        }
    }
    
    private func submitEMA() {
        let completionTime = Date().timeIntervalSince(startTime)
        
        // Create response object to pass back
        let response = EMAResponse(
            stressLevel: stressLevel,
            calmAgitationLevel: calmAgitationLevel,
            energyLevel: energyLevel,
            completionTime: completionTime,
            emaType: emaType
        )
        
        // Call completion handler - the calling code will handle DataLogger calls
        onCompletion(response)
    }
}

struct EMAResponse {
    let stressLevel: Double
    let calmAgitationLevel: Double
    let energyLevel: Double
    let completionTime: TimeInterval
    let emaType: EMAType
}

// Preview for SwiftUI Canvas
struct EMAView_Previews: PreviewProvider {
    static var previews: some View {
        EMAView(emaType: .preSession) { response in
            print("EMA Response: \(response)")
        }
    }
}
