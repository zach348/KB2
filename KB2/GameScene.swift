// Kalibrate/GameScene.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 13 - Refactoring Preparation
// Role: Main scene.

import SpriteKit
import GameplayKit
import CoreHaptics
import AVFoundation

//====================================================================================================
// MARK: - GLOBAL ENUMS
//====================================================================================================
// --- Game State Enum ---
enum GameState { case tracking, identifying, paused, breathing }

// --- Breathing Phase Enum ---
enum BreathingPhase { case idle, inhale, holdAfterInhale, exhale, holdAfterExhale }

//====================================================================================================
// MARK: - AUDIO BUFFER CACHE
//====================================================================================================
// --- VHA Audio Buffer Cache --- // REMOVED - MOVED TO AudioManager.swift
// class VHAAudioBufferCache { ... } // REMOVED

//====================================================================================================
// MARK: - GAME SCENE
//====================================================================================================
class GameScene: SKScene, SKPhysicsContactDelegate {

    //====================================================================================================
    // MARK: - CONFIGURATION & CORE PROPERTIES
    //====================================================================================================
    // --- Configuration ---
    internal let gameConfiguration = GameConfiguration()
    private var audioManager: AudioManager! // ADDED

    // --- Session Management Properties ---
    var sessionMode: Bool = false
    var sessionDuration: TimeInterval = 0
    var sessionStartTime: TimeInterval = 0
    var initialArousalLevel: CGFloat = 0.95
    
    // --- ADDED: Throttling properties for arousal updates ---
    private var lastArousalUpdateTime: TimeInterval = 0
    private let arousalUpdateInterval: TimeInterval = 0.25 // 4 times per second
    // --- END ADDED ---

    // --- Core Game State Properties ---
    internal var currentState: GameState = .tracking
    internal var _currentArousalLevel: CGFloat = 0.75 // Backing variable
    internal var currentArousalLevel: CGFloat {
        get { return _currentArousalLevel }
        set {
            let oldValue = _currentArousalLevel
            let clampedValue = max(0.0, min(newValue, 1.0))
            if clampedValue != _currentArousalLevel {
                _currentArousalLevel = clampedValue
                //Removed Arousal Level Diagnostic logging
                checkStateTransition(oldValue: oldValue, newValue: _currentArousalLevel)
                updateParametersFromArousal() // This will now call audioManager.updateAudioParameters
                checkBreathingFade()
            }
        }
    }
    
    // --- Helper: Delta Time ---
    private var lastUpdateTime: TimeInterval = 0
    
    // --- Motion Control Throttling ---
    private var motionControlActionKey = "motionControlAction"

    // --- Precision Timer Property ---
    private var precisionTimer: PrecisionTimer? // ENSURE THIS LINE IS PRESENT

    // --- TESTABILITY: Expose last calculated target audio frequency ---
    internal var lastCalculatedTargetAudioFrequencyForTests: Float? = nil

    //====================================================================================================
    // MARK: - TRACKING PHASE PROPERTIES
    //====================================================================================================
    // --- Ball & Motion Properties ---
    internal var balls: [Ball] = []
    private var motionSettings = MotionSettings()
    internal var currentTargetCount: Int = GameConfiguration().maxTargetsAtLowTrackingArousal
    
    // --- Target Shift Properties ---
    internal var isFlashSequenceRunning: Bool = false
    private var flashCooldownEndTime: TimeInterval = 0.0
    private var timeUntilNextShift: TimeInterval = 0
    private var currentMinShiftInterval: TimeInterval = 5.0
    private var currentMaxShiftInterval: TimeInterval = 10.0
    
    //====================================================================================================
    // MARK: - IDENTIFICATION PHASE PROPERTIES
    //====================================================================================================
    private var identificationTimerActionKey = "identificationTimer"
    private var identificationTimeoutActionKey = "identificationTimeout"
    private var identificationCheckNeeded: Bool = false
    internal var targetCountForNextIDRound: Int? = nil // ADDED: Snapshot for target count for the upcoming ID round
    private var timeUntilNextIDCheck: TimeInterval = 0
    private var currentMinIDInterval: TimeInterval = 10.0
    private var currentMaxIDInterval: TimeInterval = 15.0
    internal var currentIdentificationDuration: TimeInterval = GameConfiguration().identificationDuration
    internal var activeTargetColor: SKColor = GameConfiguration().targetColor_LowArousal
    internal var activeDistractorColor: SKColor = GameConfiguration().distractorColor_LowArousal
    internal var targetsToFind: Int = 0
    internal var targetsFoundThisRound: Int = 0
    internal var score: Int = 0
    internal var isEndingIdentification: Bool = false
    
