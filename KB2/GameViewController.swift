// KB2/GameViewController.swift
import UIKit
import SpriteKit
import SwiftUI
import GameplayKit // Can likely remove this import if not using GameplayKit features

class GameViewController: UIViewController {

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

        // MODIFIED: Present StartScreen directly. Pre-session EMA will be triggered from StartScreen.
        presentStartScreen()
    }

    // This method will be called by StartScreen
    func presentPreSessionEMAAndStartGame(sessionDuration: TimeInterval, sessionProfile: SessionProfile, initialArousalFromStartScreen: CGFloat) {
        // Start a new data logging session BEFORE presenting the pre-session EMA
        DataLogger.shared.startSession(sessionDuration: sessionDuration) // <-- Pass sessionDuration

        let emaView = EMAView(emaType: .preSession) { [weak self] emaResponse in
            // Log the EMA response
            self?.logPreSessionEMAResponse(emaResponse)

            // Dismiss the EMA view and then present GameScene
            self?.dismiss(animated: true, completion: {
                // Use arousal from EMA if available, otherwise fallback to StartScreen's default/placeholder
                // For now, we assume EMAView provides the necessary arousal levels in its response.
                // We'll need to ensure GameScene can accept this.
                // Let's assume emaResponse contains the necessary arousal level.
                // For simplicity, we'll use a combined or primary arousal from EMA.
                // This part might need refinement based on EMAResponse structure.
                // For now, let's assume a primary 'overallArousal' or similar from EMA,
                // or we use the initialArousalFromStartScreen as a fallback if EMA doesn't provide one directly.
                // The key is that GameScene needs an initialArousal.
                
                // For now, we'll pass the initialArousalFromStartScreen,
                // and GameScene will need to be updated to potentially use a more specific value from EMA if available.
                // Or, we decide here which arousal value to pass to GameScene.
                // Let's assume EMAView's response will give us a single value for now, e.g., average of the VAS scales or a primary one.
                // For this iteration, we'll use the initialArousalFromStartScreen as the primary source,
                // as StartScreen already had a mechanism for this. The EMA logging is separate.
                // The GameScene's initialArousalLevel will be set using this.
                
                // The EMA response itself (stress, calm, energy) is logged.
                // For initializing GameScene's arousalEstimator, we'll use the initialArousalFromStartScreen
                // as that was the prior behavior for the StartScreen's own slider.
                // If a more direct EMA-derived arousal is needed for GameScene init, GameScene's init or properties would need adjustment.
                self?.presentGameScene(
                    sessionDuration: sessionDuration,
                    sessionProfile: sessionProfile,
                    initialArousalForEstimator: initialArousalFromStartScreen, // This was the value from StartScreen's slider
                    systemInitialArousal: initialArousalFromStartScreen // GameScene's own initialArousalLevel
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
        
        print("Pre-session EMA logged: Stress=\(Int(response.stressLevel)), Calm/Agitation=\(Int(response.calmAgitationLevel)), Energy=\(Int(response.energyLevel))")
    }

    private func presentStartScreen() {
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

    private func presentGameScene(sessionDuration: TimeInterval, sessionProfile: SessionProfile, initialArousalForEstimator: CGFloat, systemInitialArousal: CGFloat) {
        if let view = self.view as? SKView {
            view.presentScene(nil) // Clear existing scene

            let gameScene = GameScene(size: view.bounds.size)
            gameScene.sessionMode = true
            gameScene.sessionDuration = sessionDuration
            gameScene.sessionProfile = sessionProfile
            gameScene.initialArousalLevel = systemInitialArousal // For GameScene's own logic
            
            // Initialize ArousalEstimator with the value from StartScreen/EMA
            gameScene.arousalEstimator = ArousalEstimator(initialArousal: initialArousalForEstimator)
            
            gameScene.scaleMode = .aspectFill
            view.presentScene(gameScene, transition: SKTransition.fade(withDuration: 0.5))
        } else {
            print("Error: GameViewController's view is not an SKView. Cannot present GameScene.")
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Restrict this view controller (and thus the app) to Portrait only
        return .portrait
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
