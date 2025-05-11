import UIKit
import SpriteKit

class SessionConfigViewController: UIViewController {
    
    // MARK: - Properties
    
    private var sessionDurationSlider: UISlider!
    private var durationLabel: UILabel!
    private var startButton: UIButton!
    
    private let minDuration: Float = 5.0   // 5 minutes
    private let maxDuration: Float = 30.0  // 30 minutes
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .darkGray
        
        // Create title label
        let titleLabel = UILabel()
        titleLabel.text = "Kalibrate Session"
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // Create subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.text = "Select your session duration"
        subtitleLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        subtitleLabel.textColor = .white
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)
        
        // Create duration label
        durationLabel = UILabel()
        durationLabel.font = UIFont.systemFont(ofSize: 36, weight: .bold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .center
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(durationLabel)
        
        // Create slider
        sessionDurationSlider = UISlider()
        sessionDurationSlider.minimumValue = minDuration
        sessionDurationSlider.maximumValue = maxDuration
        sessionDurationSlider.value = 15.0  // Default to middle value
        sessionDurationSlider.translatesAutoresizingMaskIntoConstraints = false
        sessionDurationSlider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        view.addSubview(sessionDurationSlider)
        
        // Create min/max labels
        let minLabel = UILabel()
        minLabel.text = "\(Int(minDuration)) min"
        minLabel.font = UIFont.systemFont(ofSize: 14)
        minLabel.textColor = .lightGray
        minLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(minLabel)
        
        let maxLabel = UILabel()
        maxLabel.text = "\(Int(maxDuration)) min"
        maxLabel.font = UIFont.systemFont(ofSize: 14)
        maxLabel.textColor = .lightGray
        maxLabel.translatesAutoresizingMaskIntoConstraints = false
        maxLabel.textAlignment = .right
        view.addSubview(maxLabel)
        
        // Create start button
        startButton = UIButton(type: .system)
        startButton.setTitle("Begin Session", for: .normal)
        startButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        startButton.backgroundColor = .systemBlue
        startButton.setTitleColor(.white, for: .normal)
        startButton.layer.cornerRadius = 12
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startButtonTapped), for: .touchUpInside)
        view.addSubview(startButton)
        
        // Set constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            durationLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 50),
            durationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            sessionDurationSlider.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: 50),
            sessionDurationSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            sessionDurationSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            minLabel.topAnchor.constraint(equalTo: sessionDurationSlider.bottomAnchor, constant: 8),
            minLabel.leadingAnchor.constraint(equalTo: sessionDurationSlider.leadingAnchor),
            
            maxLabel.topAnchor.constraint(equalTo: sessionDurationSlider.bottomAnchor, constant: 8),
            maxLabel.trailingAnchor.constraint(equalTo: sessionDurationSlider.trailingAnchor),
            
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            startButton.widthAnchor.constraint(equalToConstant: 200),
            startButton.heightAnchor.constraint(equalToConstant: 54)
        ])
        
        // Initialize duration label
        updateDurationLabel()
    }
    
    // MARK: - Actions
    
    @objc private func sliderValueChanged(_ sender: UISlider) {
        updateDurationLabel()
    }
    
    private func updateDurationLabel() {
        let minutes = Int(sessionDurationSlider.value)
        durationLabel.text = "\(minutes) minutes"
    }
    
    @objc private func startButtonTapped() {
        // Calculate session duration in seconds
        let durationInMinutes = sessionDurationSlider.value
        let durationInSeconds = TimeInterval(durationInMinutes * 60)
        
        startSession(duration: durationInSeconds)
    }
    
    private func startSession(duration: TimeInterval) {
        // Find the GameViewController and its SKView
        guard let parentVC = self.parent as? GameViewController,
              let skView = parentVC.view as? SKView else {
            print("Error: Could not get GameViewController or SKView")
            return
        }
        
        // Create and configure the game scene
        let scene = GameScene(size: skView.bounds.size)
        scene.scaleMode = .aspectFill
        
        // Configure for session mode
        scene.sessionMode = true
        scene.sessionDuration = duration
        scene.initialArousalLevel = 0.95 // Fixed high starting arousal
        
        // Remove self from parent view controller
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
        
        // Present the scene
        skView.presentScene(scene)
    }
} 
