import SpriteKit
import UIKit

class StartScreen: SKScene, PaywallViewControllerDelegate {
    
    // Constants
    private let minSessionMinutes: Double = 7.0
    private let maxSessionMinutes: Double = 30.0
    private let initialSessionMinutes: Double = 15.0
    private let defaultArousalLevel: CGFloat = 1.0
    
    // Brand Colors (matching PaywallViewController)
    private let primaryColor = UIColor(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0, alpha: 1.0) // #77FDC7
    private let secondaryColor = UIColor(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0, alpha: 1.0) // #A09EA1
    private let darkColor = UIColor(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0, alpha: 1.0) // #242424
    private let whiteColor = UIColor.white // #FFFFFF
    
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
        // Use brand dark color for background
        backgroundColor = SKColor(cgColor: darkColor.cgColor)
        
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
        titleLabel.fontColor = SKColor(cgColor: whiteColor.cgColor)
        titleLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 100)
        addChild(titleLabel)
        
        // Subtitle
        let subtitleLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        subtitleLabel.text = "(Don't forget your headphones...)"
        subtitleLabel.fontSize = 20
        subtitleLabel.fontColor = SKColor(cgColor: secondaryColor.cgColor)
        subtitleLabel.position = CGPoint(x: frame.midX, y: titleLabel.position.y - 40)
        addChild(subtitleLabel)
        
        // Calculate responsive positions based on screen height
        let screenHeight = frame.height
        let isSmallScreen = screenHeight < 700 // iPhone SE and similar
        
        // Duration selection label - position below subtitle with proper spacing
        durationLabel = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        durationLabel.text = "Session Duration: \(Int(initialSessionMinutes)) minutes"
        durationLabel.fontSize = isSmallScreen ? 20 : 24
        durationLabel.fontColor = SKColor(cgColor: whiteColor.cgColor)
        // Position with adequate spacing from subtitle
        durationLabel.position = CGPoint(x: frame.midX, y: subtitleLabel.position.y - (isSmallScreen ? 60 : 80))
        addChild(durationLabel)
        
        // Duration explanation text
        let explanationLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        explanationLabel.text = "Select your session duration"
        explanationLabel.fontSize = isSmallScreen ? 16 : 18
        explanationLabel.fontColor = SKColor(cgColor: secondaryColor.cgColor)
        explanationLabel.position = CGPoint(x: frame.midX, y: durationLabel.position.y - (isSmallScreen ? 30 : 35))
        addChild(explanationLabel)
        
        // Start button background - positioned with proper spacing below slider
        startButton = SKSpriteNode(color: .systemBlue, size: CGSize(width: 200, height: 60))
        startButton.position = CGPoint(x: frame.midX, y: explanationLabel.position.y - (isSmallScreen ? 90 : 120))
        startButton.zPosition = 10
        startButton.name = "startButton"
        
        // Apply rounded corners with a shape node using brand primary color
        let roundedPath = CGPath(roundedRect: CGRect(x: -100, y: -30, width: 200, height: 60), 
                               cornerWidth: 15, cornerHeight: 15, transform: nil)
        let roundedShape = SKShapeNode(path: roundedPath)
        roundedShape.fillColor = SKColor(cgColor: primaryColor.cgColor)
        roundedShape.strokeColor = .clear
        roundedShape.name = "startButton"
        roundedShape.position = startButton.position
        roundedShape.zPosition = startButton.zPosition
        addChild(roundedShape)
        
        // Start button label - use dark color for contrast against primary background
        startButtonLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        startButtonLabel.text = "Begin Session"
        startButtonLabel.fontSize = 24
        startButtonLabel.fontColor = SKColor(cgColor: darkColor.cgColor)
        startButtonLabel.position = roundedShape.position
        startButtonLabel.zPosition = roundedShape.zPosition + 1
        startButtonLabel.verticalAlignmentMode = .center
        startButtonLabel.name = "startButton"
        addChild(startButtonLabel)

        if FirstRunManager.shared.hasCompletedTutorial {
            let repeatTutorialButton = SKLabelNode(fontNamed: "HelveticaNeue-Light")
            repeatTutorialButton.text = "Repeat Tutorial"
            repeatTutorialButton.fontSize = 18
            repeatTutorialButton.fontColor = SKColor(cgColor: secondaryColor.cgColor)
            repeatTutorialButton.position = CGPoint(x: frame.midX, y: startButton.position.y - 80)
            repeatTutorialButton.name = "repeatTutorialButton"
            addChild(repeatTutorialButton)
        }
    }
    
    private func setupSlider(in view: SKView) {
        // Calculate responsive position based on screen size to match setupUI
        let screenHeight = view.bounds.height
        let isSmallScreen = screenHeight < 700 // iPhone SE and similar
        
        // Calculate the actual positions as they are set in setupUI
        let titleY = screenHeight - 100.0  // frame.maxY - 100
        let subtitleY = titleY - 40.0      // titleLabel.position.y - 40
        let durationLabelY = subtitleY - (isSmallScreen ? 60.0 : 80.0) // subtitleLabel.position.y - spacing
        let explanationLabelY = durationLabelY - (isSmallScreen ? 30.0 : 35.0) // durationLabel.position.y - spacing
        
        // Position slider between explanation label and start button with proper spacing
        let spacingBelowExplanation: CGFloat = isSmallScreen ? 40.0 : 50.0 // Reduced spacing for small screens
        let sliderYInSKCoords = explanationLabelY - spacingBelowExplanation
        
        // Convert from SKScene coordinates to UIKit coordinates
        let sliderYInUIKit = screenHeight - sliderYInSKCoords
        
        slider = UISlider(frame: CGRect(x: view.bounds.width * 0.15, 
                                        y: sliderYInUIKit,
                                        width: view.bounds.width * 0.7, 
                                        height: 30))
        slider.minimumValue = Float(minSessionMinutes)
        slider.maximumValue = Float(maxSessionMinutes)
        slider.value = Float(initialSessionMinutes)
        
        // Set up appearance using brand colors
        slider.minimumTrackTintColor = primaryColor
        slider.maximumTrackTintColor = UIColor(cgColor: secondaryColor.cgColor)
        
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
