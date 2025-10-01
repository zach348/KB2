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
// KB2/StartScreenBall.swift
// A simplified ball graphic for the start screen with responsive sizing

import SpriteKit
import UIKit

// MARK: - UIColor Extension for Brightness Manipulation
extension UIColor {
    var brightness: CGFloat {
        var brightness: CGFloat = 0
        getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
        return brightness
    }
    
    func withBrightness(_ brightness: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var alpha: CGFloat = 0
        
        getHue(&hue, saturation: &saturation, brightness: nil, alpha: &alpha)
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }
}

class StartScreenBall: SKShapeNode {
    
    // MARK: - Properties
    private let radius: CGFloat
    private let primaryColor: UIColor
    
    // MARK: - Initialization
    init(radius: CGFloat, color: UIColor) {
        self.radius = radius
        self.primaryColor = color
        super.init()
        
        setupAppearance()
        setupAnimation()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupAppearance() {
        let circlePath = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        self.path = circlePath
        self.lineWidth = 0
        
        // Create a radial gradient for 3D effect
        let gradientTexture = createGradientTexture()
        self.fillTexture = gradientTexture
        self.fillColor = SKColor.white
        self.strokeColor = .clear
    }
    
    private func createGradientTexture() -> SKTexture {
        let size = CGSize(width: radius * 2, height: radius * 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let cgContext = context.cgContext
            
            // Create gradient colors (lighter at top-left, darker at bottom-right)
            let baseColor = primaryColor
            let highlightColor = baseColor.withBrightness(min(1.0, baseColor.brightness + 0.3))
            let shadowColor = baseColor.withBrightness(max(0.0, baseColor.brightness - 0.2))
            
            let colors = [highlightColor.cgColor, baseColor.cgColor, shadowColor.cgColor]
            let locations: [CGFloat] = [0.0, 0.6, 1.0]
            
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: colors as CFArray,
                                          locations: locations) else { return }
            
            // Draw radial gradient from center to edge
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let endRadius = radius * 0.9
            
            cgContext.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: center.x - radius * 0.3, y: center.y + radius * 0.3),
                                       startRadius: 0,
                                       endCenter: center,
                                       endRadius: endRadius,
                                       options: [.drawsAfterEndLocation])
        }
        
        return SKTexture(image: image)
    }
    
    private func setupAnimation() {
        // Gentle pulsing animation
        let scaleUp = SKAction.scale(to: 1.1, duration: 1.5)
        let scaleDown = SKAction.scale(to: 1.0, duration: 1.5)
        
        // Add easing for smoother animation
        scaleUp.timingMode = .easeInEaseOut
        scaleDown.timingMode = .easeInEaseOut
        
        let pulseSequence = SKAction.sequence([scaleUp, scaleDown])
        let repeatPulse = SKAction.repeatForever(pulseSequence)
        
        self.run(repeatPulse, withKey: "pulse")
    }
}
