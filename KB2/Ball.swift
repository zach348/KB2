// NeuroGlide/Ball.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 11 Part 4: Dynamic Colors
// Role: Represents a single ball in the tracking task. Inherits from SKShapeNode.

import SpriteKit

class Ball: SKShapeNode {

    // --- Constants ---
    static let defaultRadius: CGFloat = 25.0
    static let flashDuration: TimeInterval = 1.5
    static let pulseLineWidth: CGFloat = 6.0

    // --- Colors ---
    // REMOVED: Static Appearance struct

    // --- Properties ---
    var isTarget: Bool = false {
        didSet {
            // Appearance update is now triggered externally after color calculation
            // if oldValue != isTarget && !isHidingTargets {
            //      updateAppearance() // Needs colors passed in
            // }
        }
    }
    var storedVelocity: CGVector? = nil
    var isHidingTargets: Bool = false // Flag to potentially prevent updates during hide transition
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

        // Initial appearance set externally after creation using updateAppearance
        self.lineWidth = 0
        // Default colors until set externally
        self.fillColor = .gray
        self.strokeColor = .gray

        self.position = position
        self.previousPosition = position
        setupPhysics()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // --- Appearance Update ---
    // MODIFIED: Takes colors as arguments
    func updateAppearance(targetColor: SKColor, distractorColor: SKColor) {
        let color = isTarget ? targetColor : distractorColor
        self.fillColor = color
        self.strokeColor = color // Border pulse uses this color
    }

    // --- Hiding/Revealing for Identification ---
    // MODIFIED: Takes hidden color as argument
    func hideIdentity(hiddenColor: SKColor) {
        self.isHidingTargets = true // Prevent potential didSet interference if added back
        self.fillColor = hiddenColor
        self.strokeColor = hiddenColor // Match stroke for consistency
        self.lineWidth = 0 // Ensure pulse border is off
        self.isHidingTargets = false
    }

    // MODIFIED: Takes current colors as arguments
    func revealIdentity(targetColor: SKColor, distractorColor: SKColor) {
        updateAppearance(targetColor: targetColor, distractorColor: distractorColor)
    }

    // --- Flashing Animation ---
    // MODIFIED: Takes current target color and flash color as arguments
    func flashAsNewTarget(targetColor: SKColor, flashColor: SKColor, duration: TimeInterval = Ball.flashDuration, flashes: Int = 6) {
        self.removeAction(forKey: "flash")
        let originalColor = targetColor // Should flash *to* the target color
        // let flashColor = flashColor // Passed in

        guard duration > 0, flashes > 0 else {
            self.fillColor = originalColor; self.strokeColor = originalColor; return
        }

        // Use run blocks to change fill and stroke together
        let flashOn = SKAction.run { [weak self] in self?.fillColor = flashColor; self?.strokeColor = flashColor }
        let flashOff = SKAction.run { [weak self] in self?.fillColor = originalColor; self?.strokeColor = originalColor }
        let wait = SKAction.wait(forDuration: duration / Double(flashes * 2))

        var sequence: [SKAction] = []
        for _ in 0..<flashes { sequence.append(contentsOf: [flashOn, wait, flashOff, wait]) }
        sequence.append(flashOff) // Ensure ends on correct color

        self.run(SKAction.sequence(sequence), withKey: "flash")
    }

    // --- Physics Setup ---
    private func setupPhysics() {
        self.physicsBody = SKPhysicsBody(circleOfRadius: Ball.defaultRadius)
        self.physicsBody?.isDynamic = true; self.physicsBody?.affectedByGravity = false; self.physicsBody?.allowsRotation = false
        self.physicsBody?.friction = 0.0; self.physicsBody?.restitution = 1.0
        self.physicsBody?.linearDamping = 0.0; self.physicsBody?.angularDamping = 0.0
    }

    // --- Movement ---
    func applyRandomImpulse(min: CGFloat = 5, max: CGFloat = 10) {
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
