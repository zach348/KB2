import UIKit

class SettingsViewController: UIViewController {
    
    // MARK: - Properties
    
    // Brand Colors
    private let primaryColor = UIColor(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0, alpha: 1.0) // #77FDC7
    private let secondaryColor = UIColor(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0, alpha: 1.0) // #A09EA1
    private let darkColor = UIColor(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0, alpha: 1.0) // #242424
    private let whiteColor = UIColor.white // #FFFFFF
    
    // UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let mainStackView = UIStackView()
    private let titleLabel = UILabel()
    private let subscriptionStatusLabel = UILabel()
    private let viewProgressButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let manageSubscriptionButton = UIButton(type: .system)
    private let clearHistoryButton = UIButton(type: .system)
    private let privacyButton = UIButton(type: .system)
    private let termsButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateSubscriptionStatus()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSubscriptionStatus()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = darkColor
        
        // Setup scroll view
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        setupContent()
        setupConstraints()
    }
    
    private func setupContent() {
        // Main stack view for responsive layout
        mainStackView.axis = .vertical
        mainStackView.spacing = 24
        mainStackView.alignment = .fill
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStackView)
        
        // Title
        titleLabel.text = "Settings"
        titleLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = whiteColor
        titleLabel.textAlignment = .center
        
        // Subscription status
        subscriptionStatusLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        subscriptionStatusLabel.textColor = secondaryColor
        subscriptionStatusLabel.textAlignment = .center
        subscriptionStatusLabel.numberOfLines = 0
        
        // Setup buttons
        setupButton(viewProgressButton, title: "View Progress", isPrimary: false)
        viewProgressButton.addTarget(self, action: #selector(viewProgressButtonTapped), for: .touchUpInside)
        
        setupButton(restoreButton, title: "Restore Purchases", isPrimary: false)
        restoreButton.addTarget(self, action: #selector(restoreButtonTapped), for: .touchUpInside)
        
        setupButton(manageSubscriptionButton, title: "Manage Subscription", isPrimary: false)
        manageSubscriptionButton.addTarget(self, action: #selector(manageSubscriptionButtonTapped), for: .touchUpInside)
        
        setupButton(clearHistoryButton, title: "Clear Session History", isPrimary: false, isDestructive: true)
        clearHistoryButton.addTarget(self, action: #selector(clearHistoryButtonTapped), for: .touchUpInside)
        
        setupButton(privacyButton, title: "Privacy Policy", isPrimary: false)
        privacyButton.addTarget(self, action: #selector(privacyButtonTapped), for: .touchUpInside)
        
        setupButton(termsButton, title: "Terms of Use", isPrimary: false)
        termsButton.addTarget(self, action: #selector(termsButtonTapped), for: .touchUpInside)
        
        setupButton(doneButton, title: "Done", isPrimary: true)
        doneButton.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        
        // Add elements to stack view
        mainStackView.addArrangedSubview(titleLabel)
        
        // Add spacing
        let spacer1 = UIView()
        spacer1.heightAnchor.constraint(equalToConstant: 16).isActive = true
        mainStackView.addArrangedSubview(spacer1)
        
        mainStackView.addArrangedSubview(subscriptionStatusLabel)
        
        // Add spacing
        let spacer2 = UIView()
        spacer2.heightAnchor.constraint(equalToConstant: 24).isActive = true
        mainStackView.addArrangedSubview(spacer2)
        
        mainStackView.addArrangedSubview(viewProgressButton)
        mainStackView.addArrangedSubview(restoreButton)
        mainStackView.addArrangedSubview(manageSubscriptionButton)
        mainStackView.addArrangedSubview(clearHistoryButton)
        mainStackView.addArrangedSubview(privacyButton)
        mainStackView.addArrangedSubview(termsButton)
        
        // Add spacing before done button
        let spacer3 = UIView()
        spacer3.heightAnchor.constraint(equalToConstant: 32).isActive = true
        mainStackView.addArrangedSubview(spacer3)
        
        mainStackView.addArrangedSubview(doneButton)
        
        // Loading indicator
        loadingIndicator.color = primaryColor
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupButton(_ button: UIButton, title: String, isPrimary: Bool, isDestructive: Bool = false) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        if isPrimary {
            button.backgroundColor = primaryColor
            button.setTitleColor(darkColor, for: .normal)
            button.layer.borderWidth = 0
        } else if isDestructive {
            button.backgroundColor = .clear
            button.setTitleColor(.systemRed, for: .normal)
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.systemRed.cgColor
        } else {
            button.backgroundColor = .clear
            button.setTitleColor(secondaryColor, for: .normal)
            button.layer.borderWidth = 2
            button.layer.borderColor = secondaryColor.cgColor
        }
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Main stack view
            mainStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            mainStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            mainStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - Subscription Status
    private func updateSubscriptionStatus() {
        Task { [weak self] in
            guard let self = self else { return }
            
            let isEntitled = EntitlementManager.shared.isEntitled
            let isWithinTrial = EntitlementManager.shared.isWithinTrialWindow()
            
            var statusText: String
            if isEntitled {
                if #available(iOS 15.0, *) {
                    let storeActive = await StoreManager.shared.currentEntitlementActive()
                    if storeActive {
                        statusText = "Subscription: Active"
                    } else if isWithinTrial {
                        statusText = "Subscription: Free Trial Active"
                    } else {
                        statusText = "Subscription: Trial Ended"
                    }
                } else {
                    statusText = isWithinTrial ? "Subscription: Free Trial Active" : "Subscription: Active"
                }
            } else {
                statusText = isWithinTrial ? "Subscription: Free Trial Active" : "Subscription: Inactive"
            }
            
            await MainActor.run {
                self.subscriptionStatusLabel.text = statusText
            }
        }
    }
    
    // MARK: - Actions
    @objc private func viewProgressButtonTapped() {
        let progressViewController = ProgressViewController()
        progressViewController.modalPresentationStyle = .fullScreen
        present(progressViewController, animated: true)
    }
    
    @objc private func restoreButtonTapped() {
        guard #available(iOS 15.0, *) else {
            showAlert(title: "Not Available", message: "Restore purchases requires iOS 15 or later.")
            return
        }
        
        showLoading(true)
        
        Task { [weak self] in
            guard let self = self else { return }
            
            await StoreManager.shared.restorePurchases()
            await StoreManager.shared.refreshEntitlements()
            
            await MainActor.run {
                self.showLoading(false)
                self.updateSubscriptionStatus()
                
                let isEntitled = EntitlementManager.shared.isEntitled
                if isEntitled {
                    self.showAlert(title: "Purchases Restored", message: "Your subscription has been successfully restored.")
                } else {
                    self.showAlert(title: "No Purchases Found", message: "We couldn't find any previous purchases to restore.")
                }
            }
        }
    }
    
    @objc private func manageSubscriptionButtonTapped() {
        let urlString = "itms-apps://apps.apple.com/account/subscriptions"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    @objc private func clearHistoryButtonTapped() {
        let alert = UIAlertController(
            title: "Clear Session History?",
            message: "This will permanently delete all session data and reset the adaptive difficulty system. This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear Data", style: .destructive) { [weak self] _ in
            self?.performHistoryClearing()
        })
        
        present(alert, animated: true)
    }
    
    private func performHistoryClearing() {
        showLoading(true)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Get current user ID
            let userId = UserIDManager.getUserId()
            
            // Clear session files
            let sessionResult = DataLogger.deleteAllSessionFiles()
            
            // Clear ADM state
            ADMPersistenceManager.clearState(for: userId)
            
            DispatchQueue.main.async {
                self.showLoading(false)
                
                if sessionResult.success {
                    let message = sessionResult.deletedCount > 0 
                        ? "Session history cleared successfully. Deleted \(sessionResult.deletedCount) session files and reset adaptive difficulty."
                        : "Session history cleared successfully. No session files found to delete, but adaptive difficulty has been reset."
                    
                    self.showAlert(title: "History Cleared", message: message)
                } else {
                    let errorDetails = sessionResult.errors.isEmpty ? "Unknown error occurred" : sessionResult.errors.joined(separator: "\n")
                    self.showAlert(title: "Clear Failed", message: "Failed to clear session history: \(errorDetails)")
                }
            }
        }
    }
    
    @objc private func privacyButtonTapped() {
        let urlString = "https://kalibrate.me/privacy-policy"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    @objc private func termsButtonTapped() {
        let urlString = "https://kalibrate.me/terms-of-use"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Helper Methods
    private func showLoading(_ show: Bool) {
        if show {
            loadingIndicator.startAnimating()
            view.isUserInteractionEnabled = false
        } else {
            loadingIndicator.stopAnimating()
            view.isUserInteractionEnabled = true
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
