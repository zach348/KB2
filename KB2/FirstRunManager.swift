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
// KB2/FirstRunManager.swift
import Foundation

final class FirstRunManager {
    static var shared = FirstRunManager()
    
    // MARK: - UserDefaults
    private let userDefaults: UserDefaults
    
    // MARK: - UserDefaults Keys
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private let hasCompletedTutorialKey = "hasCompletedTutorial"
    private let sessionCountKey = "sessionCount"
    private let hasAcceptedSurveyKey = "hasAcceptedSurvey"
    private let surveyPromptsDisabledKey = "surveyPromptsDisabled"
    private let surveyWallDismissalCountKey = "surveyWallDismissalCount"
    
    // MARK: - Initialization
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasCompletedOnboarding: Bool {
        get {
            userDefaults.bool(forKey: hasCompletedOnboardingKey)
        }
        set {
            userDefaults.set(newValue, forKey: hasCompletedOnboardingKey)
        }
    }

    var hasCompletedTutorial: Bool {
        get {
            userDefaults.bool(forKey: hasCompletedTutorialKey)
        }
        set {
            userDefaults.set(newValue, forKey: hasCompletedTutorialKey)
        }
    }
    
    var sessionCount: Int {
        get {
            userDefaults.integer(forKey: sessionCountKey)
        }
        set {
            userDefaults.set(newValue, forKey: sessionCountKey)
        }
    }
    
    var hasAcceptedSurvey: Bool {
        get {
            userDefaults.bool(forKey: hasAcceptedSurveyKey)
        }
        set {
            userDefaults.set(newValue, forKey: hasAcceptedSurveyKey)
        }
    }
    
    var surveyPromptsDisabled: Bool {
        get {
            userDefaults.bool(forKey: surveyPromptsDisabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: surveyPromptsDisabledKey)
        }
    }
    
    var surveyWallDismissalCount: Int {
        get {
            userDefaults.integer(forKey: surveyWallDismissalCountKey)
        }
        set {
            userDefaults.set(newValue, forKey: surveyWallDismissalCountKey)
        }
    }
    
    // Tracks whether we've shown the non-blocking subscription offer during trial
    private let hasShownSubscriptionOfferKey = "hasShownSubscriptionOffer"
    var hasShownSubscriptionOffer: Bool {
        get {
            userDefaults.bool(forKey: hasShownSubscriptionOfferKey)
        }
        set {
            userDefaults.set(newValue, forKey: hasShownSubscriptionOfferKey)
        }
    }

    #if DEBUG
    func resetForDebug() {
        userDefaults.removeObject(forKey: hasCompletedOnboardingKey)
        userDefaults.removeObject(forKey: hasCompletedTutorialKey)
        userDefaults.removeObject(forKey: hasShownSubscriptionOfferKey)
        userDefaults.removeObject(forKey: sessionCountKey)
        userDefaults.removeObject(forKey: hasAcceptedSurveyKey)
        userDefaults.removeObject(forKey: surveyPromptsDisabledKey)
        userDefaults.removeObject(forKey: surveyWallDismissalCountKey)
    }

    func resetTutorialForDebug() {
        userDefaults.removeObject(forKey: hasCompletedTutorialKey)
    }
    #endif
    
    // TestFlight reset - allows fresh experience testing
    func resetForTestFlight() {
        // Only allow in TestFlight or DEBUG builds (not App Store releases)
        guard isTestFlightOrDebugBuild() else {
            print("[FirstRunManager] resetForTestFlight() not available in App Store builds")
            return
        }
        
        userDefaults.removeObject(forKey: hasCompletedOnboardingKey)
        userDefaults.removeObject(forKey: hasCompletedTutorialKey)
        userDefaults.removeObject(forKey: hasShownSubscriptionOfferKey)
        userDefaults.removeObject(forKey: sessionCountKey)
        userDefaults.removeObject(forKey: hasAcceptedSurveyKey)
        userDefaults.removeObject(forKey: surveyPromptsDisabledKey)
        userDefaults.removeObject(forKey: surveyWallDismissalCountKey)
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