    //====================================================================================================
    // MARK: - BREATHING PHASE PROPERTIES
    //====================================================================================================
    internal var currentBreathingPhase: BreathingPhase = .idle
    private var breathingAnimationActionKey = "breathingAnimation"
    internal var breathingVisualsFaded: Bool = false
    
    // --- ADDED: Properties for Dynamic Breathing Durations ---
    internal var currentBreathingInhaleDuration: TimeInterval = GameConfiguration().breathingInhaleDuration
    internal var currentBreathingHold1Duration: TimeInterval = GameConfiguration().breathingHoldAfterInhaleDuration
    internal var currentBreathingExhaleDuration: TimeInterval = GameConfiguration().breathingExhaleDuration
    internal var currentBreathingHold2Duration: TimeInterval = GameConfiguration().breathingHoldAfterExhaleDuration
    private var needsHapticPatternUpdate: Bool = false
    // --- ADDED: Flag for deferred visual duration update ---
    private var needsVisualDurationUpdate: Bool = false
    // --- END ADDED ---
    
    //====================================================================================================
    // MARK: - UI ELEMENTS
    //====================================================================================================
    private var scoreLabel: SKLabelNode!
    private var stateLabel: SKLabelNode!
    private var countdownLabel: SKLabelNode!
    private var arousalLabel: SKLabelNode!
    private var breathingCueLabel: SKLabelNode!
    private var safeAreaTopInset: CGFloat = 0
    private var fadeOverlayNode: SKSpriteNode!
    
    // --- Session UI Elements ---
    private var sessionProgressBar: SKShapeNode?
    private var sessionProgressFill: SKShapeNode?
    private var sessionTimeLabel: SKLabelNode?
    
    //====================================================================================================
    // MARK: - FEEDBACK SYSTEMS
    //====================================================================================================
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

    // --- Rhythmic Pulse Properties --- (Audio related properties moved to AudioManager)
    private var currentTimerFrequency: Double = 5.0 {
         didSet {
             if currentTimerFrequency <= 0 { currentTimerFrequency = 1.0 }
             precisionTimer?.frequency = currentTimerFrequency
         }
     }
    public var hapticOffset: TimeInterval = 0.020
    public var audioOffset: TimeInterval = 0.040 // This offset is used by GameScene's handleAudioTick
    
    //====================================================================================================
    // MARK: - INITIALIZATION
    //====================================================================================================
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

    //====================================================================================================
    // MARK: - SCENE LIFECYCLE
    //====================================================================================================
    // --- Scene Lifecycle ---
    override func didMove(to view: SKView) {
        print("--- GameScene: didMove(to:) ---")
        backgroundColor = .darkGray
        safeAreaTopInset = view.safeAreaInsets.top
        
        // Initialize AudioManager
        // GameScene still manages currentTargetAudioFrequency as it's derived from arousal
        // and used by updateParametersFromArousal before being passed to AudioManager.
        // We need an initial value for currentTargetAudioFrequency before first updateParametersFromArousal call.
        let initialClampedArousal = max(0.0, min(sessionMode ? initialArousalLevel : _currentArousalLevel, 1.0))
        let initialAudioFreqRange = gameConfiguration.maxAudioFrequency - gameConfiguration.minAudioFrequency // Use GameConfig
        let initialTargetAudioFreq = gameConfiguration.minAudioFrequency + (initialAudioFreqRange * Float(initialClampedArousal))

        audioManager = AudioManager(
            gameConfiguration: gameConfiguration,
            initialArousal: sessionMode ? initialArousalLevel : _currentArousalLevel,
            initialTimerFrequency: currentTimerFrequency, // Use existing GameScene's currentTimerFrequency
            initialTargetAudioFrequency: initialTargetAudioFreq
        )

        setupPhysicsWorld(); setupWalls(); setupUI(); setupHaptics()
        // setupAudio() // REMOVED - handled by AudioManager init
        
        setupFadeOverlay()
        setupFeedbackAssets()
        
        if hapticsReady { startHapticEngine() }
        audioManager.startEngine() // MODIFIED
        
        if sessionMode {
            sessionStartTime = CACurrentMediaTime()
            _currentArousalLevel = initialArousalLevel
            print("DIAGNOSTIC: Session started with duration \\(sessionDuration) seconds, initial arousal \\(initialArousalLevel)")
        }
        
        updateParametersFromArousal() // This will now also update audioManager
        createBalls()
        if !balls.isEmpty { applyInitialImpulses() }
        setupTimer();
        precisionTimer?.start()
        startTrackingTimers(); updateUI()
        flashCooldownEndTime = CACurrentMediaTime()
        
        if currentState == .tracking {
            startThrottledMotionControl()
        }
        print("--- GameScene: didMove(to:) Finished ---")
    }

