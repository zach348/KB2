// NeuroGlide/GameScene.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 11 FIX 4 (COMPLETE FILE - Restored Stop Timers)
// Role: Main scene. Uses GameConfiguration struct, maps target count inversely to arousal.

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
    private var currentArousalLevel: CGFloat { // Computed property with observer
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
    // Removed SKAction timer keys, keep for removal check if needed
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

    // --- Scene Lifecycle ---
    override func didMove(to view: SKView) {
        print("--- GameScene: didMove(to:) ---")
        backgroundColor = .darkGray
        safeAreaTopInset = view.safeAreaInsets.top
        setupPhysicsWorld(); setupWalls(); setupUI(); setupHaptics(); setupAudio()
        setupFadeOverlay()
        if hapticsReady { startHapticEngine() }
        if audioReady { startAudioEngine() }
        updateParametersFromArousal() // Set initial target count before creating balls
        createBalls()
        if !balls.isEmpty { applyInitialImpulses() }
        setupTimer();
        precisionTimer?.start()
        startTrackingTimers(); // Reset manual timers based on initial arousal
        updateUI()
        flashCooldownEndTime = CACurrentMediaTime()
        print("--- GameScene: didMove(to:) Finished ---")
    }

    override func willMove(from view: SKView) {
        print("--- GameScene: willMove(from:) ---")
        precisionTimer?.stop();
        // stopTrackingTimers() // No longer needed as timers are manual
        stopIdentificationTimeout()
        stopBreathingAnimation()
        stopHapticEngine(); stopAudioEngine()
        self.removeAction(forKey: "flashSequenceCompletion"); self.removeAction(forKey: breathingAnimationActionKey)
        balls.forEach { $0.removeFromParent() }; balls.removeAll()
        scoreLabel?.removeFromParent(); stateLabel?.removeFromParent(); countdownLabel?.removeFromParent(); arousalLabel?.removeFromParent(); breathingCueLabel?.removeFromParent()
        fadeOverlayNode?.removeFromParent()
        breathingHapticPlayer = nil; hapticPlayer = nil
        precisionTimer = nil; hapticEngine = nil; customAudioEngine = nil; audioPlayerNode = nil; audioBuffer = nil
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
        breathingCueLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold"); breathingCueLabel.fontSize = 36; breathingCueLabel.fontColor = .white
        breathingCueLabel.position = CGPoint(x: frame.midX, y: frame.midY + 50); breathingCueLabel.horizontalAlignmentMode = .center; breathingCueLabel.isHidden = true; addChild(breathingCueLabel)
    }
    private func setupFadeOverlay() {
        fadeOverlayNode = SKSpriteNode(color: .black, size: self.size)
        fadeOverlayNode.position = CGPoint(x: frame.midX, y: frame.midY)
        fadeOverlayNode.zPosition = 100
        fadeOverlayNode.alpha = 0.0
        addChild(fadeOverlayNode)
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
            if ball.isTarget != shouldBeTarget { ball.isTarget = shouldBeTarget; assignmentsMade += 1; if shouldBeTarget { newlyAssignedTargets.append(ball) } }
        }
        if flashNewTargets && !newlyAssignedTargets.isEmpty {
            self.isFlashSequenceRunning = true
            newlyAssignedTargets.forEach { $0.flashAsNewTarget() }
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
        print("DIAGNOSTIC: Resetting manual timers for Shift and ID Check.")
        resetShiftTimer()
        resetIDTimer()
    }
    private func resetShiftTimer() {
        timeUntilNextShift = TimeInterval.random(in: currentMinShiftInterval...currentMaxShiftInterval)
        print("DIAGNOSTIC: Next target shift in \(String(format: "%.2f", timeUntilNextShift))s (Range: \(String(format: "%.1f", currentMinShiftInterval))-\(String(format: "%.1f", currentMaxShiftInterval)))")
    }
    private func resetIDTimer() {
        timeUntilNextIDCheck = TimeInterval.random(in: currentMinIDInterval...currentMaxIDInterval)
        print("DIAGNOSTIC: Next ID check in \(String(format: "%.2f", timeUntilNextIDCheck))s (Range: \(String(format: "%.1f", currentMinIDInterval))-\(String(format: "%.1f", currentMaxIDInterval)))")
    }
    // ** ADDED Back Timer Stop Functions (Needed by transitions) **
    private func stopTrackingTimers() {
        // No SKActions to stop, but could reset countdowns if needed (not necessary currently)
        print("DIAGNOSTIC: Stopping tracking timer logic (manual timers will stop decrementing).")
        // Resetting timeUntil... here might cause immediate trigger on resume,
        // rely on startTrackingTimers being called on transition back.
    }
    // These might be needed if other parts of code still reference them, though the actions are gone
    private func stopTargetShiftTimer() {
         self.removeAction(forKey: targetShiftTimerActionKey) // Remove old action just in case
         print("DIAGNOSTIC: Target shift timer logic stopped.")
    }
    private func stopIdentificationTimer() {
         self.removeAction(forKey: identificationTimerActionKey) // Remove old action just in case
         print("DIAGNOSTIC: Identification trigger timer logic stopped.")
    }


    // --- Identification Phase Logic ---
    private func startIdentificationPhase() {
        print("--- Starting Identification Phase ---")
        currentState = .identifying; updateUI()
        physicsWorld.speed = 0; balls.forEach { ball in ball.storedVelocity = ball.physicsBody?.velocity; ball.physicsBody?.velocity = .zero; ball.physicsBody?.isDynamic = false }
        targetsToFind = 0; targetsFoundThisRound = 0
        guard !balls.isEmpty else { endIdentificationPhase(success: false); return }
        self.targetsToFind = self.currentTargetCount
        for ball in balls { ball.hideIdentity() }
        let waitBeforeCountdown = SKAction.wait(forDuration: gameConfiguration.identificationStartDelay)
        let startCountdownAction = SKAction.run { [weak self] in self?.startIdentificationTimeout() }
        self.run(SKAction.sequence([waitBeforeCountdown, startCountdownAction]))
    }
    private func startIdentificationTimeout() {
        stopIdentificationTimeout()
        var remainingTime = gameConfiguration.identificationDuration
        countdownLabel.text = String(format: "Time: %.1f", remainingTime); countdownLabel.isHidden = false
        let wait = SKAction.wait(forDuration: 0.1); let update = SKAction.run { [weak self] in guard let self = self, self.currentState == .identifying else { self?.stopIdentificationTimeout(); return }; remainingTime -= 0.1; self.countdownLabel.text = String(format: "Time: %.1f", max(0, remainingTime)) }
        let repeatCount = Int(gameConfiguration.identificationDuration / 0.1)
        let countdownAction = SKAction.repeat(.sequence([wait, update]), count: repeatCount)
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
        currentState = .tracking
        updateUI()
        startTrackingTimers() // Reset manual timers for next cycle
    }

    // --- Touch Handling ---
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.count == 3 { incrementArousalLevel(); return }
        if touches.count == 2 { decrementArousalLevel(); return }
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
        let targetColor = Ball.Appearance.targetColor
        let currentColor = ball.fillColor
        if ball.isTarget {
            if currentColor != targetColor { targetsFoundThisRound += 1; ball.revealIdentity(); if targetsFoundThisRound >= targetsToFind { endIdentificationPhase(success: true) } }
        } else { endIdentificationPhase(success: false) }
    }
    private func changeOffsetsOnTouch() {
        if hapticOffset == 0.020 { hapticOffset = 0.050; audioOffset = 0.100 }
        else if hapticOffset == 0.050 { hapticOffset = 0.000; audioOffset = 0.040 }
        else { hapticOffset = 0.020; audioOffset = 0.040 }
        print("--- Touch (Tracking) --- Offsets -> H:\(String(format: "%.1f", hapticOffset*1000)) A:\(String(format: "%.1f", audioOffset*1000)) ---")
    }

    // --- Arousal Handling ---
    private func incrementArousalLevel() {
        guard let currentIndex = gameConfiguration.arousalSteps.lastIndex(where: { $0 <= currentArousalLevel + 0.01 }) else {
            currentArousalLevel = gameConfiguration.arousalSteps.first ?? 0.0; return
        }
        let nextIndex = (currentIndex + 1) % gameConfiguration.arousalSteps.count
        currentArousalLevel = gameConfiguration.arousalSteps[nextIndex]
    }
    private func decrementArousalLevel() {
        guard let currentIndex = gameConfiguration.arousalSteps.firstIndex(where: { $0 >= currentArousalLevel - 0.01 }) else {
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
        case .breathing:
            self.currentTimerFrequency = gameConfiguration.breathingTimerFrequency
            motionSettings.targetMeanSpeed = 0; motionSettings.targetSpeedSD = 0
            self.currentTargetCount = gameConfiguration.maxTargetsAtLowTrackingArousal
        case .paused:
             self.currentTimerFrequency = 1.0; motionSettings.targetMeanSpeed = 0; motionSettings.targetSpeedSD = 0
             self.currentTargetCount = gameConfiguration.maxTargetsAtLowTrackingArousal
        }
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
            ball.isTarget = false; ball.updateAppearance(); ball.alpha = 1.0
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
        for ball in balls { ball.physicsBody?.isDynamic = true }
        // Assign targets immediately upon returning to tracking
        assignNewTargets(flashNewTargets: false) // No flash on return
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
        guard currentState == .tracking || currentState == .breathing else { return }
        guard !balls.isEmpty else { return }
        guard let _ = balls.first?.strokeColor else { return }
        let cycleDuration = 1.0 / currentTimerFrequency
        let onDuration = cycleDuration * gameConfiguration.visualPulseOnDurationRatio
        guard onDuration > 0.001 else { return }
        for ball in balls {
            let setBorderOn = SKAction.run { ball.lineWidth = Ball.pulseLineWidth }
            let setBorderOff = SKAction.run { ball.lineWidth = 0 }
            let waitOn = SKAction.wait(forDuration: onDuration)
            let sequence = SKAction.sequence([setBorderOn, waitOn, setBorderOff])
            ball.run(sequence, withKey: "visualPulse")
        }
    }
    private func handleHapticTick(visualTickTime: CFTimeInterval) {
        guard currentState == .tracking || currentState == .breathing else { return }
        guard hapticsReady, let player = hapticPlayer else { return }
        let hapticStartTime = visualTickTime + hapticOffset
        try? player.start(atTime: hapticStartTime)
    }
    private func handleAudioTick(visualTickTime: CFTimeInterval) {
        guard currentState == .tracking || currentState == .breathing else { return }
        guard audioReady, let initialEngine = customAudioEngine, let initialPlayerNode = audioPlayerNode, let initialBuffer = audioBuffer else { return }
        guard initialEngine.isRunning else { return }
        let audioStartTime = visualTickTime + audioOffset; let currentTime = CACurrentMediaTime(); let delayUntilStartTime = max(0, audioStartTime - currentTime)
        DispatchQueue.main.asyncAfter(deadline: .now() + delayUntilStartTime) { [weak self] in
            guard let self = self else { return }
            guard (self.currentState == .tracking || self.currentState == .breathing), self.audioReady else { return }
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
}

// --- Ball class needs to be SKShapeNode ---
