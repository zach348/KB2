// KB2/FirstRunManager.swift
import Foundation

final class FirstRunManager {
    static let shared = FirstRunManager()
    private init() {}

    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private let hasCompletedTutorialKey = "hasCompletedTutorial"
    private let sessionCountKey = "sessionCount"
    private let hasAcceptedSurveyKey = "hasAcceptedSurvey"
    private let surveyLastDeclinedVersionKey = "surveyLastDeclinedVersion"

    var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey)
        }
    }

    var hasCompletedTutorial: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasCompletedTutorialKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasCompletedTutorialKey)
        }
    }
    
    var sessionCount: Int {
        get {
            UserDefaults.standard.integer(forKey: sessionCountKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: sessionCountKey)
        }
    }
    
    var hasAcceptedSurvey: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasAcceptedSurveyKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasAcceptedSurveyKey)
        }
    }
    
    var surveyLastDeclinedVersion: String? {
        get {
            UserDefaults.standard.string(forKey: surveyLastDeclinedVersionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: surveyLastDeclinedVersionKey)
        }
    }
    
    // Tracks whether we've shown the non-blocking subscription offer during trial
    private let hasShownSubscriptionOfferKey = "hasShownSubscriptionOffer"
    var hasShownSubscriptionOffer: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasShownSubscriptionOfferKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasShownSubscriptionOfferKey)
        }
    }

    #if DEBUG
    func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: hasCompletedTutorialKey)
        UserDefaults.standard.removeObject(forKey: hasShownSubscriptionOfferKey)
        UserDefaults.standard.removeObject(forKey: sessionCountKey)
        UserDefaults.standard.removeObject(forKey: hasAcceptedSurveyKey)
        UserDefaults.standard.removeObject(forKey: surveyLastDeclinedVersionKey)
    }

    func resetTutorialForDebug() {
        UserDefaults.standard.removeObject(forKey: hasCompletedTutorialKey)
    }
    #endif
    
    // TestFlight reset - allows fresh experience testing
    func resetForTestFlight() {
        // Only allow in TestFlight or DEBUG builds (not App Store releases)
        guard isTestFlightOrDebugBuild() else {
            print("[FirstRunManager] resetForTestFlight() not available in App Store builds")
            return
        }
        
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: hasCompletedTutorialKey)
        UserDefaults.standard.removeObject(forKey: hasShownSubscriptionOfferKey)
        UserDefaults.standard.removeObject(forKey: sessionCountKey)
        UserDefaults.standard.removeObject(forKey: hasAcceptedSurveyKey)
        UserDefaults.standard.removeObject(forKey: surveyLastDeclinedVersionKey)
        
        // Reset trial date for fresh TestFlight experience
        let now = Date()
        _ = KeychainManager.shared.setDate(now, forKey: "trial_start_date")
        
        print("[FirstRunManager] Reset all onboarding and survey state for TestFlight testing")
    }
    
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
}
