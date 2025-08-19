import SpriteKit
import UIKit

class StartScreen: SKScene, PaywallViewControllerDelegate {
    
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
    #if DEBUG
    private var debugTapGR: UITapGestureRecognizer?
    #endif
    
    // Selected session parameters
    private var sessionDuration: TimeInterval = 15 * 60
    // userReportedArousal is no longer needed here as it will be captured by EMAView
    
    override func didMove(to view: SKView) {
        backgroundColor = .darkGray
        
        setupUI()
        
        // Add the UISlider as a subview of the SKView
        setupSlider(in: view)
        // setupArousalSlider(in: view) // Removed arousal slider setup

        #if DEBUG
        let gr = UITapGestureRecognizer(target: self, action: #selector(handleDebugTap(_:)))
        gr.numberOfTapsRequired = 3
        view.addGestureRecognizer(gr)
        self.debugTapGR = gr
        #endif
        
        // Non-blocking subscription offer during trial (first run only)
        presentTrialOfferIfNeeded()
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

        if FirstRunManager.shared.hasCompletedTutorial {
            let repeatTutorialButton = SKLabelNode(fontNamed: "HelveticaNeue-Light")
            repeatTutorialButton.text = "Repeat Tutorial"
            repeatTutorialButton.fontSize = 18
            repeatTutorialButton.fontColor = .white
            repeatTutorialButton.position = CGPoint(x: frame.midX, y: startButton.position.y - 80)
            repeatTutorialButton.name = "repeatTutorialButton"
            addChild(repeatTutorialButton)
        }
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
            } else if node.name == "repeatTutorialButton" {
                handleRepeatTutorialTap()
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
        
        // Entitlement gate (Phase 1, feature-flagged)
        if EntitlementManager.shared.entitlementGateEnabled && !EntitlementManager.shared.isEntitled {
            presentEntitlementGate()
            return
        }
        
        // Proceed to session
        startSessionFlow()
    }
    
    private func startSessionFlow() {
        // Remove UIKit elements and start session via GameViewController
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.slider?.removeFromSuperview()
            if let gameVC = self.view?.window?.rootViewController as? GameViewController {
                gameVC.presentPreSessionEMAAndStartGame(
                    sessionDuration: self.sessionDuration,
                    sessionProfile: .fluctuating,
                    initialArousalFromStartScreen: self.defaultArousalLevel
                )
            }
        }
    }
    
    // Offer sheet shown during trial to disclose 7‑day trial and pricing (non-blocking)
    private func presentTrialOfferIfNeeded() {
        // Skip when bypass is enabled (dev)
        if EntitlementManager.shared.entitlementBypassEnabled { return }
        
        // Only show once and only if within trial window
        if FirstRunManager.shared.hasShownSubscriptionOffer { return }
        if !EntitlementManager.shared.isWithinTrialWindow() { return }
        
        // Mark as shown and present our PaywallViewController
        FirstRunManager.shared.hasShownSubscriptionOffer = true
        presentEntitlementGate()
    }
    
    private func presentEntitlementGate() {
        guard let vc = self.view?.window?.rootViewController else { return }
        
        let paywallVC = PaywallViewController()
        paywallVC.delegate = self
        paywallVC.modalPresentationStyle = .fullScreen
        
        vc.present(paywallVC, animated: true)
    }

    #if DEBUG
    @objc private func handleDebugTap(_ sender: UITapGestureRecognizer) {
        presentDebugSheet()
    }

    private func presentDebugSheet() {
        guard let vc = self.view?.window?.rootViewController else { return }
        let entitled = EntitlementManager.shared.isEntitled
        let bypass = EntitlementManager.shared.entitlementBypassEnabled
        let forced = EntitlementManager.shared.forceNonEntitledOverride
        let trialActive = EntitlementManager.shared.isWithinTrialWindow()
        let msg = "Entitled: \(entitled)\nBypass: \(bypass)\nForce Non‑Entitled: \(forced)\nTrial Active: \(trialActive)"
        let alert = UIAlertController(title: "Debug – Entitlements", message: msg, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: forced ? "Force Non‑Entitled: ON → OFF" : "Force Non‑Entitled: OFF → ON", style: .default, handler: { _ in
            EntitlementManager.shared.forceNonEntitledOverride.toggle()
            self.presentDebugSheet()
        }))

        alert.addAction(UIAlertAction(title: bypass ? "Bypass Entitlements: ON → OFF" : "Bypass Entitlements: OFF → ON", style: .default, handler: { _ in
            EntitlementManager.shared.entitlementBypassEnabled.toggle()
            self.presentDebugSheet()
        }))

        alert.addAction(UIAlertAction(title: "Simulate Trial Expired Now", style: .default, handler: { _ in
            let expired = Date().addingTimeInterval(-60 * 60 * 24 * 8)
            _ = KeychainManager.shared.setDate(expired, forKey: "trial_start_date")
            FirstRunManager.shared.hasShownSubscriptionOffer = false
            EntitlementManager.shared.start()
            Task { await StoreManager.shared.refreshEntitlements() }
        }))

        alert.addAction(UIAlertAction(title: "Reset Trial Date (Fresh)", style: .default, handler: { _ in
            let now = Date()
            _ = KeychainManager.shared.setDate(now, forKey: "trial_start_date")
            FirstRunManager.shared.hasShownSubscriptionOffer = false
            EntitlementManager.shared.start()
            Task { await StoreManager.shared.refreshEntitlements() }
        }))

        alert.addAction(UIAlertAction(title: "Refresh Entitlements", style: .default, handler: { _ in
            Task { await StoreManager.shared.refreshEntitlements() }
        }))

        alert.addAction(UIAlertAction(title: "Re‑show Trial Offer", style: .default, handler: { _ in
            FirstRunManager.shared.hasShownSubscriptionOffer = false
            self.presentTrialOfferIfNeeded()
        }))

        alert.addAction(UIAlertAction(title: "Show Paywall Now", style: .destructive, handler: { _ in
            self.presentEntitlementGate()
        }))

        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        vc.present(alert, animated: true)
    }
    #endif

    private func handleRepeatTutorialTap() {
        DispatchQueue.main.async { [weak self] in
            self?.slider?.removeFromSuperview()
            if let gameVC = self?.view?.window?.rootViewController as? GameViewController {
                gameVC.presentTutorial()
            }
        }
    }
    
    // startSession() is no longer called directly from here.
    // GameViewController will handle starting the GameScene after EMA.

    override func willMove(from view: SKView) {
        // Clean up UIKit elements when the scene is removed
        #if DEBUG
        if let gr = debugTapGR {
            view.removeGestureRecognizer(gr)
        }
        debugTapGR = nil
        #endif
        slider?.removeFromSuperview()
        slider = nil
    }
    
    // MARK: - PaywallViewControllerDelegate
    func paywallViewController(_ controller: PaywallViewController, didCompleteWith result: PaywallResult) {
        controller.dismiss(animated: true) { [weak self] in
            switch result {
            case .purchased, .restored:
                // User successfully purchased or restored, start the session
                self?.startSessionFlow()
            case .cancelled:
                // User cancelled, do nothing
                break
            }
        }
    }
}
