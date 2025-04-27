// NeuroGlide/GameScene.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 11 FIX 10 (COMPLETE FILE - Debug ID Taps)
// Role: Main scene. Debugging ID tap registration.

import SpriteKit
import GameplayKit
import CoreHaptics
import AVFoundation

// --- Game State Enum ---
enum GameState { case tracking, identifying, paused, breathing }

// --- Breathing Phase Enum ---
enum BreathingPhase { case idle, inhale, holdAfterInhale, exhale, holdAfterExhale }

class GameScene: SKScene, SKPhysicsContactDelegate {

    // --- Configuration ---
    private let gameConfiguration = GameConfiguration()

    // --- Properties ---
    private var currentState: GameState = .tracking
    private var _currentArousalLevel: CGFloat = 0.75 // Backing variable
    private var currentArousalLevel: CGFloat {
        get { return _currentArousalLevel }
        set {
            let oldValue = _currentArousalLevel
            let clampedValue = max(0.0, min(newValue, 1.0))
            if clampedValue != _currentArousalLevel {
                _currentArousalLevel = clampedValue
                print("DIAGNOSTIC: Arousal Level Changed to \(String(format: "%.2f", _currentArousalLevel))")
                checkStateTransition(oldValue: oldValue, newValue: _currentArousalLevel)
                updateParametersFromArousal()
                checkBreathingFade()
            }
        }
    }
    private var currentBreathingPhase: BreathingPhase = .idle
    private var breathingAnimationActionKey = "breathingAnimation"
    private var precisionTimer: PrecisionTimer?
    private var targetShiftTimerActionKey = "targetShiftTimer"
    private var identificationTimerActionKey = "identificationTimer"
    private var identificationTimeoutActionKey = "identificationTimeout"
    private var isFlashSequenceRunning: Bool = false
    private var flashCooldownEndTime: TimeInterval = 0.0
    private var identificationCheckNeeded: Bool = false
    private var timeUntilNextShift: TimeInterval = 0
    private var timeUntilNextIDCheck: TimeInterval = 0
    private var currentMinShiftInterval: TimeInterval = 5.0
    private var currentMaxShiftInterval: TimeInterval = 10.0
    private var currentMinIDInterval: TimeInterval = 10.0
    private var currentMaxIDInterval: TimeInterval = 15.0
    private var balls: [Ball] = []
    private var motionSettings = MotionSettings()
    private var currentTargetCount: Int = GameConfiguration().maxTargetsAtLowTrackingArousal
    private var currentIdentificationDuration: TimeInterval = GameConfiguration().identificationDuration
    private var activeTargetColor: SKColor = GameConfiguration().targetColor_LowArousal
    private var activeDistractorColor: SKColor = GameConfiguration().distractorColor_LowArousal
    private var targetsToFind: Int = 0
    private var targetsFoundThisRound: Int = 0
    private var score: Int = 0
    private var scoreLabel: SKLabelNode!
    private var stateLabel: SKLabelNode!
    private var countdownLabel: SKLabelNode!
    private var arousalLabel: SKLabelNode!
    private var breathingCueLabel: SKLabelNode!
    private var safeAreaTopInset: CGFloat = 0
    private var breathingVisualsFaded: Bool = false
    private var fadeOverlayNode: SKSpriteNode!

    // --- Feedback Properties ---
    private var correctTapEmitterTemplate: SKEmitterNode?
    private var activeParticleEmitters: [Ball: SKEmitterNode] = [:]
    private var correctTapPlayer: AVAudioPlayer?
    private var groupCompletePlayer: AVAudioPlayer?

    // --- Haptic Engine ---
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?
    private var breathingHapticPlayer: CHHapticPatternPlayer?
    private var hapticsReady: Bool = false

    // --- Audio Engine ---
    private var customAudioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioBuffer: AVAudioPCMBuffer?
    private var audioFormat: AVAudioFormat?
    private var audioReady: Bool = false

    // --- Rhythmic Pulse Properties ---
    private var currentTimerFrequency: Double = 5.0 {
         didSet {
             if currentTimerFrequency <= 0 { currentTimerFrequency = 1.0 }
             precisionTimer?.frequency = currentTimerFrequency
         }
     }
    public var hapticOffset: TimeInterval = 0.020
    public var audioOffset: TimeInterval = 0.040

    // --- Helper: Delta Time ---
    private var lastUpdateTime: TimeInterval = 0

    // --- Initializers ---
    override init(size: CGSize) {
        scoreLabel = SKLabelNode()
        stateLabel = SKLabelNode()
        countdownLabel = SKLabelNode()
        arousalLabel = SKLabelNode()
        breathingCueLabel = SKLabelNode()
        fadeOverlayNode = SKSpriteNode()
        super.init(size: size)
    }
    required init?(coder aDecoder: NSCoder) {
        scoreLabel = SKLabelNode()
        stateLabel = SKLabelNode()
        countdownLabel = SKLabelNode()
        arousalLabel = SKLabelNode()
        breathingCueLabel = SKLabelNode()
        fadeOverlayNode = SKSpriteNode()
        super.init(coder: aDecoder)
    }

    // --- Scene Lifecycle ---
    override func didMove(to view: SKView) {
        print("--- GameScene: didMove(to:) ---")
        backgroundColor = .darkGray
        safeAreaTopInset = view.safeAreaInsets.top
        setupPhysicsWorld(); setupWalls(); setupUI(); setupHaptics(); setupAudio()
        setupFadeOverlay() // Setup overlay
        setupFeedbackAssets() // Load particles and sounds
        if hapticsReady { startHapticEngine() }
        if audioReady { startAudioEngine() }
        updateParametersFromArousal()
        createBalls()
        if !balls.isEmpty { applyInitialImpulses() }
        setupTimer();
        precisionTimer?.start()
        startTrackingTimers(); updateUI()
        flashCooldownEndTime = CACurrentMediaTime()
        print("--- GameScene: didMove(to:) Finished ---")
    }

