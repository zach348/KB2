// Copyright 2025 Training State, LLC. All rights reserved.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
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
    private var settingsButton: SKLabelNode!
    private var ballGraphic: StartScreenBall!
    private var slider: UISlider!
    private var sliderValue: Double = 15.0
    private var debugTapGR: UITapGestureRecognizer?
    
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

        // Enable debug features in TestFlight builds (but not App Store)
        if isTestFlightOrDebugBuild() {
            let gr = UITapGestureRecognizer(target: self, action: #selector(handleDebugTap(_:)))
            gr.numberOfTapsRequired = 3
            view.addGestureRecognizer(gr)
            self.debugTapGR = gr
        }
        
        // Non-blocking subscription offer during trial (first run only)
        presentTrialOfferIfNeeded()
    }
    
    private func setupUI() {
        // Settings button (top-right corner)
        settingsButton = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        settingsButton.text = "Settings"
        settingsButton.fontSize = 18
        settingsButton.fontColor = SKColor(cgColor: secondaryColor.cgColor)
        settingsButton.position = CGPoint(x: frame.maxX - 80, y: frame.maxY - 60)
        settingsButton.name = "settingsButton"
        addChild(settingsButton)
        
        // Progress button (top-left corner)
        let progressButton = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        progressButton.text = "Progress"
        progressButton.fontSize = 18
        progressButton.fontColor = SKColor(cgColor: secondaryColor.cgColor)
        progressButton.position = CGPoint(x: 80, y: frame.maxY - 60)
        progressButton.name = "progressButton"
        addChild(progressButton)
        
        // Title (moved down to give settings button breathing room)
        titleLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        titleLabel.text = "Kalibrate"
        titleLabel.fontSize = 36
        titleLabel.fontColor = SKColor(cgColor: whiteColor.cgColor)
        titleLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 120)
        addChild(titleLabel)
        
        // TM symbol (smaller, positioned next to title)
        let tmLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        tmLabel.text = "™"
        tmLabel.fontSize = 14 // 60% reduction from 36
        tmLabel.fontColor = SKColor(cgColor: whiteColor.cgColor)
        // Position to the right of the main title
        let titleWidth = titleLabel.frame.width
        tmLabel.position = CGPoint(x: titleLabel.position.x + titleWidth/2 + 5, y: titleLabel.position.y + 8)
        addChild(tmLabel)
        
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
        
        // Ball graphic - positioned between subtitle and duration controls (40% larger)
        let ballRadius: CGFloat = isSmallScreen ? 49.0 : 63.0 // Increased by 40% for better prominence
        ballGraphic = StartScreenBall(radius: ballRadius, color: primaryColor)
        ballGraphic.position = CGPoint(x: frame.midX, y: subtitleLabel.position.y - (isSmallScreen ? 80 : 100))
        addChild(ballGraphic)
        
        // Duration selection label - position below ball graphic with increased spacing
        durationLabel = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        durationLabel.text = "Session Duration: \(Int(initialSessionMinutes)) minutes"
        durationLabel.fontSize = isSmallScreen ? 20 : 24
        durationLabel.fontColor = SKColor(cgColor: whiteColor.cgColor)
        // Position with increased spacing from ball graphic to reduce dead space
        durationLabel.position = CGPoint(x: frame.midX, y: ballGraphic.position.y - (isSmallScreen ? 100 : 120))
        addChild(durationLabel)
        
        // Duration explanation text
        let explanationLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        explanationLabel.text = "Select your session duration"
        explanationLabel.fontSize = isSmallScreen ? 16 : 18
        explanationLabel.fontColor = SKColor(cgColor: secondaryColor.cgColor)
        explanationLabel.position = CGPoint(x: frame.midX, y: durationLabel.position.y - (isSmallScreen ? 30 : 35))
        addChild(explanationLabel)
        
        // Start button background - positioned with more spacing for slider
        startButton = SKSpriteNode(color: .systemBlue, size: CGSize(width: 200, height: 60))
        startButton.position = CGPoint(x: frame.midX, y: explanationLabel.position.y - (isSmallScreen ? 110 : 135))
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

        // Repeat tutorial button - positioned closer to reduce dead space
        if FirstRunManager.shared.hasCompletedTutorial {
            let repeatTutorialButton = SKLabelNode(fontNamed: "HelveticaNeue-Light")
            repeatTutorialButton.text = "Repeat Tutorial"
            repeatTutorialButton.fontSize = 18
            repeatTutorialButton.fontColor = SKColor(cgColor: secondaryColor.cgColor)
            repeatTutorialButton.position = CGPoint(x: frame.midX, y: startButton.position.y - (isSmallScreen ? 60 : 70))
            repeatTutorialButton.name = "repeatTutorialButton"
            addChild(repeatTutorialButton)
        }
        
        // Add version footer to utilize bottom space
        let versionLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            versionLabel.text = "v\(appVersion)"
        } else {
            versionLabel.text = "v1.0"
        }
        versionLabel.fontSize = 12
        versionLabel.fontColor = SKColor(cgColor: secondaryColor.cgColor).withAlphaComponent(0.6)
        let bottomPosition = FirstRunManager.shared.hasCompletedTutorial ? 
            (startButton.position.y - (isSmallScreen ? 60 : 70) - 40) : 
            (startButton.position.y - 40)
        versionLabel.position = CGPoint(x: frame.midX, y: max(bottomPosition, 30))
        addChild(versionLabel)
        
        // Add copyright notice below version
        let copyrightLabel = SKLabelNode(fontNamed: "HelveticaNeue-Light")
        copyrightLabel.text = "© 2025 Training State, LLC - All rights reserved"
        copyrightLabel.fontSize = 12
        copyrightLabel.fontColor = SKColor(cgColor: secondaryColor.cgColor).withAlphaComponent(0.6)
        copyrightLabel.position = CGPoint(x: frame.midX, y: max(bottomPosition - 20, 10))
        addChild(copyrightLabel)
    }
    
    private func setupSlider(in view: SKView) {
        // Calculate responsive position based on screen size to match setupUI
        let screenHeight = view.bounds.height
        let isSmallScreen = screenHeight < 700 // iPhone SE and similar
        
        // Calculate the actual positions as they are set in setupUI (updated for larger ball and spacing)
        let titleY = screenHeight - 120.0  // frame.maxY - 120
        let subtitleY = titleY - 40.0      // titleLabel.position.y - 40
        let ballY = subtitleY - (isSmallScreen ? 80.0 : 100.0) // Updated ball position
        let durationLabelY = ballY - (isSmallScreen ? 100.0 : 120.0) // Updated duration label spacing
        let explanationLabelY = durationLabelY - (isSmallScreen ? 30.0 : 35.0) // durationLabel.position.y - spacing
        
        // Position slider between explanation label and start button - ensure slider is ABOVE button
        let spacingBelowExplanation: CGFloat = isSmallScreen ? 40.0 : 50.0 // Increased spacing for better breathing room
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
            } else if node.name == "settingsButton" {
                handleSettingsButtonTap()
                break
            } else if node.name == "progressButton" {
                handleProgressButtonTap()
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

    // MARK: - TestFlight Detection and Debug Features
    
    /// Detects if app is running in DEBUG mode OR TestFlight (but not App Store)
    private func isTestFlightOrDebugBuild() -> Bool {
        #if DEBUG
        return true
        #else
        // Check for TestFlight receipt
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.path.contains("sandboxReceipt")
        #endif
    }
    
    @objc private func handleDebugTap(_ sender: UITapGestureRecognizer) {
        // Only respond if we're in a TestFlight or Debug build
        if isTestFlightOrDebugBuild() {
            presentDebugSheet()
        }
    }

    private func presentDebugSheet() {
        // Only show if we're in a TestFlight or Debug build
        guard isTestFlightOrDebugBuild() else { return }
        
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
        
        // Survey prompts toggle
        let surveysDisabled = FirstRunManager.shared.surveyPromptsDisabled
        let surveyToggleTitle = surveysDisabled ? "Disable Survey Prompts: ON → OFF" : "Disable Survey Prompts: OFF → ON"
        alert.addAction(UIAlertAction(title: surveyToggleTitle, style: .default, handler: { _ in
            FirstRunManager.shared.surveyPromptsDisabled.toggle()
            self.presentDebugSheet()
        }))
        
        // TestFlight reset available in both DEBUG and RELEASE for testing
        alert.addAction(UIAlertAction(title: "🧪 Reset for TestFlight", style: .destructive, handler: { _ in
            let confirmAlert = UIAlertController(title: "Reset App State", message: "This will reset all onboarding progress and start a fresh trial. Use this for TestFlight testing only.", preferredStyle: .alert)
            confirmAlert.addAction(UIAlertAction(title: "Reset", style: .destructive, handler: { _ in
                FirstRunManager.shared.resetForTestFlight()
                EntitlementManager.shared.start()
                // Exit app to force fresh launch
                exit(0)
            }))
            confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            vc.present(confirmAlert, animated: true)
        }))

        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        vc.present(alert, animated: true)
    }

    private func handleRepeatTutorialTap() {
        DispatchQueue.main.async { [weak self] in
            self?.slider?.removeFromSuperview()
            if let gameVC = self?.view?.window?.rootViewController as? GameViewController {
                gameVC.presentTutorial()
            }
        }
    }
    
    private func handleSettingsButtonTap() {
        // Visual feedback
        let fadeOut = SKAction.fadeAlpha(to: 0.5, duration: 0.1)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        let sequence = SKAction.sequence([fadeOut, fadeIn])
        settingsButton.run(sequence)
        
        // Present settings screen
        DispatchQueue.main.async { [weak self] in
            guard let rootVC = self?.view?.window?.rootViewController else { return }
            let settingsVC = SettingsViewController()
            settingsVC.modalPresentationStyle = .pageSheet
            rootVC.present(settingsVC, animated: true)
        }
    }
    
    private func handleProgressButtonTap() {
        // Find the progress button for visual feedback
        if let progressButton = self.children.first(where: { $0.name == "progressButton" }) as? SKLabelNode {
            let fadeOut = SKAction.fadeAlpha(to: 0.5, duration: 0.1)
            let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.1)
            let sequence = SKAction.sequence([fadeOut, fadeIn])
            progressButton.run(sequence)
        }
        
        // Present progress screen
        DispatchQueue.main.async { [weak self] in
            guard let rootVC = self?.view?.window?.rootViewController else { return }
            let progressVC = ProgressViewController()
            progressVC.modalPresentationStyle = .pageSheet
            rootVC.present(progressVC, animated: true)
        }
    }
    
    // startSession() is no longer called directly from here.
    // GameViewController will handle starting the GameScene after EMA.

    override func willMove(from view: SKView) {
        // Clean up UIKit elements when the scene is removed
        if let gr = debugTapGR {
            view.removeGestureRecognizer(gr)
        }
        debugTapGR = nil
        slider?.removeFromSuperview()
        slider = nil
    }
    
    // MARK: - UI Refresh
    private func refreshUI() {
        guard let view = self.view else { return }
        
        // Remove all existing SpriteKit nodes
        self.removeAllChildren()
        
        // Remove UIKit elements
        slider?.removeFromSuperview()
        slider = nil
        
        // Reconstruct the UI
        setupUI()
        setupSlider(in: view)
    }
    
    // MARK: - PaywallViewControllerDelegate
    func paywallViewController(_ controller: PaywallViewController, didCompleteWith result: PaywallResult) {
        controller.dismiss(animated: true) { [weak self] in
            switch result {
            case .purchased, .restored:
                // User successfully purchased or restored, start the session
                self?.startSessionFlow()
            case .cancelled:
                // User cancelled, refresh the UI to ensure proper rendering
                self?.refreshUI()
            }
        }
    }
}
