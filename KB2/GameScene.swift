// Kalibrate/GameScene.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 13 - Refactoring Preparation
// Role: Main scene.

import SpriteKit
import GameplayKit
import CoreHaptics
import AVFoundation
import SwiftUI // Added for UIHostingController
import UIKit // Added for UIViewController presentation

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
// Add this before the GameScene class definition
struct SessionChallengePhase {
    // When this challenge starts and ends (as fraction of total session)
    let startProgress: Double
    let endProgress: Double
    
    // How much arousal increases during this challenge
    let intensity: Double
    
    // Helper computed properties
    var duration: Double { return endProgress - startProgress }
    var midPoint: Double { return startProgress + (duration / 2) }
    
    // Is this challenge phase active at the given progress point?
    func isActive(at progress: Double) -> Bool {
        return progress >= startProgress && progress <= endProgress
    }
    
    // Calculate the arousal modifier for the given progress
    func arousalModifier(at progress: Double) -> CGFloat {
        guard isActive(at: progress) else { return 0 }
        
        // Calculate relative position within the challenge (0.0 to 1.0)
        let relativePosition = (progress - startProgress) / duration
        
        // Create a multi-stage curve with faster ramp-up, plateau, and gradual decline
        // - First 30% of challenge: Rapid rise (cubic function)
        // - Middle 40% of challenge: Sustained plateau (near max value)
        // - Final 30% of challenge: Gradual decline (linear fade)
        
        if relativePosition < 0.3 {
            // First 30%: Rapid rise using a cubic function normalized to reach ~1.0 at relativePosition = 0.3
            let normalizedPos = relativePosition / 0.3
            return CGFloat(intensity * pow(normalizedPos, 2.5)) // Steeper rise with power > 1
        } 
        else if relativePosition < 0.7 {
            // Middle 40%: Plateau with slight variation to make it feel organic
            let plateauCenter = 0.5
            let distanceFromCenter = abs(relativePosition - plateauCenter) / 0.2
            let minVariation = 0.9 // Keep intensity at least 90% during plateau
            let variation = 1.0 - (1.0 - minVariation) * pow(distanceFromCenter, 2)
            return CGFloat(intensity * variation)
        }
        else {
            // Final 30%: More gradual linear decline
            let normalizedPos = (1.0 - relativePosition) / 0.3 // Reverse and normalize
            return CGFloat(intensity * normalizedPos * 0.9) // Linear decline from 90%
        }
    }
}

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
var initialArousalLevel: CGFloat = 1.0
var sessionProfile: SessionProfile = .standard // Default profile
var challengePhases: [SessionChallengePhase] = [] // Challenge phases for this session
var breathingTransitionPoint: Double = 0.5  // Add this variable to store the randomized transition point

// --- User Arousal Estimation ---
var arousalEstimator: ArousalEstimator? // Tracks the user's estimated arousal level
private var adaptiveDifficultyManager: AdaptiveDifficultyManager! // ADDED for Adaptive Difficulty