    override func willMove(from view: SKView) {
        print("--- GameScene: willMove(from:) ---")
        precisionTimer?.stop(); // stopTrackingTimers();
        stopIdentificationTimeout()
        stopBreathingAnimation()
        stopHapticEngine(); stopAudioEngine()
        correctTapPlayer?.stop(); groupCompletePlayer?.stop() // Stop feedback sounds
        self.removeAction(forKey: "flashSequenceCompletion"); self.removeAction(forKey: breathingAnimationActionKey)
        balls.forEach { $0.removeFromParent() }; balls.removeAll()
        scoreLabel.removeFromParent(); stateLabel.removeFromParent(); countdownLabel.removeFromParent(); arousalLabel.removeFromParent(); breathingCueLabel.removeFromParent()
        fadeOverlayNode.removeFromParent()
        breathingHapticPlayer = nil; hapticPlayer = nil
        correctTapEmitterTemplate = nil; activeParticleEmitters.removeAll() // Clear feedback assets
        correctTapPlayer = nil; groupCompletePlayer = nil
        precisionTimer = nil; hapticEngine = nil; customAudioEngine = nil; audioPlayerNode = nil; audioBuffer = nil
        print("GameScene cleaned up resources.")
        print("--- GameScene: willMove(from:) Finished ---")
    }

    // --- Physics Setup ---
    private func setupPhysicsWorld() { physicsWorld.gravity = CGVector(dx: 0, dy: 0); physicsWorld.contactDelegate = self }
    private func setupWalls() { let b = SKPhysicsBody(edgeLoopFrom: self.frame); b.friction = 0.0; b.restitution = 1.0; self.physicsBody = b }

    // --- UI Setup ---
    private func setupUI() {
        scoreLabel.fontName = "HelveticaNeue-Light"; scoreLabel.fontSize = 20; scoreLabel.fontColor = .white
        scoreLabel.position = CGPoint(x: frame.minX + 20, y: frame.maxY - safeAreaTopInset - 30); scoreLabel.horizontalAlignmentMode = .left; addChild(scoreLabel)
        stateLabel.fontName = "HelveticaNeue-Bold"; stateLabel.fontSize = 24; stateLabel.fontColor = .yellow
        stateLabel.position = CGPoint(x: frame.midX, y: frame.maxY - safeAreaTopInset - 30); stateLabel.horizontalAlignmentMode = .center; addChild(stateLabel)
        countdownLabel.fontName = "HelveticaNeue-Medium"; countdownLabel.fontSize = 22; countdownLabel.fontColor = .orange
        countdownLabel.position = CGPoint(x: frame.midX, y: frame.maxY - safeAreaTopInset - 60); countdownLabel.horizontalAlignmentMode = .center; countdownLabel.isHidden = true; addChild(countdownLabel)
        arousalLabel.fontName = "HelveticaNeue-Light"; arousalLabel.fontSize = 16; arousalLabel.fontColor = .lightGray
        arousalLabel.position = CGPoint(x: frame.maxX - 20, y: frame.maxY - safeAreaTopInset - 30); arousalLabel.horizontalAlignmentMode = .right; addChild(arousalLabel)
        breathingCueLabel.fontName = "HelveticaNeue-Bold"; breathingCueLabel.fontSize = 36; breathingCueLabel.fontColor = .white
        breathingCueLabel.position = CGPoint(x: frame.midX, y: frame.midY + 50); breathingCueLabel.horizontalAlignmentMode = .center; breathingCueLabel.isHidden = true; addChild(breathingCueLabel)
    }
    // MODIFIED: Disable user interaction on overlay
    private func setupFadeOverlay() {
        fadeOverlayNode.color = .black; fadeOverlayNode.size = self.size
        fadeOverlayNode.position = CGPoint(x: frame.midX, y: frame.midY)
        fadeOverlayNode.zPosition = 100; fadeOverlayNode.alpha = 0.0
        fadeOverlayNode.isUserInteractionEnabled = false // Explicitly disable interaction
        if fadeOverlayNode.parent == nil { addChild(fadeOverlayNode) }
    }

    // --- UI Update ---
    private func updateUI() {
        scoreLabel.text = "Score: \(score)"
        arousalLabel.text = "Arousal: \(String(format: "%.2f", currentArousalLevel))"
        switch currentState {
        case .tracking: stateLabel.text = "Tracking"; stateLabel.fontColor = .yellow; countdownLabel.isHidden = true; breathingCueLabel.isHidden = true
        case .identifying: stateLabel.text = "Identify!"; stateLabel.fontColor = .red; countdownLabel.isHidden = false; breathingCueLabel.isHidden = true
        case .breathing: stateLabel.text = "Breathing"; stateLabel.fontColor = .systemBlue; countdownLabel.isHidden = true; breathingCueLabel.isHidden = false
        case .paused: stateLabel.text = "Paused"; stateLabel.fontColor = .gray; countdownLabel.isHidden = true; breathingCueLabel.isHidden = true
        }
    }

    // --- Ball Creation ---
    private func createBalls() {
         guard balls.isEmpty else { return }
         guard currentTargetCount <= gameConfiguration.numberOfBalls else { return }
         guard self.frame.width > 0 && self.frame.height > 0 else { return }
         for i in 0..<gameConfiguration.numberOfBalls {
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
             newBall.updateAppearance(targetColor: activeTargetColor, distractorColor: activeDistractorColor)
             balls.append(newBall); addChild(newBall)
         }
         if !balls.isEmpty { assignNewTargets(flashNewTargets: false) }
    }
    private func applyInitialImpulses() { balls.forEach { $0.applyRandomImpulse() } }

    // --- Target Shift Logic ---
    private func assignNewTargets(flashNewTargets: Bool) {
        guard currentTargetCount <= balls.count, !balls.isEmpty else { return }
        let shuffledBalls = balls.shuffled(); var newlyAssignedTargets: [Ball] = []; var assignmentsMade = 0
        for (index, ball) in shuffledBalls.enumerated() {
            let shouldBeTarget = index < currentTargetCount
            if ball.isTarget != shouldBeTarget {
                ball.isTarget = shouldBeTarget
                ball.updateAppearance(targetColor: activeTargetColor, distractorColor: activeDistractorColor)
                assignmentsMade += 1
                if shouldBeTarget { newlyAssignedTargets.append(ball) }
            }
        }
        if flashNewTargets && !newlyAssignedTargets.isEmpty {
            self.isFlashSequenceRunning = true
            newlyAssignedTargets.forEach { $0.flashAsNewTarget(targetColor: activeTargetColor, flashColor: gameConfiguration.flashColor) }
            let flashEndTime = CACurrentMediaTime() + Ball.flashDuration
            self.flashCooldownEndTime = flashEndTime + gameConfiguration.flashCooldownDuration
             let waitAction = SKAction.wait(forDuration: Ball.flashDuration)
             let clearSequenceFlagAction = SKAction.run { [weak self] in
                 self?.isFlashSequenceRunning = false
             }
             self.run(SKAction.sequence([waitAction, clearSequenceFlagAction]), withKey: "flashSequenceCompletion")
        }
    }

