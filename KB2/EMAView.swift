// Copyright 2025 Training State, LLC. All rights reserved.
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
    @State private var calmJitteryLevel: Double = 50
    @State private var startTime: Date = Date()
    
    // Brand Colors (matching PaywallViewController and other views)
    private let primaryColor = Color(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0) // #77FDC7
    private let secondaryColor = Color(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0) // #A09EA1
    private let darkColor = Color(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0) // #242424
    
    // Responsive design properties
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 700 // iPhone SE and similar
    }
    
    private var titleFontSize: Font {
        isSmallScreen ? .title2 : .title
    }
    
    private var headlineFontSize: Font {
        isSmallScreen ? .body : .headline
    }
    
    private var sectionSpacing: CGFloat {
        isSmallScreen ? 15 : 30
    }
    
    private var innerSpacing: CGFloat {
        isSmallScreen ? 8 : 15
    }
    
    private var horizontalPadding: CGFloat {
        isSmallScreen ? 16 : 20
    }
    
    var body: some View {
        ZStack {
            // Dark background using brand color
            darkColor.edgesIgnoringSafeArea(.all)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: sectionSpacing) {
                    // Title
                    VStack(spacing: 8) {
                        Text(emaType.title)
                            .font(titleFontSize)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                        
                        Text("(Your responses are anonymous)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, isSmallScreen ? 10 : 20)
                    
                    // Stress Level VAS
                    VStack(spacing: innerSpacing) {
                        Text("How stressed do you feel right now?")
                            .font(headlineFontSize)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(spacing: 8) {
                            Slider(value: $stressLevel, in: 0...100, step: 1)
                                .accentColor(primaryColor)
                            
                            HStack {
                                Text("Not Stressed at All")
                                    .font(isSmallScreen ? .caption2 : .caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Text("Extremely Stressed")
                                    .font(isSmallScreen ? .caption2 : .caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        
                        Text("\(Int(stressLevel))")
                            .font(isSmallScreen ? .title3 : .title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, horizontalPadding)
                    
                    // Calm/Agitation Level VAS
                    VStack(spacing: innerSpacing) {
                        Text("How calm or jittery do you feel right now?")
                            .font(headlineFontSize)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(spacing: 8) {
                            Slider(value: $calmJitteryLevel, in: 0...100, step: 1)
                                .accentColor(primaryColor)
                            
                            HStack {
                                Text("Very Calm")
                                    .font(isSmallScreen ? .caption2 : .caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Text("Very Jittery")
                                    .font(isSmallScreen ? .caption2 : .caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        
                        Text("\(Int(calmJitteryLevel))")
                            .font(isSmallScreen ? .title3 : .title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, horizontalPadding)
                    
                    // Submit Button using brand colors
                    Button(action: submitEMA) {
                        Text(emaType.buttonText)
                            .font(isSmallScreen ? .title3 : .title2)
                            .fontWeight(.bold)
                            .foregroundColor(darkColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: isSmallScreen ? 50 : 55)
                            .background(primaryColor)
                            .cornerRadius(15)
                    }
                    .padding(.horizontal, isSmallScreen ? 30 : 40)
                    .padding(.bottom, isSmallScreen ? 20 : 30)
                }
                .padding(.bottom, 20) // Extra bottom padding for scroll view
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
            calmJitteryLevel: calmJitteryLevel,
            completionTime: completionTime,
            emaType: emaType
        )
        
        // Call completion handler - the calling code will handle DataLogger calls
        onCompletion(response)
    }
}

struct EMAResponse {
    let stressLevel: Double
    let calmJitteryLevel: Double
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