// --- Game Session Tracking ---
private var hasLoggedSessionStart = false
private var isSessionCompleted = false // Added to prevent multiple completions
    
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
                
                // ADDED: Update AdaptiveDifficultyManager with the new arousal level
                if let adm = self.adaptiveDifficultyManager { // Ensure ADM is initialized
                    adm.updateArousalLevel(clampedValue)
                }
                
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
    
    // --- Touch Duration Tracking ---
    private var activeTouchContext: [UITouch: (startTime: TimeInterval, startLocation: CGPoint, tappedBall: Ball?, sceneBallPositions: [String: CGPoint]?, sceneTargetIDs: Set<String>?, sceneDistractorIDs: Set<String>?)] = [:]

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
    internal var currentBreathingHoldAfterInhaleDuration: TimeInterval = GameConfiguration().breathingHoldAfterInhaleDuration
    internal var currentBreathingExhaleDuration: TimeInterval = GameConfiguration().breathingExhaleDuration
    internal var currentBreathingHoldAfterExhaleDuration: TimeInterval = GameConfiguration().breathingHoldAfterExhaleDuration
    private var needsHapticPatternUpdate: Bool = false
    // --- ADDED: Flag for deferred visual duration update ---
    private var needsVisualDurationUpdate: Bool = false
    // --- END ADDED ---
    
    // Add a variable to track if first breathing cycle is completed
    private var completedFirstBreathingCycle: Bool = false
    
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
    
    // --- Challenge Phase UI Elements ---
    internal var challengeIndicator: SKShapeNode!
    private var challengeLabel: SKLabelNode!
    // Change from private to internal for testing purposes
    internal var isInChallengePhase: Bool = false
    
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
        
        // Log the estimated user arousal if available
        if let estimator = arousalEstimator {
            print("USER AROUSAL: Initial value is \(String(format: "%.2f", estimator.currentUserArousalLevel))")
        }
        
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

        // ADDED: Initialize AdaptiveDifficultyManager
        let admInitialArousal = self.sessionMode ? self.initialArousalLevel : self._currentArousalLevel
        self.adaptiveDifficultyManager = AdaptiveDifficultyManager(
            configuration: self.gameConfiguration,
            initialArousal: admInitialArousal
        )
        print("GameScene: AdaptiveDifficultyManager initialized with arousal: \(admInitialArousal)")

        setupPhysicsWorld(); setupWalls(); setupUI(); setupHaptics()
        // setupAudio() // REMOVED - handled by AudioManager init
        
        setupFadeOverlay()
        setupFeedbackAssets()
        
        if hapticsReady { startHapticEngine() }
        audioManager.startEngine() // MODIFIED
        
        if sessionMode {
            sessionStartTime = CACurrentMediaTime()
            _currentArousalLevel = initialArousalLevel
            
            // Randomly determine when the breathing state should begin (40-60% range)
            breathingTransitionPoint = Double.random(in: 
                gameConfiguration.breathingStateTargetRangeMin...gameConfiguration.breathingStateTargetRangeMax)
            
            print("DIAGNOSTIC: Session started with duration \(sessionDuration) seconds, initial arousal \(initialArousalLevel)")
            print("DIAGNOSTIC: Breathing transition target point: \(Int(breathingTransitionPoint * 100))% of session")
            
            // Debug the session profile type with updated labels
            switch sessionProfile {
            case .manual:
                print("DIAGNOSITC: Using MANUAL session profile")
            case .standard:
                print("DIAGNOSTIC: Using SMOOTH session profile - smooth curve, no challenges")
            case .fluctuating:
                print("DIAGNOSTIC: Using DYNAMIC session profile - small variations in arousal")
                generateFluctuations()
            case .challenge:
                print("DIAGNOSTIC: Using CHALLENGE session profile - includes challenging periods")
                generateChallengePhases()
            case .variable:
                print("DIAGNOSTIC: Using VARIABLE session profile - both fluctuations and challenges")
                generateFluctuations()
                generateChallengePhases()
            }
            
            print("DIAGNOSTIC: Generated \(challengePhases.count) challenge phases for this session")
        }
        
        updateParametersFromArousal() // This will now also update audioManager
        
        // ADDED: Update target count from ADM before creating balls
        updateTargetCountFromADM()
        
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
        
        // Setup challenge phase indicator (moved to bottom-right corner)
        challengeIndicator = SKShapeNode(circleOfRadius: 10)
        challengeIndicator.fillColor = .systemRed
        challengeIndicator.strokeColor = .white
        challengeIndicator.lineWidth = 1
        challengeIndicator.position = CGPoint(x: frame.maxX - 30, y: frame.minY + 30) // Changed from top-right to bottom-right
        challengeIndicator.alpha = 0 // Initially invisible
        challengeIndicator.zPosition = 101
        addChild(challengeIndicator)
        
        // Setup challenge notification label
        challengeLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        challengeLabel.text = "CHALLENGE PHASE"
        challengeLabel.fontSize = 24
        challengeLabel.fontColor = .systemRed
        challengeLabel.horizontalAlignmentMode = .center
        challengeLabel.verticalAlignmentMode = .center
        challengeLabel.position = CGPoint(x: frame.midX, y: frame.midY + 100)
        challengeLabel.alpha = 0 // Initially invisible
        challengeLabel.zPosition = 101
        addChild(challengeLabel)
        
        // Add session progress bar if in session mode
        if sessionMode {
            setupSessionProgressBar()
        }
    }
    
    private func setupFadeOverlay() {
        fadeOverlayNode.color = .black // Explicitly set to black
        fadeOverlayNode.size = self.size
        fadeOverlayNode.position = CGPoint(x: frame.midX, y: frame.midY)
        fadeOverlayNode.zPosition = 100
        fadeOverlayNode.alpha = 0.0
        fadeOverlayNode.isUserInteractionEnabled = false // Explicitly disable interaction
        if fadeOverlayNode.parent == nil { addChild(fadeOverlayNode) }
    }

    // --- UI Update ---
    private func updateUI() {
        scoreLabel.text = "Score: \(score)"
        
        // Display both system and user arousal if estimator is available
        if let estimator = arousalEstimator {
            arousalLabel.text = "S: \(String(format: "%.2f", currentArousalLevel)) U: \(String(format: "%.2f", estimator.currentUserArousalLevel))"
        } else {
            arousalLabel.text = "Arousal: \(String(format: "%.2f", currentArousalLevel))"
        }
        switch currentState {
        case .tracking: stateLabel.text = "Tracking"; stateLabel.fontColor = .yellow; countdownLabel.isHidden = true; breathingCueLabel.isHidden = true
        case .identifying: stateLabel.text = "Identify!"; stateLabel.fontColor = .red; countdownLabel.isHidden = false; breathingCueLabel.isHidden = true
        case .breathing: stateLabel.text = "Breathing"; stateLabel.fontColor = .systemBlue; countdownLabel.isHidden = true; breathingCueLabel.isHidden = false
        case .paused: stateLabel.text = "Paused"; stateLabel.fontColor = .gray; countdownLabel.isHidden = true; breathingCueLabel.isHidden = true
        }
        
        // Update session progress if in session mode
        if sessionMode {
            updateSessionProgressBar()
            // The check for session completion (progress >= 1.0) is now handled within 
            // updateSessionProgressBar and updateArousalForSession to ensure 'progress' is in scope.
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
            let minFlashDuration: TimeInterval = 0.85 // High arousal (changed from 1.5)
            let maxFlashDuration: TimeInterval = 2.25 // Low arousal (changed from 2.5)
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
    // MARK: - TASK STATE SNAPSHOT
    //====================================================================================================
    
    /// Create a comprehensive snapshot of the current task state for logging
    private func createTaskStateSnapshot() -> ArousalEstimator.DynamicTaskStateSnapshot {
        let currentTime = CACurrentMediaTime()
        
        // Calculate normalized tracking arousal
        let trackingRange = gameConfiguration.trackingArousalThresholdHigh - gameConfiguration.trackingArousalThresholdLow
        var normalizedTrackingArousal: CGFloat = 0.0
        if trackingRange > 0 {
            let clampedArousal = max(gameConfiguration.trackingArousalThresholdLow, min(currentArousalLevel, gameConfiguration.trackingArousalThresholdHigh))
            normalizedTrackingArousal = (clampedArousal - gameConfiguration.trackingArousalThresholdLow) / trackingRange
        }
        
        // Get visual pulse duration
        let visualPulseDuration = precisionTimer?.visualPulseDuration ?? (1.0 / currentTimerFrequency * gameConfiguration.visualPulseOnDurationRatio)
        
        // Extract RGBA components safely using getRed method
        var r_t: CGFloat = 0, g_t: CGFloat = 0, b_t: CGFloat = 0, a_t: CGFloat = 0
        activeTargetColor.getRed(&r_t, green: &g_t, blue: &b_t, alpha: &a_t)
        
        var r_d: CGFloat = 0, g_d: CGFloat = 0, b_d: CGFloat = 0, a_d: CGFloat = 0
        activeDistractorColor.getRed(&r_d, green: &g_d, blue: &b_d, alpha: &a_d)
        
        var r_f: CGFloat = 0, g_f: CGFloat = 0, b_f: CGFloat = 0, a_f: CGFloat = 0
        gameConfiguration.flashColor.getRed(&r_f, green: &g_f, blue: &b_f, alpha: &a_f)
        
        // Calculate current audio amplitude based on arousal level
        let clampedArousal = max(0.0, min(currentArousalLevel, 1.0))
        let currentAudioAmplitude = 0.3 + (0.4 * Float(clampedArousal)) // Range 0.3-0.7, matching ArousalManager calculation
        
        return ArousalEstimator.DynamicTaskStateSnapshot(
            systemCurrentArousalLevel: currentArousalLevel,
            userCurrentArousalLevel: arousalEstimator?.currentUserArousalLevel,
            normalizedTrackingArousal: normalizedTrackingArousal,
            totalBallCount: gameConfiguration.numberOfBalls,
            currentTargetCount: currentTargetCount,
            targetMeanSpeed: motionSettings.targetMeanSpeed,
            targetSpeedSD: motionSettings.targetSpeedSD,
            currentIdentificationDuration: currentIdentificationDuration,
            currentMinShiftInterval: currentMinShiftInterval,
            currentMaxShiftInterval: currentMaxShiftInterval,
            currentMinIDInterval: currentMinIDInterval,
            currentMaxIDInterval: currentMaxIDInterval,
            currentTimerFrequency: currentTimerFrequency,
            visualPulseDuration: visualPulseDuration,
            activeTargetColor: (r: r_t, g: g_t, b: b_t, a: a_t),
            activeDistractorColor: (r: r_d, g: g_d, b: b_d, a: a_d),
            currentTargetAudioFrequency: lastCalculatedTargetAudioFrequencyForTests ?? gameConfiguration.minAudioFrequency,
            currentAmplitude: currentAudioAmplitude,
            lastFlashColor: (r: r_f, g: g_f, b: b_f, a: a_f),
            lastNumberOfFlashes: nil,
            lastFlashDuration: nil,
            flashSpeedFactor: gameConfiguration.flashSpeedFactor,
            normalizedFeedbackArousal: calculateNormalizedFeedbackArousal(),
            currentBreathingInhaleDuration: currentState == .breathing ? currentBreathingInhaleDuration : nil,
            currentBreathingHoldAfterInhaleDuration: currentState == .breathing ? currentBreathingHoldAfterInhaleDuration : nil,
            currentBreathingExhaleDuration: currentState == .breathing ? currentBreathingExhaleDuration : nil,
            currentBreathingHoldAfterExhaleDuration: currentState == .breathing ? currentBreathingHoldAfterExhaleDuration : nil,
            snapshotTimestamp: currentTime
        )
    }
    
    //====================================================================================================
    // MARK: - IDENTIFICATION PHASE
    //====================================================================================================
    internal func startIdentificationPhase() {
        isEndingIdentification = false
        currentState = .identifying; updateUI()
        physicsWorld.speed = 0; balls.forEach { ball in ball.storedVelocity = ball.physicsBody?.velocity; ball.physicsBody?.velocity = .zero; ball.physicsBody?.isDynamic = false }
        
        // Record identification task start time for performance tracking
        let identificationStartTime = CACurrentMediaTime()
        print("PROXY_TASK: Starting identification task at \(String(format: "%.2f", identificationStartTime))s with \(targetsToFind) targets to find")
        arousalEstimator?.startIdentificationTask(at: identificationStartTime)
        
        // Create and set task state snapshot for comprehensive logging
        if let estimator = arousalEstimator {
            let snapshot = createTaskStateSnapshot()
            estimator.setInitialTaskSnapshot(snapshot)
        }
        
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
        
        // Record identification task completion for performance tracking
        let completionTime = CACurrentMediaTime()
        print("PROXY_TASK: Completing identification task at \(String(format: "%.2f", completionTime))s, success: \(success), found \(targetsFoundThisRound) of \(targetsToFind) targets")
        arousalEstimator?.completeIdentificationTask(at: completionTime, wasSuccessful: success)

        // ADDED: Collect KPIs and forward to AdaptiveDifficultyManager
        if let lastPerformance = self.arousalEstimator?.recentPerformanceHistory.first,
           let adm = self.adaptiveDifficultyManager {

            let taskSuccessKPI = lastPerformance.success
            // Ensure targetsToFind for the completed round is used, not a future/stale value
            let actualTargetsInCompletedRound = self.targetsToFind 
            let tfTtfRatioKPI = actualTargetsInCompletedRound > 0 ? CGFloat(lastPerformance.correctTaps) / CGFloat(actualTargetsInCompletedRound) : 0.0
            
            // Use reactionTime from performance record; fallback to currentIdentificationDuration if no taps recorded
            let reactionTimeKPI = lastPerformance.reactionTime ?? self.currentIdentificationDuration 
            
            var firstTapTimePerf: TimeInterval? = nil
            var lastTapTimePerf: TimeInterval? = nil
            if !lastPerformance.tapEvents.isEmpty {
                firstTapTimePerf = lastPerformance.tapEvents.min(by: { $0.timestamp < $1.timestamp })?.timestamp
                lastTapTimePerf = lastPerformance.tapEvents.max(by: { $0.timestamp < $1.timestamp })?.timestamp
            }
            
            let responseDurationKPI: TimeInterval
            if let first = firstTapTimePerf, let last = lastTapTimePerf, last > first {
                responseDurationKPI = last - first
            } else if lastPerformance.totalTaps > 0 {
                responseDurationKPI = lastPerformance.duration // Fallback to task duration if taps exist but timing is off
            } else {
                responseDurationKPI = 0.0 // No taps, so no response duration
            }

            var totalAccuracyDistance: CGFloat = 0
            var validAccuracyTaps: Int = 0
            
            if !lastPerformance.tapEvents.isEmpty {
                for tapEvent in lastPerformance.tapEvents {
            // Check if tap hit a specific ball
            if let tappedBallName = tapEvent.tappedElementID {
                // Find the tapped ball by iterating through balls
                var foundBall: Ball? = nil
                for ball in self.balls {
                    if ball.name == tappedBallName {
                        foundBall = ball
                        break
                    }
                }
                
                // If we found the ball, calculate distance
                if let tappedBallNode = foundBall {
                    let ballPos = tappedBallNode.position
                    let tapPos = tapEvent.tapLocation
                    let distance = CGPointDistance(from: ballPos, to: tapPos)
                    totalAccuracyDistance += distance
                    validAccuracyTaps += 1
                }
            } else if !self.balls.isEmpty {
                // Tap missed all balls - find distance to nearest ball
                var minDistanceToBall = CGFloat.greatestFiniteMagnitude
                
                for ballNode in self.balls {
                    let ballPos = ballNode.position
                    let tapPos = tapEvent.tapLocation
                    let distance = CGPointDistance(from: ballPos, to: tapPos)
                    
                    if distance < minDistanceToBall {
                        minDistanceToBall = distance
                    }
                }
                
                totalAccuracyDistance += minDistanceToBall
                validAccuracyTaps += 1
            }
                }
            }
            
            let averageTapAccuracyKPI: CGFloat
            if validAccuracyTaps > 0 {
                averageTapAccuracyKPI = totalAccuracyDistance / CGFloat(validAccuracyTaps)
            } else {
                averageTapAccuracyKPI = gameConfiguration.tapAccuracy_WorstExpected_Points
            }

            adm.recordIdentificationPerformance(
                taskSuccess: taskSuccessKPI,
                tfTtfRatio: tfTtfRatioKPI,
                reactionTime: reactionTimeKPI,
                responseDuration: responseDurationKPI,
                averageTapAccuracy: averageTapAccuracyKPI,
                actualTargetsToFindInRound: actualTargetsInCompletedRound
            )
            
            // Explicitly force a DOM update after recording performance
            // This ensures that changes to normalized positions are immediately
            // reflected in the absolute DOM values before the next gameplay phase
            adm.updateForCurrentArousal()
            
            print("GameScene: Sent KPIs to ADM. Success: \(taskSuccessKPI), TF/TTF: \(tfTtfRatioKPI), RT: \(reactionTimeKPI), RD: \(responseDurationKPI), Acc: \(averageTapAccuracyKPI)")
            print("GameScene: Forced DOM update after identification phase")
        }
        // END ADDED KPI Collection

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
                let currentTime = CACurrentMediaTime()
                let tappedNodes = nodes(at: location)
                print("DEBUG: Tap at \(location). Nodes hit: \(tappedNodes.map { $0.name ?? "Unnamed" })") // DEBUG
                
                // Find the tapped ball (if any)
                var tappedBall: Ball? = nil
                for node in tappedNodes {
                    if let ball = node as? Ball {
                        print("DEBUG: Ball node identified: \(ball.name ?? "Unknown")") // DEBUG
                        tappedBall = ball
                        break // Process only the first ball tapped
                    }
                }
                
                // Store touch context for detailed logging
                let ballPositions = Dictionary(uniqueKeysWithValues: balls.map { ($0.name ?? "unknown", $0.position) })
                let targetIDs = Set(balls.filter { $0.isTarget }.compactMap { $0.name })
                let distractorIDs = Set(balls.filter { !$0.isTarget }.compactMap { $0.name })
                
                activeTouchContext[touch] = (
                    startTime: currentTime,
                    startLocation: location,
                    tappedBall: tappedBall,
                    sceneBallPositions: ballPositions,
                    sceneTargetIDs: targetIDs,
                    sceneDistractorIDs: distractorIDs
                )
                
                // Continue with immediate feedback for game responsiveness
                if let ball = tappedBall {
                    handleBallTap(ball)
                }
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard currentState == .identifying else {
            // Clean up any stored contexts for non-identification touches
            for touch in touches {
                activeTouchContext.removeValue(forKey: touch)
            }
            return
        }
        
        // Process each ended touch
        for touch in touches {
            guard let context = activeTouchContext.removeValue(forKey: touch) else {
                continue // No stored context for this touch
            }
            
            let endTime = CACurrentMediaTime()
            let duration = endTime - context.startTime
            
            // Determine if this was a correct tap
            let wasCorrect = context.tappedBall?.isTarget == true
            
            // Send detailed tap event to delegate (via arousalEstimator)
            if let estimator = arousalEstimator {
                estimator.recordDetailedTapEvent(
                    timestamp: context.startTime,
                    tapLocation: context.startLocation,
                    tappedElementID: context.tappedBall?.name,
                    wasCorrect: wasCorrect,
                    ballPositions: context.sceneBallPositions ?? [:],
                    targetBallIDs: context.sceneTargetIDs ?? [],
                    distractorBallIDs: context.sceneDistractorIDs ?? [],
                    tapDuration: duration
                )
            }
            
            print("DEBUG: Touch ended - Duration: \(String(format: "%.3f", duration))s, Correct: \(wasCorrect)") // DEBUG
        }
    }
    
    internal func handleBallTap(_ ball: Ball) {
        guard currentState == .identifying else {
            return
        }

        // --- Calculate Feedback Salience based on Arousal (Used by all feedback in this function) ---
        let normalizedFeedbackArousal = calculateNormalizedFeedbackArousal()
        // ---------------------------------------------------------------------------------------
        
        // Get the current time for performance tracking
        let tapTime = CACurrentMediaTime()
        print("PROXY_TAP: Ball tapped at \(String(format: "%.2f", tapTime))s, ball is target: \(ball.isTarget), hidden: \(ball.isVisuallyHidden)")
        let isCorrectTap = ball.isTarget && ball.isVisuallyHidden && activeParticleEmitters[ball] == nil

        // Check if the ball is currently hidden visually and hasn't already been correctly identified (no emitter attached)
        if ball.isVisuallyHidden && activeParticleEmitters[ball] == nil {
            if ball.isTarget {
                targetsFoundThisRound += 1
                ball.revealIdentity(targetColor: activeTargetColor, distractorColor: activeDistractorColor) // Reveal it
                
                // Record correct tap for performance tracking
                arousalEstimator?.recordTap(at: tapTime, wasCorrect: true)

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
                
                // Record incorrect tap for performance tracking
                arousalEstimator?.recordTap(at: tapTime, wasCorrect: false)

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
    // MARK: - COLOR & DISCRIMINABILITY MANAGEMENT
    //====================================================================================================
    // Dedicated method to update colors based on current discriminability factor
    private func updateColorsFromCurrentDiscriminabilityFactor() {
        // Skip color updates if not in tracking or identifying
        guard currentState == .tracking || currentState == .identifying else { return }
        
        // 1. Calculate normalized arousal value for tracking state
        let trackingRange = gameConfiguration.trackingArousalThresholdHigh - gameConfiguration.trackingArousalThresholdLow
        var normalizedTrackingArousal: CGFloat = 0.0
        if trackingRange > 0 {
            let clampedTrackingArousal = max(gameConfiguration.trackingArousalThresholdLow, min(currentArousalLevel, gameConfiguration.trackingArousalThresholdHigh))
            normalizedTrackingArousal = (clampedTrackingArousal - gameConfiguration.trackingArousalThresholdLow) / trackingRange
        }
        
        // 2. Calculate arousal-driven base target color
        let baseTargetColor = interpolateColor(
            from: gameConfiguration.targetColor_LowArousal,
            to: gameConfiguration.targetColor_HighArousal,
            t: normalizedTrackingArousal
        )
        self.activeTargetColor = baseTargetColor
        
        // 3. Calculate arousal-driven base for "maximally distinct" distractor color
        let baseMaxDistinctDistractorColor = interpolateColor(
            from: gameConfiguration.distractorColor_LowArousal,
            to: gameConfiguration.distractorColor_HighArousal,
            t: normalizedTrackingArousal
        )
        
        // 4. Get the currentDiscriminabilityFactor from ADM
        let dfFromADM = self.adaptiveDifficultyManager?.currentDiscriminabilityFactor ??
                        (gameConfiguration.discriminabilityFactor_MinArousal_EasiestSetting +
                         (gameConfiguration.discriminabilityFactor_MinArousal_HardestSetting - gameConfiguration.discriminabilityFactor_MinArousal_EasiestSetting) * 0.5)
        
        // 5. Calculate the activeDistractorColor using the DF from ADM
        self.activeDistractorColor = interpolateColor(
            from: self.activeTargetColor,
            to: baseMaxDistinctDistractorColor,
            t: dfFromADM
        )
        
        print("GameScene: Updated colors - DF: \(String(format: "%.3f", dfFromADM))")
        
        // 6. Update ball appearances if in tracking state
        if currentState == .tracking { 
            for ball in balls { 
                ball.updateAppearance(targetColor: activeTargetColor, distractorColor: activeDistractorColor) 
            } 
        }
    }
    
    //====================================================================================================
    // MARK: - SPEED PARAMETER MANAGEMENT
    //====================================================================================================
    // Dedicated method to update speed parameters from ADM
    private func updateSpeedParametersFromADM() {
        // Skip speed updates if not in tracking or identifying
        guard currentState == .tracking || currentState == .identifying else { return }
        
        // Get current speed values from ADM
        let meanSpeedFromADM = self.adaptiveDifficultyManager?.currentMeanBallSpeed ??
                               (gameConfiguration.meanBallSpeed_MinArousal_EasiestSetting +
                                (gameConfiguration.meanBallSpeed_MinArousal_HardestSetting - gameConfiguration.meanBallSpeed_MinArousal_EasiestSetting) * 0.5)
        
        let speedSDFromADM = self.adaptiveDifficultyManager?.currentBallSpeedSD ??
                             (gameConfiguration.ballSpeedSD_MinArousal_EasiestSetting +
                              (gameConfiguration.ballSpeedSD_MinArousal_HardestSetting - gameConfiguration.ballSpeedSD_MinArousal_EasiestSetting) * 0.5)
        
        // Update motion settings with ADM values
        self.motionSettings.targetMeanSpeed = meanSpeedFromADM
        self.motionSettings.targetSpeedSD = speedSDFromADM
        
        print("GameScene: Updated speeds from ADM - Mean: \(String(format: "%.1f", meanSpeedFromADM)), SD: \(String(format: "%.1f", speedSDFromADM))")
    }
    
    //====================================================================================================
    // MARK: - TARGET COUNT MANAGEMENT
    //====================================================================================================
    // Dedicated method to update target count from ADM
    private func updateTargetCountFromADM() {
        // Skip target count updates if not in tracking or identifying
        guard currentState == .tracking || currentState == .identifying else { return }
        
        // Get current target count from ADM
        let targetCountFromADM: Int
        if let admTargetCount = self.adaptiveDifficultyManager?.currentTargetCount {
            targetCountFromADM = admTargetCount
        } else {
            // Calculate fallback value
            let easyCount = CGFloat(gameConfiguration.targetCount_MinArousal_EasiestSetting)
            let hardCount = CGFloat(gameConfiguration.targetCount_MinArousal_HardestSetting)
            let midpoint = easyCount + (hardCount - easyCount) * 0.5
            targetCountFromADM = Int(midpoint)
        }
        
        // Only update and reassign targets if the count has changed
        if targetCountFromADM != self.currentTargetCount {
            let oldCount = self.currentTargetCount
            self.currentTargetCount = targetCountFromADM
            print("GameScene: Updated target count from ADM - Old: \(oldCount), New: \(targetCountFromADM)")
            
            // Call removed - target assignment should wait until next scheduled shift
//            if currentState == .tracking && !isFlashSequenceRunning {
//                assignNewTargets()
//            }
        }
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
        
        // First, update the timer frequency
        self.currentTimerFrequency = targetTimerFrequency 
        
        // Update the visual pulse duration whenever timer frequency changes
        let newVisualPulseDuration = 1.0 / targetTimerFrequency * gameConfiguration.visualPulseOnDurationRatio
        precisionTimer?.updateVisualPulseDuration(newDuration: newVisualPulseDuration)
        
        // Then update audio parameters
        audioManager.updateAudioParameters(
            newArousal: currentArousalLevel,
            newTimerFrequency: targetTimerFrequency,
            newTargetAudioFrequency: newTargetAudioFrequency
        )

        // --- State-Specific Overrides & Calculations ---
        switch currentState {
        case .tracking, .identifying:
            // ... (rest of tracking/identifying specific parameter updates: motion, colors, intervals, etc.)
            // ... (ensure activeTargetColor, activeDistractorColor updates remain)
            let trackingRange = gameConfiguration.trackingArousalThresholdHigh - gameConfiguration.trackingArousalThresholdLow
            var normalizedTrackingArousal: CGFloat = 0.0
            if trackingRange > 0 {
                let clampedTrackingArousal = max(gameConfiguration.trackingArousalThresholdLow, min(currentArousalLevel, gameConfiguration.trackingArousalThresholdHigh))
                normalizedTrackingArousal = (clampedTrackingArousal - gameConfiguration.trackingArousalThresholdLow) / trackingRange
            }

            // Speed parameters are now managed by ADM via updateSpeedParametersFromADM()
            // which is called in the throttled motion control loop
            // Target count is also now managed by ADM via updateTargetCountFromADM()

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

            // Update the colors based on the current arousal and DF
            updateColorsFromCurrentDiscriminabilityFactor()
            
            if currentState == .tracking { for ball in balls { ball.updateAppearance(targetColor: activeTargetColor, distractorColor: activeDistractorColor) } }
            needsHapticPatternUpdate = false

        case .breathing:
            self.currentTimerFrequency = targetTimerFrequency
            updateDynamicBreathingParameters()
            motionSettings.targetMeanSpeed = 0
            motionSettings.targetSpeedSD = 0
            // activeTargetColor and activeDistractorColor should persist from the
            // previous state (tracking/identifying) when transitioning into breathing.
            // The balls will be made uniform using the current activeDistractorColor
            // in transitionToBreathingState().

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

        // ADDED: Stop any ongoing flash actions on balls before setting breathing appearance
        for ball in balls {
            ball.removeAction(forKey: "flash")
        }

        for (index, ball) in balls.enumerated() {
            ball.physicsBody?.isDynamic = false; ball.physicsBody?.velocity = .zero; ball.storedVelocity = nil
            ball.isTarget = false // Ensure it's not a target

            // MODIFIED LINE: Use the scene's current active colors.
            // Since isTarget is false, updateAppearance will use activeDistractorColor.
            ball.updateAppearance(targetColor: self.activeTargetColor, distractorColor: self.activeDistractorColor)
            
            ball.alpha = 1.0 // Ensure ball is visible if it was faded
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
        
        // Ensure fade overlay is black for normal breathing fade
        fadeOverlayNode.color = .black
        
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
        
        // Ensure fade overlay is black for normal breathing visuals
        fadeOverlayNode.color = .black
        
        breathingVisualsFaded = false
        let fadeIn = SKAction.fadeIn(withDuration: gameConfiguration.fadeDuration)
        let fadeOutOverlay = SKAction.fadeOut(withDuration: gameConfiguration.fadeDuration)
        balls.forEach { $0.run(fadeIn) }
        breathingCueLabel.run(fadeIn)
        fadeOverlayNode.run(fadeOutOverlay)
    }

    //====================================================================================================
    // MARK: - BREATHING ANIMATION
    //====================================================================================================
    // --- Breathing Animation ---
    private func startBreathingAnimation() {
        guard currentState == .breathing else { return }
        currentBreathingPhase = .inhale
        // Reset the flag when starting a new breathing session
        completedFirstBreathingCycle = false
        runBreathingCycleAction()
    }
    
    private func stopBreathingAnimation() {
        self.removeAction(forKey: breathingAnimationActionKey)
        try? breathingHapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        currentBreathingPhase = .idle
        breathingCueLabel.isHidden = true
        // Reset the flag when stopping
        completedFirstBreathingCycle = false
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

                 let minInhale = gameConfiguration.dynamicBreathingMinInhaleDuration
                 let maxInhale = gameConfiguration.dynamicBreathingMaxInhaleDuration
                 let minExhale = gameConfiguration.dynamicBreathingMinExhaleDuration
                 let maxExhale = gameConfiguration.dynamicBreathingMaxExhaleDuration

                 let targetInhaleDuration = minInhale + (maxInhale - minInhale) * normalizedBreathingArousal
                 let targetExhaleDuration = maxExhale + (minExhale - maxExhale) * normalizedBreathingArousal

                 // Calculate proportional hold durations
                 // Hold after inhale: 30% at low arousal -> 5% at high arousal
                 let holdAfterInhaleProportion = gameConfiguration.holdAfterInhaleProportion_LowArousal + 
                     (gameConfiguration.holdAfterInhaleProportion_HighArousal - gameConfiguration.holdAfterInhaleProportion_LowArousal) * normalizedBreathingArousal
                 let targetHoldAfterInhaleDuration = targetInhaleDuration * TimeInterval(holdAfterInhaleProportion)
                 
                 // Hold after exhale: 50% at low arousal -> 20% at high arousal
                 let holdAfterExhaleProportion = gameConfiguration.holdAfterExhaleProportion_LowArousal + 
                     (gameConfiguration.holdAfterExhaleProportion_HighArousal - gameConfiguration.holdAfterExhaleProportion_LowArousal) * normalizedBreathingArousal
                 let targetHoldAfterExhaleDuration = targetExhaleDuration * TimeInterval(holdAfterExhaleProportion)

                 currentBreathingInhaleDuration = targetInhaleDuration
                 currentBreathingExhaleDuration = targetExhaleDuration
                 currentBreathingHoldAfterInhaleDuration = targetHoldAfterInhaleDuration
                 currentBreathingHoldAfterExhaleDuration = targetHoldAfterExhaleDuration
                 
                 print("DIAGNOSTIC: Updated visual durations - Inhale: \(String(format: "%.2f", currentBreathingInhaleDuration)), Exhale: \(String(format: "%.2f", currentBreathingExhaleDuration))")
                 print("DIAGNOSTIC: Updated hold durations - After Inhale: \(String(format: "%.2f", currentBreathingHoldAfterInhaleDuration)), After Exhale: \(String(format: "%.2f", currentBreathingHoldAfterExhaleDuration))")
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
        let holdAfterInhaleVisual = SKAction.wait(forDuration: currentBreathingHoldAfterInhaleDuration)
        let exhaleAction = SKAction.customAction(withDuration: currentBreathingExhaleDuration) { _, elapsedTime in
            let fraction = elapsedTime / CGFloat(self.currentBreathingExhaleDuration)
            let currentRadius = self.gameConfiguration.breathingCircleMaxRadius - (self.gameConfiguration.breathingCircleMaxRadius - self.gameConfiguration.breathingCircleMinRadius) * fraction
            let positions = MotionController.circlePoints(numPoints: self.balls.count, center: centerPoint, radius: currentRadius)
            for (index, ball) in self.balls.enumerated() { if index < positions.count { ball.position = positions[index] } }
        }; exhaleAction.timingMode = .easeInEaseOut
        let holdAfterExhaleVisual = SKAction.wait(forDuration: currentBreathingHoldAfterExhaleDuration)
        let setInhaleCue = SKAction.run { [weak self] in 
            guard let self = self else { return }
            self.updateBreathingPhase(.inhale)
            // Ensure label stays hidden after first cycle
            if self.completedFirstBreathingCycle {
                self.breathingCueLabel.isHidden = true
            }
        }
        let setHoldAfterInhaleCue = SKAction.run { [weak self] in 
            guard let self = self else { return }
            self.updateBreathingPhase(.holdAfterInhale)
            // Ensure label stays hidden after first cycle
            if self.completedFirstBreathingCycle {
                self.breathingCueLabel.isHidden = true
            }
        }
        let setExhaleCue = SKAction.run { [weak self] in 
            guard let self = self else { return }
            self.updateBreathingPhase(.exhale)
            // Ensure label stays hidden after first cycle
            if self.completedFirstBreathingCycle {
                self.breathingCueLabel.isHidden = true
            }
        }
        let setHoldAfterExhaleCue = SKAction.run { [weak self] in 
            guard let self = self else { return }
            self.updateBreathingPhase(.holdAfterExhale)
            // Ensure label stays hidden after first cycle
            if self.completedFirstBreathingCycle {
                self.breathingCueLabel.isHidden = true
            }
        }
        let restartHaptics = SKAction.run { [weak self] in
             try? self?.breathingHapticPlayer?.start(atTime: CHHapticTimeImmediate)
        }
        let sequence = SKAction.sequence([
            restartHaptics, setInhaleCue, inhaleAction,
            setHoldAfterInhaleCue, holdAfterInhaleVisual,
            setExhaleCue, exhaleAction,
            setHoldAfterExhaleCue, holdAfterExhaleVisual
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

        let runAgain = SKAction.run { [weak self] in 
            guard let self = self else { return }
            // Mark the first cycle as completed before running the next cycle
            self.completedFirstBreathingCycle = true
            self.runBreathingCycleAction() 
        }
        self.run(SKAction.sequence([sequence, applyDeferredHapticUpdate, runAgain]), withKey: breathingAnimationActionKey)
    }
    
    private func updateBreathingPhase(_ newPhase: BreathingPhase) {
        currentBreathingPhase = newPhase
        
        // Only update the breathing cue label text if this is the first cycle
        if !completedFirstBreathingCycle {
            switch newPhase {
            case .idle: breathingCueLabel.text = ""
            case .inhale: breathingCueLabel.text = "Inhale"
            case .holdAfterInhale: breathingCueLabel.text = "Hold"
            case .exhale: breathingCueLabel.text = "Exhale"
            case .holdAfterExhale: breathingCueLabel.text = "Hold"
            }
            breathingCueLabel.isHidden = false
        } else {
            // For cycles after the first one, hide the label and clear the text
            breathingCueLabel.isHidden = true
            breathingCueLabel.text = ""
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
                                                                   holdAfterInhaleDuration: currentBreathingHoldAfterInhaleDuration,
                                                                   exhaleDuration: currentBreathingExhaleDuration,
                                                                   holdAfterExhaleDuration: currentBreathingHoldAfterExhaleDuration) {
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
    private func generateBreathingHapticPattern(inhaleDuration: TimeInterval, holdAfterInhaleDuration: TimeInterval, exhaleDuration: TimeInterval, holdAfterExhaleDuration: TimeInterval) -> CHHapticPattern? {
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
         while relativeTime < holdAfterInhaleDuration - 0.01 {
             let absoluteTime = phaseStartTime + relativeTime
             let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: hapticIntensity)
             let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpnessMin)
             allBreathingEvents.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: absoluteTime))
             relativeTime += minimumDelay
         }
         phaseStartTime += holdAfterInhaleDuration

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
         // No HoldAfterExhale Events

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

        // Define target duration ranges using GameConfiguration
        let minInhale = gameConfiguration.dynamicBreathingMinInhaleDuration
        let maxInhale = gameConfiguration.dynamicBreathingMaxInhaleDuration
        let minExhale = gameConfiguration.dynamicBreathingMinExhaleDuration
        let maxExhale = gameConfiguration.dynamicBreathingMaxExhaleDuration

        // Interpolate: Low arousal (norm=0.0) -> Long exhale; High arousal (norm=1.0) -> Balanced
        let targetInhaleDuration = minInhale + (maxInhale - minInhale) * normalizedBreathingArousal
        let targetExhaleDuration = maxExhale + (minExhale - maxExhale) * normalizedBreathingArousal

        // Calculate proportional hold durations
        // Hold after inhale: 30% at low arousal -> 5% at high arousal
        let holdAfterInhaleProportion = gameConfiguration.holdAfterInhaleProportion_LowArousal + 
            (gameConfiguration.holdAfterInhaleProportion_HighArousal - gameConfiguration.holdAfterInhaleProportion_LowArousal) * normalizedBreathingArousal
        let targetHoldAfterInhaleDuration = targetInhaleDuration * TimeInterval(holdAfterInhaleProportion)
        
        // Hold after exhale: 50% at low arousal -> 20% at high arousal
        let holdAfterExhaleProportion = gameConfiguration.holdAfterExhaleProportion_LowArousal + 
            (gameConfiguration.holdAfterExhaleProportion_HighArousal - gameConfiguration.holdAfterExhaleProportion_LowArousal) * normalizedBreathingArousal
        let targetHoldAfterExhaleDuration = targetExhaleDuration * TimeInterval(holdAfterExhaleProportion)

        // --- INTENTIONALLY PLACING DURATION CHECK HERE ---
        // Check if change exceeds tolerance
        let tolerance: TimeInterval = 0.1
        if abs(targetInhaleDuration - currentBreathingInhaleDuration) > tolerance || 
           abs(targetExhaleDuration - currentBreathingExhaleDuration) > tolerance ||
           abs(targetHoldAfterInhaleDuration - currentBreathingHoldAfterInhaleDuration) > tolerance ||
           abs(targetHoldAfterExhaleDuration - currentBreathingHoldAfterExhaleDuration) > tolerance {
            print("DIAGNOSTIC: Breathing duration change detected. Flagging for update...")
            print("DIAGNOSTIC: Target pattern - Inhale: \(String(format: "%.1f", targetInhaleDuration))s, Exhale: \(String(format: "%.1f", targetExhaleDuration))s")
            print("DIAGNOSTIC: Target holds - After Inhale: \(String(format: "%.1f", targetHoldAfterInhaleDuration))s, After Exhale: \(String(format: "%.1f", targetHoldAfterExhaleDuration))s")
            
            // Log breathing pattern change to DataLogger
            DataLogger.shared.logBreathingPatternChange(
                oldInhaleDuration: currentBreathingInhaleDuration,
                newInhaleDuration: targetInhaleDuration,
                oldExhaleDuration: currentBreathingExhaleDuration,
                newExhaleDuration: targetExhaleDuration,
                oldHoldAfterInhaleDuration: currentBreathingHoldAfterInhaleDuration,
                newHoldAfterInhaleDuration: targetHoldAfterInhaleDuration,
                oldHoldAfterExhaleDuration: currentBreathingHoldAfterExhaleDuration,
                newHoldAfterExhaleDuration: targetHoldAfterExhaleDuration,
                arousalLevel: currentArousalLevel,
                normalizedBreathingArousal: normalizedBreathingArousal
            )
            
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
                                                               holdAfterInhaleDuration: currentBreathingHoldAfterInhaleDuration,
                                                               exhaleDuration: currentBreathingExhaleDuration,
                                                               holdAfterExhaleDuration: currentBreathingHoldAfterExhaleDuration) else {
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
        
        // Log arousal levels much less frequently to avoid flooding
        if Int(currentTime) % 30 == 0 && Int(lastUpdateTime) % 30 != 0 {
            if let estimator = arousalEstimator {
                print("PROXY_UPDATE: Current arousal levels - System: \(String(format: "%.2f", currentArousalLevel)), User: \(String(format: "%.2f", estimator.currentUserArousalLevel))")
            }
        }
        
        // Log session start data if needed
        if sessionMode && !hasLoggedSessionStart {
            hasLoggedSessionStart = true
            
            // Log system arousal level at start
            print("DIAGNOSTIC: Session started with system arousal at \(String(format: "%.2f", currentArousalLevel))")
            
            // Log user arousal level if available
            if let estimator = arousalEstimator {
                print("DIAGNOSTIC: Initial user arousal estimate is \(String(format: "%.2f", estimator.currentUserArousalLevel))")
                
                // Log the difference between system and user arousal
                let difference = abs(currentArousalLevel - estimator.currentUserArousalLevel)
                print("DIAGNOSTIC: Initial arousal mismatch is \(String(format: "%.2f", difference))")
            }
            
            // Log session phase is now handled by startSession()
        }
        
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
        // Get the base arousal value following the power curve
        let baseArousal = calculateBaseArousalForProgress(progress)
        
        // Apply profile-specific modifiers
        var modifiedArousal = baseArousal
        
        switch sessionProfile {
        case .manual:
            break
        case .standard:
            // Standard curve, no modifications
            return baseArousal
            
        case .fluctuating, .variable:
            // Add small random fluctuations
            modifiedArousal = applyFluctuations(to: baseArousal, at: progress)
            fallthrough // Allow challenge phases to also apply in variable mode
            
        case .challenge:
            // Apply any active challenge phases
            modifiedArousal = applyChallengePhases(to: modifiedArousal, at: progress)
        }
        
        // Ensure we don't go beyond valid range
        return max(0.0, min(initialArousalLevel, modifiedArousal))
    }

    // New method: Calculate base arousal using the original power curve formula
    internal func calculateBaseArousalForProgress(_ progress: Double) -> CGFloat {
        // Use a Power Curve: A(p) = A_start * (1 - p)^n
        // Where n is calculated to make A(0.5) = breathingThreshold
        
        let startArousal = initialArousalLevel
        let endArousal: CGFloat = 0.0 // Target end arousal
        let breathingThreshold = gameConfiguration.trackingArousalThresholdLow
        
        // Use the randomized transition point instead of the fixed 0.5
        let targetProgress: Double = breathingTransitionPoint
        
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

    // New method: Apply subtle fluctuations to arousal value
    private func applyFluctuations(to baseArousal: CGFloat, at progress: Double) -> CGFloat {
        // No fluctuations at very start or end of session
        if progress < 0.05 || progress > 0.95 {
            return baseArousal
        }
        
        // Create deterministic but pseudo-random fluctuations based on progress
        // Using multiple sine waves of different frequencies creates natural-feeling variation
        let frequency1 = 15.0 // High frequency component
        let frequency2 = 5.0  // Medium frequency component
        let frequency3 = 2.0  // Low frequency component
        
        let wave1 = sin(progress * .pi * frequency1) * 0.02 // Small amplitude
        let wave2 = sin(progress * .pi * frequency2) * 0.03 // Medium amplitude
        let wave3 = sin(progress * .pi * frequency3) * 0.01 // Small amplitude
        
        // Combined weighted fluctuation
        let fluctuation = CGFloat(wave1 + wave2 + wave3)
        
        // Apply fluctuation but ensure we don't go below 0 or above initial arousal
        return max(0.01, min(initialArousalLevel, baseArousal + fluctuation))
    }

    // New method: Apply challenge phase modifications
    private func applyChallengePhases(to baseArousal: CGFloat, at progress: Double) -> CGFloat {
        // If no challenges or none active, return the base value
        guard !challengePhases.isEmpty, 
              (sessionProfile == .challenge || sessionProfile == .variable) else {
            return baseArousal
        }
        
        // Find any active challenge phases
        var totalModifier: CGFloat = 0
        var activeChallenge = false
        
        for phase in challengePhases {
            if phase.isActive(at: progress) {
                activeChallenge = true
                // Get this phase's modifier and add it to the total
                let modifier = phase.arousalModifier(at: progress)
                totalModifier += modifier
                
                // Debug output for significant modifiers
                if modifier > 0.05 {
                    print("CHALLENGE EFFECT: Adding \(String(format: "%.2f", modifier)) to arousal at progress \(Int(progress * 100))%")
                }
            }
        }
        
        // Apply total modifier to base arousal
        let modifiedArousal = baseArousal + totalModifier
        
        // Ensure we stay within valid range - but allow exceeding the initial value during challenges
        // This is key to making challenges noticeable - they can temporarily increase arousal
        let maxLimit = max(initialArousalLevel, baseArousal + 0.3) // Allow going above initial arousal
        return max(0.0, min(maxLimit, modifiedArousal))
    }

    private func updateArousalForSession() {
        guard sessionMode, !isSessionCompleted else { return } // Do not update if session is already completed
        
        // Throttle updates to improve performance
        let currentTime = CACurrentMediaTime()
        // Only update if enough time has passed since the last update
        guard (currentTime - lastArousalUpdateTime) >= arousalUpdateInterval else { return }
        
        // Update the timestamp for next check
        lastArousalUpdateTime = currentTime
        
        // For manual profile, only update session progress and check completion
        if sessionProfile == .manual {
            let elapsedTime = currentTime - sessionStartTime
            let progress = min(1.0, elapsedTime / sessionDuration)
            
            // Check for session completion
            if progress >= 1.0 && !isSessionCompleted {
                print("DEBUG: Manual profile session completion detected.")
                handleSessionCompletion()
            }
            
            // Update UI for session progress only, no arousal modulation
            updateUI()
            return
        }
        
        let elapsedTime = currentTime - sessionStartTime
        let progress = min(1.0, elapsedTime / sessionDuration)

        // Check for session completion FIRST (moved to updateUI and also checked here for safety)
        if progress >= 1.0 {
            if !isSessionCompleted {
                 print("DEBUG: updateArousalForSession detected session completion. Calling handleSessionCompletion.")
                handleSessionCompletion()
            }
            return // Stop further processing if session is done
        }
        
        // Every 5 seconds, print the progress
        if Int(elapsedTime) % 5 == 0 && Int(elapsedTime) > 0 {
            print("Session progress: \(Int(progress * 100))% (\(Int(elapsedTime))s / \(Int(sessionDuration))s)")
            
            // Check and report on any active challenge
            if sessionProfile == .challenge || sessionProfile == .variable {
                for (i, phase) in challengePhases.enumerated() {
                    if phase.isActive(at: progress) {
                        // Calculate how far into the challenge we are
                        let challengeProgress = (progress - phase.startProgress) / phase.duration
                        let phaseDescription = challengeProgress < 0.3 ? "RAMP-UP" : 
                                              (challengeProgress < 0.7 ? "PLATEAU" : "DECLINE")
                        
                        print("  ACTIVE CHALLENGE \(i+1): \(Int(challengeProgress * 100))% complete - \(phaseDescription) phase")
                        print("  Phase timing: \(Int(phase.startProgress * 100))-\(Int(phase.endProgress * 100))% with intensity \(phase.intensity)")
                        
                        // Show the actual effect of the challenge on arousal
                        let baseArousal = calculateBaseArousalForProgress(progress)
                        let modifier = phase.arousalModifier(at: progress)
                        print("  Challenge effect: +\(String(format: "%.2f", modifier)) to arousal")
                    }
                }
            }
        }
        
        // Calculate target arousal based on exponential decay
        let baseArousal = calculateBaseArousalForProgress(progress)
        let targetArousal = calculateArousalForProgress(progress)
        
        // If there's a significant difference, log it (likely due to a challenge)
        if abs(targetArousal - baseArousal) > 0.05 {
            print("AROUSAL MODIFICATION: Base: \(String(format: "%.2f", baseArousal)), Target: \(String(format: "%.2f", targetArousal)), Diff: \(String(format: "%.2f", targetArousal - baseArousal))")
        }
        
        // Apply arousal change more smoothly
        let arousalDifference = targetArousal - currentArousalLevel
        if abs(arousalDifference) > 0.001 {
            // Apply gradual change rather than jumping directly to target
            let newArousal = currentArousalLevel + (arousalDifference * 0.05)  // 5% step toward target
            currentArousalLevel = newArousal
        }
        
        // Check for challenge phase
        let wasInChallengePhase = isInChallengePhase
        isInChallengePhase = false
        
        // Check if we're currently in any challenge phase
        if sessionProfile == .challenge || sessionProfile == .variable {
            for phase in challengePhases {
                if phase.isActive(at: progress) {
                    isInChallengePhase = true
                    break
                }
            }
        }
        
        // Handle challenge phase visualization
        if isInChallengePhase != wasInChallengePhase {
            if isInChallengePhase {
                // Starting a challenge phase
                print("CHALLENGE PHASE STARTED at \(Int(progress * 100))% (\(Int(elapsedTime))s)")
                startChallengePhaseVisualization()
            } else {
                // Ending a challenge phase
                print("CHALLENGE PHASE ENDED at \(Int(progress * 100))% (\(Int(elapsedTime))s)")
                endChallengePhaseVisualization()
            }
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
        // Allow one final update if session was just completed to show 100%
        if isSessionCompleted && progressFill.path?.boundingBox.width == (sessionProgressBar?.frame.width ?? 0) {
             return
        }

        let currentTime = CACurrentMediaTime()
        let elapsedTime = currentTime - sessionStartTime
        let progress = min(1.0, elapsedTime / sessionDuration) // progress is calculated here
        let timeRemaining = max(0, sessionDuration - elapsedTime)

        // Check for session completion
        if progress >= 1.0 && !isSessionCompleted {
            print("DEBUG: updateSessionProgressBar detected session completion. Calling handleSessionCompletion.")
            // Call handleSessionCompletion, but allow this UI update to complete to show 100%
            // The isSessionCompleted flag will prevent repeated logic in handleSessionCompletion
            handleSessionCompletion() 
        }
        
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
        
        // Add continuous update for AdaptiveDifficultyManager
        let updateADM = SKAction.run { [weak self] in
            guard let self = self, let adm = self.adaptiveDifficultyManager else { return }
            
            // Continuously update DOM targets based on current arousal
            adm.updateForCurrentArousal()
            
            // Recalculate colors based on the updated DF from ADM
            self.updateColorsFromCurrentDiscriminabilityFactor()
            
            // Update speed parameters from ADM
            self.updateSpeedParametersFromADM()
            
            // Update target count from ADM
            self.updateTargetCountFromADM()
            
            // If we're in tracking state, update ball appearances to reflect any DF changes
            if self.currentState == .tracking {
                for ball in self.balls {
                    ball.updateAppearance(targetColor: self.activeTargetColor, distractorColor: self.activeDistractorColor)
                }
            }
        }
        
        let sequence = SKAction.sequence([wait, update, updateADM])
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
        
        // Set initial visual pulse duration based on game configuration
        let visualPulseDuration = 1.0 / currentTimerFrequency * gameConfiguration.visualPulseOnDurationRatio
        precisionTimer?.updateVisualPulseDuration(newDuration: visualPulseDuration)
        
        precisionTimer?.onVisualTick = { [weak self] in self?.handleVisualTick() }
        precisionTimer?.onHapticTick = { [weak self] t in self?.handleHapticTick(visualTickTime: t) }
        precisionTimer?.onAudioTick = { [weak self] t in self?.handleAudioTick(visualTickTime: t) }
    }

    // --- Timer Callback Handlers ---
    private func handleVisualTick() {
        guard currentState == .tracking || currentState == .identifying || currentState == .breathing else { return }
        guard !balls.isEmpty else { return }
        guard let _ = balls.first?.strokeColor else { return } 
        
        // Use the visual pulse duration from the timer for consistency
        let visualPulseDuration = precisionTimer?.visualPulseDuration ?? 0.02
        
        for ball in balls {
            if !breathingVisualsFaded || currentState != .breathing {
                let setBorderOn = SKAction.run { ball.lineWidth = Ball.pulseLineWidth }
                let setBorderOff = SKAction.run { ball.lineWidth = 0 }
                let waitOn = SKAction.wait(forDuration: visualPulseDuration)
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
        
        // Ensure haptic offset is within reasonable bounds
        let safeHapticOffset = max(-0.05, min(hapticOffset, 0.05)) // Limit between -50ms and +50ms
        let hapticStartTime = visualTickTime + safeHapticOffset
        
        try? player.start(atTime: hapticStartTime)
    }

    private func handleAudioTick(visualTickTime: CFTimeInterval) {
        let clampedArousal = max(0.0, min(currentArousalLevel, 1.0))
        let audioFreqRange = gameConfiguration.maxAudioFrequency - gameConfiguration.minAudioFrequency
        let currentActualTargetAudioFreq = gameConfiguration.minAudioFrequency + (audioFreqRange * Float(clampedArousal))
        self.lastCalculatedTargetAudioFrequencyForTests = currentActualTargetAudioFreq // Update for tests

        // Ensure audio offset is within reasonable bounds
        let safeAudioOffset = max(-0.05, min(audioOffset, 0.05)) // Limit between -50ms and +50ms

        audioManager.handleAudioTick(
            visualTickTime: visualTickTime,
            currentArousal: currentArousalLevel,
            currentTargetAudioFreq: currentActualTargetAudioFreq,
            audioOffset: safeAudioOffset,
            sceneCurrentState: currentState
        )
    }

    // --- Session Profile Generation ---
    private func generateSessionProfile() {
        // Clear any existing challenge phases
        challengePhases.removeAll()
        
        switch sessionProfile {
        case .manual:
            break
        case .standard:
            // Standard profile has no challenges or fluctuations
            break
            
        case .fluctuating:
            // Generate small random fluctuations throughout the session
            generateFluctuations()
            
        case .challenge:
            // Generate specific challenge phases
            generateChallengePhases()
            
        case .variable:
            // Both fluctuations and challenges
            generateFluctuations()
            generateChallengePhases()
        }
    }

    private func generateFluctuations() {
        // For now, fluctuations are implemented in the calculateArousalForProgress method
        // They don't require pre-generation like challenge phases
    }

    private func generateChallengePhases() {
        // Only generate challenge phases with the configured probability
        guard Double.random(in: 0...1) <= gameConfiguration.challengePhaseProbability else {
            print("DIAGNOSTIC: No challenge phases for this session (random probability)")
            return
        }
        
        // Determine how many challenge phases to include
        let count = Int.random(in: gameConfiguration.challengePhaseCount)
        print("DIAGNOSTIC: Generating \(count) challenge phases for this session")
        
        // Available progress range for challenges
        let startRange = gameConfiguration.challengePhaseRelativeStart
        let durationRange = gameConfiguration.challengePhaseDuration
        let intensityRange = gameConfiguration.challengePhaseIntensity
        
        // Ensure no challenge extends into the final 10% of the session
        let finalCutoffPoint: Double = 0.9
        
        // Track already used progress ranges to avoid overlaps
        var usedRanges: [(start: Double, end: Double)] = []
        
        // Generate each challenge phase
        for i in 0..<count {
            var attempts = 0
            var validPhaseFound = false
            var newPhase: SessionChallengePhase?
            
            // Try to find a non-overlapping placement
            while !validPhaseFound && attempts < 10 {
                attempts += 1
                
                // Random parameters for this challenge
                let start = Double.random(in: startRange)
                let duration = Double.random(in: durationRange)
                let end = min(start + duration, finalCutoffPoint - 0.01) // Ensure it ends before final 10%
                
                // Skip this attempt if the end would be too close to the start (due to cutoff)
                if end - start < durationRange.lowerBound {
                    continue
                }
                
                let intensity = Double.random(in: intensityRange)
                
                // Check if this overlaps with any existing phases
                let overlaps = usedRanges.contains { 
                    (start <= $0.end + 0.05 && end >= $0.start - 0.05) 
                }
                
                if !overlaps {
                    newPhase = SessionChallengePhase(
                        startProgress: start,
                        endProgress: end,
                        intensity: intensity
                    )
                    usedRanges.append((start, end))
                    validPhaseFound = true
                }
            }
            
            if let phase = newPhase {
                challengePhases.append(phase)
                print("DIAGNOSTIC: Added challenge phase \(i+1): \(phase.startProgress) to \(phase.endProgress), intensity \(phase.intensity)")
            }
        }
        
        // Sort challenges by start time
        challengePhases.sort { $0.startProgress < $1.startProgress }
        
        // Extra diagnostics
        if challengePhases.isEmpty {
            print("WARNING: Failed to generate any challenge phases despite trying")
        } else {
            print("DIAGNOSTIC: Final challenge phases for this session:")
            for (i, phase) in challengePhases.enumerated() {
                let startSecs = phase.startProgress * sessionDuration
                let endSecs = phase.endProgress * sessionDuration
                let durationSecs = endSecs - startSecs
                print("  Phase \(i+1): Start at \(Int(startSecs))s, End at \(Int(endSecs))s, Duration: \(Int(durationSecs))s, Intensity: \(phase.intensity)")
            }
        }
    }

    // New methods to handle challenge phase visualization
    internal func startChallengePhaseVisualization() {
        // Show persistent indicator with more contrast
        challengeIndicator.fillColor = .systemRed
        challengeIndicator.strokeColor = .white
        challengeIndicator.lineWidth = 2
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        challengeIndicator.run(fadeIn)
        
        // Make the challenge label more prominent
        challengeLabel.fontColor = .white
        challengeLabel.fontSize = 28
        
        // Add background to the label for contrast
        let labelBackground = SKShapeNode(rectOf: CGSize(width: 300, height: 50), cornerRadius: 10)
        labelBackground.fillColor = .systemRed
        labelBackground.strokeColor = .white
        labelBackground.lineWidth = 2
        labelBackground.position = challengeLabel.position
        labelBackground.zPosition = challengeLabel.zPosition - 1
        labelBackground.alpha = 0
        labelBackground.name = "challengeLabelBg"
        addChild(labelBackground)
        
        // Show and then hide notification banner with background
        let showBanner = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        let wait = SKAction.wait(forDuration: 3.0) // Longer display time
        let hideBanner = SKAction.fadeAlpha(to: 0.0, duration: 0.5)
        challengeLabel.run(SKAction.sequence([showBanner, wait, hideBanner]))
        labelBackground.run(SKAction.sequence([showBanner, wait, hideBanner]))
        
        // Add stronger pulse effect to the indicator
        let scaleUp = SKAction.scale(to: 1.5, duration: 0.4)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.4)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        let repeatPulse = SKAction.repeatForever(pulse)
        challengeIndicator.run(repeatPulse, withKey: "challengePulse")
        
        // More noticeable screen flash
        fadeOverlayNode.color = .red
        fadeOverlayNode.alpha = 0
        let flashOn = SKAction.fadeAlpha(to: 0.25, duration: 0.2)
        let flashOff = SKAction.fadeAlpha(to: 0.0, duration: 0.2)
        fadeOverlayNode.run(SKAction.sequence([flashOn, flashOff, flashOn, flashOff, flashOn, flashOff]))
    }

    internal func endChallengePhaseVisualization() {
        // Hide indicator
        let fadeOut = SKAction.fadeAlpha(to: 0.0, duration: 0.5)
        challengeIndicator.run(fadeOut)
        challengeIndicator.removeAction(forKey: "challengePulse")
        
        // Remove label background
        if let bg = childNode(withName: "challengeLabelBg") {
            bg.run(SKAction.sequence([fadeOut, SKAction.removeFromParent()]))
        }
        
        // Reset scale
        challengeIndicator.setScale(1.0)
        
        // Reset fadeOverlayNode color back to black for breathing state
        fadeOverlayNode.color = .black
        fadeOverlayNode.alpha = 0
    }

    // --- ADDED: Session Completion and EMA Handling ---
    private func handleSessionCompletion() {
        guard !isSessionCompleted else {
            print("DEBUG: handleSessionCompletion called but session already marked as completed.")
            return
        }
        isSessionCompleted = true // Mark as completed to prevent multiple calls

        print("--- Session Completed ---")
        DataLogger.shared.logStateTransition(from: "session_active", to: "session_end")

        // Stop all game activities
        precisionTimer?.stop()
        stopIdentificationTimeout()
        stopBreathingAnimation()
        stopThrottledMotionControl()
        audioManager.stopEngine() // Assuming AudioManager has a stopEngine or similar method
        
        if hapticsReady {
            hapticEngine?.stop(completionHandler: { error in
                if let error = error { print("Error stopping haptic engine: \(error.localizedDescription)") }
            })
        }
        
        // Pause physics and clear actions
        self.isPaused = true // This pauses SKActions as well
        self.physicsWorld.speed = 0
        self.removeAllActions() // Clear any pending scene actions

        // Log final arousal levels before EMA
        if let estimator = arousalEstimator {
            DataLogger.shared.logArousalLevels(
                systemArousal: currentArousalLevel,
                userArousal: estimator.currentUserArousalLevel,
                phase: "session_end_pre_ema"
            )
        } else {
            DataLogger.shared.logArousalLevels(
                systemArousal: currentArousalLevel,
                userArousal: nil, // No estimator
                phase: "session_end_pre_ema"
            )
        }
        
        // Present the post-session EMA
        // Ensure this is done on the main thread as it involves UI updates
        DispatchQueue.main.async { [weak self] in
            self?.presentPostSessionEMA()
        }
    }

    private func presentPostSessionEMA() {
        print("Presenting Post-Session EMA")
        guard let view = self.view, let rootViewController = view.window?.rootViewController else {
            print("ERROR: Could not get rootViewController to present EMA.")
            // Fallback: Directly transition to StartScreen if EMA cannot be presented
            transitionToStartScreenAfterEMA()
            return
        }

        let emaView = EMAView(emaType: .postSession) { [weak self, weak rootViewController] response in
            guard let self = self, let strongRootViewController = rootViewController else { return }

            // Log the EMA response
            self.logPostSessionEMAResponse(response)

            // End the session and trigger the cloud upload.
            // This is the final data collection point for the session.
            DataLogger.shared.endSession()

            // Dismiss the EMA view
            strongRootViewController.dismiss(animated: true) {
                // Present the survey modal after EMA is dismissed
                self.presentSurveyModal()
            }
        }

        let hostingController = UIHostingController(rootView: emaView)
        hostingController.modalPresentationStyle = .fullScreen
        hostingController.view.backgroundColor = .clear // Allow scene to be visible underneath if not fully opaque
        
        // Ensure presentation is on main thread
        if Thread.isMainThread {
            rootViewController.present(hostingController, animated: true, completion: nil)
        } else {
            DispatchQueue.main.async {
                rootViewController.present(hostingController, animated: true, completion: nil)
            }
        }
    }
    
    private func logPostSessionEMAResponse(_ response: EMAResponse) {
        let contextString = response.emaType.rawValue // Should be "post_session_ema"
        
        DataLogger.shared.logEMAResponse(
            questionId: "ema_\(contextString)_stress",
            questionText: "How stressed do you feel right now?",
            response: response.stressLevel,
            responseType: "VAS",
            completionTime: response.completionTime,
            context: contextString
        )
        
        DataLogger.shared.logEMAResponse(
            questionId: "ema_\(contextString)_calm_agitation",
            questionText: "How calm or agitated do you feel right now?",
            response: response.calmAgitationLevel,
            responseType: "VAS",
            completionTime: response.completionTime,
            context: contextString
        )
        
        DataLogger.shared.logEMAResponse(
            questionId: "ema_\(contextString)_energy",
            questionText: "How energetic or drained do you feel right now?",
            response: response.energyLevel,
            responseType: "VAS",
            completionTime: response.completionTime,
            context: contextString
        )
        
        print("Post-session EMA logged: Stress=\(Int(response.stressLevel)), Calm/Agitation=\(Int(response.calmAgitationLevel)), Energy=\(Int(response.energyLevel))")
    }

    private func presentSurveyModal() {
        print("Presenting Survey Modal")
        guard let view = self.view, let rootViewController = view.window?.rootViewController else {
            print("ERROR: Could not get rootViewController to present survey modal.")
            // Fallback: Directly transition to StartScreen if survey modal cannot be presented
            transitionToStartScreenAfterEMA()
            return
        }
        
        // Create the survey view with completion handlers
        let surveyView = SurveyView(
            onConfirm: { [weak self, weak rootViewController] in
                // User tapped "I'll help!"
                // Open survey URL and dismiss the modal
                self?.openSurveyURL()
                rootViewController?.dismiss(animated: true) {
                    self?.transitionToStartScreenAfterEMA()
                }
            },
            onDecline: { [weak self, weak rootViewController] in
                // User tapped "No thanks"
                // Dismiss the modal and go back to start screen
                rootViewController?.dismiss(animated: true) {
                    self?.transitionToStartScreenAfterEMA()
                }
            }
        )
        
        let hostingController = UIHostingController(rootView: surveyView)
        hostingController.modalPresentationStyle = .fullScreen
        hostingController.view.backgroundColor = .clear // Allow scene to be visible underneath
        
        // Ensure presentation is on main thread
        if Thread.isMainThread {
            rootViewController.present(hostingController, animated: true, completion: nil)
        } else {
            DispatchQueue.main.async {
                rootViewController.present(hostingController, animated: true, completion: nil)
            }
        }
    }
    
    private func openSurveyURL() {
        let surveyURLString = "https://www.surveymonkey.com/r/HXFLWWG"
        if let url = URL(string: surveyURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            print("Opening survey URL: \(surveyURLString)")
        } else {
            print("ERROR: Invalid survey URL")
        }
    }
    
    private func transitionToStartScreenAfterEMA() {
        print("Transitioning to StartScreen after EMA")
        guard let view = self.view else {
            print("ERROR: No SKView found to present StartScreen.")
            return
        }
        
        // Ensure cleanup of any remaining UIKit elements from StartScreen (though willMove(from:) should handle this)
        // This is more of a safeguard.
        view.subviews.forEach { subview in
            if subview is UISlider || subview is UISegmentedControl {
                subview.removeFromSuperview()
            }
        }

        let startScreen = StartScreen(size: view.bounds.size)
        startScreen.scaleMode = .aspectFill
        
        // Perform transition on the main thread
        DispatchQueue.main.async {
            view.presentScene(startScreen, transition: SKTransition.fade(withDuration: 0.5))
        }
    }
    // --- END ADDED ---

} // Final closing brace for GameScene Class

// --- Ball class needs to be SKShapeNode ---