    // --- Tracking Timers ---
    private func startTrackingTimers() {
        resetShiftTimer()
        resetIDTimer()
    }
    private func resetShiftTimer() {
        timeUntilNextShift = TimeInterval.random(in: currentMinShiftInterval...currentMaxShiftInterval)
    }
    private func resetIDTimer() {
        timeUntilNextIDCheck = TimeInterval.random(in: currentMinIDInterval...currentMaxIDInterval)
    }
    // Removed stop functions

    // --- Identification Phase Logic ---
    private func startIdentificationPhase() {
        print("--- Starting Identification Phase ---")
        currentState = .identifying; updateUI()
        physicsWorld.speed = 0; balls.forEach { ball in ball.storedVelocity = ball.physicsBody?.velocity; ball.physicsBody?.velocity = .zero; ball.physicsBody?.isDynamic = false }
        targetsToFind = 0; targetsFoundThisRound = 0
        guard !balls.isEmpty else { endIdentificationPhase(success: false); return }
        self.targetsToFind = self.currentTargetCount
        // Hide using the *current* active distractor color
        print("DIAGNOSTIC: Hiding balls with distractor color: \(activeDistractorColor.description)")
        for ball in balls { ball.hideIdentity(hiddenColor: self.activeDistractorColor) } // Pass active color
        let waitBeforeCountdown = SKAction.wait(forDuration: gameConfiguration.identificationStartDelay)
        let startCountdownAction = SKAction.run { [weak self] in self?.startIdentificationTimeout() }
        self.run(SKAction.sequence([waitBeforeCountdown, startCountdownAction]))
    }
    private func startIdentificationTimeout() {
        stopIdentificationTimeout()
        var remainingTime = currentIdentificationDuration
        guard remainingTime > 0 else { endIdentificationPhase(success: false); return }
        countdownLabel.text = String(format: "Time: %.1f", remainingTime); countdownLabel.isHidden = false
        let wait = SKAction.wait(forDuration: 0.1); let update = SKAction.run { [weak self] in guard let self = self, self.currentState == .identifying else { self?.stopIdentificationTimeout(); return }; remainingTime -= 0.1; self.countdownLabel.text = String(format: "Time: %.1f", max(0, remainingTime)) }
        let repeatCount = Int(currentIdentificationDuration / 0.1)
        let countdownAction = SKAction.repeat(.sequence([wait, update]), count: repeatCount)
        let timeoutAction = SKAction.run { [weak self] in print("--- Identification Timeout! ---"); self?.endIdentificationPhase(success: false) }
        self.run(.sequence([countdownAction, timeoutAction]), withKey: identificationTimeoutActionKey)
    }
    private func stopIdentificationTimeout() { self.removeAction(forKey: identificationTimeoutActionKey); countdownLabel.isHidden = true }
    private func endIdentificationPhase(success: Bool) {
        guard currentState == .identifying else { return }
        print("--- Ending Identification Phase (Success: \(success)) ---"); stopIdentificationTimeout()

        // --- Remove Active Particle Emitters ---
        for (_, emitter) in activeParticleEmitters {
            emitter.removeFromParent()
        }
        activeParticleEmitters.removeAll()
        // --------------------------------------

        if success { print("Correct!"); score += 1 } else { print("Incorrect/Timeout.") }
        balls.forEach { $0.revealIdentity(targetColor: activeTargetColor, distractorColor: activeDistractorColor) }
        balls.forEach { ball in ball.physicsBody?.isDynamic = true; ball.physicsBody?.velocity = ball.storedVelocity ?? .zero; ball.storedVelocity = nil }; physicsWorld.speed = 1
        currentState = .tracking
        updateUI()
        startTrackingTimers()
    }

    // --- Touch Handling ---
    // MODIFIED: Added diagnostics
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("DEBUG: touchesBegan - Count: \(touches.count), State: \(currentState)") // DEBUG
        if touches.count == 3 { incrementArousalLevel(); return }
        if touches.count == 2 { decrementArousalLevel(); return }

        guard currentState == .identifying else {
            if currentState == .tracking && touches.count == 1 { changeOffsetsOnTouch() }
            return
        }

