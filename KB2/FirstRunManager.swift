// KB2/FirstRunManager.swift
import Foundation

final class FirstRunManager {
    static let shared = FirstRunManager()
    private init() {}

    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private let hasCompletedTutorialKey = "hasCompletedTutorial"

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

    #if DEBUG
    func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: hasCompletedTutorialKey)
    }

    func resetTutorialForDebug() {
        UserDefaults.standard.removeObject(forKey: hasCompletedTutorialKey)
    }
    #endif
}
