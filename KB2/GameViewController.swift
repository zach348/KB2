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

        // Option 2: Simpler direct creation (if you delete GameScene.sks or prefer code-only)
        
        if let view = self.view as! SKView? {
            let scene = GameScene(size: view.bounds.size) // Create scene directly
            scene.scaleMode = .aspectFill // Or .resizeFill, .fill
            view.presentScene(scene)
            view.ignoresSiblingOrder = true
            view.showsFPS = true
            view.showsNodeCount = true
        }
        
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