        // Handle single taps during identification phase
        if touches.count == 1 {
            for touch in touches {
                let location = touch.location(in: self)
                let tappedNodes = nodes(at: location)
                print("DEBUG: Tap at \(location). Nodes hit: \(tappedNodes.map { $0.name ?? "Unnamed" })") // DEBUG
                for node in tappedNodes {
                    if let tappedBall = node as? Ball {
                        print("DEBUG: Ball node identified: \(tappedBall.name ?? "Unknown")") // DEBUG
                        handleBallTap(tappedBall)
                        break // Process only the first ball tapped
                    } else {
                        // Allow touches to pass through overlay if needed, but log what was hit
                        // print("DEBUG: Tapped node is not a Ball: \(node.name ?? "Unnamed"), Type: \(type(of: node))")
                    }
                }
            }
        }
    }
    // MODIFIED: Use isVisuallyHidden flag instead of color comparison
    private func handleBallTap(_ ball: Ball) {
        guard currentState == .identifying else { return }
        print("DEBUG: handleBallTap called for \(ball.name ?? "Unknown"). IsTarget: \(ball.isTarget), IsHidden: \(ball.isVisuallyHidden)") // DEBUG

        // Check if the ball is currently hidden visually and hasn't already been correctly identified (no emitter attached)
        if ball.isVisuallyHidden && activeParticleEmitters[ball] == nil {
            if ball.isTarget {
                print("DEBUG: Correct tap on hidden target.")
                targetsFoundThisRound += 1
                ball.revealIdentity(targetColor: activeTargetColor, distractorColor: activeDistractorColor) // Reveal it

                // --- Calculate Feedback Salience based on Arousal ---
                let minArousal = gameConfiguration.feedbackMinArousalThreshold
                let maxArousal = gameConfiguration.feedbackMaxArousalThreshold
                var normalizedFeedbackArousal: CGFloat = 0.0
                if currentArousalLevel >= minArousal {
                    let arousalRange = maxArousal - minArousal
                    if arousalRange > 0 {
                        normalizedFeedbackArousal = min(1.0, (currentArousalLevel - minArousal) / arousalRange)
                    } else if currentArousalLevel >= maxArousal {
                        normalizedFeedbackArousal = 1.0 // Handle edge case where min == max
                    }
                }
                // -----------------------------------------------------

                // --- Add Visual Feedback (Particle Emitter) ---
                if normalizedFeedbackArousal > 0, let template = correctTapEmitterTemplate {
                    let emitter = template.copy() as! SKEmitterNode
                    // Map arousal to emitter properties (e.g., birth rate, scale)
                    emitter.particleBirthRate = gameConfiguration.particleFeedbackMaxBirthRate * normalizedFeedbackArousal
                    emitter.particleScale = gameConfiguration.particleFeedbackMaxScale * normalizedFeedbackArousal
                    emitter.targetNode = self // Particles should move relative to the scene
                    ball.addChild(emitter) // Attach to the ball
                    activeParticleEmitters[ball] = emitter // Track it
                    // print("DIAGNOSTIC: Added particle emitter to \(ball.name ?? "Unknown") with birthRate: \(emitter.particleBirthRate)")
                }
                // -----------------------------------------------

                // --- Play Audio Feedback (Correct Tap) ---
                if normalizedFeedbackArousal > 0, let player = correctTapPlayer {
                    player.volume = gameConfiguration.audioFeedbackMaxVolume * Float(normalizedFeedbackArousal)
                    player.currentTime = 0 // Rewind
                    player.play()
                    // print("DIAGNOSTIC: Played correct tap sound with volume: \(player.volume)")
                }
                // -------------------------------------------

                // --- Check for Round Completion ---
                if targetsFoundThisRound >= targetsToFind {
                    // --- Play Audio Feedback (Group Complete) ---
                    if normalizedFeedbackArousal > 0, let player = groupCompletePlayer {
                        player.volume = gameConfiguration.audioFeedbackMaxVolume * Float(normalizedFeedbackArousal)
                        player.currentTime = 0 // Rewind
                        player.play()
                        // print("DIAGNOSTIC: Played group complete sound with volume: \(player.volume)")
                    }
                    // --------------------------------------------
                    endIdentificationPhase(success: true)
                }
                // -----------------------------------

            } else {
                // Tapped a hidden distractor
                print("DEBUG: Incorrect tap on hidden distractor.")
                endIdentificationPhase(success: false)
            }
        } else {
            // Ball was likely already revealed or tapped incorrectly before
            print("DEBUG: Tap on already revealed or previously tapped ball.")
            // Optional: Add penalty for tapping revealed ball? For now, do nothing.
        }
    }
    private func changeOffsetsOnTouch() {
        if hapticOffset == 0.020 { hapticOffset = 0.050; audioOffset = 0.100 }
        else if hapticOffset == 0.050 { hapticOffset = 0.000; audioOffset = 0.040 }
        else { hapticOffset = 0.020; audioOffset = 0.040 }
        print("--- Touch (Tracking) --- Offsets -> H:\(String(format: "%.1f", hapticOffset*1000)) A:\(String(format: "%.1f", audioOffset*1000)) ---")
    }

    // --- Arousal Handling ---
    private func incrementArousalLevel() {
        let tolerance: CGFloat = 0.01
        guard let currentIndex = gameConfiguration.arousalSteps.lastIndex(where: { $0 <= currentArousalLevel + tolerance }) else {
            currentArousalLevel = gameConfiguration.arousalSteps.first ?? 0.0; return
        }
        let nextIndex = (currentIndex + 1) % gameConfiguration.arousalSteps.count
        currentArousalLevel = gameConfiguration.arousalSteps[nextIndex]
    }
    private func decrementArousalLevel() {
        let tolerance: CGFloat = 0.01
        guard let currentIndex = gameConfiguration.arousalSteps.firstIndex(where: { $0 >= currentArousalLevel - tolerance }) else {
            currentArousalLevel = gameConfiguration.arousalSteps.last ?? 1.0; return
        }
        let nextIndex = (currentIndex == 0) ? (gameConfiguration.arousalSteps.count - 1) : (currentIndex - 1)
        currentArousalLevel = gameConfiguration.arousalSteps[nextIndex]
    }
    private func updateParametersFromArousal() {
        switch currentState {
        case .tracking, .identifying:
            let trackingRange = gameConfiguration.trackingArousalThresholdHigh - gameConfiguration.trackingArousalThresholdLow
            guard trackingRange > 0 else { return }
            let clampedArousal = max(gameConfiguration.trackingArousalThresholdLow, min(currentArousalLevel, gameConfiguration.trackingArousalThresholdHigh))
            let normalizedTrackingArousal = (clampedArousal - gameConfiguration.trackingArousalThresholdLow) / trackingRange
            let speedRange = gameConfiguration.maxTargetSpeedAtTrackingThreshold - gameConfiguration.minTargetSpeedAtTrackingThreshold
            motionSettings.targetMeanSpeed = gameConfiguration.minTargetSpeedAtTrackingThreshold + (speedRange * normalizedTrackingArousal)
            let sdRange = gameConfiguration.maxTargetSpeedSDAtTrackingThreshold - gameConfiguration.minTargetSpeedSDAtTrackingThreshold
            motionSettings.targetSpeedSD = gameConfiguration.minTargetSpeedSDAtTrackingThreshold + (sdRange * normalizedTrackingArousal)
            let freqRange = gameConfiguration.maxTimerFrequencyAtTrackingThreshold - gameConfiguration.minTimerFrequencyAtTrackingThreshold
            self.currentTimerFrequency = gameConfiguration.minTimerFrequencyAtTrackingThreshold + (freqRange * normalizedTrackingArousal)
            let targetCountRange = CGFloat(gameConfiguration.maxTargetsAtLowTrackingArousal - gameConfiguration.minTargetsAtHighTrackingArousal)
            let calculatedTargetCount = CGFloat(gameConfiguration.maxTargetsAtLowTrackingArousal) - (targetCountRange * normalizedTrackingArousal)
            self.currentTargetCount = max(gameConfiguration.minTargetsAtHighTrackingArousal, min(gameConfiguration.maxTargetsAtLowTrackingArousal, Int(calculatedTargetCount.rounded())))
            let idDurationRange = gameConfiguration.maxIdentificationDurationAtLowArousal - gameConfiguration.minIdentificationDurationAtHighArousal
            self.currentIdentificationDuration = gameConfiguration.maxIdentificationDurationAtLowArousal - (idDurationRange * normalizedTrackingArousal)
            self.currentIdentificationDuration = max(0.1, self.currentIdentificationDuration)
            let shiftMinRange = gameConfiguration.shiftIntervalMin_HighArousal - gameConfiguration.shiftIntervalMin_LowArousal
            currentMinShiftInterval = gameConfiguration.shiftIntervalMin_LowArousal + (shiftMinRange * normalizedTrackingArousal)
            let shiftMaxRange = gameConfiguration.shiftIntervalMax_HighArousal - gameConfiguration.shiftIntervalMax_LowArousal
            currentMaxShiftInterval = gameConfiguration.shiftIntervalMax_LowArousal + (shiftMaxRange * normalizedTrackingArousal)
            if currentMinShiftInterval > currentMaxShiftInterval { currentMinShiftInterval = currentMaxShiftInterval }
            let idMinRange = gameConfiguration.idIntervalMin_HighArousal - gameConfiguration.idIntervalMin_LowArousal
            currentMinIDInterval = gameConfiguration.idIntervalMin_LowArousal + (idMinRange * normalizedTrackingArousal)
            let idMaxRange = gameConfiguration.idIntervalMax_HighArousal - gameConfiguration.idIntervalMax_LowArousal
            currentMaxIDInterval = gameConfiguration.idIntervalMax_LowArousal + (idMaxRange * normalizedTrackingArousal)
            if currentMinIDInterval > currentMaxIDInterval { currentMinIDInterval = currentMaxIDInterval }
            activeTargetColor = interpolateColor(from: gameConfiguration.targetColor_LowArousal, to: gameConfiguration.targetColor_HighArousal, t: normalizedTrackingArousal)
            activeDistractorColor = interpolateColor(from: gameConfiguration.distractorColor_LowArousal, to: gameConfiguration.distractorColor_HighArousal, t: normalizedTrackingArousal)
            if currentState == .tracking { for ball in balls { ball.updateAppearance(targetColor: activeTargetColor, distractorColor: activeDistractorColor) } }
        case .breathing:
            self.currentTimerFrequency = gameConfiguration.breathingTimerFrequency
            motionSettings.targetMeanSpeed = 0; motionSettings.targetSpeedSD = 0
            self.currentTargetCount = gameConfiguration.maxTargetsAtLowTrackingArousal
            self.currentIdentificationDuration = gameConfiguration.maxIdentificationDurationAtLowArousal
            activeTargetColor = gameConfiguration.targetColor_LowArousal
            activeDistractorColor = gameConfiguration.distractorColor_LowArousal
        case .paused:
             self.currentTimerFrequency = 1.0; motionSettings.targetMeanSpeed = 0; motionSettings.targetSpeedSD = 0
             self.currentTargetCount = gameConfiguration.maxTargetsAtLowTrackingArousal
             self.currentIdentificationDuration = gameConfiguration.maxIdentificationDurationAtLowArousal
             activeTargetColor = gameConfiguration.targetColor_LowArousal
             activeDistractorColor = gameConfiguration.distractorColor_LowArousal
        }
        precisionTimer?.frequency = self.currentTimerFrequency
        updateUI()
    }

    // --- State Transition Logic ---
    private func checkStateTransition(oldValue: CGFloat, newValue: CGFloat) {
        if (currentState == .tracking || currentState == .identifying) && newValue < gameConfiguration.trackingArousalThresholdLow && oldValue >= gameConfiguration.trackingArousalThresholdLow {
            transitionToBreathingState()
        }
        else if currentState == .breathing && newValue >= gameConfiguration.trackingArousalThresholdLow && oldValue < gameConfiguration.trackingArousalThresholdLow {
            transitionToTrackingState()
        }
    }
    private func transitionToBreathingState() {
        guard currentState == .tracking || currentState == .identifying else { return }
        print("--- Transitioning to Breathing State (Arousal: \(String(format: "%.2f", currentArousalLevel))) ---")
        var calculatedMaxDuration: TimeInterval = 0.5
        if currentState == .tracking && !balls.isEmpty {
            let currentMeanSpeed = MotionController.calculateStats(balls: balls).meanSpeed
            let targetTransitionSpeed = max(gameConfiguration.breathingMinTransitionSpeed, currentMeanSpeed * gameConfiguration.transitionSpeedFactor)
            let centerPoint = CGPoint(x: frame.midX, y: frame.midY)
            let targetPositions = MotionController.circlePoints(numPoints: balls.count, center: centerPoint, radius: gameConfiguration.breathingCircleMinRadius)
            if targetPositions.count == balls.count {
                var maxDurationForAnyBall: TimeInterval = 0
                for (index, ball) in balls.enumerated() {
                    let startPos = ball.position; let endPos = targetPositions[index]
                    let distance = sqrt(pow(endPos.x - startPos.x, 2) + pow(endPos.y - startPos.y, 2))
                    if targetTransitionSpeed > 0 { let durationForBall = TimeInterval(distance / targetTransitionSpeed); maxDurationForAnyBall = max(maxDurationForAnyBall, durationForBall) }
                }
                calculatedMaxDuration = min(gameConfiguration.maxTransitionDuration, maxDurationForAnyBall)
                calculatedMaxDuration = max(0.5, calculatedMaxDuration)
            }
        }
        let finalTransitionDuration = calculatedMaxDuration

        if currentState == .identifying { endIdentificationPhase(success: false) }
        // stopTrackingTimers() // No longer needed

        currentState = .breathing; currentBreathingPhase = .idle
        updateParametersFromArousal(); updateUI(); breathingVisualsFaded = false

        let centerPoint = CGPoint(x: frame.midX, y: frame.midY)
        let targetPositions = MotionController.circlePoints(numPoints: balls.count, center: centerPoint, radius: gameConfiguration.breathingCircleMinRadius)
        guard targetPositions.count == balls.count else { return }

        for (index, ball) in balls.enumerated() {
            ball.physicsBody?.isDynamic = false; ball.physicsBody?.velocity = .zero; ball.storedVelocity = nil
            ball.isTarget = false
            ball.updateAppearance(targetColor: gameConfiguration.targetColor_LowArousal, distractorColor: gameConfiguration.distractorColor_LowArousal)
            ball.alpha = 1.0
            let moveAction = SKAction.move(to: targetPositions[index], duration: finalTransitionDuration)
            moveAction.timingMode = .easeInEaseOut; ball.run(moveAction)
        }
        breathingCueLabel.alpha = 1.0; breathingCueLabel.isHidden = false
        fadeOverlayNode.alpha = 0.0

        let waitFormation = SKAction.wait(forDuration: finalTransitionDuration)
        let startAnimation = SKAction.run { [weak self] in self?.startBreathingAnimation() }
        self.run(SKAction.sequence([waitFormation, startAnimation]))
    }
    private func transitionToTrackingState() {
        guard currentState == .breathing else { return }
        print("--- Transitioning to Tracking State (Arousal: \(String(format: "%.2f", currentArousalLevel))) ---")
        stopBreathingAnimation();
        currentState = .tracking; currentBreathingPhase = .idle
        fadeInBreathingVisuals()
        updateParametersFromArousal()
        updateUI()
        for ball in balls {
            ball.physicsBody?.isDynamic = true
            ball.updateAppearance(targetColor: activeTargetColor, distractorColor: activeDistractorColor)
        }
        assignNewTargets(flashNewTargets: false)
        applyInitialImpulses()
        startTrackingTimers() // Reset manual timers
    }
    private func checkBreathingFade() {
        guard currentState == .breathing else { return }
        guard fadeOverlayNode != nil else { return }
        if currentArousalLevel < gameConfiguration.breathingFadeOutThreshold && !breathingVisualsFaded {
            print("DIAGNOSTIC: Fading out breathing visuals...")
            breathingVisualsFaded = true
            let fadeOut = SKAction.fadeOut(withDuration: gameConfiguration.fadeDuration)
            let fadeInOverlay = SKAction.fadeIn(withDuration: gameConfiguration.fadeDuration)
            balls.forEach { $0.run(fadeOut) }; breathingCueLabel.run(fadeOut)
            fadeOverlayNode.run(fadeInOverlay)
        } else if currentArousalLevel >= gameConfiguration.breathingFadeOutThreshold && breathingVisualsFaded {
            fadeInBreathingVisuals()
        }
    }
    private func fadeInBreathingVisuals() {
         guard breathingVisualsFaded else { return }
         guard fadeOverlayNode != nil else { return }
         print("DIAGNOSTIC: Fading in breathing visuals...")
         breathingVisualsFaded = false
         let fadeIn = SKAction.fadeIn(withDuration: gameConfiguration.fadeDuration)
         let fadeOutOverlay = SKAction.fadeOut(withDuration: gameConfiguration.fadeDuration)
         balls.forEach { $0.run(fadeIn) }; breathingCueLabel.run(fadeIn)
         fadeOverlayNode.run(fadeOutOverlay)
    }

    // --- Breathing Animation ---
    private func startBreathingAnimation() {
        guard currentState == .breathing else { return }
        currentBreathingPhase = .inhale
        runBreathingCycleAction()
    }
    private func stopBreathingAnimation() {
        self.removeAction(forKey: breathingAnimationActionKey)
        try? breathingHapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        currentBreathingPhase = .idle
        breathingCueLabel.isHidden = true
    }
    private func runBreathingCycleAction() {
        let centerPoint = CGPoint(x: frame.midX, y: frame.midY)
        let inhaleAction = SKAction.customAction(withDuration: gameConfiguration.breathingInhaleDuration) { _, elapsedTime in
            let fraction = elapsedTime / CGFloat(self.gameConfiguration.breathingInhaleDuration)
            let currentRadius = self.gameConfiguration.breathingCircleMinRadius + (self.gameConfiguration.breathingCircleMaxRadius - self.gameConfiguration.breathingCircleMinRadius) * fraction
            let positions = MotionController.circlePoints(numPoints: self.balls.count, center: centerPoint, radius: currentRadius)
            for (index, ball) in self.balls.enumerated() { if index < positions.count { ball.position = positions[index] } }
        }; inhaleAction.timingMode = .easeInEaseOut
        let hold1Visual = SKAction.wait(forDuration: gameConfiguration.breathingHoldAfterInhaleDuration)
        let exhaleAction = SKAction.customAction(withDuration: gameConfiguration.breathingExhaleDuration) { _, elapsedTime in
            let fraction = elapsedTime / CGFloat(self.gameConfiguration.breathingExhaleDuration)
            let currentRadius = self.gameConfiguration.breathingCircleMaxRadius - (self.gameConfiguration.breathingCircleMaxRadius - self.gameConfiguration.breathingCircleMinRadius) * fraction
            let positions = MotionController.circlePoints(numPoints: self.balls.count, center: centerPoint, radius: currentRadius)
            for (index, ball) in self.balls.enumerated() { if index < positions.count { ball.position = positions[index] } }
        }; exhaleAction.timingMode = .easeInEaseOut
        let hold2Visual = SKAction.wait(forDuration: gameConfiguration.breathingHoldAfterExhaleDuration)
        let setInhaleCue = SKAction.run { [weak self] in self?.updateBreathingPhase(.inhale) }
        let setHold1Cue = SKAction.run { [weak self] in self?.updateBreathingPhase(.holdAfterInhale) }
        let setExhaleCue = SKAction.run { [weak self] in self?.updateBreathingPhase(.exhale) }
        let setHold2Cue = SKAction.run { [weak self] in self?.updateBreathingPhase(.holdAfterExhale) }
        let restartHaptics = SKAction.run { [weak self] in
             try? self?.breathingHapticPlayer?.start(atTime: CHHapticTimeImmediate)
        }
        let sequence = SKAction.sequence([
            restartHaptics, setInhaleCue, inhaleAction,
            setHold1Cue, hold1Visual,
            setExhaleCue, exhaleAction,
            setHold2Cue, hold2Visual
        ])
        let runAgain = SKAction.run { [weak self] in self?.runBreathingCycleAction() }
        self.run(SKAction.sequence([sequence, runAgain]), withKey: breathingAnimationActionKey)
    }
    private func updateBreathingPhase(_ newPhase: BreathingPhase) {
        currentBreathingPhase = newPhase
        switch newPhase {
        case .idle: breathingCueLabel.text = ""
        case .inhale: breathingCueLabel.text = "Inhale"
        case .holdAfterInhale: breathingCueLabel.text = "Hold"
        case .exhale: breathingCueLabel.text = "Exhale"
        case .holdAfterExhale: breathingCueLabel.text = "Hold"
        }
    }

    // --- Haptic Setup ---
    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { hapticsReady = false; return }
        do {
            hapticEngine = try CHHapticEngine(); hapticEngine?.playsHapticsOnly = false;
            hapticEngine?.stoppedHandler = { [weak self] r in print("Haptic stopped: \(r)"); self?.hapticsReady = false; self?.stopBreathingAnimation() }
            hapticEngine?.resetHandler = { [weak self] in print("Haptic reset."); self?.hapticsReady = false; self?.startHapticEngine() }
            let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8); let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            let e = CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0); let p = try CHHapticPattern(events: [e], parameters: [])
            hapticPlayer = try hapticEngine?.makePlayer(with: p)
            prepareBreathingHaptics()
            hapticsReady = true
        } catch { print("DIAGNOSTIC: setupHaptics - Error: \(error.localizedDescription)"); hapticsReady = false }
    }
    private func startHapticEngine() {
         guard hapticsReady, let engine = hapticEngine else { print("DIAGNOSTIC: startHapticEngine - Aborted. Ready:\(hapticsReady), Engine:\(self.hapticEngine != nil)."); return }
         do { try engine.start() } catch { print("DIAGNOSTIC: startHapticEngine - Error: \(error.localizedDescription)"); hapticsReady = false }
    }
    private func stopHapticEngine() {
         guard let engine = hapticEngine else { return }; engine.stop { e in if let err = e { print("Error stopping haptic: \(err.localizedDescription)") } }; hapticsReady = false
    }
    private func prepareBreathingHaptics() {
        guard let engine = hapticEngine else { return }
        var allBreathingEvents: [CHHapticEvent] = []
        var phaseStartTime: TimeInterval = 0.0; var inhaleEventTimes: [TimeInterval] = []
        let inhaleDuration = gameConfiguration.breathingInhaleDuration
        let hold1Duration = gameConfiguration.breathingHoldAfterInhaleDuration
        let exhaleDuration = gameConfiguration.breathingExhaleDuration
        let hapticIntensity = gameConfiguration.breathingHapticIntensity
        let sharpnessMin = gameConfiguration.breathingHapticSharpnessMin
        let sharpnessMax = gameConfiguration.breathingHapticSharpnessMax
        let accelFactor = gameConfiguration.breathingHapticAccelFactor

        // Inhale Phase
        var relativeTime: TimeInterval = 0; var currentDelayFactor: Double = 1.0
        let baseInhaleDelay = inhaleDuration / 23.0
        let sharpnessRangeInhale = sharpnessMax - sharpnessMin
        while relativeTime < inhaleDuration - 0.01 {
            let absoluteTime = phaseStartTime + relativeTime; inhaleEventTimes.append(absoluteTime)
            let fraction = relativeTime / inhaleDuration
            let sharpness = sharpnessMax - (sharpnessRangeInhale * Float(fraction))
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: hapticIntensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            allBreathingEvents.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: absoluteTime))
            let delay = baseInhaleDelay / currentDelayFactor; relativeTime += delay; currentDelayFactor += accelFactor
        }
        let minimumDelay = inhaleEventTimes.count > 1 ? (inhaleEventTimes.last! - inhaleEventTimes[inhaleEventTimes.count-2]) : 0.05
        phaseStartTime += inhaleDuration

        // Hold After Inhale Phase
        relativeTime = 0
        while relativeTime < hold1Duration - 0.01 {
            let absoluteTime = phaseStartTime + relativeTime
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: hapticIntensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpnessMin)
            allBreathingEvents.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: absoluteTime))
            relativeTime += minimumDelay
        }
        phaseStartTime += hold1Duration

        // Exhale Phase
        relativeTime = 0
        let baseExhaleDelay = exhaleDuration / 23.0
        let numSteps = inhaleEventTimes.count
        let maxFactor = 1.0 + accelFactor * Double(numSteps)
        currentDelayFactor = maxFactor
        let sharpnessRangeExhale = sharpnessMax - sharpnessMin
        while relativeTime < exhaleDuration - 0.01 {
             let absoluteTime = phaseStartTime + relativeTime
             let fraction = relativeTime / exhaleDuration
             let sharpness = sharpnessMin + (sharpnessRangeExhale * Float(fraction))
             let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: hapticIntensity)
             let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
             allBreathingEvents.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: absoluteTime))
             let delay = baseExhaleDelay / max(0.1, currentDelayFactor)
             relativeTime += delay; currentDelayFactor -= accelFactor
             if currentDelayFactor < 1.0 { currentDelayFactor = 1.0 }
        }
        // No Hold2 Events

        allBreathingEvents.sort { $0.relativeTime < $1.relativeTime }
        guard !allBreathingEvents.isEmpty else { return }
        do {
            let breathingPattern = try CHHapticPattern(events: allBreathingEvents, parameters: [])
            breathingHapticPlayer = try engine.makePlayer(with: breathingPattern)
        } catch { print("Error creating single breathing haptic pattern/player: \(error.localizedDescription)") }
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
        precisionTimer = PrecisionTimer();
        precisionTimer?.frequency = self.currentTimerFrequency
        precisionTimer?.onVisualTick = { [weak self] in self?.handleVisualTick() }
        precisionTimer?.onHapticTick = { [weak self] t in self?.handleHapticTick(visualTickTime: t) }; precisionTimer?.onAudioTick = { [weak self] t in self?.handleAudioTick(visualTickTime: t) }
    }

    // --- Timer Callback Handlers ---
    private func handleVisualTick() {
        guard currentState == .tracking || currentState == .identifying || currentState == .breathing else { return }
        guard !balls.isEmpty else { return }
        guard let _ = balls.first?.strokeColor else { return }
        let cycleDuration = 1.0 / currentTimerFrequency
        let onDuration = cycleDuration * gameConfiguration.visualPulseOnDurationRatio
        guard onDuration > 0.001 else { return }
        for ball in balls {
            if !breathingVisualsFaded || currentState != .breathing {
                let setBorderOn = SKAction.run { ball.lineWidth = Ball.pulseLineWidth }
                let setBorderOff = SKAction.run { ball.lineWidth = 0 }
                let waitOn = SKAction.wait(forDuration: onDuration)
                let sequence = SKAction.sequence([setBorderOn, waitOn, setBorderOff])
                ball.run(sequence, withKey: "visualPulse")
            } else {
                ball.removeAction(forKey: "visualPulse"); ball.lineWidth = 0
            }
        }
    }
    private func handleHapticTick(visualTickTime: CFTimeInterval) {
        guard currentState == .tracking || currentState == .identifying || currentState == .breathing else { return }
        guard hapticsReady, let player = hapticPlayer else { return }
        let hapticStartTime = visualTickTime + hapticOffset
        try? player.start(atTime: hapticStartTime)
    }
    private func handleAudioTick(visualTickTime: CFTimeInterval) {
        guard currentState == .tracking || currentState == .identifying || currentState == .breathing else { return }
        guard audioReady, let initialEngine = customAudioEngine, let initialPlayerNode = audioPlayerNode, let initialBuffer = audioBuffer else { return }
        guard initialEngine.isRunning else { return }
        let audioStartTime = visualTickTime + audioOffset; let currentTime = CACurrentMediaTime(); let delayUntilStartTime = max(0, audioStartTime - currentTime)
        DispatchQueue.main.asyncAfter(deadline: .now() + delayUntilStartTime) { [weak self] in
            guard let self = self else { return }
            guard (self.currentState == .tracking || self.currentState == .identifying || self.currentState == .breathing), self.audioReady else { return }
            guard let currentEngine = self.customAudioEngine, currentEngine.isRunning,
                  let currentPlayerNode = self.audioPlayerNode, currentPlayerNode === initialPlayerNode,
                  let currentBuffer = self.audioBuffer, currentBuffer === initialBuffer
            else { return }
            currentPlayerNode.scheduleBuffer(currentBuffer, at: nil, options: .interrupts) { }; if !currentPlayerNode.isPlaying { currentPlayerNode.play() }
        }
    }

    // --- Update Loop ---
    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        if currentState == .tracking {
            timeUntilNextShift -= dt
            timeUntilNextIDCheck -= dt

            if timeUntilNextShift <= 0 && !isFlashSequenceRunning {
                assignNewTargets(flashNewTargets: true)
                resetShiftTimer()
            }

            if timeUntilNextIDCheck <= 0 {
                identificationCheckNeeded = true
                resetIDTimer()
            }
        }

        if identificationCheckNeeded {
            if currentState == .tracking && !isFlashSequenceRunning && currentTime >= flashCooldownEndTime {
                startIdentificationPhase()
                identificationCheckNeeded = false
            }
        }

        if currentState == .tracking && !balls.isEmpty {
            let stats = MotionController.calculateStats(balls: balls)
            if Int(currentTime * 60) % 60 == 0 {
                 print(String(format: "Motion Stats - Mean: %.1f (Tgt: %.1f) | SD: %.1f (Tgt: %.1f)",
                              stats.meanSpeed, motionSettings.targetMeanSpeed,
                              stats.speedSD, motionSettings.targetSpeedSD))
            }
            MotionController.applyCorrections(balls: balls, settings: motionSettings, scene: self)
        }
    }

    // --- Physics Contact Delegate Method ---
    func didBegin(_ contact: SKPhysicsContact) { }

    // --- Feedback Setup ---
    private func setupFeedbackAssets() {
        // Load Particle Emitter Template
        if let emitter = SKEmitterNode(fileNamed: gameConfiguration.correctTapParticleEffectFileName) {
            correctTapEmitterTemplate = emitter
            // print("DIAGNOSTIC: Loaded particle emitter template: \(gameConfiguration.correctTapParticleEffectFileName)")
        } else {
            print("ERROR: Could not load particle emitter file: \(gameConfiguration.correctTapParticleEffectFileName)")
        }

        // Prepare Audio Players
        correctTapPlayer = prepareAudioPlayer(filename: gameConfiguration.correctTapSoundFileName)
        groupCompletePlayer = prepareAudioPlayer(filename: gameConfiguration.groupCompleteSoundFileName)
    }

    private func prepareAudioPlayer(filename: String) -> AVAudioPlayer? {
        // Attempt to find the sound file with common extensions
        let extensions = ["wav", "mp3", "m4a", "caf"]
        var soundURL: URL? = nil
        for ext in extensions {
            if let url = Bundle.main.url(forResource: filename, withExtension: ext) {
                soundURL = url
                break
            }
        }

        guard let url = soundURL else {
            print("ERROR: Could not find sound file: \(filename) with extensions \(extensions)")
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            // print("DIAGNOSTIC: Prepared audio player for: \(filename)")
            return player
        } catch {
            print("ERROR: Could not create AVAudioPlayer for \(filename): \(error.localizedDescription)")
            return nil
        }
    }
}

// --- Ball class needs to be SKShapeNode ---
