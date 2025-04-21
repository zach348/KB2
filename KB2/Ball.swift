// NeuroGlide/Ball.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 7 FIX: Convert to SKShapeNode, Use Border Pulse
// Role: Represents a single ball in the tracking task. Inherits from SKShapeNode.

import SpriteKit

class Ball: SKShapeNode { // MODIFIED: Inherit from SKShapeNode

    // --- Constants ---
    static let defaultRadius: CGFloat = 25.0
    static let flashDuration: TimeInterval = 1.5
    // MODIFIED: Define pulse border width
    static let pulseLineWidth: CGFloat = 6.0

    // --- Colors ---
    struct Appearance {
        static let targetColor: SKColor = .cyan
        static let distractorColor: SKColor = .magenta
        static let flashColor: SKColor = .white // Color used during target indication flash
        static let hiddenColor: SKColor = .magenta // Color targets turn during identification
        // removed static border color - each ball will use its fill color for the border
    }

    // --- Properties ---
    var isTarget: Bool = false {
        didSet {
            if oldValue != isTarget && !isHidingTargets {
                 updateAppearance()
            }
        }
    }
    var storedVelocity: CGVector? = nil
    var isHidingTargets: Bool = false
    private var previousPosition: CGPoint?
    private var stuckCounterX: Int = 0
    private var stuckCounterY: Int = 0
    private let stuckThreshold: Int = 5

    // --- Initialization ---
    // MODIFIED: Initialize as SKShapeNode
    init(isTarget: Bool, position: CGPoint) {
        self.isTarget = isTarget // Set state before super.init call might use it

        // Call SKShapeNode initializer
        super.init()
        let circlePath = CGPath(ellipseIn: CGRect(x: -Ball.defaultRadius, y: -Ball.defaultRadius, width: Ball.defaultRadius * 2, height: Ball.defaultRadius * 2), transform: nil)
        self.path = circlePath

        // Set initial appearance
        self.lineWidth = 0 // Start with no border pulse
        updateAppearance() // Set initial fill color based on isTarget

        self.position = position
        self.previousPosition = position
        setupPhysics()
    }

    // Required initializer
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // --- Texture Creation Helper ---
    // REMOVED: No longer needed

    // --- Appearance Update ---
    // MODIFIED: Sets fillColor and matching strokeColor
    func updateAppearance() {
        let color = isTarget ? Appearance.targetColor : Appearance.distractorColor
        self.fillColor = color
        self.strokeColor = color
    }

    // --- Hiding/Revealing for Identification ---
    // MODIFIED: Sets fillColor
    func hideIdentity() {
        self.isHidingTargets = true
        self.fillColor = Appearance.hiddenColor
        self.strokeColor = Appearance.hiddenColor
        self.isHidingTargets = false
    }
    func revealIdentity() {
        updateAppearance() // Restore correct target/distractor color
    }

    // --- Flashing Animation ---
    // MODIFIED: Uses fillColor changes
    func flashAsNewTarget(duration: TimeInterval = Ball.flashDuration, flashes: Int = 6) {
        self.removeAction(forKey: "flash")
        let originalColor = isTarget ? Appearance.targetColor : Appearance.distractorColor // Should always be target color here
        let flashColor = Appearance.flashColor

        guard duration > 0, flashes > 0 else {
            self.fillColor = originalColor
            return
        }

        let flashOn = SKAction.run { [weak self] in self?.fillColor = flashColor }
        let flashOff = SKAction.run { [weak self] in self?.fillColor = originalColor }
        let wait = SKAction.wait(forDuration: duration / Double(flashes * 2))

        var sequence: [SKAction] = []
        for _ in 0..<flashes {
            sequence.append(contentsOf: [flashOn, wait, flashOff, wait])
        }
        // Ensure it ends on the correct color
        sequence.append(SKAction.run { [weak self] in self?.fillColor = originalColor })

        self.run(SKAction.sequence(sequence), withKey: "flash")
    }

    // --- Physics Setup ---
    // MODIFIED: Physics body needs offset if path origin is center
    private func setupPhysics() {
        // SKShapeNode path origin is center, so physics body is centered automatically
        self.physicsBody = SKPhysicsBody(circleOfRadius: Ball.defaultRadius)
        self.physicsBody?.isDynamic = true
        self.physicsBody?.affectedByGravity = false
        self.physicsBody?.allowsRotation = false
        self.physicsBody?.friction = 0.0
        self.physicsBody?.restitution = 1.0
        self.physicsBody?.linearDamping = 0.0
        self.physicsBody?.angularDamping = 0.0
    }

    // --- Movement ---
    func applyRandomImpulse(min: CGFloat = 5, max: CGFloat = 10) {
        let randomDx = CGFloat.random(in: -max...max); let randomDy = CGFloat.random(in: -max...max)
        let impulseVector = CGVector(dx: abs(randomDx) < min ? (randomDx < 0 ? -min : min) : randomDx, dy: abs(randomDy) < min ? (randomDy < 0 ? -min : min) : randomDy)
        guard let body = self.physicsBody else { return }
        body.applyImpulse(impulseVector)
    }

    func currentSpeed() -> CGFloat {
        guard let velocity = self.physicsBody?.velocity else { return 0 }
        guard !velocity.dx.isNaN && !velocity.dy.isNaN else { self.physicsBody?.velocity = .zero; return 0 }
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        return speed.isNaN ? 0 : speed
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

// --- SKView Extension ---
// REMOVED: No longer needed for texture generation
