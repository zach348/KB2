// NeuroGlide/Ball.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 6: Motion Control Helpers (COMPLETE FILE)
// Role: Represents a single ball in the tracking task. Subclass of SKSpriteNode.

import SpriteKit

class Ball: SKSpriteNode {

    // --- Constants ---
    static let defaultRadius: CGFloat = 25.0
    static let flashDuration: TimeInterval = 1.5

    // --- Colors ---
    struct Appearance {
        static let targetColor: SKColor = .cyan
        static let distractorColor: SKColor = .magenta
        static let flashColor: SKColor = .white
        static let hiddenColor: SKColor = .magenta
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
    init(isTarget: Bool, position: CGPoint) {
        self.isTarget = isTarget
        let initialColor = isTarget ? Appearance.targetColor : Appearance.distractorColor
        let texture = Ball.createTexture(color: initialColor)
        super.init(texture: texture, color: .white, size: texture.size())
        self.position = position
        self.previousPosition = position
        setupPhysics()
    }

    // Required initializer (part of SKSpriteNode)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // --- Texture Creation Helper ---
    static func createTexture(color: SKColor) -> SKTexture {
        let shape = SKShapeNode(circleOfRadius: Ball.defaultRadius); shape.fillColor = color; shape.strokeColor = .clear
        guard let view = SKView.shared else { print("Warning: No shared SKView found."); let v = SKView(frame: CGRect(x: 0, y: 0, width: 1, height: 1)); return v.texture(from: shape) ?? SKTexture() }
        return view.texture(from: shape) ?? SKTexture()
    }

    // --- Appearance Update ---
    func updateAppearance() {
        let newColor = isTarget ? Appearance.targetColor : Appearance.distractorColor
        self.texture = Ball.createTexture(color: newColor)
    }

    // --- Hiding/Revealing for Identification ---
    func hideIdentity() { self.isHidingTargets = true; self.texture = Ball.createTexture(color: Appearance.hiddenColor); self.isHidingTargets = false }
    func revealIdentity() { updateAppearance() }

    // --- Flashing Animation ---
    func flashAsNewTarget(duration: TimeInterval = Ball.flashDuration, flashes: Int = 6) {
        self.removeAction(forKey: "flash")
        let originalTexture = Ball.createTexture(color: Appearance.targetColor)
        let flashTexture = Ball.createTexture(color: Appearance.flashColor)
        guard duration > 0, flashes > 0 else { self.texture = originalTexture; return }
        let flashOn = SKAction.setTexture(flashTexture, resize: false); let flashOff = SKAction.setTexture(originalTexture, resize: false)
        let wait = SKAction.wait(forDuration: duration / Double(flashes * 2))
        var sequence: [SKAction] = []
        for _ in 0..<flashes { sequence.append(contentsOf: [flashOn, wait, flashOff, wait]) }
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
    }

    // --- Movement ---
    func applyRandomImpulse(min: CGFloat = 5, max: CGFloat = 10) {
        let randomDx = CGFloat.random(in: -max...max); let randomDy = CGFloat.random(in: -max...max)
        let impulseVector = CGVector(dx: abs(randomDx) < min ? (randomDx < 0 ? -min : min) : randomDx, dy: abs(randomDy) < min ? (randomDy < 0 ? -min : min) : randomDy)
        // Ensure physics body exists before applying impulse
        guard let body = self.physicsBody else { return }
        body.applyImpulse(impulseVector)
    }

    func currentSpeed() -> CGFloat {
        guard let velocity = self.physicsBody?.velocity else { return 0 }
        guard !velocity.dx.isNaN && !velocity.dy.isNaN else { self.physicsBody?.velocity = .zero; return 0 }
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        return speed.isNaN ? 0 : speed
    }

    /// Modifies the ball's velocity by multiplying by a factor, preserving direction.
    func modifySpeed(factor: CGFloat) {
        guard let currentVelocity = self.physicsBody?.velocity else { return }
        guard factor > 0 && factor != 1.0 else { return }
        let newVelocity = CGVector(dx: currentVelocity.dx * factor, dy: currentVelocity.dy * factor)
        self.physicsBody?.velocity = newVelocity
    }

    /// Updates the position history for stuck detection. Call this each frame before checking if stuck.
    func updatePositionHistory() {
        guard let prevPos = previousPosition else { previousPosition = position; return }
        if abs(position.x - prevPos.x) < 0.1 { stuckCounterX += 1 } else { stuckCounterX = 0 }
        if abs(position.y - prevPos.y) < 0.1 { stuckCounterY += 1 } else { stuckCounterY = 0 }
        previousPosition = position
    }

    /// Returns true if the ball appears to be stuck horizontally against a boundary.
    func ballStuckX() -> Bool { return stuckCounterX >= stuckThreshold }

    /// Returns true if the ball appears to be stuck vertically against a boundary.
    func ballStuckY() -> Bool { return stuckCounterY >= stuckThreshold }
}

// --- SKView Extension ---
extension SKView {
    static var shared: SKView? {
         if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene { return windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.view as? SKView }
         else { return UIApplication.shared.keyWindow?.rootViewController?.view as? SKView }
    }
}
