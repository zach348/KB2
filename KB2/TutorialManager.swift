import SpriteKit

class TutorialManager {
    
    private weak var scene: GameScene?
    private var tutorialStep = 0
    
    // Brand Colors (matching other views)
    private let primaryColor = UIColor(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0, alpha: 1.0) // #77FDC7
    private let secondaryColor = UIColor(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0, alpha: 1.0) // #A09EA1
    private let darkColor = UIColor(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0, alpha: 1.0) // #242424
    
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
        overlay?.fillColor = SKColor(cgColor: darkColor.cgColor).withAlphaComponent(0.3)
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
        nextButton?.fillColor = SKColor(cgColor: primaryColor.cgColor)
        nextButton?.strokeColor = .clear
        nextButton?.lineWidth = 0
        nextButton?.zPosition = 201
        nextButton?.name = "tutorialNextButton"
        overlay?.addChild(nextButton!)
        
        nextButtonLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        nextButtonLabel?.fontSize = 20
        nextButtonLabel?.fontColor = SKColor(cgColor: darkColor.cgColor)
        nextButtonLabel?.verticalAlignmentMode = .center
        nextButtonLabel?.zPosition = 202
        nextButtonLabel?.name = "tutorialNextButton"
        nextButton?.addChild(nextButtonLabel!)
    }
    
    private func presentStep() {
        guard let scene = scene else { return }
        
        switch tutorialStep {
        case 0:
            // Step 1: Single, Clear Instruction
            scene.pauseBalls()
            calloutLabel?.text = "First, keep track of the highlighted targets as they move."
            calloutLabel?.position = CGPoint(x: scene.frame.midX, y: scene.frame.midY + 100)
            nextButton?.position = CGPoint(x: scene.frame.midX, y: scene.frame.midY - 100)
            nextButtonLabel?.text = "Start Practice"
            nextButton?.isHidden = false
        case 1:
            // Step 2: One Practice Round - Track Phase
            calloutLabel?.isHidden = true
            nextButton?.isHidden = true
            scene.resumeBalls()
            let wait = SKAction.wait(forDuration: 5.0)
            let startIdentification = SKAction.run {
                scene.startIdentificationPhase(isTutorial: true)
                self.advanceStep()
            }
            scene.run(SKAction.sequence([wait, startIdentification]))
        case 2:
            // Step 2: One Practice Round - Tap Phase (No-fail with visual timer)
            calloutLabel?.text = "Now, tap the targets. In a real session, this timer will count down, but for this practice, it's paused. Take all the time you need."
            calloutLabel?.isHidden = false
            nextButton?.isHidden = true
            // Note: We start the identification phase to show the timer visually, but don't call startIdentificationTimeout
            // so there's no actual timeout - the user can take as long as they need
        case 3:
            // Step 3: Reinforce the "Why" and transition
            scene.pauseBalls()
            calloutLabel?.text = "Well done. The goal of this focus task is to prepare your mind for the guided breathing that follows. Ready to start your first session?"
            calloutLabel?.position = CGPoint(x: scene.frame.midX, y: scene.frame.midY + 100)
            nextButton?.position = CGPoint(x: scene.frame.midX, y: scene.frame.midY - 100)
            nextButtonLabel?.text = "Start Session"
            nextButton?.isHidden = false
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
        
        // Stop all audio and haptic feedback before transitioning
        scene?.stopTutorialAudioAndHaptics()
        
        // Trigger the completion handler to continue the flow
        scene?.tutorialCompletionHandler?()
    }
    
    func handleTap(at location: CGPoint) {
        guard let scene = scene, let nextButton = nextButton else { return }
        
        if nextButton.contains(location) && !nextButton.isHidden {
            if tutorialStep == 3 {
                endTutorial()
            } else {
                advanceStep()
            }
            return
        }
        
        if tutorialStep == 2 {
            let nodes = scene.nodes(at: location)
            for node in nodes {
                if let ball = node as? Ball, ball.isTarget {
                    scene.handleBallTap(ball)
                }
            }
        }
    }
}
