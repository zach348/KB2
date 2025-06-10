import SpriteKit
import UIKit

class StartScreen: SKScene {
    
    // Constants
    private let minSessionMinutes: Double = 7.0
    private let maxSessionMinutes: Double = 30.0
    private let initialSessionMinutes: Double = 15.0
    private let defaultArousalLevel: CGFloat = 1.0
    
    // UI Elements
    private var titleLabel: SKLabelNode!
    private var durationLabel: SKLabelNode!
    private var startButton: SKSpriteNode!
    private var startButtonLabel: SKLabelNode!
    private var slider: UISlider!
    private var sliderValue: Double = 15.0
    
    // Selected session parameters
    private var sessionDuration: TimeInterval = 15 * 60
    // userReportedArousal is no longer needed here as it will be captured by EMAView
    
    override func didMove(to view: SKView) {
        backgroundColor = .darkGray
        
        setupUI()
        
        // Add the UISlider as a subview of the SKView
        setupSlider(in: view)
        // setupArousalSlider(in: view) // Removed arousal slider setup
    }
    
    private func setupUI() {
        // Title
        titleLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        titleLabel.text = "Kalibrate"
        titleLabel.fontSize = 36
        titleLabel.fontColor = .white
        titleLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 100)
        addChild(titleLabel)
        
        // Subtitle
        let subtitleLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        subtitleLabel.text = "(Don't forget your headphones...)"
        subtitleLabel.fontSize = 20
        subtitleLabel.fontColor = .lightGray
        subtitleLabel.position = CGPoint(x: frame.midX, y: titleLabel.position.y - 40)
        addChild(subtitleLabel)
        
        // Duration selection label - moved up
        durationLabel = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        durationLabel.text = "Session Duration: \(Int(initialSessionMinutes)) minutes"
        durationLabel.fontSize = 24
        durationLabel.fontColor = .white
        durationLabel.position = CGPoint(x: frame.midX, y: frame.midY + 160) // Moved up
        addChild(durationLabel)
        
        // Duration explanation text
        let explanationLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        explanationLabel.text = "Select your session duration"
        explanationLabel.fontSize = 18
        explanationLabel.fontColor = .lightGray
        explanationLabel.position = CGPoint(x: frame.midX, y: durationLabel.position.y - 40)
        addChild(explanationLabel)
        
        // Start button background - moved further down, adjusted due to removal of arousal slider
        startButton = SKSpriteNode(color: .systemBlue, size: CGSize(width: 200, height: 60))
        startButton.position = CGPoint(x: frame.midX, y: explanationLabel.position.y - 120) // Adjusted position after removing arousal slider
        startButton.zPosition = 10
        startButton.name = "startButton"
        
        // Apply rounded corners with a shape node
        let roundedPath = CGPath(roundedRect: CGRect(x: -100, y: -30, width: 200, height: 60), 
                               cornerWidth: 15, cornerHeight: 15, transform: nil)
        let roundedShape = SKShapeNode(path: roundedPath)
        roundedShape.fillColor = .systemBlue
        roundedShape.strokeColor = .clear
        roundedShape.name = "startButton"
        roundedShape.position = startButton.position
        roundedShape.zPosition = startButton.zPosition
        addChild(roundedShape)
        
        // Start button label
        startButtonLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        startButtonLabel.text = "Begin Session"
        startButtonLabel.fontSize = 24
        startButtonLabel.fontColor = .white
        startButtonLabel.position = roundedShape.position
        startButtonLabel.zPosition = roundedShape.zPosition + 1
        startButtonLabel.verticalAlignmentMode = .center
        startButtonLabel.name = "startButton"
        addChild(startButtonLabel)
    }
    
    private func setupSlider(in view: SKView) {
        // Create the slider - moved up
        slider = UISlider(frame: CGRect(x: view.bounds.width * 0.15, 
                                        y: view.bounds.height * 0.35, // Moved up
                                        width: view.bounds.width * 0.7, 
                                        height: 30))
        slider.minimumValue = Float(minSessionMinutes)
        slider.maximumValue = Float(maxSessionMinutes)
        slider.value = Float(initialSessionMinutes)
        
        // Set up appearance
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .darkGray
        
        // Add action for value change
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        
        // Add to view
        view.addSubview(slider)
    }
    
    // Removed setupArousalSlider method
    
    @objc private func sliderValueChanged(_ sender: UISlider) {
        sliderValue = Double(sender.value.rounded())
        sessionDuration = sliderValue * 60 // Convert to seconds
        durationLabel.text = "Session Duration: \(Int(sliderValue)) minutes"
    }
    
    // Removed arousalSliderChanged and arousalLevelDescription methods
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let nodes = self.nodes(at: location)
        
        for node in nodes {
            if node.name == "startButton" {
                handleStartButtonTap()
                break
            }
        }
    }
    
    private func handleStartButtonTap() {
        // Visual feedback
        let scaleDown = SKAction.scale(to: 0.95, duration: 0.1) // This is an animation scale, not related to arousal
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        let sequence = SKAction.sequence([scaleDown, scaleUp])
        
        let buttonNodes = self.children.filter { $0.name == "startButton" }
        buttonNodes.forEach { $0.run(sequence) }
        
        // Remove UIKit elements
        DispatchQueue.main.async { [weak self] in
            self?.slider?.removeFromSuperview()

            // Call GameViewController to present pre-session EMA and then start game
            if let gameVC = self?.view?.window?.rootViewController as? GameViewController {
                // Pass selected parameters to GameViewController
                // The userReportedArousal will be captured by the EMAView itself.
                // We pass a default or placeholder here if needed by GameScene init,
                // but GameScene should ideally get it from the EMA response.
                // For now, we'll pass the defaultArousalLevel from StartScreen,
                // GameScene will use the EMA response value once available.
                gameVC.presentPreSessionEMAAndStartGame(
                    sessionDuration: self?.sessionDuration ?? (15 * 60),
                    sessionProfile: .fluctuating, // Hardcode to dynamic profile
                    initialArousalFromStartScreen: self?.defaultArousalLevel ?? 0.7 // Placeholder, will be overwritten by EMA
                )
            }
        }
    }
    
    // startSession() is no longer called directly from here.
    // GameViewController will handle starting the GameScene after EMA.

    override func willMove(from view: SKView) {
        // Clean up UIKit elements when the scene is removed
        slider?.removeFromSuperview()
        slider = nil
    }
}