    override func willMove(from view: SKView) {
        print("--- GameScene: willMove(from:) ---")
        precisionTimer?.stop();
        stopIdentificationTimeout()
        stopBreathingAnimation()
        stopThrottledMotionControl()
        
        print("Stopping audio engines...")
        audioManager.cleanup() // MODIFIED - Calls AudioManager's cleanup
        
        stopHapticEngine()
        
        // ... (rest of cleanup code for feedback players, actions, balls, UI, etc.)
        correctTapPlayer?.stop(); groupCompletePlayer?.stop()
        incorrectTapPlayer?.stop(); targetShiftPlayer?.stop()
        self.removeAction(forKey: "flashSequenceCompletion"); self.removeAction(forKey: breathingAnimationActionKey)
        self.removeAction(forKey: "targetShiftSoundSequence")
        balls.forEach { $0.removeFromParent() }; balls.removeAll()
        scoreLabel.removeFromParent(); stateLabel.removeFromParent(); countdownLabel.removeFromParent(); arousalLabel.removeFromParent(); breathingCueLabel.removeFromParent()
        fadeOverlayNode.removeFromParent()
        breathingHapticPlayer = nil; hapticPlayer = nil
        correctTapEmitterTemplate = nil; activeParticleEmitters.removeAll()
        correctTapPlayer = nil; groupCompletePlayer = nil
        incorrectTapPlayer = nil; targetShiftPlayer = nil
        
        precisionTimer = nil; hapticEngine = nil
        // customAudioEngine, audioPlayerNode, audioBuffer, audioBufferCache, audioPulser are now in AudioManager

        print("GameScene cleaned up non-audio resources.") // Audio cleanup handled by audioManager
        print("--- GameScene: willMove(from:) Finished ---")
    }

    //====================================================================================================
    // MARK: - SETUP & CONFIGURATION
    //====================================================================================================
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
        
