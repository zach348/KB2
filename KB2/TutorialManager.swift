import SpriteKit

class TutorialManager {
    
    private weak var scene: GameScene?
    private var tutorialStep = 0
    
    // UI Elements
    private var overlay: SKShapeNode?
    private var calloutLabel: SKLabelNode?
    private var nextButton: SKShapeNode?
    private var nextButtonLabel: SKLabelNode?
    
    func start(in scene: GameScene) {
        self.scene = scene
        setupOverlay()
        presentStep()
    }
    
    private func setupOverlay() {
        guard let scene = scene else { return }
        
        overlay = SKShapeNode(rect: scene.frame)
        overlay?.fillColor = SKColor.black.withAlphaComponent(0.5)
        overlay?.zPosition = 200
        overlay?.name = "tutorialOverlay"
        scene.addChild(overlay!)
        
        calloutLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        calloutLabel?.fontSize = 24
        calloutLabel?.fontColor = .white
        calloutLabel?.zPosition = 201
        calloutLabel?.numberOfLines = 0
        calloutLabel?.preferredMaxLayoutWidth = scene.frame.width * 0.8
        overlay?.addChild(calloutLabel!)
        
        let buttonWidth: CGFloat = 150
        let buttonHeight: CGFloat = 50
        nextButton = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 10)
        nextButton?.fillColor = .systemBlue
        nextButton?.strokeColor = .white
        nextButton?.lineWidth = 1
        nextButton?.zPosition = 201
        nextButton?.name = "tutorialNextButton"
        overlay?.addChild(nextButton!)
        
        nextButtonLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        nextButtonLabel?.fontSize = 20
        nextButtonLabel?.fontColor = .white
        nextButtonLabel?.verticalAlignmentMode = .center
        nextButtonLabel?.zPosition = 202
        nextButtonLabel?.name = "tutorialNextButton"
        nextButton?.addChild(nextButtonLabel!)
    }
    
    private func presentStep() {
        guard let scene = scene else { return }
        
        switch tutorialStep {
        case 0:
            scene.pauseBalls()
            calloutLabel?.text = "Track the highlighted balls as they move."
            calloutLabel?.position = CGPoint(x: scene.frame.midX, y: scene.frame.midY + 100)
            nextButton?.position = CGPoint(x: scene.frame.midX, y: scene.frame.midY - 100)
            nextButtonLabel?.text = "Next"
            nextButton?.isHidden = false
        case 1:
            calloutLabel?.isHidden = true
            nextButton?.isHidden = true
            scene.resumeBalls()
            let wait = SKAction.wait(forDuration: 5.0)
            let startIdentification = SKAction.run {
                scene.startIdentificationPhase()
                self.advanceStep()
            }
            scene.run(SKAction.sequence([wait, startIdentification]))
        case 2:
            calloutLabel?.text = "Tap the targets before time runs out."
            calloutLabel?.isHidden = false
            nextButton?.isHidden = true
            scene.startIdentificationTimeout(duration: 7.0)
        case 3:
            calloutLabel?.text = "Great job!"
            nextButton?.isHidden = true
            let wait = SKAction.wait(forDuration: 2.0)
            let advance = SKAction.run { self.advanceStep() }
            scene.run(SKAction.sequence([wait, advance]))
        case 4:
            calloutLabel?.text = "Let's try that again. Track the highlighted balls."
            nextButton?.isHidden = true
            scene.resumeBalls()
            let wait2 = SKAction.wait(forDuration: 5.0)
            let startIdentification2 = SKAction.run {
                scene.startIdentificationPhase()
                self.advanceStep()
            }
            scene.run(SKAction.sequence([wait2, startIdentification2]))
        case 5:
            calloutLabel?.text = "Tap the tracked balls one more time."
            calloutLabel?.isHidden = false
            nextButton?.isHidden = true
            scene.startIdentificationTimeout(duration: 7.0)
        case 6:
            calloutLabel?.text = "Excellent!"
            nextButton?.isHidden = true
            let wait3 = SKAction.wait(forDuration: 2.0)
            let advance3 = SKAction.run { self.advanceStep() }
            scene.run(SKAction.sequence([wait3, advance3]))
        case 7:
            scene.pauseBalls()
            calloutLabel?.text = "That’s the task. In a session, difficulty adapts as you play."
            nextButton?.isHidden = false
            nextButtonLabel?.text = "Finish"
        default:
            endTutorial()
        }
    }
    
    func advanceStep() {
        tutorialStep += 1
        presentStep()
    }
    
    private func endTutorial() {
        FirstRunManager.shared.hasCompletedTutorial = true
        overlay?.removeFromParent()
        if let view = scene?.view, let vc = view.window?.rootViewController as? GameViewController {
            vc.presentStartScreen()
        }
    }
    
    func handleTap(at location: CGPoint) {
        guard let scene = scene, let nextButton = nextButton else { return }
        
        if nextButton.contains(location) && !nextButton.isHidden {
            if tutorialStep == 7 {
                endTutorial()
            } else {
                advanceStep()
            }
            return
        }
        
        if tutorialStep == 2 || tutorialStep == 5 {
            let nodes = scene.nodes(at: location)
            for node in nodes {
                if let ball = node as? Ball, ball.isTarget {
                    scene.handleBallTap(ball)
                }
            }
        }
    }
}
