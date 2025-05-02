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

    // --- ADDED: Properties for Dynamic Breathing Durations ---
    private var currentBreathingInhaleDuration: TimeInterval = GameConfiguration().breathingInhaleDuration
    private var currentBreathingHold1Duration: TimeInterval = GameConfiguration().breathingHoldAfterInhaleDuration
    private var currentBreathingExhaleDuration: TimeInterval = GameConfiguration().breathingExhaleDuration
    private var currentBreathingHold2Duration: TimeInterval = GameConfiguration().breathingHoldAfterExhaleDuration
    private var needsHapticPatternUpdate: Bool = false
    // --- ADDED: Flag for deferred visual duration update ---
    private var needsVisualDurationUpdate: Bool = false
    // --- END ADDED ---

    // --- Feedback Properties ---
    private var correctTapEmitterTemplate: SKEmitterNode?
    private var activeParticleEmitters: [Ball: SKEmitterNode] = [:]
    private var correctTapPlayer: AVAudioPlayer?
    private var groupCompletePlayer: AVAudioPlayer?
    private var incorrectTapPlayer: AVAudioPlayer?
    private var targetShiftPlayer: AVAudioPlayer?

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
    private var currentTargetAudioFrequency: Float = 440.0
    private var currentBufferFrequency: Float? = nil
    private let minAudioFrequency: Float = 200.0
    private let maxAudioFrequency: Float = 1000.0

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
        incorrectTapPlayer?.stop(); targetShiftPlayer?.stop() // Stop new feedback sounds
        self.removeAction(forKey: "flashSequenceCompletion"); self.removeAction(forKey: breathingAnimationActionKey)
        self.removeAction(forKey: "targetShiftSoundSequence") // Stop sound sequence
        balls.forEach { $0.removeFromParent() }; balls.removeAll()
        scoreLabel.removeFromParent(); stateLabel.removeFromParent(); countdownLabel.removeFromParent(); arousalLabel.removeFromParent(); breathingCueLabel.removeFromParent()
        fadeOverlayNode.removeFromParent()
        breathingHapticPlayer = nil; hapticPlayer = nil
        correctTapEmitterTemplate = nil; activeParticleEmitters.removeAll() // Clear feedback assets
        correctTapPlayer = nil; groupCompletePlayer = nil
        incorrectTapPlayer = nil; targetShiftPlayer = nil // Clear new feedback assets
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

            // --- Calculate Flash Color based on Arousal --- 
            let trackingRange = gameConfiguration.trackingArousalThresholdHigh - gameConfiguration.trackingArousalThresholdLow
            var normalizedTrackingArousal: CGFloat = 0.0
            if trackingRange > 0 {
                let clampedArousal = max(gameConfiguration.trackingArousalThresholdLow, min(currentArousalLevel, gameConfiguration.trackingArousalThresholdHigh))
                normalizedTrackingArousal = (clampedArousal - gameConfiguration.trackingArousalThresholdLow) / trackingRange
            }
            let baseFlashColor = gameConfiguration.flashColor // e.g., White
            let lowArousalFlashColor = self.activeDistractorColor
            let currentFlashColor = interpolateColor(from: lowArousalFlashColor, to: baseFlashColor, t: normalizedTrackingArousal)
            // print("DIAGNOSTIC: Arousal \(String(format: "%.2f", currentArousalLevel)), Norm: \(String(format: "%.2f", normalizedTrackingArousal)), FlashColor: \(currentFlashColor.description)")
            // -----------------------------------------------

            // --- Calculate Number of Flashes based on Arousal (Inverse mapping) ---
            let minFlashes: CGFloat = 3.0
            let maxFlashes: CGFloat = 6.0
            let calculatedFloatFlashes = maxFlashes + (minFlashes - maxFlashes) * normalizedTrackingArousal
            let numberOfFlashes = max(Int(minFlashes), min(Int(maxFlashes), Int(calculatedFloatFlashes.rounded())))
            // print("DIAGNOSTIC: Calculated Flashes: \(numberOfFlashes)")
            // ------------------------------------------------------------------

            // Start visual flash on each ball using the calculated flash color and count
            // --- MODIFIED: Pass calculated numberOfFlashes --- 
            newlyAssignedTargets.forEach { $0.flashAsNewTarget(targetColor: activeTargetColor, flashColor: currentFlashColor, flashes: numberOfFlashes) }
            // -------------------------------------------------

            // --- Start CONCURRENT sound sequence on the SCENE --- 
            let flashDuration = Ball.flashDuration
            if numberOfFlashes > 0 && flashDuration > 0 {
                 // Duration calculation needs to account for the variable number of flashes
                 // Total duration = flashDuration, so each on/off phase duration is flashDuration / (numberOfFlashes * 2)
                // Base duration for one ON-OFF cycle 
                let baseCycleDuration = flashDuration / Double(numberOfFlashes)
                // Apply speed factor to get the actual cycle duration
                let adjustedCycleDuration = max(0.002, baseCycleDuration * gameConfiguration.flashSpeedFactor)
                let waitBetweenSounds = adjustedCycleDuration // Wait for one full adjusted cycle

                let playSoundAction = SKAction.run { [weak self] in
                    guard let self = self else { return }
                    let normalizedFeedbackArousal = self.calculateNormalizedFeedbackArousal()
                    if normalizedFeedbackArousal > 0, let player = self.targetShiftPlayer {
                        player.volume = self.gameConfiguration.audioFeedbackMaxVolume * Float(normalizedFeedbackArousal)
                        player.currentTime = 0 // Rewind
                        player.play()
                        // print("DIAGNOSTIC: Played target shift sound (in sequence) with volume: \(player.volume)")
                    }
                }
                let waitAction = SKAction.wait(forDuration: waitBetweenSounds)
                // --- MODIFIED: Use calculated numberOfFlashes for sound repeat count --- 
                let soundSequence = SKAction.repeat(SKAction.sequence([playSoundAction, waitAction]), count: numberOfFlashes) 
                // -------------------------------------------------------------------

                // Stop previous sequence if any, then run the new one
                self.removeAction(forKey: "targetShiftSoundSequence")
                self.run(soundSequence, withKey: "targetShiftSoundSequence")
            } 
            // ---------------------------------------------------

            // --- MODIFIED: Calculate actual duration based on factor ---
            // The total duration of the flashing is reduced by the speed factor.
            let actualFlashSequenceDuration = flashDuration * gameConfiguration.flashSpeedFactor
            let flashEndTime = CACurrentMediaTime() + actualFlashSequenceDuration
            // ---------------------------------------------------------
            self.flashCooldownEndTime = flashEndTime + gameConfiguration.flashCooldownDuration
             // --- MODIFIED: Wait for the adjusted duration --- 
             let waitAction = SKAction.wait(forDuration: actualFlashSequenceDuration)
             // -------------------------------------------
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

        // --- REMOVED: Emitter cleanup moved to after delay ---
        // for (_, emitter) in activeParticleEmitters {
        //     emitter.removeFromParent()
        // }
        // activeParticleEmitters.removeAll()
        // --------------------------------------

        if success { print("Correct!"); score += 1 } else { print("Incorrect/Timeout.") }
        balls.forEach { $0.revealIdentity(targetColor: activeTargetColor, distractorColor: activeDistractorColor) }
        
        // --- MODIFIED: Delay motion resumption ---
        let delayAction = SKAction.wait(forDuration: 1.0) // MODIFIED: Increased delay to 1.0s
        let resumeMotionAction = SKAction.run { [weak self] in
            guard let self = self else { return }

            // --- ADDED: Clean up emitters before resuming motion ---
            print("--- Cleaning up emitters after delay ---") // Diagnostic
            for (_, emitter) in self.activeParticleEmitters {
                emitter.removeFromParent()
            }
            self.activeParticleEmitters.removeAll()
            // --- END ADDED ---

            // Resume physics and apply stored velocity
            self.balls.forEach { ball in 
                ball.physicsBody?.isDynamic = true
                ball.physicsBody?.velocity = ball.storedVelocity ?? .zero
                ball.storedVelocity = nil 
            }
            self.physicsWorld.speed = 1
            print("--- Resumed Motion after Delay ---") // Diagnostic
        }
        
        // Run the sequence on the scene
        self.run(SKAction.sequence([delayAction, resumeMotionAction]), withKey: "resumeMotionAfterID")
        // --- END MODIFIED ---

        // These happen immediately, before the delay starts
        currentState = .tracking
        updateUI()
        startTrackingTimers()
    }

    // --- Touch Handling ---
    // MODIFIED: Changed to use screen position for two-finger taps
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("DEBUG: touchesBegan - Count: \(touches.count), State: \(currentState)") // DEBUG
        
        // Handle two-finger taps based on screen position
        if touches.count == 2 {
            // Get the average Y position of the two touches
            let touchPositions = touches.map { $0.location(in: self) }
            let avgY = touchPositions.reduce(0) { $0 + $1.y } / CGFloat(touchPositions.count)
            
            // If tap is on top half of screen, increment arousal; if on bottom half, decrement
            if avgY > self.frame.height / 2 {
                incrementArousalLevel()
            } else {
                decrementArousalLevel()
            }
            return
        }

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

        // --- Calculate Feedback Salience based on Arousal (Used by all feedback in this function) ---
        let normalizedFeedbackArousal = calculateNormalizedFeedbackArousal()
        // ---------------------------------------------------------------------------------------

        // Check if the ball is currently hidden visually and hasn't already been correctly identified (no emitter attached)
        if ball.isVisuallyHidden && activeParticleEmitters[ball] == nil {
            if ball.isTarget {
                print("DEBUG: Correct tap on hidden target.")
                targetsFoundThisRound += 1
                ball.revealIdentity(targetColor: activeTargetColor, distractorColor: activeDistractorColor) // Reveal it

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

                // --- Play Audio Feedback (Incorrect Tap) ---
                if normalizedFeedbackArousal > 0, let player = incorrectTapPlayer {
                    player.volume = gameConfiguration.audioFeedbackMaxVolume * Float(normalizedFeedbackArousal)
                    player.currentTime = 0 // Rewind
                    player.play()
                    // print("DIAGNOSTIC: Played incorrect tap sound with volume: \(player.volume)")
                }
                // -------------------------------------------

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

        // --- Global Parameter Updates (Applied regardless of state unless overridden) ---

        // --- Frequency Calculation (Global, Non-Linear) ---
        let clampedArousal = max(0.0, min(currentArousalLevel, 1.0))
        let normalizedPosition = pow(Float(clampedArousal), 2.0) // Quadratic curve (x^2)
        let minFreq = gameConfiguration.minTimerFrequency
        let maxFreq = gameConfiguration.maxTimerFrequency
        let freqRange = maxFreq - minFreq
        let targetFrequency = minFreq + freqRange * Double(normalizedPosition)

        // --- Audio Pitch Calculation (Still Linear 0.0-1.0) ---
        let audioFreqRange = maxAudioFrequency - minAudioFrequency
        self.currentTargetAudioFrequency = minAudioFrequency + (audioFreqRange * Float(clampedArousal))

        // --- State-Specific Overrides & Calculations ---
        switch currentState {
        case .tracking, .identifying:
            // Apply calculated frequency
            self.currentTimerFrequency = targetFrequency

            // --- Motion, Colors, Intervals etc. based on arousal in TRACKING RANGE (0.35-1.0) ---
            let trackingRange = gameConfiguration.trackingArousalThresholdHigh - gameConfiguration.trackingArousalThresholdLow
            var normalizedTrackingArousal: CGFloat = 0.0
            if trackingRange > 0 {
                let clampedTrackingArousal = max(gameConfiguration.trackingArousalThresholdLow, min(currentArousalLevel, gameConfiguration.trackingArousalThresholdHigh))
                normalizedTrackingArousal = (clampedTrackingArousal - gameConfiguration.trackingArousalThresholdLow) / trackingRange
            }
            let speedRange = gameConfiguration.maxTargetSpeedAtTrackingThreshold - gameConfiguration.minTargetSpeedAtTrackingThreshold
            motionSettings.targetMeanSpeed = gameConfiguration.minTargetSpeedAtTrackingThreshold + (speedRange * normalizedTrackingArousal)
            let sdRange = gameConfiguration.maxTargetSpeedSDAtTrackingThreshold - gameConfiguration.minTargetSpeedSDAtTrackingThreshold
            motionSettings.targetSpeedSD = gameConfiguration.minTargetSpeedSDAtTrackingThreshold + (sdRange * normalizedTrackingArousal)
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

            // Ensure dynamic breathing params NOT updated here
            needsHapticPatternUpdate = false // Reset flag if we transition out of breathing

        case .breathing:
            // Apply calculated frequency
            self.currentTimerFrequency = targetFrequency

            // Update dynamic breathing parameters (which might flag haptic update)
            updateDynamicBreathingParameters()

            // Ensure motion stops & colors are low arousal
            motionSettings.targetMeanSpeed = 0
            motionSettings.targetSpeedSD = 0
            activeTargetColor = gameConfiguration.targetColor_LowArousal
            activeDistractorColor = gameConfiguration.distractorColor_LowArousal

        case .paused:
            // Override frequency to fixed paused value
            self.currentTimerFrequency = 1.0;
            // Ensure motion stops & parameters reset to low arousal defaults
            motionSettings.targetMeanSpeed = 0; motionSettings.targetSpeedSD = 0
            self.currentTargetCount = gameConfiguration.maxTargetsAtLowTrackingArousal
            self.currentIdentificationDuration = gameConfiguration.maxIdentificationDurationAtLowArousal
            activeTargetColor = gameConfiguration.targetColor_LowArousal
            activeDistractorColor = gameConfiguration.distractorColor_LowArousal
            // Ensure dynamic breathing params NOT updated here
             needsHapticPatternUpdate = false // Reset flag if we pause
        }

        // --- Apply Updated Timer Frequency --- 
        // (Do this *after* the switch to ensure the correct value is applied)
        precisionTimer?.frequency = self.currentTimerFrequency

        // --- Update UI --- 
        updateUI()
    }

    // --- State Transition Logic ---
    private func checkStateTransition(oldValue: CGFloat, newValue: CGFloat) {
        // Only allow transition to .breathing from .tracking
        if currentState == .tracking && newValue < gameConfiguration.trackingArousalThresholdLow && oldValue >= gameConfiguration.trackingArousalThresholdLow {
            transitionToBreathingState()
        }
        else if currentState == .breathing && newValue >= gameConfiguration.trackingArousalThresholdLow && oldValue < gameConfiguration.trackingArousalThresholdLow {
            transitionToTrackingState()
        }
        // If in .identifying and arousal drops below threshold, set a flag to check after returning to .tracking
        else if currentState == .identifying && newValue < gameConfiguration.trackingArousalThresholdLow && oldValue >= gameConfiguration.trackingArousalThresholdLow {
            // Set a flag to check after returning to .tracking
            identificationCheckNeeded = true
        }
    }
    private func transitionToBreathingState() {
        // --- ADDED: Cancel any pending motion resumption from ID phase --- 
        self.removeAction(forKey: "resumeMotionAfterID")
        // -------------------------------------------------------------
        
        guard currentState == .tracking else { 
            print("ERROR: Attempted to transition to breathing from invalid state: \(currentState)") // Added error check
            return 
        }
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
        self.removeAction(forKey: "targetShiftSoundSequence") // Stop shift sound sequence if running

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
        
        // --- ADDED: Explicitly resume physics simulation ---
        self.physicsWorld.speed = 1
        // -------------------------------------------------
        
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
        // --- ADDED: Apply deferred VISUAL duration updates at the START of the cycle ---
        if needsVisualDurationUpdate {
            print("DIAGNOSTIC: Applying deferred visual duration update at start of cycle.")
            // Recalculate target durations based on the *current* arousal level
            let breathingArousalRange = gameConfiguration.trackingArousalThresholdLow
            if breathingArousalRange > 0 {
                 let clampedBreathingArousal = max(0.0, min(currentArousalLevel, breathingArousalRange))
                 let normalizedBreathingArousal = clampedBreathingArousal / breathingArousalRange

                 let minInhale: TimeInterval = 3.5 // TODO: Refactor these magic numbers
                 let maxInhale: TimeInterval = 5.0
                 let minExhale: TimeInterval = 5.0
                 let maxExhale: TimeInterval = 6.5

                 let targetInhaleDuration = minInhale + (maxInhale - minInhale) * normalizedBreathingArousal
                 let targetExhaleDuration = maxExhale + (minExhale - maxExhale) * normalizedBreathingArousal

                 currentBreathingInhaleDuration = targetInhaleDuration
                 currentBreathingExhaleDuration = targetExhaleDuration
                 // Holds remain constant for now
                 print("DIAGNOSTIC: Updated visual durations - Inhale: \(String(format: "%.2f", currentBreathingInhaleDuration)), Exhale: \(String(format: "%.2f", currentBreathingExhaleDuration))")
             }
             needsVisualDurationUpdate = false // Reset the flag
        }
        // --- END ADDED ---

        let centerPoint = CGPoint(x: frame.midX, y: frame.midY)
        let inhaleAction = SKAction.customAction(withDuration: currentBreathingInhaleDuration) { _, elapsedTime in
            let fraction = elapsedTime / CGFloat(self.currentBreathingInhaleDuration)
            let currentRadius = self.gameConfiguration.breathingCircleMinRadius + (self.gameConfiguration.breathingCircleMaxRadius - self.gameConfiguration.breathingCircleMinRadius) * fraction
            let positions = MotionController.circlePoints(numPoints: self.balls.count, center: centerPoint, radius: currentRadius)
            for (index, ball) in self.balls.enumerated() { if index < positions.count { ball.position = positions[index] } }
        }; inhaleAction.timingMode = .easeInEaseOut
        let hold1Visual = SKAction.wait(forDuration: currentBreathingHold1Duration)
        let exhaleAction = SKAction.customAction(withDuration: currentBreathingExhaleDuration) { _, elapsedTime in
            let fraction = elapsedTime / CGFloat(self.currentBreathingExhaleDuration)
            let currentRadius = self.gameConfiguration.breathingCircleMaxRadius - (self.gameConfiguration.breathingCircleMaxRadius - self.gameConfiguration.breathingCircleMinRadius) * fraction
            let positions = MotionController.circlePoints(numPoints: self.balls.count, center: centerPoint, radius: currentRadius)
            for (index, ball) in self.balls.enumerated() { if index < positions.count { ball.position = positions[index] } }
        }; exhaleAction.timingMode = .easeInEaseOut
        let hold2Visual = SKAction.wait(forDuration: currentBreathingHold2Duration)
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

        // --- ADDED: Check and apply deferred haptic update at end of cycle ---
        let applyDeferredHapticUpdate = SKAction.run {
            [weak self] in
            guard let self = self else { return }
            if self.needsHapticPatternUpdate {
                print("DIAGNOSTIC: Applying deferred haptic pattern update at end of cycle.")
                self.updateBreathingHaptics() // Regenerates and restarts haptics
            }
        }
        // --- END ADDED ---

        let runAgain = SKAction.run { [weak self] in self?.runBreathingCycleAction() }
        self.run(SKAction.sequence([sequence, applyDeferredHapticUpdate, runAgain]), withKey: breathingAnimationActionKey)
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
            let transientEvent = CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: 0)
            let transientPattern = try CHHapticPattern(events: [transientEvent], parameters: [])
            hapticPlayer = try hapticEngine?.makePlayer(with: transientPattern) // Basic player for simple taps

            // --- MODIFIED: Generate initial breathing pattern & player ---
            if let initialPattern = generateBreathingHapticPattern(inhaleDuration: currentBreathingInhaleDuration,
                                                                   hold1Duration: currentBreathingHold1Duration,
                                                                   exhaleDuration: currentBreathingExhaleDuration,
                                                                   hold2Duration: currentBreathingHold2Duration) {
                 breathingHapticPlayer = try hapticEngine?.makePlayer(with: initialPattern)
             } else {
                 print("ERROR: Failed to create initial breathing haptic pattern.")
            }
            // --- END MODIFIED ---

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

    // --- MODIFIED: Parameterized function to generate pattern ---
    private func generateBreathingHapticPattern(inhaleDuration: TimeInterval, hold1Duration: TimeInterval, exhaleDuration: TimeInterval, hold2Duration: TimeInterval) -> CHHapticPattern? {
         guard let engine = hapticEngine else { return nil }
         var allBreathingEvents: [CHHapticEvent] = []
         var phaseStartTime: TimeInterval = 0.0; var inhaleEventTimes: [TimeInterval] = []

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
         guard !allBreathingEvents.isEmpty else { return nil }
         do {
             let breathingPattern = try CHHapticPattern(events: allBreathingEvents, parameters: [])
             return breathingPattern
         } catch { print("Error creating breathing haptic pattern: \(error.localizedDescription)"); return nil }
     }

    // --- ADDED: Helper to Update Dynamic Breathing Parameters & Trigger Haptic Regen ---
    private func updateDynamicBreathingParameters() {
        guard currentState == .breathing else { return }

        // Normalize arousal within the breathing range [0.0, thresholdLow]
        let breathingArousalRange = gameConfiguration.trackingArousalThresholdLow
        guard breathingArousalRange > 0 else { return } // Avoid division by zero
        let clampedBreathingArousal = max(0.0, min(currentArousalLevel, breathingArousalRange))
        let normalizedBreathingArousal = clampedBreathingArousal / breathingArousalRange // Range 0.0 to 1.0

        // Define target duration ranges (Example: Inhale 3.5s-5.0s, Exhale 6.5s-5.0s)
        let minInhale: TimeInterval = 3.5
        let maxInhale: TimeInterval = 5.0
        let minExhale: TimeInterval = 5.0
        let maxExhale: TimeInterval = 6.5

        // Interpolate: Low arousal (norm=0.0) -> Long exhale; High arousal (norm=1.0) -> Balanced
        let targetInhaleDuration = minInhale + (maxInhale - minInhale) * normalizedBreathingArousal
        let targetExhaleDuration = maxExhale + (minExhale - maxExhale) * normalizedBreathingArousal

        // --- INTENTIONALLY PLACING DURATION CHECK HERE ---
        // Check if change exceeds tolerance
        let tolerance: TimeInterval = 0.1
        if abs(targetInhaleDuration - currentBreathingInhaleDuration) > tolerance || abs(targetExhaleDuration - currentBreathingExhaleDuration) > tolerance {
            print("DIAGNOSTIC: Breathing duration change detected. Flagging for update...")
            // --- MODIFIED: Don't update durations directly, just set flags ---
            // currentBreathingInhaleDuration = targetInhaleDuration
            // currentBreathingExhaleDuration = targetExhaleDuration
            needsVisualDurationUpdate = true // Flag for visual update at next cycle start
            needsHapticPatternUpdate = true // Flag for haptic update at end of current cycle
            // --- END MODIFIED ---
        }
    }
    // --- END ADDED ---

    // --- ADDED: Function to Update Breathing Haptics ---
    private func updateBreathingHaptics() {
        guard hapticsReady, let engine = hapticEngine else { return }

        print("DIAGNOSTIC: Updating breathing haptic pattern...")
        // Stop the current player
        try? breathingHapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        breathingHapticPlayer = nil // Release old player

        // Generate new pattern with current durations
        guard let newPattern = generateBreathingHapticPattern(inhaleDuration: currentBreathingInhaleDuration,
                                                               hold1Duration: currentBreathingHold1Duration,
                                                               exhaleDuration: currentBreathingExhaleDuration,
                                                               hold2Duration: currentBreathingHold2Duration) else {
            print("ERROR: Failed to generate new breathing haptic pattern during update.")
            return
        }

        // Create and start a new player
        do {
            breathingHapticPlayer = try engine.makePlayer(with: newPattern)
            // Try starting immediately - might cause slight jump if called mid-cycle
            try? breathingHapticPlayer?.start(atTime: CHHapticTimeImmediate)
             print("DIAGNOSTIC: Successfully updated and started new breathing haptic player.")
        } catch {
            print("ERROR: Failed to create or start new breathing haptic player: \(error.localizedDescription)")
        }

        needsHapticPatternUpdate = false // Reset flag
    }
    // --- END ADDED ---

    // --- Audio Setup ---
    private func setupAudio() {
        customAudioEngine = AVAudioEngine(); audioPlayerNode = AVAudioPlayerNode()
        guard let engine = customAudioEngine, let playerNode = audioPlayerNode else { audioReady = false; return }
        do {
            engine.attach(playerNode)
            // Define format (assuming standard CD quality)
            audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)
            guard let format = audioFormat else { audioReady = false; return }

            // --- MODIFIED: Generate initial buffer using helper ---
            self.audioBuffer = generateAudioBuffer(frequency: self.currentTargetAudioFrequency, arousalLevel: self.currentArousalLevel)
            guard self.audioBuffer != nil else {
                print("ERROR: Initial audio buffer generation failed.")
                audioReady = false; return
            }
            self.currentBufferFrequency = self.currentTargetAudioFrequency // Track frequency of initial buffer
            // --- END MODIFIED ---

            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            try engine.prepare()
            audioReady = true
        } catch { print("DIAGNOSTIC: setupAudio - Error: \(error.localizedDescription)"); audioReady = false }
    }
    // --- MODIFIED: Remove amplitude param, calculate internally based on arousalLevel, use odd harmonics for square wave approximation ---
    private func generateAudioBuffer(frequency: Float, arousalLevel: CGFloat) -> AVAudioPCMBuffer? {
        guard let format = audioFormat, format.sampleRate > 0 else { return nil }
        let sampleRate = Float(format.sampleRate)
        let duration: Float = 0.1 // Keep duration short for rhythmic pulse
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount // Important: Set the frame length

        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        let angularFrequency = 2 * .pi * frequency / sampleRate
        // --- Calculate amplitude based on arousal ---
        let minAmplitude: Float = 0.3
        let maxAmplitude: Float = 0.7
        let amplitudeRange = maxAmplitude - minAmplitude
        let clampedArousal = max(0.0, min(arousalLevel, 1.0))
        let calculatedAmplitude = minAmplitude + (amplitudeRange * Float(clampedArousal))
        // --- END ---

        // --- Square wave approximation via odd harmonics ---
        let squarenessFactor = Float(clampedArousal) // 0.0 (sine) to 1.0 (more square)

        let angularFreq3 = 3.0 * angularFrequency
        let amplitude3 = (calculatedAmplitude / 3.0) * squarenessFactor

        let angularFreq5 = 5.0 * angularFrequency
        let amplitude5 = (calculatedAmplitude / 5.0) * squarenessFactor

        let angularFreq7 = 7.0 * angularFrequency
        let amplitude7 = (calculatedAmplitude / 7.0) * squarenessFactor
        // --- END ---


        for frame in 0..<Int(frameCount) {
            let time = Float(frame)
            // --- Sum fundamental and scaled odd harmonics ---
            let fundamentalValue = sin(time * angularFrequency) * calculatedAmplitude
            let harmonic3Value = sin(time * angularFreq3) * amplitude3
            let harmonic5Value = sin(time * angularFreq5) * amplitude5
            let harmonic7Value = sin(time * angularFreq7) * amplitude7

            channelData[frame] = fundamentalValue + harmonic3Value + harmonic5Value + harmonic7Value
            // Optional: Clamp to avoid potential clipping, although unlikely with these amplitudes
            // channelData[frame] = max(-1.0, min(1.0, channelData[frame]))
            // --- END ---
        }
        // print("DIAGNOSTIC: Generated audio buffer Freq:\(frequency) Hz, Amp:\(calculatedAmplitude), Squareness:\(squarenessFactor)")
        return buffer
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
        // --- FIX: Use CACurrentMediaTime() --- 
        let audioStartTime = visualTickTime + audioOffset; let currentTime = CACurrentMediaTime(); let delayUntilStartTime = max(0, audioStartTime - currentTime)
        DispatchQueue.main.asyncAfter(deadline: .now() + delayUntilStartTime) { [weak self] in
            guard let self = self else { return }
            guard (self.currentState == .tracking || self.currentState == .identifying || self.currentState == .breathing), self.audioReady else { return }

            // --- MODIFIED: Regenerate buffer if frequency changed ---
            var bufferToPlay = self.audioBuffer // Start with the existing buffer
            if self.currentBufferFrequency == nil || abs(self.currentBufferFrequency! - self.currentTargetAudioFrequency) > 1.0 /* Tolerance */ {
                // print("DIAGNOSTIC: Regenerating audio buffer for frequency: \(self.currentTargetAudioFrequency) Hz")
                if let newBuffer = self.generateAudioBuffer(frequency: self.currentTargetAudioFrequency, arousalLevel: self.currentArousalLevel) {
                    self.audioBuffer = newBuffer          // Update the stored buffer
                    self.currentBufferFrequency = self.currentTargetAudioFrequency // Update the tracking frequency
                    bufferToPlay = newBuffer              // Use the new buffer for this tick
                } else {
                    print("ERROR: Failed to regenerate audio buffer for frequency \(self.currentTargetAudioFrequency)")
                    // Keep using the old buffer if regeneration fails
                }
            }
            // --- END MODIFIED ---

            // --- MODIFIED: Ensure engine/node/buffer still valid and schedule the potentially updated buffer ---
            guard let currentEngine = self.customAudioEngine, currentEngine.isRunning,
                  let currentPlayerNode = self.audioPlayerNode, // No need to check identity anymore
                  let buffer = bufferToPlay // Use the potentially updated buffer
            else {
                 print("DIAGNOSTIC: Audio tick aborted - engine/node/buffer invalid after potential regeneration check.")
                 return
            }
            // --- END MODIFIED ---

            // Schedule and play
            currentPlayerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { /* Completion handler */ }
            if !currentPlayerNode.isPlaying { currentPlayerNode.play() }
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

            // Check if we need to transition to .breathing after returning from .identifying
            if identificationCheckNeeded && currentArousalLevel < gameConfiguration.trackingArousalThresholdLow {
                transitionToBreathingState()
                identificationCheckNeeded = false
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
        incorrectTapPlayer = prepareAudioPlayer(filename: gameConfiguration.incorrectTapSoundFileName)
        targetShiftPlayer = prepareAudioPlayer(filename: gameConfiguration.targetShiftSoundFileName)
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

    // --- Helper Function for Feedback Arousal Mapping ---
    private func calculateNormalizedFeedbackArousal() -> CGFloat {
        let minArousal = gameConfiguration.feedbackMinArousalThreshold
        let maxArousal = gameConfiguration.feedbackMaxArousalThreshold
        guard currentArousalLevel >= minArousal else { return 0.0 }

        let arousalRange = maxArousal - minArousal
        if arousalRange > 0 {
            return min(1.0, (currentArousalLevel - minArousal) / arousalRange)
        } else {
            // Handle edge case where min == max
            return (currentArousalLevel >= maxArousal) ? 1.0 : 0.0
        }
    }
}

// --- Ball class needs to be SKShapeNode ---
