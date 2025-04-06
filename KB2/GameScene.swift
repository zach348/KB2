// NeuroGlide/GameScene.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 4 Adjustments RE-APPLIED (Timer Logic Verified)
// Role: Main scene for the game. Manages balls, target/distractor state,
//       and target shifts. Includes timer/sync foundation.

import SpriteKit
import GameplayKit
import CoreHaptics
import AVFoundation

class GameScene: SKScene, SKPhysicsContactDelegate {

    // --- Configuration ---
    // Rhythm Timer
    public var timerFrequency: Double = 5.0 { didSet { precisionTimer?.frequency = timerFrequency } }
    public var hapticOffset: TimeInterval = 0.020
    public var audioOffset: TimeInterval = 0.040
    // Tracking Task
    let numberOfBalls = 10 // Adjusted ball count
    let numberOfTargets = 3
    let targetShiftInterval: TimeInterval = 5.0

    // --- Properties ---
    private var precisionTimer: PrecisionTimer?
    private var balls: [Ball] = []
    private var targetShiftTimerActionKey = "targetShiftTimer"

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
        setupPhysicsWorld()
        setupWalls()
        setupHaptics()
        setupAudio()

        if hapticsReady { startHapticEngine() }
        if audioReady { startAudioEngine() }

        createBalls()
        applyInitialImpulses()

        // *** ENSURE TIMER SETUP AND START ARE CALLED ***
        setupTimer()
        precisionTimer?.start()
        // ***********************************************

