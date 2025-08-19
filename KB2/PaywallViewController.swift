import UIKit

protocol PaywallViewControllerDelegate: AnyObject {
    func paywallViewController(_ controller: PaywallViewController, didCompleteWith result: PaywallResult)
}

enum PaywallResult {
    case purchased
    case restored
    case cancelled
}

class PaywallViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: PaywallViewControllerDelegate?
    
    // Brand Colors
    private let primaryColor = UIColor(red: 0x77/255.0, green: 0xFD/255.0, blue: 0xC7/255.0, alpha: 1.0) // #77FDC7
    private let secondaryColor = UIColor(red: 0xA0/255.0, green: 0x9E/255.0, blue: 0xA1/255.0, alpha: 1.0) // #A09EA1
    private let darkColor = UIColor(red: 0x24/255.0, green: 0x24/255.0, blue: 0x24/255.0, alpha: 1.0) // #242424
    private let whiteColor = UIColor.white // #FFFFFF
    
    // UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let monthlyButton = UIButton(type: .system)
    private let annualButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let trialInfoLabel = UILabel()
    private let privacyButton = UIButton(type: .system)
    private let termsButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    
    // Product data
    private var monthlyPrice: String = "$0.99"
    private var annualPrice: String = "$7.99"
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadProductPrices()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = darkColor
        
        // Close button
        view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("✕", for: .normal)
        closeButton.setTitleColor(secondaryColor, for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        
        // Scroll view setup
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        setupContent()
        setupConstraints()
    }
    
    private func setupContent() {
        // Title and subtitle - dynamic based on trial status
        let isWithinTrial = EntitlementManager.shared.isWithinTrialWindow()
        
        if isWithinTrial {
            titleLabel.text = "Welcome! Your 7-Day Free Trial Has Started"
            subtitleLabel.text = "Enjoy unlimited sessions for 7 days. Subscribe to continue after your trial ends."
        } else {
            titleLabel.text = "Your Free Trial Has Ended"
            subtitleLabel.text = "Subscribe now to continue your cognitive training journey with unlimited sessions."
        }
        
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = whiteColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)
        
        subtitleLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        subtitleLabel.textColor = secondaryColor
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        contentView.addSubview(subtitleLabel)
        
        // Monthly subscription button
        setupSubscriptionButton(monthlyButton, title: "Monthly", price: monthlyPrice, isRecommended: false)
        monthlyButton.addTarget(self, action: #selector(monthlyButtonTapped), for: .touchUpInside)
        contentView.addSubview(monthlyButton)
        
        // Annual subscription button (recommended)
        setupSubscriptionButton(annualButton, title: "Annual", price: annualPrice, isRecommended: true)
        annualButton.addTarget(self, action: #selector(annualButtonTapped), for: .touchUpInside)
        contentView.addSubview(annualButton)
        
        // Trial info - dynamic based on trial status
        if isWithinTrial {
            trialInfoLabel.text = "Your free trial is active. You won't be charged until it expires. Cancel anytime."
        } else {
            trialInfoLabel.text = "Subscribe now to regain access to unlimited cognitive training sessions. Cancel anytime."
        }
        
        trialInfoLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        trialInfoLabel.textColor = secondaryColor
        trialInfoLabel.textAlignment = .center
        trialInfoLabel.numberOfLines = 0
        contentView.addSubview(trialInfoLabel)
        
        // Restore button
        restoreButton.setTitle("Restore Purchases", for: .normal)
        restoreButton.setTitleColor(secondaryColor, for: .normal)
        restoreButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        restoreButton.addTarget(self, action: #selector(restoreButtonTapped), for: .touchUpInside)
        contentView.addSubview(restoreButton)
        
        // Legal links
        setupLegalButton(privacyButton, title: "Privacy Policy")
        privacyButton.addTarget(self, action: #selector(privacyButtonTapped), for: .touchUpInside)
        contentView.addSubview(privacyButton)
        
        setupLegalButton(termsButton, title: "Terms of Use")
        termsButton.addTarget(self, action: #selector(termsButtonTapped), for: .touchUpInside)
        contentView.addSubview(termsButton)
        
        // Loading indicator
        loadingIndicator.color = primaryColor
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        
        // Set constraints for all elements
        [titleLabel, subtitleLabel, monthlyButton, annualButton, trialInfoLabel, restoreButton, privacyButton, termsButton, loadingIndicator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
    }
    
    private func setupSubscriptionButton(_ button: UIButton, title: String, price: String, isRecommended: Bool) {
        button.backgroundColor = isRecommended ? primaryColor : darkColor
        button.setTitleColor(isRecommended ? darkColor : whiteColor, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = isRecommended ? 0 : 2
        button.layer.borderColor = isRecommended ? UIColor.clear.cgColor : secondaryColor.cgColor
        
        var buttonTitle = "\(title) - \(price)"
        if isRecommended {
            buttonTitle += " (Family Sharing)"
        }
        button.setTitle(buttonTitle, for: .normal)
    }
    
    private func setupLegalButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(secondaryColor, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Annual button (recommended, shown first)
            annualButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 48),
            annualButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            annualButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            annualButton.heightAnchor.constraint(equalToConstant: 56),
            
            // Monthly button
            monthlyButton.topAnchor.constraint(equalTo: annualButton.bottomAnchor, constant: 16),
            monthlyButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            monthlyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            monthlyButton.heightAnchor.constraint(equalToConstant: 56),
            
            // Trial info
            trialInfoLabel.topAnchor.constraint(equalTo: monthlyButton.bottomAnchor, constant: 24),
            trialInfoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            trialInfoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Restore button
            restoreButton.topAnchor.constraint(equalTo: trialInfoLabel.bottomAnchor, constant: 32),
            restoreButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            restoreButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Privacy button
            privacyButton.topAnchor.constraint(equalTo: restoreButton.bottomAnchor, constant: 24),
            privacyButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            privacyButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Terms button
            termsButton.topAnchor.constraint(equalTo: restoreButton.bottomAnchor, constant: 24),
            termsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            termsButton.heightAnchor.constraint(equalToConstant: 32),
            termsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - Actions
    @objc private func closeButtonTapped() {
        delegate?.paywallViewController(self, didCompleteWith: .cancelled)
    }
    
    @objc private func monthlyButtonTapped() {
        purchaseProduct(productID: "com.kalibrate.kb2.monthly")
    }
    
    @objc private func annualButtonTapped() {
        purchaseProduct(productID: "com.kalibrate.kb2.annual")
    }
    
    @objc private func restoreButtonTapped() {
        restorePurchases()
    }
    
    @objc private func privacyButtonTapped() {
        // TODO: Replace with actual Privacy Policy URL
        let urlString = "https://example.com/privacy"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    @objc private func termsButtonTapped() {
        // TODO: Replace with actual Terms of Use URL
        let urlString = "https://example.com/terms"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Store Operations
    private func loadProductPrices() {
        if #available(iOS 15.0, *) {
            Task { [weak self] in
                guard let self = self else { return }
                
                let monthlyPrice = await StoreManager.shared.displayPrice(for: "com.kalibrate.kb2.monthly") ?? "$0.99"
                let annualPrice = await StoreManager.shared.displayPrice(for: "com.kalibrate.kb2.annual") ?? "$7.99"
                
                await MainActor.run {
                    self.monthlyPrice = monthlyPrice
                    self.annualPrice = annualPrice
                    self.updateButtonTitles()
                }
            }
        }
    }
    
    private func updateButtonTitles() {
        setupSubscriptionButton(monthlyButton, title: "Monthly", price: monthlyPrice, isRecommended: false)
        setupSubscriptionButton(annualButton, title: "Annual", price: annualPrice, isRecommended: true)
    }
    
    private func purchaseProduct(productID: String) {
        guard #available(iOS 15.0, *) else {
            showAlert(title: "Not Available", message: "Purchases require iOS 15 or later.")
            return
        }
        
        showLoading(true)
        
        Task { [weak self] in
            guard let self = self else { return }
            
            let result = await StoreManager.shared.purchase(productID: productID)
            
            await MainActor.run {
                self.showLoading(false)
                
                switch result {
                case .success:
                    self.delegate?.paywallViewController(self, didCompleteWith: .purchased)
                case .pending:
                    Task {
                        await StoreManager.shared.refreshEntitlements()
                        let storeEntitlementActive = await StoreManager.shared.currentEntitlementActive()
                        let active = EntitlementManager.shared.isEntitled || storeEntitlementActive
                        await MainActor.run {
                            if active {
                                self.delegate?.paywallViewController(self, didCompleteWith: .purchased)
                            } else {
                                self.showAlert(title: "Purchase Pending", message: "Your purchase is being processed. Please try again in a moment.")
                            }
                        }
                    }
                case .userCancelled:
                    break // User cancelled, no action needed
                case .failed:
                    self.showAlert(title: "Purchase Failed", message: "Unable to complete the purchase. Please try again.")
                }
            }
        }
    }
    
    private func restorePurchases() {
        guard #available(iOS 15.0, *) else {
            showAlert(title: "Not Available", message: "Restore purchases requires iOS 15 or later.")
            return
        }
        
        showLoading(true)
        
        Task { [weak self] in
            guard let self = self else { return }
            
            await StoreManager.shared.restorePurchases()
            let storeEntitlementActive = await StoreManager.shared.currentEntitlementActive()
            let active = EntitlementManager.shared.isEntitled || storeEntitlementActive
            
            await MainActor.run {
                self.showLoading(false)
                
                if active {
                    self.delegate?.paywallViewController(self, didCompleteWith: .restored)
                } else {
                    self.showAlert(title: "No Purchases Found", message: "We couldn't find any previous purchases to restore.")
                }
            }
        }
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
