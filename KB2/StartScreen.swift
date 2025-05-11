import SpriteKit
import UIKit

class StartScreen: SKScene {
    
    // Constants
    private let minSessionMinutes: Double = 5.0
    private let maxSessionMinutes: Double = 30.0
    private let initialSessionMinutes: Double = 15.0
    private let defaultArousalLevel: CGFloat = 0.95
    
    // UI Elements
    private var titleLabel: SKLabelNode!
    private var durationLabel: SKLabelNode!
    private var startButton: SKSpriteNode!
    private var startButtonLabel: SKLabelNode!
    private var slider: UISlider!
    private var sliderValue: Double = 15.0
    
    // Selected session parameters
    private var sessionDuration: TimeInterval = 15 * 60
    
    override func didMove(to view: SKView) {
        backgroundColor = .darkGray
        
        setupUI()
        
        // Add the UISlider as a subview of the SKView
        setupSlider(in: view)
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
        subtitleLabel.text = "Arousal Regulation Training"
        subtitleLabel.fontSize = 20
        subtitleLabel.fontColor = .lightGray
        subtitleLabel.position = CGPoint(x: frame.midX, y: titleLabel.position.y - 40)
        addChild(subtitleLabel)
        
        // Duration selection label
        durationLabel = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        durationLabel.text = "Session Duration: \(Int(initialSessionMinutes)) minutes"
        durationLabel.fontSize = 24
        durationLabel.fontColor = .white
        durationLabel.position = CGPoint(x: frame.midX, y: frame.midY + 60)
        addChild(durationLabel)
        
        // Explanation text
        let explanationLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        explanationLabel.text = "Select your session duration"
        explanationLabel.fontSize = 18
        explanationLabel.fontColor = .lightGray
        explanationLabel.position = CGPoint(x: frame.midX, y: durationLabel.position.y - 40)
        addChild(explanationLabel)
        
        // Start button background
        startButton = SKSpriteNode(color: .systemBlue, size: CGSize(width: 200, height: 60))
        startButton.position = CGPoint(x: frame.midX, y: frame.midY - 100)
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
        // Create the slider
        slider = UISlider(frame: CGRect(x: view.bounds.width * 0.15, 
                                        y: view.bounds.height * 0.5 - 10, 
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
    
    @objc private func sliderValueChanged(_ sender: UISlider) {
        sliderValue = Double(sender.value.rounded())
        sessionDuration = sliderValue * 60 // Convert to seconds
        durationLabel.text = "Session Duration: \(Int(sliderValue)) minutes"
    }
    
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
        let scaleDown = SKAction.scale(to: 0.95, duration: 0.1)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        let sequence = SKAction.sequence([scaleDown, scaleUp])
        
        let buttonNodes = self.children.filter { $0.name == "startButton" }
        buttonNodes.forEach { $0.run(sequence) }
        
        // Remove the slider from the parent view
        DispatchQueue.main.async { [weak self] in
            self?.slider?.removeFromSuperview()
            self?.startSession()
        }
    }
    
    private func startSession() {
        // Create and present the game scene with session mode enabled
        if let view = self.view {
            let scene = GameScene(size: view.bounds.size)
            scene.sessionMode = true
            scene.sessionDuration = sessionDuration
            scene.initialArousalLevel = defaultArousalLevel
            
            scene.scaleMode = .aspectFill
            view.presentScene(scene, transition: SKTransition.fade(withDuration: 0.5))
        }
    }
    
    override func willMove(from view: SKView) {
        // Clean up slider when the scene is removed
        slider?.removeFromSuperview()
        slider = nil
    }
} 
