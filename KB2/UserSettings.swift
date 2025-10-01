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
