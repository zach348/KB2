// Kalibrate/ColorUtils.swift
// Created: [Current Date]
// Role: Utility functions for color manipulation.

import SpriteKit // Or UIKit if using UIColor directly

// Helper function to interpolate between two colors
// t = 0.0 returns color1, t = 1.0 returns color2
func interpolateColor(from color1: SKColor, to color2: SKColor, t: CGFloat) -> SKColor {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

    color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

    // Clamp t to [0, 1]
    let clampedT = max(0.0, min(1.0, t))

    let r = r1 + (r2 - r1) * clampedT
    let g = g1 + (g2 - g1) * clampedT
    let b = b1 + (b2 - b1) * clampedT
    let a = a1 + (a2 - a1) * clampedT // Interpolate alpha too? Or keep it fixed? Let's interpolate.

    return SKColor(red: r, green: g, blue: b, alpha: a)
}
