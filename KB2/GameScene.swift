// NeuroGlide/GameScene.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 3: Tracking Task Basic Setup
// Role: Main scene for the game. Sets up balls and physics environment.
//       Still includes timer/sync foundation from Step 2.

import SpriteKit
import GameplayKit // Can remove if not using GK features later
import CoreHaptics
import AVFoundation

class GameScene: SKScene, SKPhysicsContactDelegate { // <-- Add SKPhysicsContactDelegate

    // --- Configuration ---
    public var timerFrequency: Double = 10.0 { didSet { precisionTimer?.frequency = timerFrequency } }
    public var hapticOffset: TimeInterval = 0.020
    public var audioOffset: TimeInterval = 0.040
    let numberOfBalls = 8 // How many balls to create

    // --- Properties ---
    private var precisionTimer: PrecisionTimer?
    // private var feedbackNode: SKShapeNode? // REMOVED - Replaced by actual game elements
    private var balls: [Ball] = [] // Array to hold our Ball objects

    // --- Haptic Engine ---
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?
    private var hapticsReady: Bool = false

    // --- Audio Engine ---
    private var customAudioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioBuffer: AVAudioPCMBuffer?
    private var audioFormat: AVAudioFormat?
    private var audioReady: Bool = false

    // --- Scene Lifecycle ---
    override func didMove(to view: SKView) {
        print("GameScene: didMove(to:)")
        backgroundColor = .darkGray

        setupPhysicsWorld() // <-- Setup gravity and collision delegate
        setupWalls()        // <-- Setup screen boundaries

        // setupFeedbackNode() // REMOVED
        setupHaptics()
        setupAudio()

        if hapticsReady { startHapticEngine() }
        if audioReady { startAudioEngine() }

        createBalls()      // <-- Create the balls
        applyInitialImpulses() // <-- Start the balls moving

        setupTimer()
        precisionTimer?.start() // Start rhythmic pulses (will apply to balls later)
    }

    override func willMove(from view: SKView) {
        print("GameScene: willMove(from:)")
        precisionTimer?.stop()
        stopHapticEngine()
        stopAudioEngine()
        // Clear ball array and remove nodes
        balls.forEach { $0.removeFromParent() }
        balls.removeAll()
        // Release other resources
        precisionTimer = nil
        hapticEngine = nil
        hapticPlayer = nil
        customAudioEngine = nil
        audioPlayerNode = nil
        audioBuffer = nil
        print("GameScene cleaned up resources.")
    }

    // --- Physics Setup ---
    private func setupPhysicsWorld() {
        // Set gravity to zero (no downward pull)
        physicsWorld.gravity = CGVector(dx: 0, dy: 0)
        // Set the scene as the contact delegate to receive collision notifications (if needed later)
        physicsWorld.contactDelegate = self
    }

    private func setupWalls() {
        // Create a physics body that represents the edges of the screen
        // An "edge loop" is a hollow shape, perfect for boundaries.
        let borderBody = SKPhysicsBody(edgeLoopFrom: self.frame)

        // Keep friction low, bounciness high for walls too
        borderBody.friction = 0.0
        borderBody.restitution = 1.0 // Make walls bouncy

        // Assign this physics body to the scene itself
        self.physicsBody = borderBody

        // Define physics category for walls (Example, uncomment if using categories)
        // self.physicsBody?.categoryBitMask = PhysicsCategory.Wall
    }

    // --- Ball Creation ---
    private func createBalls() {
        guard balls.isEmpty else { return } // Only create if array is empty

        for i in 0..<numberOfBalls {
            // Determine a starting position (avoid placing exactly on edge or overlapping)
            let buffer: CGFloat = Ball.defaultRadius * 2.5 // Space from edge and other balls
            let randomX = CGFloat.random(in: frame.minX + buffer ..< frame.maxX - buffer)
            let randomY = CGFloat.random(in: frame.minY + buffer ..< frame.maxY - buffer)
            let startPosition = CGPoint(x: randomX, y: randomY)

            // Alternate colors for now (replace with target/distractor logic later)
            let ballColor: SKColor = (i % 2 == 0) ? .cyan : .magenta

            // Create a Ball instance
            let newBall = Ball(color: ballColor, position: startPosition)
            newBall.name = "ball_\(i)" // Give it a unique name for debugging/identification

            // Add to array and scene
            balls.append(newBall)
            addChild(newBall)
             print("Created ball \(i) at \(startPosition)")
        }
         print("Total balls created: \(balls.count)")
    }

    private func applyInitialImpulses() {
        print("Applying initial impulses...")
        for ball in balls {
            ball.applyRandomImpulse()
        }
    }


