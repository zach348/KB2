// NeuroGlide/Ball.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 4 Adjustments: Radius, Flash Timing
// Role: Represents a single ball in the tracking task. Subclass of SKSpriteNode.
//       Manages its state (target/distractor) and appearance.

import SpriteKit

class Ball: SKSpriteNode {

    // --- Constants ---
    // MODIFIED: Ball radius increased
    static let defaultRadius: CGFloat = 25.0

    // --- Colors (Configurable externally if needed) ---
    struct Appearance {
        static let targetColor: SKColor = .cyan
        static let distractorColor: SKColor = .magenta
        static let flashColor: SKColor = .white // Color used during flash animation
    }

    // --- Properties ---
    var isTarget: Bool = false {
        didSet {
            if oldValue != isTarget {
                 updateAppearance()
            }
        }
    }

    // --- Initialization ---
    init(isTarget: Bool, position: CGPoint) {
        self.isTarget = isTarget
        let initialColor = isTarget ? Appearance.targetColor : Appearance.distractorColor
        let texture = Ball.createTexture(color: initialColor)
        super.init(texture: texture, color: .white, size: texture.size())
        self.position = position
        setupPhysics()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // --- Texture Creation Helper ---
    private static func createTexture(color: SKColor) -> SKTexture {
        let shape = SKShapeNode(circleOfRadius: Ball.defaultRadius)
        shape.fillColor = color
        shape.strokeColor = .clear
        guard let view = SKView.shared else {
             print("Warning: No shared SKView found for texture generation.")
             let fallbackView = SKView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
             return fallbackView.texture(from: shape) ?? SKTexture()
        }
        return view.texture(from: shape) ?? SKTexture()
    }

    // --- Appearance Update ---
    func updateAppearance() {
        let newColor = isTarget ? Appearance.targetColor : Appearance.distractorColor
        self.texture = Ball.createTexture(color: newColor)
        // print("Updated appearance for ball \(self.name ?? "?"). Is target: \(isTarget)") // Keep commented unless debugging
    }

    // --- Flashing Animation ---
    // MODIFIED: Default duration and flash count doubled
    func flashAsNewTarget(duration: TimeInterval = 1.5, flashes: Int = 6) {
         print("Flashing ball \(self.name ?? "?") as new target (Duration: \(duration)s, Flashes: \(flashes)).")
        self.removeAction(forKey: "flash")

        // Ensure we have valid textures to work with
        let originalTexture = self.texture ?? Ball.createTexture(color: Appearance.targetColor)
        let flashTexture = Ball.createTexture(color: Appearance.flashColor)

        // Check for zero duration or flashes to avoid division by zero
        guard duration > 0, flashes > 0 else {
            print("Warning: Flash duration or count is zero, skipping flash.")
            // Ensure the ball has the correct final texture even if flashing is skipped
            self.texture = originalTexture
            return
        }

        let flashOn = SKAction.setTexture(flashTexture, resize: false) // Use resize: false if textures are same size
        let flashOff = SKAction.setTexture(originalTexture, resize: false)
        // MODIFIED: Wait calculation adjusted for potentially new duration/flashes
        let wait = SKAction.wait(forDuration: duration / Double(flashes * 2))

        var sequence: [SKAction] = []
        for _ in 0..<flashes {
            sequence.append(flashOn)
            sequence.append(wait)
            sequence.append(flashOff)
            sequence.append(wait)
        }

        // No need to append final setTexture, loop ends on flashOff + wait, then naturally holds original texture.
        // If duration isn't perfectly divisible, last wait might be slightly off, but usually negligible.

        self.run(SKAction.sequence(sequence), withKey: "flash")
    }


    // --- Physics Setup (Unchanged) ---
    private func setupPhysics() {
        self.physicsBody = SKPhysicsBody(circleOfRadius: Ball.defaultRadius) // Automatically uses updated radius
        self.physicsBody?.isDynamic = true
        self.physicsBody?.affectedByGravity = false
        self.physicsBody?.allowsRotation = false
        self.physicsBody?.friction = 0.0
        self.physicsBody?.restitution = 1.0
        self.physicsBody?.linearDamping = 0.0
        self.physicsBody?.angularDamping = 0.0
    }

    // --- Movement (Unchanged) ---
    func applyRandomImpulse(min: CGFloat = 5, max: CGFloat = 10) {
        let randomDx = CGFloat.random(in: -max...max)
        let randomDy = CGFloat.random(in: -max...max)
        let impulseVector = CGVector(dx: abs(randomDx) < min ? (randomDx < 0 ? -min : min) : randomDx,
                                     dy: abs(randomDy) < min ? (randomDy < 0 ? -min : min) : randomDy)
        self.physicsBody?.applyImpulse(impulseVector)
    }

    func currentSpeed() -> CGFloat {
        guard let velocity = self.physicsBody?.velocity else { return 0 }
        guard !velocity.dx.isNaN && !velocity.dy.isNaN else {
            print("Warning: NaN velocity detected for ball \(self.name ?? "?"). Resetting velocity.")
            self.physicsBody?.velocity = .zero
            return 0
        }
        return sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
    }
}

// --- SKView Extension (Unchanged) ---
extension SKView {
    static var shared: SKView? {
         if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
             return windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.view as? SKView
         }
         return nil
    }
}
