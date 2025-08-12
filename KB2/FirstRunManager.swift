// KB2/FirstRunManager.swift
import Foundation

final class FirstRunManager {
    static let shared = FirstRunManager()
    private init() {}

    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey)
        }
    }

    #if DEBUG
    func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
    }
    #endif
}
