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
// KB2/KeychainManager.swift
// Minimal Keychain wrapper for storing small values (e.g., trial_start_date)

import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()
    private init() {}
    
    // Adjust if you change your bundle identifier
    private let service = "com.kalibrate.kb2"
    
    // MARK: - Public API
    
    @discardableResult
    func setString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return setData(data, forKey: key)
    }
    
    func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    @discardableResult
    func setDate(_ value: Date, forKey key: String) -> Bool {
        let iso = ISO8601DateFormatter().string(from: value)
        return setString(iso, forKey: key)
    }
    
    func getDate(forKey key: String) -> Date? {
        guard let iso = getString(forKey: key) else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }
    
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Internal
    
    @discardableResult
    private func setData(_ data: Data, forKey key: String) -> Bool {
        // Try update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            // Add if it doesn't exist
            var addQuery = query
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
    
    private func getData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return (item as? Data)
    }
}