    // --- Haptic Setup (No changes from Step 2) ---
    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { print("Haptics not supported."); return }
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.playsHapticsOnly = false
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            hapticPlayer = try hapticEngine?.makePlayer(with: pattern)
            hapticEngine?.stoppedHandler = { [weak self] reason in print("Haptic engine stopped: \(reason)"); self?.hapticsReady = false }
            hapticEngine?.resetHandler = { [weak self] in print("Haptic engine reset. Restarting."); self?.startHapticEngine() }
            print("Haptic engine created and player prepared."); hapticsReady = true
        } catch { print("Error setting up haptic engine: \(error.localizedDescription)"); hapticsReady = false }
    }
    private func startHapticEngine() {
        guard hapticsReady, let engine = hapticEngine else { return }
        do { try engine.start(); print("Haptic engine started.") }
        catch { print("Error starting haptic engine: \(error.localizedDescription)"); hapticsReady = false }
    }
    private func stopHapticEngine() {
        guard let engine = hapticEngine else { return }
        engine.stop { error in if let e = error { print("Error stopping haptic engine: \(e.localizedDescription)") } else { print("Haptic engine stopped.") } }
        hapticsReady = false
    }

    // --- Audio Setup (No changes from Step 2) ---
    private func setupAudio() {
        customAudioEngine = AVAudioEngine(); audioPlayerNode = AVAudioPlayerNode()
        guard let engine = customAudioEngine, let playerNode = audioPlayerNode else { print("Audio engine/node init failed."); return }
        do {
            engine.attach(playerNode)
            audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)
            guard let format = audioFormat else { print("Audio format failed."); audioReady = false; return }
            let sampleRate = Float(format.sampleRate); let toneFrequency: Float = 440.0; let duration: Float = 0.05
            let frameCount = AVAudioFrameCount(sampleRate * duration)
            audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            guard let buffer = audioBuffer else { print("Audio buffer failed."); audioReady = false; return }
            buffer.frameLength = frameCount
            guard let channelData = buffer.floatChannelData?[0] else { print("Audio channel data failed."); audioReady = false; return }
            let amplitude: Float = 0.5; let angularFrequency = 2 * .pi * toneFrequency / sampleRate
            for frame in 0..<Int(frameCount) { channelData[frame] = sin(Float(frame) * angularFrequency) * amplitude }
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            try engine.prepare()
            print("Audio engine created and tone buffer prepared."); audioReady = true
        } catch { print("Error setting up audio: \(error.localizedDescription)"); audioReady = false }
    }
    private func startAudioEngine() {
        guard audioReady, let engine = customAudioEngine, !engine.isRunning else { return }
        do { try engine.start(); print("Audio engine started.") }
        catch { print("Error starting audio: \(error.localizedDescription)"); audioReady = false }
    }
    private func stopAudioEngine() {
        guard let engine = customAudioEngine, engine.isRunning else { return }
        engine.stop(); print("Audio engine stopped."); audioReady = false
    }

    // --- Timer Setup (No changes from Step 2) ---
    private func setupTimer() {
        precisionTimer = PrecisionTimer()
        precisionTimer?.frequency = timerFrequency
        precisionTimer?.onVisualTick = { [weak self] in self?.handleVisualTick() }
        precisionTimer?.onHapticTick = { [weak self] targetTime in self?.handleHapticTick(visualTickTime: targetTime) }
        precisionTimer?.onAudioTick = { [weak self] targetTime in self?.handleAudioTick(visualTickTime: targetTime) }
    }

    // --- Timer Callback Handlers (Visual handler updated) ---
    private func handleVisualTick() {
        // Now, instead of pulsing the feedback node, let's pulse *all* balls
         // print("Visual Tick!")
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.05), // Scale up slightly
            SKAction.scale(to: 1.0, duration: 0.15)  // Scale back to normal
        ])
        balls.forEach { $0.run(pulseAction) } // Apply to all balls
    }

    private func handleHapticTick(visualTickTime: CFTimeInterval) {
        guard hapticsReady, let player = hapticPlayer else { return }
        let hapticStartTime = visualTickTime + hapticOffset
        do { try player.start(atTime: hapticStartTime) }
        catch { print("Error scheduling haptic player: \(error.localizedDescription)") }
    }

    private func handleAudioTick(visualTickTime: CFTimeInterval) {
       guard audioReady, let engine = customAudioEngine, let playerNode = audioPlayerNode, let buffer = audioBuffer else { return }
       let audioStartTime = visualTickTime + audioOffset
       let currentTime = CACurrentMediaTime()
       let delayUntilStartTime = max(0, audioStartTime - currentTime)
       DispatchQueue.main.asyncAfter(deadline: .now() + delayUntilStartTime) {
           guard self.audioReady, engine.isRunning, self.audioPlayerNode === playerNode, self.audioBuffer === buffer else { return }
           playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { }
           if !playerNode.isPlaying { playerNode.play() }
       }
    }

    // --- Update Loop ---
    override func update(_ currentTime: TimeInterval) {
        // Called before each frame is rendered
        // Could add code here later for things not tied to the PrecisionTimer rhythm,
        // like checking ball speeds continuously for the MotionControl logic (Step 6).
         // Example: Print average speed periodically
         // if Int(currentTime) % 2 == 0 { // Print every ~2 seconds
         //     let avgSpeed = balls.reduce(0.0) { $0 + $1.currentSpeed() } / CGFloat(max(1, balls.count))
         //     print(String(format: "Avg Ball Speed: %.2f", avgSpeed))
         // }
    }

    // --- Touch Handling (Kept for testing offsets) ---
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
       if hapticOffset == 0.020 { hapticOffset = 0.050; audioOffset = 0.100 }
       else if hapticOffset == 0.050 { hapticOffset = 0.000; audioOffset = 0.040 }
       else { hapticOffset = 0.020; audioOffset = 0.040 }
       print("--- Touch ---"); print("Offsets -> H: \(String(format: "%.1f", hapticOffset * 1000))ms, A: \(String(format: "%.1f", audioOffset * 1000))ms"); print("---------------")
    }

    // --- Physics Contact Delegate Method ---
    func didBegin(_ contact: SKPhysicsContact) {
        // This method is called automatically when two physics bodies collide
        // (if their contactTestBitMasks are set up correctly).
        // We don't need it *yet* but it's required by SKPhysicsContactDelegate.
        // We could add sounds or effects on collision here later.
        // print("Contact between: \(contact.bodyA.node?.name ?? "nil") and \(contact.bodyB.node?.name ?? "nil")")
    }
}
