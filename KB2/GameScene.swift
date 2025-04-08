// NeuroGlide/GameScene.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 7 Addendum: Log Actual Mean Speed
// Role: Main scene for the game. Includes basic arousal state linked to motion.

import SpriteKit
import GameplayKit
import CoreHaptics
import AVFoundation

// --- Game State Enum ---
enum GameState { case tracking, identifying, paused }

class GameScene: SKScene, SKPhysicsContactDelegate {

    // --- Configuration ---
    public var timerFrequency: Double = 5.0 { didSet { precisionTimer?.frequency = timerFrequency } }
    public var hapticOffset: TimeInterval = 0.020
    public var audioOffset: TimeInterval = 0.040
    let numberOfBalls = 10
    let numberOfTargets = 3
    let targetShiftInterval: TimeInterval = 5.0
    let identificationInterval: TimeInterval = 10.0
    let identificationDuration: TimeInterval = 5.0
    let identificationStartDelay: TimeInterval = 0.5
    let flashCooldownDuration: TimeInterval = 0.5
    let minTargetSpeedForArousal: CGFloat = 80.0
    let maxTargetSpeedForArousal: CGFloat = 700.0

    // --- Properties ---
    private var currentState: GameState = .tracking
    private var currentArousalLevel: CGFloat = 0.75 {
        didSet {
            currentArousalLevel = max(0.0, min(currentArousalLevel, 1.0))
            print("DIAGNOSTIC: Arousal Level Changed to \(String(format: "%.2f", currentArousalLevel))")
            updateParametersFromArousal()
        }
    }
    private var precisionTimer: PrecisionTimer?
    private var targetShiftTimerActionKey = "targetShiftTimer"
    private var identificationTimerActionKey = "identificationTimer"
    private var identificationTimeoutActionKey = "identificationTimeout"
    private var isFlashSequenceRunning: Bool = false
    private var flashCooldownEndTime: TimeInterval = 0.0
    private var identificationCheckNeeded: Bool = false
    private var balls: [Ball] = []
    private var motionSettings = MotionSettings()
    private var targetsToFind: Int = 0
    private var targetsFoundThisRound: Int = 0
    private var score: Int = 0
    private var scoreLabel: SKLabelNode!
    private var stateLabel: SKLabelNode!
    private var countdownLabel: SKLabelNode!
    private var arousalLabel: SKLabelNode!
    private var safeAreaTopInset: CGFloat = 0

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
        print("--- GameScene: didMove(to:) ---")
        backgroundColor = .darkGray
        safeAreaTopInset = view.safeAreaInsets.top
        setupPhysicsWorld(); setupWalls(); setupUI(); setupHaptics(); setupAudio()
        if hapticsReady { startHapticEngine() }
        if audioReady { startAudioEngine() }
        createBalls()
        if !balls.isEmpty { applyInitialImpulses() }
        setupTimer(); precisionTimer?.start()
        updateParametersFromArousal()
        startTrackingTimers(); updateUI()
        flashCooldownEndTime = CACurrentMediaTime()
        print("--- GameScene: didMove(to:) Finished ---")
    }

    override func willMove(from view: SKView) {
        print("--- GameScene: willMove(from:) ---")
        precisionTimer?.stop(); stopTrackingTimers(); stopIdentificationTimeout()
        stopHapticEngine(); stopAudioEngine()
        self.removeAction(forKey: "flashSequenceCompletion")
        balls.forEach { $0.removeFromParent() }; balls.removeAll()
        scoreLabel?.removeFromParent(); stateLabel?.removeFromParent(); countdownLabel?.removeFromParent(); arousalLabel?.removeFromParent()
        precisionTimer = nil; hapticEngine = nil; hapticPlayer = nil; customAudioEngine = nil; audioPlayerNode = nil; audioBuffer = nil
        print("GameScene cleaned up resources.")
        print("--- GameScene: willMove(from:) Finished ---")
    }

    // --- Physics Setup ---
    private func setupPhysicsWorld() { physicsWorld.gravity = CGVector(dx: 0, dy: 0); physicsWorld.contactDelegate = self }
    private func setupWalls() { let b = SKPhysicsBody(edgeLoopFrom: self.frame); b.friction = 0.0; b.restitution = 1.0; self.physicsBody = b }

    // --- UI Setup ---
    private func setupUI() {
        scoreLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light"); scoreLabel.fontSize = 20; scoreLabel.fontColor = .white
        scoreLabel.position = CGPoint(x: frame.minX + 20, y: frame.maxY - safeAreaTopInset - 30); scoreLabel.horizontalAlignmentMode = .left; addChild(scoreLabel)
        stateLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold"); stateLabel.fontSize = 24; stateLabel.fontColor = .yellow
        stateLabel.position = CGPoint(x: frame.midX, y: frame.maxY - safeAreaTopInset - 30); stateLabel.horizontalAlignmentMode = .center; addChild(stateLabel)
        countdownLabel = SKLabelNode(fontNamed: "HelveticaNeue-Medium"); countdownLabel.fontSize = 22; countdownLabel.fontColor = .orange
        countdownLabel.position = CGPoint(x: frame.midX, y: frame.maxY - safeAreaTopInset - 60); countdownLabel.horizontalAlignmentMode = .center; countdownLabel.isHidden = true; addChild(countdownLabel)
        arousalLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light"); arousalLabel.fontSize = 16; arousalLabel.fontColor = .lightGray
        arousalLabel.position = CGPoint(x: frame.maxX - 20, y: frame.maxY - safeAreaTopInset - 30); arousalLabel.horizontalAlignmentMode = .right; addChild(arousalLabel)
    }

    // --- UI Update ---
    private func updateUI() {
        scoreLabel.text = "Score: \(score)"
        arousalLabel.text = "Arousal: \(String(format: "%.2f", currentArousalLevel))"
        switch currentState {
        case .tracking: stateLabel.text = "Tracking"; stateLabel.fontColor = .yellow; countdownLabel.isHidden = true
        case .identifying: stateLabel.text = "Identify!"; stateLabel.fontColor = .red
        case .paused: stateLabel.text = "Paused"; stateLabel.fontColor = .gray; countdownLabel.isHidden = true
        }
    }

    // --- Ball Creation ---
    private func createBalls() {
         guard balls.isEmpty else { return }
         guard numberOfTargets <= numberOfBalls else { return }
         guard self.frame.width > 0 && self.frame.height > 0 else { return }
         for i in 0..<numberOfBalls {
             let buffer: CGFloat = Ball.defaultRadius * 2.5; let safeFrame = self.frame.insetBy(dx: buffer, dy: buffer)
             var startPosition: CGPoint
             if safeFrame.width <= 0 || safeFrame.height <= 0 {
                 let smallerBuffer = Ball.defaultRadius * 1.25; let smallerSafeFrame = self.frame.insetBy(dx: smallerBuffer, dy: smallerBuffer)
                 guard smallerSafeFrame.width > 0 && smallerSafeFrame.height > 0 else { continue }
                 startPosition = CGPoint(x: CGFloat.random(in: smallerSafeFrame.minX ..< smallerSafeFrame.maxX), y: CGFloat.random(in: smallerSafeFrame.minY ..< smallerSafeFrame.maxY))
             } else {
                 startPosition = CGPoint(x: CGFloat.random(in: safeFrame.minX ..< safeFrame.maxX), y: CGFloat.random(in: safeFrame.minY ..< safeFrame.maxY))
             }
             let newBall = Ball(isTarget: false, position: startPosition); newBall.name = "ball_\(i)"
             balls.append(newBall); addChild(newBall)
         }
         if !balls.isEmpty { assignNewTargets(flashNewTargets: false) }
    }
    private func applyInitialImpulses() { balls.forEach { $0.applyRandomImpulse() } }

    // --- Target Shift Logic ---
    private func assignNewTargets(flashNewTargets: Bool) {
        guard numberOfTargets <= balls.count, !balls.isEmpty else { return }
        let shuffledBalls = balls.shuffled(); var newlyAssignedTargets: [Ball] = []; var assignmentsMade = 0
        for (index, ball) in shuffledBalls.enumerated() {
            let shouldBeTarget = index < numberOfTargets
            if ball.isTarget != shouldBeTarget { ball.isTarget = shouldBeTarget; assignmentsMade += 1; if shouldBeTarget { newlyAssignedTargets.append(ball) } }
        }
        if flashNewTargets && !newlyAssignedTargets.isEmpty {
            // print("DIAGNOSTIC: assignNewTargets - Flashing \(newlyAssignedTargets.count) new targets.")
            self.isFlashSequenceRunning = true
            newlyAssignedTargets.forEach { $0.flashAsNewTarget() }
            let flashEndTime = CACurrentMediaTime() + Ball.flashDuration
            self.flashCooldownEndTime = flashEndTime + flashCooldownDuration
            // print("DIAGNOSTIC: Flash sequence started. Cooldown ends at: \(self.flashCooldownEndTime)")
             let waitAction = SKAction.wait(forDuration: Ball.flashDuration)
             let clearSequenceFlagAction = SKAction.run { [weak self] in
                 // print("DIAGNOSTIC: Flash sequence Action finished.")
                 self?.isFlashSequenceRunning = false
             }
             self.run(SKAction.sequence([waitAction, clearSequenceFlagAction]), withKey: "flashSequenceCompletion")
        }
    }

    // --- Tracking Timers ---
    private func startTrackingTimers() {
        // Target Shift Timer
        stopTargetShiftTimer()
        let waitShift = SKAction.wait(forDuration: targetShiftInterval)
        let performShift = SKAction.run { [weak self] in
            guard let self = self, self.currentState == .tracking else { return }
            self.assignNewTargets(flashNewTargets: true)
        }
        self.run(SKAction.repeatForever(.sequence([waitShift, performShift])), withKey: targetShiftTimerActionKey)

        // Identification Trigger Timer (sets flag only)
        stopIdentificationTimer()
        let waitIdentify = SKAction.wait(forDuration: identificationInterval)
        let setCheckNeededFlagAction = SKAction.run { [weak self] in
            guard let self = self else { return }
            // print("DIAGNOSTIC: ID Timer Fired - Setting identificationCheckNeeded = true")
            self.identificationCheckNeeded = true
        }
        self.run(SKAction.repeatForever(.sequence([waitIdentify, setCheckNeededFlagAction])), withKey: identificationTimerActionKey)
    }
    private func stopTrackingTimers() { stopTargetShiftTimer(); stopIdentificationTimer() }
    private func stopTargetShiftTimer() { self.removeAction(forKey: targetShiftTimerActionKey) }
    private func stopIdentificationTimer() { self.removeAction(forKey: identificationTimerActionKey) }

    // --- Identification Phase Logic ---
    private func startIdentificationPhase() {
        print("--- Starting Identification Phase ---")
        currentState = .identifying; updateUI()
        physicsWorld.speed = 0; balls.forEach { ball in ball.storedVelocity = ball.physicsBody?.velocity; ball.physicsBody?.velocity = .zero; ball.physicsBody?.isDynamic = false }
        targetsToFind = 0; targetsFoundThisRound = 0
        guard !balls.isEmpty else { endIdentificationPhase(success: false); return }
        for ball in balls { if ball.isTarget { targetsToFind += 1 }; ball.hideIdentity() }
        let waitBeforeCountdown = SKAction.wait(forDuration: identificationStartDelay)
        let startCountdownAction = SKAction.run { [weak self] in self?.startIdentificationTimeout() }
        self.run(SKAction.sequence([waitBeforeCountdown, startCountdownAction]))
    }
    private func startIdentificationTimeout() {
        stopIdentificationTimeout(); var remainingTime = identificationDuration
        countdownLabel.text = String(format: "Time: %.1f", remainingTime); countdownLabel.isHidden = false
        let wait = SKAction.wait(forDuration: 0.1); let update = SKAction.run { [weak self] in guard let self = self, self.currentState == .identifying else { self?.stopIdentificationTimeout(); return }; remainingTime -= 0.1; self.countdownLabel.text = String(format: "Time: %.1f", max(0, remainingTime)) }
        let countdownAction = SKAction.repeat(.sequence([wait, update]), count: Int(identificationDuration / 0.1))
        let timeoutAction = SKAction.run { [weak self] in print("--- Identification Timeout! ---"); self?.endIdentificationPhase(success: false) }
        self.run(.sequence([countdownAction, timeoutAction]), withKey: identificationTimeoutActionKey)
    }
    private func stopIdentificationTimeout() { self.removeAction(forKey: identificationTimeoutActionKey); countdownLabel.isHidden = true }
    private func endIdentificationPhase(success: Bool) {
        guard currentState == .identifying else { return }
        print("--- Ending Identification Phase (Success: \(success)) ---"); stopIdentificationTimeout()
        if success { print("Correct!"); score += 1 } else { print("Incorrect/Timeout.") }
        balls.forEach { $0.revealIdentity() }
        balls.forEach { ball in ball.physicsBody?.isDynamic = true; ball.physicsBody?.velocity = ball.storedVelocity ?? .zero; ball.storedVelocity = nil }; physicsWorld.speed = 1
        currentState = .tracking; updateUI()
        startTrackingTimers() // Restart timers
    }

    // --- Touch Handling ---
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.count == 2 {
            cycleArousalLevel(); return
        }
        guard currentState == .identifying else {
            if currentState == .tracking && touches.count == 1 { changeOffsetsOnTouch() }
            return
        }
        if touches.count == 1 {
            for touch in touches {
                let location = touch.location(in: self); let tappedNodes = nodes(at: location)
                for node in tappedNodes { if let tappedBall = node as? Ball { handleBallTap(tappedBall); break } }
            }
        }
    }
    private func handleBallTap(_ ball: Ball) {
        guard currentState == .identifying else { return }
        let targetTexture = Ball.createTexture(color: Ball.Appearance.targetColor); let currentTexture = ball.texture
        if ball.isTarget {
            if currentTexture != targetTexture { targetsFoundThisRound += 1; ball.revealIdentity(); if targetsFoundThisRound >= targetsToFind { endIdentificationPhase(success: true) } }
        } else { endIdentificationPhase(success: false) }
    }
    private func changeOffsetsOnTouch() {
        if hapticOffset == 0.020 { hapticOffset = 0.050; audioOffset = 0.100 }
        else if hapticOffset == 0.050 { hapticOffset = 0.000; audioOffset = 0.040 }
        else { hapticOffset = 0.020; audioOffset = 0.040 }
        print("--- Touch (Tracking) --- Offsets -> H:\(String(format: "%.1f", hapticOffset*1000)) A:\(String(format: "%.1f", audioOffset*1000)) ---")
    }

    // --- Arousal Handling ---
    private func cycleArousalLevel() {
        let steps: [CGFloat] = [0.25, 0.50, 0.75, 1.00]
        if let currentIndex = steps.firstIndex(where: { abs($0 - currentArousalLevel) < 0.01 }) {
            let nextIndex = (currentIndex + 1) % steps.count
            currentArousalLevel = steps[nextIndex]
        } else {
            currentArousalLevel = steps.first ?? 0.25
        }
    }
    private func updateParametersFromArousal() {
        let speedRange = maxTargetSpeedForArousal - minTargetSpeedForArousal
        motionSettings.targetMeanSpeed = minTargetSpeedForArousal + (speedRange * currentArousalLevel)
        // print("DIAGNOSTIC: Parameters updated for arousal \(String(format: "%.2f", currentArousalLevel)). TargetSpeed: \(String(format: "%.1f", motionSettings.targetMeanSpeed))") // Less verbose
        updateUI()
    }

    // --- Haptic Setup ---
    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { hapticsReady = false; return }
        do { hapticEngine = try CHHapticEngine(); hapticEngine?.playsHapticsOnly = false; let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8); let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6); let e = CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0); let p = try CHHapticPattern(events: [e], parameters: []); hapticPlayer = try hapticEngine?.makePlayer(with: p); hapticEngine?.stoppedHandler = { [weak self] r in print("Haptic stopped: \(r)"); self?.hapticsReady = false }; hapticEngine?.resetHandler = { [weak self] in print("Haptic reset."); self?.startHapticEngine() }; hapticsReady = true } catch { print("DIAGNOSTIC: setupHaptics - Error: \(error.localizedDescription)"); hapticsReady = false }
    }
    private func startHapticEngine() {
         guard hapticsReady, let engine = hapticEngine else { print("DIAGNOSTIC: startHapticEngine - Aborted. Ready:\(hapticsReady), Engine:\(self.hapticEngine != nil)."); return }
         do { try engine.start() } catch { print("DIAGNOSTIC: startHapticEngine - Error: \(error.localizedDescription)"); hapticsReady = false }
    }
    private func stopHapticEngine() {
         guard let engine = hapticEngine else { return }; engine.stop { e in if let err = e { print("Error stopping haptic: \(err.localizedDescription)") } }; hapticsReady = false
    }

    // --- Audio Setup ---
    private func setupAudio() {
        customAudioEngine = AVAudioEngine(); audioPlayerNode = AVAudioPlayerNode()
        guard let engine = customAudioEngine, let playerNode = audioPlayerNode else { audioReady = false; return }
        do { engine.attach(playerNode); audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1); guard let format = audioFormat else { audioReady = false; return }; let sr = Float(format.sampleRate); let fq: Float = 440.0; let dur: Float = 0.1; let fc = AVAudioFrameCount(sr * dur); audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: fc); guard let buffer = audioBuffer else { audioReady = false; return }; buffer.frameLength = fc; guard let cd = buffer.floatChannelData?[0] else { audioReady = false; return }; let amp: Float = 0.5; let af = 2 * .pi * fq / sr; for frame in 0..<Int(fc) { cd[frame] = sin(Float(frame) * af) * amp }; engine.connect(playerNode, to: engine.mainMixerNode, format: format); try engine.prepare(); audioReady = true } catch { print("DIAGNOSTIC: setupAudio - Error: \(error.localizedDescription)"); audioReady = false }
    }
    private func startAudioEngine() {
         guard audioReady, let engine = customAudioEngine else { print("DIAGNOSTIC: startAudioEngine - Aborted. Ready:\(audioReady), Engine:\(self.customAudioEngine != nil)."); return }
         if engine.isRunning { return }
         do { try engine.start() } catch { print("DIAGNOSTIC: startAudioEngine - Error: \(error.localizedDescription)"); audioReady = false }
    }
    private func stopAudioEngine() {
        guard let engine = customAudioEngine else { return }; if engine.isRunning { engine.stop() }; audioReady = false
    }

    // --- Timer Setup ---
    private func setupTimer() {
        precisionTimer = PrecisionTimer(); precisionTimer?.frequency = timerFrequency
        precisionTimer?.onVisualTick = { [weak self] in self?.handleVisualTick() }
        precisionTimer?.onHapticTick = { [weak self] t in self?.handleHapticTick(visualTickTime: t) }; precisionTimer?.onAudioTick = { [weak self] t in self?.handleAudioTick(visualTickTime: t) }
    }

    // --- Timer Callback Handlers ---
    private func handleVisualTick() {
        guard currentState == .tracking else { return }; guard !balls.isEmpty else { return }
        let pulseAction = SKAction.sequence([.scale(to: 1.15, duration: 0.05), .scale(to: 1.0, duration: 0.15)]); balls.forEach { $0.run(pulseAction) }
    }
    private func handleHapticTick(visualTickTime: CFTimeInterval) {
        guard currentState == .tracking else { return }
        guard hapticsReady, let player = hapticPlayer else { return }
        let hapticStartTime = visualTickTime + hapticOffset; do { try player.start(atTime: hapticStartTime) } catch { print("Error scheduling haptic player: \(error.localizedDescription)") }
    }
    private func handleAudioTick(visualTickTime: CFTimeInterval) {
        guard currentState == .tracking else { return }
        guard audioReady, let initialEngine = customAudioEngine, let initialPlayerNode = audioPlayerNode, let initialBuffer = audioBuffer else { return }
        guard initialEngine.isRunning else { return }
        let audioStartTime = visualTickTime + audioOffset; let currentTime = CACurrentMediaTime(); let delayUntilStartTime = max(0, audioStartTime - currentTime)
        DispatchQueue.main.asyncAfter(deadline: .now() + delayUntilStartTime) { [weak self] in
            guard let self = self else { return }
            guard self.currentState == .tracking, self.audioReady else { return }
            guard let currentEngine = self.customAudioEngine, currentEngine.isRunning,
                  let currentPlayerNode = self.audioPlayerNode, currentPlayerNode === initialPlayerNode,
                  let currentBuffer = self.audioBuffer, currentBuffer === initialBuffer
            else { return }
            currentPlayerNode.scheduleBuffer(currentBuffer, at: nil, options: .interrupts) { }; if !currentPlayerNode.isPlaying { currentPlayerNode.play() }
        }
    }

    // --- Update Loop ---
    // MODIFIED: Added actual mean speed logging
    override func update(_ currentTime: TimeInterval) {
        // --- Identification Phase Check ---
        if identificationCheckNeeded {
            if currentState == .tracking && !isFlashSequenceRunning && currentTime >= flashCooldownEndTime {
                startIdentificationPhase()
                identificationCheckNeeded = false // Consume flag ONLY if starting
            }
        }

        // --- Motion Control & Logging ---
        if currentState == .tracking && !balls.isEmpty {
            // Calculate stats *before* applying corrections for accurate logging
            let stats = MotionController.calculateStats(balls: balls)

            // Log the actual vs target mean speed
            // Reduce frequency of logging to avoid spamming console (e.g., every 60 frames ~ 1s)
            if Int(currentTime * 60) % 60 == 0 {
                 print(String(format: "Motion Speed - Actual Mean: %.1f (Target: %.1f)",
                              stats.meanSpeed, motionSettings.targetMeanSpeed))
            }

            // Apply corrections using the potentially updated settings
            MotionController.applyCorrections(balls: balls, settings: motionSettings, scene: self)
        }
    }

    // --- Physics Contact Delegate Method ---
    func didBegin(_ contact: SKPhysicsContact) { }
}

// --- Ball.swift needs the flashDuration constant added ---
