// KB2/GameViewController.swift
import UIKit
import SpriteKit
import SwiftUI
import GameplayKit // Can likely remove this import if not using GameplayKit features

class GameViewController: UIViewController {

    // Stores the pre-session EMA response for later visualization
    var preSessionEMA: EMAResponse?
    
    private var didCheckEntryFlow = false
    
    // Store session parameters while tutorial is running
    private var pendingSessionParameters: (duration: TimeInterval, profile: SessionProfile, initialArousal: CGFloat)?
    
    // Achievement tracking properties
    private var currentSessionDuration: TimeInterval = 0
    private var sessionStartTime: TimeInterval = 0
    
    // Reference to the active GameScene for VHA control
    private weak var activeGameScene: GameScene?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Load 'GameScene.sks' as a GKScene. This provides gameplay related content
        // including entities and graphs.
        // NOTE: We are creating the scene programmatically in GameScene.swift's didMove(to:),
        // so this loading from .sks is less critical, but the standard template does it.
        // We get the SKScene instance from it.

        // Option 1: Standard template loading (if GameScene.sks exists)
//        if let scene = GKScene(fileNamed: "GameScene") {
//             // Get the SKScene from the loaded GKScene
//            if let sceneNode = scene.rootNode as! GameScene? {
//
//                // Copy gameplay related content over to the scene
//                // sceneNode.entities = scene.entities // Only if using GKEntity
//                // sceneNode.graphs = scene.graphs     // Only if using GKGraph
//
//                // Set the scale mode to scale to fit the window
//                sceneNode.scaleMode = .aspectFill // Or .resizeFill, .fill depending on need
//
//                 // Present the scene
//                if let view = self.view as! SKView? {
//                    view.presentScene(sceneNode)
//
//                    view.ignoresSiblingOrder = true // Performance optimization
//
//                    view.showsFPS = true        // Show FPS counter (useful for debugging)
//                    view.showsNodeCount = true  // Show node count (useful for debugging)
//                }
//            }
//        }

        // Entry gating occurs in viewDidAppear based on onboarding state
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Gate entry: present onboarding on first run, otherwise go straight to StartScreen
        guard !didCheckEntryFlow else { return }
        didCheckEntryFlow = true

        let config = GameConfiguration()
        let shouldForceOnboarding = config.forceShowOnboarding
        