        // Add session progress bar if in session mode
        if sessionMode {
            setupSessionProgressBar()
        }
    }
    
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
        
        // Update session progress if in session mode
        if sessionMode {
            updateSessionProgressBar()
        }
    }

    //====================================================================================================
    // MARK: - BALL MANAGEMENT
    //====================================================================================================
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
         if !balls.isEmpty { assignNewTargets() } // MODIFIED: Removed flashNewTargets param
    }
    
    private func applyInitialImpulses() { balls.forEach { $0.applyRandomImpulse() } }

    //====================================================================================================
    // MARK: - TARGET MANAGEMENT
    //====================================================================================================
    // --- Target Shift Logic ---
    internal func assignNewTargets() {
        guard currentTargetCount <= balls.count, !balls.isEmpty else {
            return
        }
        let shuffledBalls = balls.shuffled(); var newlyAssignedTargets: [Ball] = []; var assignmentsMade = 0
        
        // This loop determines which balls *should* be targets based on currentTargetCount
        // and updates their isTarget state and appearance.
        for (index, ball) in shuffledBalls.enumerated() {
            let shouldBeTarget = index < currentTargetCount
            if ball.isTarget != shouldBeTarget {
                ball.isTarget = shouldBeTarget
                ball.updateAppearance(targetColor: activeTargetColor, distractorColor: activeDistractorColor)
                assignmentsMade += 1
                if shouldBeTarget { newlyAssignedTargets.append(ball) }
            }
        }

        // Snapshot the currentTargetCount that will be used for the next ID round, based on THIS assignment pass.
        // This is done regardless of whether we flash, as this count reflects the current state of targets.
        self.targetCountForNextIDRound = self.currentTargetCount

        // Always flash if there are newly assigned targets (targets that were just turned ON)
        if !newlyAssignedTargets.isEmpty {
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

            // --- Calculate Number of Flashes based on Arousal (Inverse mapping) ---
            let minFlashes: CGFloat = 2.0 // Changed from 3.0 to 2.0
            let maxFlashes: CGFloat = 6.0
            let calculatedFloatFlashes = maxFlashes + (minFlashes - maxFlashes) * normalizedTrackingArousal
            let numberOfFlashes = max(Int(minFlashes), min(Int(maxFlashes), Int(calculatedFloatFlashes.rounded())))
            
            // --- Calculate Flash Duration based on Arousal (Inverse mapping) ---
            let minFlashDuration: TimeInterval = 0.75 // High arousal (changed from 1.5)
            let maxFlashDuration: TimeInterval = 2.0 // Low arousal (changed from 2.5)
            let calculatedFlashDuration = minFlashDuration + (maxFlashDuration - minFlashDuration) * (1.0 - normalizedTrackingArousal)
            
            newlyAssignedTargets.forEach { $0.flashAsNewTarget(targetColor: activeTargetColor, flashColor: currentFlashColor, duration: calculatedFlashDuration, flashes: numberOfFlashes) }

            let flashDuration = calculatedFlashDuration // Use the calculated duration instead of Ball.flashDuration
            if numberOfFlashes > 0 && flashDuration > 0 {
                let baseCycleDuration = flashDuration / Double(numberOfFlashes)
                let adjustedCycleDuration = max(0.002, baseCycleDuration * gameConfiguration.flashSpeedFactor)
                let waitBetweenSounds = adjustedCycleDuration

                let playSoundAction = SKAction.run { [weak self] in
                    guard let self = self else { return }
                    let normalizedFeedbackArousal = self.calculateNormalizedFeedbackArousal()
                    if normalizedFeedbackArousal > 0, let player = self.targetShiftPlayer {
                        player.volume = self.gameConfiguration.audioFeedbackMaxVolume * Float(normalizedFeedbackArousal)
                        player.currentTime = 0 // Rewind
                        player.play()
                    }
                }
                let waitAction = SKAction.wait(forDuration: waitBetweenSounds)
                let soundSequence = SKAction.sequence([playSoundAction, waitAction])
                let repeatAction = SKAction.repeat(soundSequence, count: numberOfFlashes)
                self.run(repeatAction, withKey: "targetShiftSoundSequence")

            let actualFlashSequenceDuration = flashDuration * gameConfiguration.flashSpeedFactor
            let flashEndTime = CACurrentMediaTime() + actualFlashSequenceDuration
            self.flashCooldownEndTime = flashEndTime + gameConfiguration.flashCooldownDuration
                 let waitEndFlash = SKAction.wait(forDuration: actualFlashSequenceDuration)
             let clearSequenceFlagAction = SKAction.run { [weak self] in
                self?.isFlashSequenceRunning = false
            }
                let sequence = SKAction.sequence([waitEndFlash, clearSequenceFlagAction])
                self.run(sequence, withKey: "flashSequenceCompletion")
            } else {
                // If parameters are invalid, ensure the sequence ends
                self.isFlashSequenceRunning = false
            }
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

    //====================================================================================================
    // MARK: - IDENTIFICATION PHASE
    //====================================================================================================
    internal func startIdentificationPhase() {
        isEndingIdentification = false
        currentState = .identifying; updateUI()
        physicsWorld.speed = 0; balls.forEach { ball in ball.storedVelocity = ball.physicsBody?.velocity; ball.physicsBody?.velocity = .zero; ball.physicsBody?.isDynamic = false }
        
        let previousTargetsToFindValue = targetsToFind
        targetsToFind = 0; targetsFoundThisRound = 0

        guard !balls.isEmpty else {
            endIdentificationPhase(success: false);
            return
        }
        
        // Use the snapshotted value if available, otherwise fallback to currentTargetCount
        let countToUse = self.targetCountForNextIDRound ?? self.currentTargetCount
        let source = self.targetCountForNextIDRound != nil ? "snapshot (targetCountForNextIDRound)" : "fallback (self.currentTargetCount)"
        self.targetsToFind = countToUse
        
        // Reset the snapshot after using it
        self.targetCountForNextIDRound = nil

        for ball in balls { ball.hideIdentity(hiddenColor: self.activeDistractorColor) } 
        
        let waitBeforeCountdown = SKAction.wait(forDuration: gameConfiguration.identificationStartDelay)
        let startCountdownAction = SKAction.run { [weak self] in 
            self?.startIdentificationTimeout() 
        }
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
    
    private func stopIdentificationTimeout() {
        let actionWasPresent = self.action(forKey: identificationTimeoutActionKey) != nil
        self.removeAction(forKey: identificationTimeoutActionKey);
        countdownLabel.isHidden = true
    }
    
    internal func endIdentificationPhase(success: Bool) {
        guard currentState == .identifying else {
            return
        }
        // --- FIX: Prevent double execution --- 
        guard !isEndingIdentification else { 
            return
        }
        isEndingIdentification = true // Set flag immediately
        // -----------------------------------

        if success { score += 1 } 
        balls.forEach { $0.revealIdentity(targetColor: activeTargetColor, distractorColor: activeDistractorColor) }
        
        // --- MODIFIED: Delay motion resumption ---
        let delayAction = SKAction.wait(forDuration: 1.0)
        let resumeMotionAction = SKAction.run { [weak self] in
            guard let self = self else {
                return
            }

            // --- ADDED: Clean up emitters before resuming motion ---
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
            
            // --- MOVED: Start tracking timers AFTER motion resumes --- 
            self.currentState = .tracking
            self.updateUI()
            self.startTrackingTimers()
            // --- END MOVED --- 
            
            // Restart throttled motion control
            self.startThrottledMotionControl()
            
            // Reset the ending flag *after* all resumption logic is complete
            self.isEndingIdentification = false
        }
        
        // Run the sequence on the scene
        // Use a unique key to ensure it runs even if called rapidly
        let sequenceKey = "resumeMotionAfterID_\(CACurrentMediaTime())" 
        self.run(SKAction.sequence([delayAction, resumeMotionAction]), withKey: sequenceKey)
        // --- END MODIFIED ---
    }

    //====================================================================================================
    // MARK: - TOUCH HANDLING
    //====================================================================================================
    // --- Touch Handling ---
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
    
    internal func handleBallTap(_ ball: Ball) {
        guard currentState == .identifying else {
            return
        }

        // --- Calculate Feedback Salience based on Arousal (Used by all feedback in this function) ---
        let normalizedFeedbackArousal = calculateNormalizedFeedbackArousal()
        // ---------------------------------------------------------------------------------------

        // Check if the ball is currently hidden visually and hasn't already been correctly identified (no emitter attached)
        if ball.isVisuallyHidden && activeParticleEmitters[ball] == nil {
            if ball.isTarget {
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
                }
                // -----------------------------------------------

                // --- Play Audio Feedback (Correct Tap) ---
                if normalizedFeedbackArousal > 0, let player = correctTapPlayer {
                    player.volume = gameConfiguration.audioFeedbackMaxVolume * Float(normalizedFeedbackArousal)
                    player.currentTime = 0 // Rewind
                    player.play()
                }
                // -------------------------------------------

                // --- Check for Round Completion ---
                if targetsFoundThisRound >= targetsToFind {
                     // --- Play Audio Feedback (Group Complete) ---   // <<< RESTORED BLOCK
                     if normalizedFeedbackArousal > 0, let player = groupCompletePlayer {
                         player.volume = gameConfiguration.audioFeedbackMaxVolume * Float(normalizedFeedbackArousal)
                         player.currentTime = 0 // Rewind
                         player.play()
                     }
                     // --------------------------------------------   // <<< END RESTORED BLOCK
                    // --- FIX: Stop the timeout immediately upon success --- 
                    stopIdentificationTimeout() // Prevent race condition
                    // -----------------------------------------------------
                    endIdentificationPhase(success: true) // Ends with success
                }
                // -----------------------------------

            } else {
                // Tapped a hidden distractor

                // --- Play Audio Feedback (Incorrect Tap) ---
                if normalizedFeedbackArousal > 0, let player = incorrectTapPlayer {
                    player.volume = gameConfiguration.audioFeedbackMaxVolume * Float(normalizedFeedbackArousal)
                    player.currentTime = 0 // Rewind
                    player.play()
                }
                // -------------------------------------------

                // --- FIX: Also stop timeout on incorrect tap --- 
                stopIdentificationTimeout() // Stop timer immediately
                // ---------------------------------------------
                endIdentificationPhase(success: false)
            }
        } else {
            // Ball was likely already revealed or tapped incorrectly before
            // Optional: Add penalty for tapping revealed ball? For now, do nothing.
        }
    }
    
    private func changeOffsetsOnTouch() {
        if hapticOffset == 0.020 { hapticOffset = 0.050; audioOffset = 0.100 }
        else if hapticOffset == 0.050 { hapticOffset = 0.000; audioOffset = 0.040 }
        else { hapticOffset = 0.020; audioOffset = 0.040 }
        print("--- Touch (Tracking) --- Offsets -> H:\(String(format: "%.1f", hapticOffset*1000)) A:\(String(format: "%.1f", audioOffset*1000)) ---")
    }

    //====================================================================================================
    // MARK: - AROUSAL MANAGEMENT
    //====================================================================================================
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

    internal func updateParametersFromArousal() {
        let clampedArousal = max(0.0, min(currentArousalLevel, 1.0))
        let normalizedPosition = pow(Float(clampedArousal), 2.0)
        let minFreq = gameConfiguration.minTimerFrequency
        let maxFreq = gameConfiguration.maxTimerFrequency
        let freqRange = maxFreq - minFreq
        let targetTimerFrequency = minFreq + freqRange * Double(normalizedPosition)

        let audioFreqRange = gameConfiguration.maxAudioFrequency - gameConfiguration.minAudioFrequency
        let newTargetAudioFrequency = gameConfiguration.minAudioFrequency + (audioFreqRange * Float(clampedArousal))
        self.lastCalculatedTargetAudioFrequencyForTests = newTargetAudioFrequency // Update for tests
        
        audioManager.updateAudioParameters(
            newArousal: currentArousalLevel,
            newTimerFrequency: targetTimerFrequency,
            newTargetAudioFrequency: newTargetAudioFrequency
        )

        // --- State-Specific Overrides & Calculations ---
        switch currentState {
        case .tracking, .identifying:
            self.currentTimerFrequency = targetTimerFrequency // GameScene updates its own timer frequency
            // ... (rest of tracking/identifying specific parameter updates: motion, colors, intervals, etc.)
            // ... (ensure activeTargetColor, activeDistractorColor updates remain)
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
            // let oldTargetCount = self.currentTargetCount // Keep if needed for other logic
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
            needsHapticPatternUpdate = false

        case .breathing:
            self.currentTimerFrequency = targetTimerFrequency
            updateDynamicBreathingParameters()
            motionSettings.targetMeanSpeed = 0
            motionSettings.targetSpeedSD = 0
            activeTargetColor = gameConfiguration.targetColor_LowArousal
            activeDistractorColor = gameConfiguration.distractorColor_LowArousal

        case .paused:
            self.currentTimerFrequency = 1.0;
            motionSettings.targetMeanSpeed = 0; motionSettings.targetSpeedSD = 0
            self.currentTargetCount = gameConfiguration.maxTargetsAtLowTrackingArousal
            self.currentIdentificationDuration = gameConfiguration.maxIdentificationDurationAtLowArousal
            activeTargetColor = gameConfiguration.targetColor_LowArousal
            activeDistractorColor = gameConfiguration.distractorColor_LowArousal
            needsHapticPatternUpdate = false
        }
        precisionTimer?.frequency = self.currentTimerFrequency
        updateUI()
    }

    //====================================================================================================
    // MARK: - STATE TRANSITION
    //====================================================================================================
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
            return 
        }
        
        // Stop throttled motion control
        stopThrottledMotionControl()
        
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
        stopBreathingAnimation();
        currentState = .tracking; currentBreathingPhase = .idle
        fadeInBreathingVisuals()
        updateParametersFromArousal() // This will set currentTargetCount based on new arousal
        updateUI()
        
        // --- ADDED: Explicitly resume physics simulation ---
        self.physicsWorld.speed = 1
        // -------------------------------------------------
        
        for ball in balls {
            ball.physicsBody?.isDynamic = true
            ball.updateAppearance(targetColor: activeTargetColor, distractorColor: activeDistractorColor)
        }
        assignNewTargets() // MODIFIED: Removed flashNewTargets param. This will use updated currentTargetCount and flash.
        applyInitialImpulses()
        startTrackingTimers() // Reset manual timers
        
        // Start throttled motion control
        startThrottledMotionControl()
    }
    
    private func checkBreathingFade() {
        guard currentState == .breathing else { return }
        guard fadeOverlayNode != nil else { return }
        if currentArousalLevel < gameConfiguration.breathingFadeOutThreshold && !breathingVisualsFaded {
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
         breathingVisualsFaded = false
         let fadeIn = SKAction.fadeIn(withDuration: gameConfiguration.fadeDuration)
         let fadeOutOverlay = SKAction.fadeOut(withDuration: gameConfiguration.fadeDuration)
         balls.forEach { $0.run(fadeIn) }; breathingCueLabel.run(fadeIn)
         fadeOverlayNode.run(fadeOutOverlay)
    }

    //====================================================================================================
    // MARK: - BREATHING ANIMATION
    //====================================================================================================
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

    //====================================================================================================
    // MARK: - HAPTIC SYSTEM
    //====================================================================================================
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
            try? breathingHapticPlayer?.start(atTime: CHHapticTimeImmediate)
             print("DIAGNOSTIC: Successfully updated and started new breathing haptic player.")
        } catch {
            print("ERROR: Failed to create or start new breathing haptic player: \(error.localizedDescription)")
        }

        needsHapticPatternUpdate = false // Reset flag
    }

   

    //====================================================================================================
    // MARK: - UPDATE LOOP & PHYSICS
    //====================================================================================================
    // --- Update Loop ---
    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        // Update arousal for session mode
        if sessionMode {
            // Note: updateArousalForSession itself contains throttling logic
            updateArousalForSession()
        }

        if currentState == .tracking {
            timeUntilNextShift -= dt
            timeUntilNextIDCheck -= dt

            if timeUntilNextShift <= 0 && !isFlashSequenceRunning {
                assignNewTargets() // MODIFIED: Removed flashNewTargets param
                resetShiftTimer()
            }

            if timeUntilNextIDCheck <= 0 {
                identificationCheckNeeded = true
                resetIDTimer()
            }

            // Check if we need to transition to .breathing after returning from .identifying
            // This was previously inside the `if identificationCheckNeeded` block, but it's a general state check.
            if identificationCheckNeeded && currentArousalLevel < gameConfiguration.trackingArousalThresholdLow {
                transitionToBreathingState()
                identificationCheckNeeded = false // Reset the flag as we are acting on it by changing state
            }
        }

        // This block handles initiating the ID phase if it's needed and conditions are met.
        // It is separate from the `currentState == .tracking` block because `identificationCheckNeeded` can be set
        // and then persist even if other state changes or updates occur before ID can start.
        if identificationCheckNeeded {
            if currentState == .tracking && !isFlashSequenceRunning && currentTime >= flashCooldownEndTime {
                startIdentificationPhase()
                identificationCheckNeeded = false // Reset the flag as we are starting the ID phase
            }
        }
        
        // Motion control is now handled via SKAction in startThrottledMotionControl()
    }

    // --- Physics Contact Delegate Method ---
    func didBegin(_ contact: SKPhysicsContact) { }

    //====================================================================================================
    // MARK: - FEEDBACK SYSTEMS
    //====================================================================================================
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
    internal func calculateNormalizedFeedbackArousal() -> CGFloat {
        // Calculate a 0-1 value with 0.7 as midpoint (1.0 at 0.9+ arousal, 0.0 at 0.5- arousal)
        let lowerBound: CGFloat = 0.5
        let upperBound: CGFloat = 0.9
        let normalized = (currentArousalLevel - lowerBound) / (upperBound - lowerBound)
        return min(1.0, max(0.0, normalized))
    }

    //====================================================================================================
    // MARK: - SESSION MANAGEMENT
    //====================================================================================================
    // --- Session Management Methods ---
    internal func calculateArousalForProgress(_ progress: Double) -> CGFloat {
        // Use a Power Curve: A(p) = A_start * (1 - p)^n
        // Where n is calculated to make A(0.5) = breathingThreshold
        
        let startArousal = initialArousalLevel
        let endArousal: CGFloat = 0.0 // Target end arousal
        let breathingThreshold = gameConfiguration.trackingArousalThresholdLow
        let targetProgress: Double = 0.5 // Progress at which to hit the threshold

        // Calculate the exponent 'n' needed to hit the threshold at the target progress
        // Formula derivation: threshold = start * (1 - targetProgress)^n
        // threshold / start = (1 - targetProgress)^n
        // log(threshold / start) = n * log(1 - targetProgress)
        // n = log(threshold / start) / log(1 - targetProgress)
        let n = log(breathingThreshold / startArousal) / log(1.0 - targetProgress)
        
        // Apply the power curve formula
        // Ensure progress doesn't exceed 1.0 to avoid issues with pow()
        let clampedProgress = min(progress, 1.0)
        let calculatedArousal = startArousal * CGFloat(pow(1.0 - clampedProgress, n))
        
        // Clamp the result between endArousal and startArousal
        return max(endArousal, min(startArousal, calculatedArousal))
    }

    private func updateArousalForSession() {
        guard sessionMode else { return }
        
        // Throttle updates to improve performance
        let currentTime = CACurrentMediaTime()
        // Only update if enough time has passed since the last update
        guard (currentTime - lastArousalUpdateTime) >= arousalUpdateInterval else { return }
        
        // Update the timestamp for next check
        lastArousalUpdateTime = currentTime
        
        let elapsedTime = currentTime - sessionStartTime
        let progress = min(1.0, elapsedTime / sessionDuration)
        
        // Calculate target arousal based on exponential decay
        let targetArousal = calculateArousalForProgress(progress)
        
        // Apply arousal change more smoothly
        let arousalDifference = targetArousal - currentArousalLevel
        if abs(arousalDifference) > 0.001 {
            // Apply gradual change rather than jumping directly to target
            let newArousal = currentArousalLevel + (arousalDifference * 0.05)  // 5% step toward target
            currentArousalLevel = newArousal
        }
    }
    
    // --- Session UI Methods ---
    private func setupSessionProgressBar() {
        // Create container for progress bar
        let barWidth = frame.width * 0.8
        let barHeight: CGFloat = 8
        let barPath = CGPath(roundedRect: CGRect(x: -barWidth/2, y: -barHeight/2, width: barWidth, height: barHeight), cornerWidth: 4, cornerHeight: 4, transform: nil)
        
        sessionProgressBar = SKShapeNode(path: barPath)
        sessionProgressBar?.position = CGPoint(x: frame.midX, y: frame.maxY - safeAreaTopInset - 70)
        sessionProgressBar?.fillColor = .darkGray
        sessionProgressBar?.strokeColor = .gray
        sessionProgressBar?.lineWidth = 1
        sessionProgressBar?.zPosition = 100
        addChild(sessionProgressBar!)
        
        // Create fill for progress bar
        let fillPath = CGPath(roundedRect: CGRect(x: 0, y: -barHeight/2, width: 0, height: barHeight), cornerWidth: 4, cornerHeight: 4, transform: nil)
        sessionProgressFill = SKShapeNode(path: fillPath)
        sessionProgressFill?.position = CGPoint(x: -barWidth/2, y: 0)
        sessionProgressFill?.fillColor = .systemBlue
        sessionProgressFill?.strokeColor = .clear
        sessionProgressFill?.zPosition = 101
        sessionProgressBar?.addChild(sessionProgressFill!)
        
        // Add time remaining label
        sessionTimeLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        sessionTimeLabel?.fontSize = 14
        sessionTimeLabel?.fontColor = .white
        sessionTimeLabel?.position = CGPoint(x: 0, y: -20)
        sessionTimeLabel?.horizontalAlignmentMode = .center
        sessionTimeLabel?.text = formatTimeRemaining(sessionDuration)
        sessionProgressBar?.addChild(sessionTimeLabel!)
    }
    
    private func updateSessionProgressBar() {
        guard sessionMode, let progressFill = sessionProgressFill, let timeLabel = sessionTimeLabel else { return }
        
        let currentTime = CACurrentMediaTime()
        let elapsedTime = currentTime - sessionStartTime
        let progress = min(1.0, elapsedTime / sessionDuration)
        let timeRemaining = max(0, sessionDuration - elapsedTime)
        
        // Update progress bar fill
        let barWidth = (sessionProgressBar?.frame.width ?? 100)
        let fillWidth = barWidth * CGFloat(progress)
        
        let barHeight: CGFloat = 8
        let fillPath = CGPath(roundedRect: CGRect(x: 0, y: -barHeight/2, width: fillWidth, height: barHeight), cornerWidth: 4, cornerHeight: 4, transform: nil)
        progressFill.path = fillPath
        
        // Update time remaining label
        timeLabel.text = formatTimeRemaining(timeRemaining)
        
        // Change color based on progress
        if progress < 0.33 {
            progressFill.fillColor = .systemBlue
        } else if progress < 0.66 {
            progressFill.fillColor = .systemGreen
        } else {
            progressFill.fillColor = .systemIndigo
        }
    }
    
    private func formatTimeRemaining(_ timeInSeconds: TimeInterval) -> String {
        let minutes = Int(timeInSeconds) / 60
        let seconds = Int(timeInSeconds) % 60
        return String(format: "%d:%02d remaining", minutes, seconds)
    }

    //====================================================================================================
    // MARK: - MOTION CONTROL
    //====================================================================================================
    // --- Motion Control Throttling Methods ---
    private func startThrottledMotionControl() {
        // Remove any existing action first
        self.removeAction(forKey: motionControlActionKey)
        
        // Create a repeating action that runs every 0.025 seconds (40Hz)
        let wait = SKAction.wait(forDuration: 0.025)
        let update = SKAction.run { [weak self] in
            guard let self = self, self.currentState == .tracking, !self.balls.isEmpty else { return }
            
            let stats = MotionController.calculateStats(balls: self.balls)
            if Int(CACurrentMediaTime() * 60) % 60 == 0 {
                print(String(format: "Motion Stats - Mean: %.1f (Tgt: %.1f) | SD: %.1f (Tgt: %.1f)",
                             stats.meanSpeed, self.motionSettings.targetMeanSpeed,
                             stats.speedSD, self.motionSettings.targetSpeedSD))
            }
            MotionController.applyCorrections(balls: self.balls, settings: self.motionSettings, scene: self)
        }
        
        let sequence = SKAction.sequence([wait, update])
        let repeatAction = SKAction.repeatForever(sequence)
        
        // Run the action on the scene
        self.run(repeatAction, withKey: motionControlActionKey)
    }
    
    private func stopThrottledMotionControl() {
        self.removeAction(forKey: motionControlActionKey)
    }

    //====================================================================================================
    // MARK: - PRECISION TIMER
    //====================================================================================================
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
        let clampedArousal = max(0.0, min(currentArousalLevel, 1.0))
        let audioFreqRange = gameConfiguration.maxAudioFrequency - gameConfiguration.minAudioFrequency
        let currentActualTargetAudioFreq = gameConfiguration.minAudioFrequency + (audioFreqRange * Float(clampedArousal))
        self.lastCalculatedTargetAudioFrequencyForTests = currentActualTargetAudioFreq // Update for tests

        audioManager.handleAudioTick(
            visualTickTime: visualTickTime,
            currentArousal: currentArousalLevel,
            currentTargetAudioFreq: currentActualTargetAudioFreq,
            audioOffset: audioOffset,
            sceneCurrentState: currentState
        )
    }

} // Final closing brace for GameScene Class

// --- Ball class needs to be SKShapeNode ---
