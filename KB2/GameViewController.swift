// KB2/GameViewController.swift
import UIKit
import SpriteKit
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

        // MODIFIED: Present the StartScreen first instead of GameScene
        if let view = self.view as! SKView? {
            let startScreen = StartScreen(size: view.bounds.size)
            startScreen.scaleMode = .aspectFill
            
            view.presentScene(startScreen)
            view.ignoresSiblingOrder = true
            view.showsFPS = true
            view.showsNodeCount = true
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