        if FirstRunManager.shared.hasCompletedOnboarding && !shouldForceOnboarding {
            presentStartScreen()
        } else {
            let onboarding = OnboardingView {
                [weak self] in
                // Persist completion; force flag simply overrides gating on launch.
                FirstRunManager.shared.hasCompletedOnboarding = true
                self?.dismiss(animated: true, completion: {
                    self?.presentStartScreen()
                })
            }
            let hosting = UIHostingController(rootView: onboarding)
            hosting.modalPresentationStyle = .fullScreen
            hosting.overrideUserInterfaceStyle = .dark
            self.present(hosting, animated: true, completion: nil)
        }
    }

    // This method will be called by StartScreen
    func presentPreSessionEMAAndStartGame(sessionDuration: TimeInterval, sessionProfile: SessionProfile, initialArousalFromStartScreen: CGFloat) {
        let config = GameConfiguration()
        let shouldForceTutorial = config.forceShowTutorial
        let shouldShowTutorial = shouldForceTutorial || !FirstRunManager.shared.hasCompletedTutorial

        if shouldShowTutorial {
            // Store session parameters for after tutorial completion
            self.pendingSessionParameters = (sessionDuration, sessionProfile, initialArousalFromStartScreen)
            presentTutorial { [weak self] in
                self?.startPendingSession()
            }
            return
        }
        // Start a new data logging session BEFORE presenting the pre-session EMA
        DataLogger.shared.startSession(sessionDuration: sessionDuration) // <-- Pass sessionDuration

        let emaView = EMAView(emaType: .preSession) { [weak self] emaResponse in
            // Capture pre-session EMA for later visualization
            self?.preSessionEMA = emaResponse

            // Log the EMA response
            self?.logPreSessionEMAResponse(emaResponse)

            // Dismiss the EMA view and then present GameScene
            self?.dismiss(animated: true, completion: {
                // NEW: Calculate dynamic initial arousal from EMA responses
                let calculatedArousal = self?.calculateInitialArousal(from: emaResponse) ?? initialArousalFromStartScreen
                
                self?.presentGameScene(
                    sessionDuration: sessionDuration,
                    sessionProfile: sessionProfile,
                    initialArousalForEstimator: calculatedArousal, // Now using EMA-calculated value
                    systemInitialArousal: calculatedArousal // Now using EMA-calculated value
                )
            })
        }

        let hostingController = UIHostingController(rootView: emaView)
        hostingController.modalPresentationStyle = .fullScreen
        hostingController.view.backgroundColor = .clear

        DispatchQueue.main.async {
            self.present(hostingController, animated: true, completion: nil)
        }
    }
    
    private func logPreSessionEMAResponse(_ response: EMAResponse) {
        let contextString = response.emaType.rawValue // Should be "pre_session_ema"
        
        DataLogger.shared.logEMAResponse(
            questionId: "ema_\(contextString)_stress",
            questionText: "How stressed do you feel right now?",
            response: response.stressLevel,
            responseType: "VAS",
            completionTime: response.completionTime,
            context: contextString
        )
        
        DataLogger.shared.logEMAResponse(
            questionId: "ema_\(contextString)_calm_jittery",
            questionText: "How calm or jittery do you feel right now?",
            response: response.calmJitteryLevel,
            responseType: "VAS",
            completionTime: response.completionTime,
            context: contextString
        )
        
        print("Pre-session EMA logged: Stress=\(Int(response.stressLevel)), Calm/Jittery=\(Int(response.calmJitteryLevel))")
    }
    
    /// Calculates the initial arousal level based on EMA responses
    /// - Parameter emaResponse: The user's pre-session EMA responses
    /// - Returns: A CGFloat in the range specified by emaArousalTargetMin to emaArousalTargetMax
    private func calculateInitialArousal(from emaResponse: EMAResponse) -> CGFloat {
        let config = GameConfiguration()
        
        // Normalize EMA scores from 0-100 to 0.0-1.0
        let normalizedJittery = emaResponse.calmJitteryLevel / 100.0
        let normalizedStress = emaResponse.stressLevel / 100.0
        
        // Calculate weighted average: 75% jittery level, 25% stress
        // Jittery level is weighted more heavily as it's more directly related to physiological arousal
        let emaArousal = (normalizedJittery * 0.75) + (normalizedStress * 0.25)
        
        // Map to the tunable range from GameConfiguration
        let rangeSpan = config.emaArousalTargetMax - config.emaArousalTargetMin
        let initialArousal = config.emaArousalTargetMin + (emaArousal * rangeSpan)
        
        print("[GameViewController] EMA-based arousal calculation:")
        print("  ├─ Jittery: \(Int(emaResponse.calmJitteryLevel)) → \(String(format: "%.3f", normalizedJittery))")
        print("  ├─ Stress: \(Int(emaResponse.stressLevel)) → \(String(format: "%.3f", normalizedStress))")
        print("  ├─ Weighted average: \(String(format: "%.3f", emaArousal))")
        print("  ├─ Target range: [\(String(format: "%.3f", config.emaArousalTargetMin)), \(String(format: "%.3f", config.emaArousalTargetMax))]")
        print("  └─ Calculated initial arousal: \(String(format: "%.3f", initialArousal))")
        
        return CGFloat(initialArousal)
    }

    func presentStartScreen() {
        if let view = self.view as? SKView { // Ensure it's an SKView
            // Clear any existing scene first to avoid overlap issues
            view.presentScene(nil)
            
            let startScreen = StartScreen(size: view.bounds.size)
            startScreen.scaleMode = .aspectFill
            
            view.presentScene(startScreen)
            view.ignoresSiblingOrder = true
            
            // These are useful for debugging, can be removed for release
            view.showsFPS = true
            view.showsNodeCount = true
        } else {
            print("Error: GameViewController's view is not an SKView. Cannot present StartScreen.")
            // Handle this error appropriately, perhaps by showing an alert or logging.
        }
    }

    func presentTutorial(completion: (() -> Void)? = nil) {
        guard let view = self.view as? SKView else {
            print("Error: GameViewController's view is not an SKView. Cannot present Tutorial.")
            return
        }
        view.presentScene(nil)
        let tutorialScene = GameScene(size: view.bounds.size)
        tutorialScene.tutorialMode = true
        tutorialScene.tutorialCompletionHandler = completion
        tutorialScene.scaleMode = .aspectFill
        view.presentScene(tutorialScene, transition: SKTransition.fade(withDuration: 0.5))
        view.ignoresSiblingOrder = true
        view.showsFPS = true
        view.showsNodeCount = true
    }
    
    private func startPendingSession() {
        guard let params = pendingSessionParameters else {
            presentStartScreen() // Fallback
            return
        }
        
        // Clear the pending parameters
        pendingSessionParameters = nil
        
        // Now start the session flow with the stored parameters
        presentPreSessionEMAAndStartGame(
            sessionDuration: params.duration,
            sessionProfile: params.profile,
            initialArousalFromStartScreen: params.initialArousal
        )
    }

    private func presentGameScene(sessionDuration: TimeInterval, sessionProfile: SessionProfile, initialArousalForEstimator: CGFloat, systemInitialArousal: CGFloat) {
        if let view = self.view as? SKView {
            view.presentScene(nil) // Clear existing scene
            
            // Track session start time and duration for achievements
            currentSessionDuration = sessionDuration
            sessionStartTime = CACurrentMediaTime()

            let gameScene = GameScene(size: view.bounds.size)
            gameScene.sessionMode = true
            gameScene.sessionDuration = sessionDuration
            gameScene.sessionProfile = sessionProfile
            gameScene.initialArousalLevel = systemInitialArousal // For GameScene's own logic
            
            // NEW: Pass the target arousal for warmup ramp
            gameScene.targetArousalForWarmup = systemInitialArousal
            
            // ADDED: Pass pre-session EMA data for dynamic session structure
            gameScene.preSessionEMA = self.preSessionEMA
            
            // Initialize ArousalEstimator with the value from StartScreen/EMA
            gameScene.arousalEstimator = ArousalEstimator(initialArousal: initialArousalForEstimator)
            
            // Track the active GameScene for VHA control
            activeGameScene = gameScene
            
            gameScene.scaleMode = .aspectFill
            view.presentScene(gameScene, transition: SKTransition.fade(withDuration: 0.5))
        } else {
            print("Error: GameViewController's view is not an SKView. Cannot present GameScene.")
        }
    }
    
    // MARK: - VHA Control
    
    /// Suspends VHA stimulation by forwarding to the active GameScene
    func suspendVHA() {
        print("GameViewController: Suspending VHA stimulation...")
        activeGameScene?.suspendVHA()
    }
    
    /// Resumes VHA stimulation by forwarding to the active GameScene
    func resumeVHA() {
        print("GameViewController: Resuming VHA stimulation...")
        activeGameScene?.resumeVHA()
    }
    
    // MARK: - Achievement Integration
    
    /// Called by GameScene when post-session EMA is completed to finalize achievement processing
    func completeAchievementSession(postSessionEMA: EMAResponse) {
        // Calculate actual session duration
        let actualDuration = CACurrentMediaTime() - sessionStartTime
        
        // Call AchievementManager with complete session data
        AchievementManager.shared.endSession(
            duration: actualDuration,
            preSessionEMA: preSessionEMA,
            postSessionEMA: postSessionEMA
        )
        
        print("GameViewController: Achievement session completed with duration \(String(format: "%.1f", actualDuration))s")
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Restrict this view controller (and thus the app) to Portrait only
        return .portrait
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
