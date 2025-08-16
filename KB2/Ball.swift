// Kalibrate/Ball.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 11 FIX 9: Added isVisuallyHidden flag
// Role: Represents a single ball in the tracking task. Inherits from SKShapeNode.

import SpriteKit

class Ball: SKShapeNode {

    // --- Constants ---
    static let defaultRadius: CGFloat = 25.0
    static let defaultFlashDuration: TimeInterval = 1.5 // Default - actual duration will be passed in
    static let pulseLineWidth: CGFloat = 6.0

    // --- Properties ---
    var isTarget: Bool = false {
        didSet {
            // Appearance update is triggered externally after color calculation
        }
    }
    var storedVelocity: CGVector? = nil
    // MODIFIED: Added flag to track hidden state reliably
    var isVisuallyHidden: Bool = false
    // --- Internal state for stuck detection ---
    private var previousPosition: CGPoint?
    private var stuckCounterX: Int = 0
    private var stuckCounterY: Int = 0
    private let stuckThreshold: Int = 5

    // --- Initialization ---
    init(isTarget: Bool, position: CGPoint) {
        self.isTarget = isTarget
        super.init()
        let circlePath = CGPath(ellipseIn: CGRect(x: -Ball.defaultRadius, y: -Ball.defaultRadius, width: Ball.defaultRadius * 2, height: Ball.defaultRadius * 2), transform: nil)
        self.path = circlePath
        self.lineWidth = 0
        self.fillColor = .gray // Default until set by updateAppearance
        self.strokeColor = .gray
        self.position = position
        self.previousPosition = position
        setupPhysics()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // --- Appearance Update ---
    func updateAppearance(targetColor: SKColor, distractorColor: SKColor) {
        let color = isTarget ? targetColor : distractorColor
        self.fillColor = color
        self.strokeColor = color
         // When appearance is explicitly updated, it's not hidden
        self.isVisuallyHidden = false
    }

    // --- Hiding/Revealing for Identification ---
    // MODIFIED: Sets/unsets isVisuallyHidden flag
    func hideIdentity(hiddenColor: SKColor) {
        // self.isHidingTargets = true // No longer needed with explicit flag
        self.fillColor = hiddenColor
        self.strokeColor = hiddenColor
        self.lineWidth = 0
        self.isVisuallyHidden = true // Mark as hidden
        // self.isHidingTargets = false
    }

    func revealIdentity(targetColor: SKColor, distractorColor: SKColor) {
        updateAppearance(targetColor: targetColor, distractorColor: distractorColor) // This sets isVisuallyHidden = false
    }

    // --- Flashing Animation ---
    func flashAsNewTarget(targetColor: SKColor, flashColor: SKColor, duration: TimeInterval = Ball.defaultFlashDuration, flashes: Int = 6) {
        self.removeAction(forKey: "flash")
        let originalColor = targetColor
        guard duration > 0, flashes > 0 else {
            self.fillColor = originalColor; self.strokeColor = originalColor; return
        }

        // --- Apply Speed Factor --- 
        // Need access to GameConfiguration here. Simplest is to pass it in or make factor static.
        // Let's assume GameConfiguration is accessible or factor is passed.
        // For now, hardcoding it as an example, but should be read from config.
        // *** TODO: Read flashSpeedFactor properly from GameConfiguration *** 
        let configSpeedFactor = GameConfiguration().flashSpeedFactor // Direct access if needed 
        // ---------------------------

        let flashOn = SKAction.run { [weak self] in self?.fillColor = flashColor; self?.strokeColor = flashColor }
        let flashOff = SKAction.run { [weak self] in self?.fillColor = originalColor; self?.strokeColor = originalColor }
        
        // Calculate total time available per flash
        let timePerFlash = duration / Double(flashes)
        
        // Allocate 85% of each cycle to flash-on and 15% to flash-off
        let flashOnRatio: Double = 0.85
        let flashOffRatio: Double = 1.0 - flashOnRatio
        
        // Calculate adjusted durations for on and off phases
        let onDuration = timePerFlash * flashOnRatio * configSpeedFactor
        let offDuration = timePerFlash * flashOffRatio * configSpeedFactor
        
        // Ensure minimum durations
        let adjustedOnDuration = max(0.001, onDuration)
        let adjustedOffDuration = max(0.001, offDuration)
        
        let waitActionOn = SKAction.wait(forDuration: adjustedOnDuration)
        let waitActionOff = SKAction.wait(forDuration: adjustedOffDuration)
        
        var sequence: [SKAction] = []
        for _ in 0..<flashes { 
            sequence.append(contentsOf: [flashOn, waitActionOn, flashOff, waitActionOff]) 
        }
        sequence.append(flashOff) // Ensure ends on correct color
        
        // Flashing means it's not hidden
        let setNotHidden = SKAction.run { [weak self] in self?.isVisuallyHidden = false }
        sequence.append(setNotHidden)

        self.run(SKAction.sequence(sequence), withKey: "flash")
    }

    // --- Physics Setup ---
    private func setupPhysics() {
        self.physicsBody = SKPhysicsBody(circleOfRadius: Ball.defaultRadius)
        self.physicsBody?.isDynamic = true
        self.physicsBody?.affectedByGravity = false
        self.physicsBody?.allowsRotation = false
        self.physicsBody?.friction = 0.0
        self.physicsBody?.restitution = 1.0
        self.physicsBody?.linearDamping = 0.0
        self.physicsBody?.angularDamping = 0.0
        
        // Set up collision detection with proper bitmasks
        self.physicsBody?.categoryBitMask = 1
        self.physicsBody?.collisionBitMask = 1
        self.physicsBody?.contactTestBitMask = 1
    }

    // --- Movement ---
    func applyRandomImpulse(min: CGFloat = 15, max: CGFloat = 30) {
        let randomDx = CGFloat.random(in: -max...max); let randomDy = CGFloat.random(in: -max...max)
        let impulseVector = CGVector(dx: abs(randomDx) < min ? (randomDx < 0 ? -min : min) : randomDx, dy: abs(randomDy) < min ? (randomDy < 0 ? -min : min) : randomDy)
        guard let body = self.physicsBody else { return }; body.applyImpulse(impulseVector)
    }
    func currentSpeed() -> CGFloat {
        guard let velocity = self.physicsBody?.velocity else { return 0 }
        guard !velocity.dx.isNaN && !velocity.dy.isNaN else { self.physicsBody?.velocity = .zero; return 0 }
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy); return speed.isNaN ? 0 : speed
    }
    func modifySpeed(factor: CGFloat) {
        guard let currentVelocity = self.physicsBody?.velocity else { return }
        guard factor > 0 && factor != 1.0 else { return }
        let newVelocity = CGVector(dx: currentVelocity.dx * factor, dy: currentVelocity.dy * factor)
        self.physicsBody?.velocity = newVelocity
    }
    func updatePositionHistory() {
        guard let prevPos = previousPosition else { previousPosition = position; return }
        if abs(position.x - prevPos.x) < 0.1 { stuckCounterX += 1 } else { stuckCounterX = 0 }
        if abs(position.y - prevPos.y) < 0.1 { stuckCounterY += 1 } else { stuckCounterY = 0 }
        previousPosition = position
    }
    func ballStuckX() -> Bool { return stuckCounterX >= stuckThreshold }
    func ballStuckY() -> Bool { return stuckCounterY >= stuckThreshold }
}
