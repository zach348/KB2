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
    private var segmentedControl: UISegmentedControl!
    private var sliderValue: Double = 15.0
    private var selectedProfile: SessionProfile = .fluctuating
    
    // New EMA elements
    private var arousalSlider: UISlider?
    private var arousalLabel: SKLabelNode?
    private var userReportedArousal: CGFloat = 0.7 // Default mid-high value
    
    // Selected session parameters
    private var sessionDuration: TimeInterval = 15 * 60
    
    override func didMove(to view: SKView) {
        backgroundColor = .darkGray
        
        setupUI()
        
        // Add the UISlider and UISegmentedControl as subviews of the SKView
        setupSlider(in: view)
        setupProfileSelector(in: view)
        setupArousalSlider(in: view)
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
        
        // Profile selector label - moved up further to prevent occlusion
        let profileLabel = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        profileLabel.text = "Session Type"
        profileLabel.fontSize = 24
        profileLabel.fontColor = .white
        profileLabel.position = CGPoint(x: frame.midX, y: explanationLabel.position.y - 70) // Adjusted position
        addChild(profileLabel)
        
        // Add arousal self-report label
        let arousalSelfReportLabel = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        arousalSelfReportLabel.text = "Current Arousal Level"
        arousalSelfReportLabel.fontSize = 24
        arousalSelfReportLabel.fontColor = .white
        arousalSelfReportLabel.position = CGPoint(x: frame.midX, y: profileLabel.position.y - 80)
        addChild(arousalSelfReportLabel)
        
        // Add arousal description
        let arousalDescriptionLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        arousalDescriptionLabel.text = "Calm                  Alert                  Anxious"
        arousalDescriptionLabel.fontSize = 14
        arousalDescriptionLabel.fontColor = .lightGray
        arousalDescriptionLabel.position = CGPoint(x: frame.midX, y: arousalSelfReportLabel.position.y - 60)
        addChild(arousalDescriptionLabel)
        
        // Current arousal value label
        arousalLabel = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        arousalLabel?.text = arousalLevelDescription(for: userReportedArousal)
        arousalLabel?.fontSize = 18
        arousalLabel?.fontColor = .white
        arousalLabel?.position = CGPoint(x: frame.midX, y: arousalSelfReportLabel.position.y - 30)
        addChild(arousalLabel!)
        
        // Start button background - moved further down
        startButton = SKSpriteNode(color: .systemBlue, size: CGSize(width: 200, height: 60))
        startButton.position = CGPoint(x: frame.midX, y: frame.midY - 220) // Moved down more
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
    
    private func setupProfileSelector(in view: SKView) {
        // Create the segmented control - moved up
        segmentedControl = UISegmentedControl(items: ["Smooth", "Dynamic", "Challenge", "Variable"])
        segmentedControl.frame = CGRect(x: view.bounds.width * 0.15,
                                       y: view.bounds.height * 0.45, // Moved up
                                       width: view.bounds.width * 0.7,
                                       height: 35)
        
        // Set default selection
        segmentedControl.selectedSegmentIndex = 1 // 'Dynamic' by default
        
        // Set up appearance
        segmentedControl.backgroundColor = .darkGray
        segmentedControl.selectedSegmentTintColor = .systemBlue
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.lightGray], for: .normal)
        
        // Add action for selection change
        segmentedControl.addTarget(self, action: #selector(profileSelectionChanged(_:)), for: .valueChanged)
        
        // Add to view
        view.addSubview(segmentedControl)
    }
    
    private func setupArousalSlider(in view: SKView) {
        // Create the arousal slider - position in lower half of screen
        arousalSlider = UISlider(frame: CGRect(x: view.bounds.width * 0.15,
                                              y: view.bounds.height * 0.65, // Adjusted to be between profile selector and start button
                                              width: view.bounds.width * 0.7,
                                              height: 30))
        
        guard let arousalSlider = arousalSlider else { return }
        
        arousalSlider.minimumValue = 0.0
        arousalSlider.maximumValue = 1.0
        arousalSlider.value = Float(userReportedArousal)
        
        // Appearance
        arousalSlider.minimumTrackTintColor = .systemGreen
        arousalSlider.maximumTrackTintColor = .systemRed
        
        // Add value changed action
        arousalSlider.addTarget(self, action: #selector(arousalSliderChanged(_:)), for: .valueChanged)
        
        // Add to view
        view.addSubview(arousalSlider)
    }
    
    @objc private func sliderValueChanged(_ sender: UISlider) {
        sliderValue = Double(sender.value.rounded())
        sessionDuration = sliderValue * 60 // Convert to seconds
        durationLabel.text = "Session Duration: \(Int(sliderValue)) minutes"
    }
    
    @objc private func profileSelectionChanged(_ sender: UISegmentedControl) {
        // Update the selected profile based on segment index
        switch sender.selectedSegmentIndex {
        case 0:
            selectedProfile = .standard // "Smooth"
        case 1:
            selectedProfile = .fluctuating // "Dynamic"
        case 2:
            selectedProfile = .challenge
        case 3:
            selectedProfile = .variable
        default:
            selectedProfile = .fluctuating // Default to "Dynamic"
        }
    }
    
    @objc private func arousalSliderChanged(_ sender: UISlider) {
        userReportedArousal = CGFloat(sender.value)
        arousalLabel?.text = arousalLevelDescription(for: userReportedArousal)
    }
    
    private func arousalLevelDescription(for level: CGFloat) -> String {
        if level < 0.33 {
            return "Calm/Relaxed (\(Int(level * 100))%)"
        } else if level < 0.67 {
            return "Alert/Focused (\(Int(level * 100))%)"
        } else {
            return "Energetic/Tense (\(Int(level * 100))%)"
        }
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
        
        // Log the self-reported arousal level
        DataLogger.shared.logSelfReport(arousalLevel: userReportedArousal, phase: "pre-session")
        
        // Remove the slider and segmented control from the parent view
        DispatchQueue.main.async { [weak self] in
            self?.slider?.removeFromSuperview()
            self?.segmentedControl?.removeFromSuperview()
            self?.arousalSlider?.removeFromSuperview()
            self?.startSession()
        }
    }
    
    private func startSession() {
        // Create and present the game scene with session mode enabled
        if let view = self.view {
            let scene = GameScene(size: view.bounds.size)
            
            // Initialize the ArousalEstimator with the user's self-reported arousal
            let arousalEstimator = ArousalEstimator(initialArousal: userReportedArousal)
            
            // Configure session parameters
            scene.sessionMode = true
            scene.sessionDuration = sessionDuration
            scene.initialArousalLevel = defaultArousalLevel  // System arousal starts high
            scene.sessionProfile = selectedProfile
            
            // Provide the arousal estimator to the scene (we'll modify GameScene.swift next)
            scene.arousalEstimator = arousalEstimator
            
            scene.scaleMode = .aspectFill
            view.presentScene(scene, transition: SKTransition.fade(withDuration: 0.5))
        }
    }
    
    override func willMove(from view: SKView) {
        // Clean up UIKit elements when the scene is removed
        slider?.removeFromSuperview()
        segmentedControl?.removeFromSuperview()
        arousalSlider?.removeFromSuperview()
        slider = nil
        segmentedControl = nil
        arousalSlider = nil
    }
} 
