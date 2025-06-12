import Foundation
import Security

/// Manages a persistent, anonymous user ID using the device's Keychain.
/// This ensures the ID persists across app installs and updates.
class UserIDManager {
    
    // A unique service name to identify our app's entry in the Keychain.
    private static let serviceName = "com.kalibrate.userid"
    
    /// Retrieves the persistent user ID from the Keychain.
    /// If no ID exists, it generates a new one, saves it, and returns it.
    /// - Returns: A string representing the unique, persistent user ID.
    static func getUserId() -> String {
        // First, try to retrieve an existing ID from the Keychain.
        if let existingId = retrieveFromKeychain() {
            print("UserIDManager: Found existing user ID.")
            return existingId
        }
        
        // If no ID was found, generate a new one.
        let newId = UUID().uuidString
        print("UserIDManager: No existing user ID found. Generated new ID: \(newId)")
        
        // Save the new ID to the Keychain for future use.
        saveToKeychain(userId: newId)
        
        return newId
    }
    
    /// Saves the user ID to the device's Keychain.
    /// - Parameter userId: The user ID string to save.
    private static func saveToKeychain(userId: String) {
        guard let data = userId.data(using: .utf8) else {
            print("UserIDManager: Error converting user ID to data.")
            return
        }
        
        // Create a query to save the item.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecValueData as String: data,
            // Set accessibility to allow access even when the device is locked.
            // This is important for background tasks.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // First, delete any old item to ensure we can write a new one.
        SecItemDelete(query as CFDictionary)
        
        // Add the new item to the Keychain.
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("UserIDManager: Error saving to Keychain. Status: \(status)")
        }
    }
    
    /// Retrieves the user ID from the device's Keychain.
    /// - Returns: The user ID string if found, otherwise nil.
    private static func retrieveFromKeychain() -> String? {
        // Create a query to search for the item.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let retrievedData = dataTypeRef as? Data,
               let userId = String(data: retrievedData, encoding: .utf8) {
                return userId
            }
        }
        
        // If no item is found (errSecItemNotFound), this is not an error,
        // it just means we need to create one. We don't log this case.
        if status != errSecItemNotFound {
            print("UserIDManager: Error retrieving from Keychain. Status: \(status)")
        }
        
        return nil
    }
}