        startTargetShiftTimer()
    }

    override func willMove(from view: SKView) {
        print("GameScene: willMove(from:)")
        // Stop all timers and engines
        precisionTimer?.stop() // Make sure timer stops
        stopTargetShiftTimer()
        stopHapticEngine()
        stopAudioEngine()
        // Cleanup nodes and resources
        balls.forEach { $0.removeFromParent() }
        balls.removeAll()
        precisionTimer = nil
        hapticEngine = nil
        hapticPlayer = nil
        customAudioEngine = nil
        audioPlayerNode = nil
        audioBuffer = nil
        print("GameScene cleaned up resources.")
    }

    // --- Physics Setup (Unchanged) ---
    private func setupPhysicsWorld() {
        physicsWorld.gravity = CGVector(dx: 0, dy: 0)
        physicsWorld.contactDelegate = self
    }
    private func setupWalls() {
        let borderBody = SKPhysicsBody(edgeLoopFrom: self.frame)
        borderBody.friction = 0.0
        borderBody.restitution = 1.0
        self.physicsBody = borderBody
    }

    // --- Ball Creation (Includes adjustments and safety check) ---
    private func createBalls() {
        guard balls.isEmpty else { return }
        guard numberOfTargets <= numberOfBalls else {
            print("Error: numberOfTargets (\(numberOfTargets)) cannot exceed numberOfBalls (\(numberOfBalls)).")
            return
        }

        for i in 0..<numberOfBalls {
            let buffer: CGFloat = Ball.defaultRadius * 2.5 // Uses updated Ball.defaultRadius
            let safeFrame = self.frame.insetBy(dx: buffer, dy: buffer)

            var startPosition: CGPoint
            if safeFrame.width <= 0 || safeFrame.height <= 0 {
                print("Warning: Frame too small for ball radius buffer. Using smaller buffer.")
                let smallerBuffer = Ball.defaultRadius * 1.25
                 let smallerSafeFrame = self.frame.insetBy(dx: smallerBuffer, dy: smallerBuffer)
                 guard smallerSafeFrame.width > 0 && smallerSafeFrame.height > 0 else {
                     print("Error: Frame still too small. Cannot place ball \(i).")
                     continue // Skip this ball if still impossible
                 }
                let randomX = CGFloat.random(in: smallerSafeFrame.minX ..< smallerSafeFrame.maxX)
                let randomY = CGFloat.random(in: smallerSafeFrame.minY ..< smallerSafeFrame.maxY)
                startPosition = CGPoint(x: randomX, y: randomY)
            } else {
                let randomX = CGFloat.random(in: safeFrame.minX ..< safeFrame.maxX)
                let randomY = CGFloat.random(in: safeFrame.minY ..< safeFrame.maxY)
                startPosition = CGPoint(x: randomX, y: randomY)
            }

            // Uses Ball initializer which uses adjusted radius
            let newBall = Ball(isTarget: false, position: startPosition)
            newBall.name = "ball_\(i)"
            balls.append(newBall)
            addChild(newBall)
        }

        assignNewTargets(flashNewTargets: false)

        print("Initial balls created. Total: \(balls.count). Targets: \(balls.filter { $0.isTarget }.count)")
    }

    private func applyInitialImpulses() {
        balls.forEach { $0.applyRandomImpulse() }
    }

    // --- Target Shift Logic (Unchanged) ---
    private func assignNewTargets(flashNewTargets: Bool) {
        guard numberOfTargets <= balls.count else { return }
        let shuffledBalls = balls.shuffled()
        var newlyAssignedTargets: [Ball] = []
        for (index, ball) in shuffledBalls.enumerated() {
            let shouldBeTarget = index < numberOfTargets
            if ball.isTarget != shouldBeTarget {
                ball.isTarget = shouldBeTarget
                if shouldBeTarget { newlyAssignedTargets.append(ball) }
            }
        }
        if flashNewTargets {
            // Uses updated flash defaults from Ball.swift
            newlyAssignedTargets.forEach { $0.flashAsNewTarget() }
        }
    }
    private func startTargetShiftTimer() {
        stopTargetShiftTimer()
        let waitAction = SKAction.wait(forDuration: targetShiftInterval)
        let performShiftAction = SKAction.run { [weak self] in
            self?.assignNewTargets(flashNewTargets: true)
        }
        let sequence = SKAction.sequence([waitAction, performShiftAction])
        let repeatForever = SKAction.repeatForever(sequence)
        self.run(repeatForever, withKey: targetShiftTimerActionKey)
    }
    private func stopTargetShiftTimer() {
        self.removeAction(forKey: targetShiftTimerActionKey)
    }

    // --- Haptic Setup (Verified - Same as working Step 4) ---
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
         // Allow restarting even if 'running' according to its state, e.g., after a reset
         do { try engine.start(); print("Haptic engine started.") }
         catch { print("Error starting haptic engine: \(error.localizedDescription)"); hapticsReady = false }
    }
    private func stopHapticEngine() {
         guard let engine = hapticEngine else { return }
         engine.stop { error in if let e = error { print("Error stopping haptic engine: \(e.localizedDescription)") } else { print("Haptic engine stopped.") } }
         hapticsReady = false // Mark as not ready after stopping
    }

    // --- Audio Setup (Verified - Same as working Step 4) ---
    private func setupAudio() {
        customAudioEngine = AVAudioEngine(); audioPlayerNode = AVAudioPlayerNode()
        guard let engine = customAudioEngine, let playerNode = audioPlayerNode else { print("Audio engine/node init failed."); return }
        do {
            engine.attach(playerNode)
            audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)
            guard let format = audioFormat else { print("Audio format failed."); audioReady = false; return }
            let sampleRate = Float(format.sampleRate); let toneFrequency: Float = 440.0; let duration: Float = 0.1
            let frameCount = AVAudioFrameCount(sampleRate * duration)
            audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            guard let buffer = audioBuffer else { print("Audio buffer failed."); audioReady = false; return }
            buffer.frameLength = frameCount
            guard let channelData = buffer.floatChannelData?[0] else { print("Audio channel data failed."); audioReady = false; return }
            let amplitude: Float = 0.5; let angularFrequency = 2 * .pi * toneFrequency / sampleRate
            for frame in 0..<Int(frameCount) { channelData[frame] = sin(Float(frame) * angularFrequency) * amplitude }
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            try engine.prepare() // Use try? to avoid crash on prepare fail
            print("Audio engine created and tone buffer prepared."); audioReady = true
        } catch { print("Error setting up audio: \(error.localizedDescription)"); audioReady = false }
    }
    private func startAudioEngine() {
        guard audioReady, let engine = customAudioEngine, !engine.isRunning else {
             if !audioReady { print("Audio not ready, cannot start engine.") }
             if let engine = customAudioEngine, engine.isRunning { print("Audio engine already running.") }
             return
         }
        do { try engine.start(); print("Audio engine started.") }
        catch { print("Error starting audio: \(error.localizedDescription)"); audioReady = false }
    }
    private func stopAudioEngine() {
        guard let engine = customAudioEngine, engine.isRunning else { return }
        engine.stop(); print("Audio engine stopped."); audioReady = false // Mark as not ready after stopping
    }

    // *** VERIFY THIS TIMER SETUP SECTION ***
    private func setupTimer() {
        print("Setting up PrecisionTimer...")
        precisionTimer = PrecisionTimer()
        precisionTimer?.frequency = timerFrequency
        // Use [weak self] to prevent retain cycles
        precisionTimer?.onVisualTick = { [weak self] in
            self?.handleVisualTick()
        }
        precisionTimer?.onHapticTick = { [weak self] targetTime in
             self?.handleHapticTick(visualTickTime: targetTime)
        }
         precisionTimer?.onAudioTick = { [weak self] targetTime in
             self?.handleAudioTick(visualTickTime: targetTime)
         }
         print("PrecisionTimer callbacks assigned.")
    }
    // *************************************

    // *** VERIFY THESE TIMER CALLBACK HANDLERS ***
    private func handleVisualTick() {
        // print("Visual Tick!") // DIAGNOSTIC (uncomment if needed)
        let pulseAction = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.05),
            SKAction.scale(to: 1.0, duration: 0.15)
        ])
        // Ensure balls array is not empty before trying to run action
        guard !balls.isEmpty else { return }
        balls.forEach { $0.run(pulseAction) }
    }

    private func handleHapticTick(visualTickTime: CFTimeInterval) {
         guard hapticsReady, let player = hapticPlayer else {
             // print("Haptic Tick skipped: Haptics not ready or no player.") // DIAGNOSTIC
             return
         }
         // print("Haptic Tick!") // DIAGNOSTIC (uncomment if needed)
         let hapticStartTime = visualTickTime + hapticOffset
         do { try player.start(atTime: hapticStartTime) }
         catch { print("Error scheduling haptic player: \(error.localizedDescription)") }
    }

    private func handleAudioTick(visualTickTime: CFTimeInterval) {
        guard audioReady, let engine = customAudioEngine, let playerNode = audioPlayerNode, let buffer = audioBuffer else {
            // print("Audio Tick skipped: Audio not ready or missing components.") // DIAGNOSTIC
            return
        }
        // print("Audio Tick!") // DIAGNOSTIC (uncomment if needed)
        let audioStartTime = visualTickTime + audioOffset
        let currentTime = CACurrentMediaTime()
        let delayUntilStartTime = max(0, audioStartTime - currentTime)

        DispatchQueue.main.asyncAfter(deadline: .now() + delayUntilStartTime) { [weak self] in // Added weak self capture here too
            // Add extra check inside async block
            guard let self = self, self.audioReady, engine.isRunning, self.audioPlayerNode === playerNode, self.audioBuffer === buffer else {
                // print("Audio playback aborted: State changed before execution.") // DIAGNOSTIC
                return
            }
            playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { }
            if !playerNode.isPlaying { playerNode.play() }
        }
    }
    // ******************************************

    // --- Update Loop (Unchanged) ---
    override func update(_ currentTime: TimeInterval) { /* ... */ }

    // --- Touch Handling (Unchanged) ---
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hapticOffset == 0.020 { hapticOffset = 0.050; audioOffset = 0.100 }
        else if hapticOffset == 0.050 { hapticOffset = 0.000; audioOffset = 0.040 }
        else { hapticOffset = 0.020; audioOffset = 0.040 }
        print("--- Touch ---"); print("Offsets -> H: \(String(format: "%.1f", hapticOffset * 1000))ms, A: \(String(format: "%.1f", audioOffset * 1000))ms"); print("---------------")
    }

    // --- Physics Contact Delegate Method (Unchanged) ---
    func didBegin(_ contact: SKPhysicsContact) { /* ... */ }
}
