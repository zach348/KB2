// KB2/Ball.swift
// Created: [Current Date]
// Role: Represents a single ball in the tracking task. Subclass of SKSpriteNode.

import SpriteKit

class Ball: SKSpriteNode {

    // --- Properties ---
    static let defaultRadius: CGFloat = 25.0 // Size of the ball
    // Add other ball-specific properties later (isTarget, etc.)

    // --- Initialization ---
    init(color: SKColor, position: CGPoint) {
        // Create a texture for a filled circle (using SKShapeNode initially)
        // This is slightly inefficient but easy for now. Could use image assets later.
        let shape = SKShapeNode(circleOfRadius: Ball.defaultRadius)
        shape.fillColor = color
        shape.strokeColor = .clear // No border initially
        let texture = SKView().texture(from: shape) // Create texture from shape

        // Call the SKSpriteNode initializer with the texture
        super.init(texture: texture, color: .white, size: texture?.size() ?? CGSize(width: Ball.defaultRadius*2, height: Ball.defaultRadius*2))

        // Set initial position
        self.position = position

        // Setup physics body
        setupPhysics()
    }

    // Required initializer if initializing from a scene file (which we aren't doing here)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // --- Physics Setup ---
    private func setupPhysics() {
        // Create a circular physics body matching the ball's size
        self.physicsBody = SKPhysicsBody(circleOfRadius: Ball.defaultRadius)

        // Basic physics properties
        self.physicsBody?.isDynamic = true // Affected by physics simulation (forces, impulses, collisions)
        self.physicsBody?.affectedByGravity = false // No gravity pulling balls down
        self.physicsBody?.allowsRotation = false // Keep balls from spinning visually on collision

        // Collision properties
        self.physicsBody?.friction = 0.0 // No loss of speed sliding against other objects
        self.physicsBody?.restitution = 1.0 // Bounciness (1.0 = perfectly elastic, no energy loss on bounce)
        self.physicsBody?.linearDamping = 0.0 // No gradual slowdown over time (like air resistance)
        self.physicsBody?.angularDamping = 0.0 // No slowdown of rotation (though rotation is disallowed anyway)

        // Collision masking (Covered in more detail later if needed)
        // By default, all physics bodies belong to the same category and collide with everything.
        // This is fine for now (balls hit balls, balls hit walls).
        // self.physicsBody?.categoryBitMask = PhysicsCategory.Ball // Example for later
        // self.physicsBody?.collisionBitMask = PhysicsCategory.Wall | PhysicsCategory.Ball // Example
        // self.physicsBody?.contactTestBitMask = PhysicsCategory.Ball // Example if we need collision notifications
    }

    // --- Movement ---
    func applyRandomImpulse(min: CGFloat = 5, max: CGFloat = 10) {
        let randomDx = CGFloat.random(in: -max...max)
        let randomDy = CGFloat.random(in: -max...max)
        // Ensure minimum impulse so balls don't start too slow or stationary
        let impulseVector = CGVector(dx: abs(randomDx) < min ? (randomDx < 0 ? -min : min) : randomDx,
                                     dy: abs(randomDy) < min ? (randomDy < 0 ? -min : min) : randomDy)
        self.physicsBody?.applyImpulse(impulseVector)
         print("Applied impulse \(impulseVector) to ball at \(position)")
    }

    // We will add methods like currentSpeed(), modifySpeed(), etc. later (Step 6)
    func currentSpeed() -> CGFloat {
        guard let velocity = self.physicsBody?.velocity else { return 0 }
        return sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
    }

}

// Example Physics Category Definition (We'll uncomment/use this later if needed)
/*
struct PhysicsCategory {
    static let None: UInt32 = 0
    static let All: UInt32 = UInt32.max
    static let Wall: UInt32 = 0b1       // 1
    static let Ball: UInt32 = 0b10      // 2
    // Add other categories as needed (e.g., TargetBall, DistractorBall)
}
*/
