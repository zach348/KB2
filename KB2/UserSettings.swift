// Copyright 2025 Training State, LLC. All rights reserved.
import Foundation

struct UserSettings {
    
    // MARK: - Keys
    private enum Keys {
        static let isAudioEnabled = "UserSettings.isAudioEnabled"
        static let isHapticsEnabled = "UserSettings.isHapticsEnabled"
    }
    
    // MARK: - VHA Stimulation Settings
    
    /// Controls whether rhythmic audio tones are enabled. Defaults to `true`.
    static var isAudioEnabled: Bool {
        get {
            // If no value is set, default to true.
            return UserDefaults.standard.object(forKey: Keys.isAudioEnabled) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.isAudioEnabled)
            print("UserSettings: Audio enabled set to \(newValue)")
        }
    }
    
    /// Controls whether rhythmic haptic feedback is enabled. Defaults to `true`.
    static var isHapticsEnabled: Bool {
        get {
            // If no value is set, default to true.
            return UserDefaults.standard.object(forKey: Keys.isHapticsEnabled) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.isHapticsEnabled)
            print("UserSettings: Haptics enabled set to \(newValue)")
        }
    }
}
