// KB2/StoreNotifications.swift
// Centralized Notification.Name constants for Store/Entitlement events

import Foundation

public extension Notification.Name {
    static let storeProductsDidLoad = Notification.Name("StoreProductsDidLoad")
    static let storeEntitlementDidChange = Notification.Name("StoreEntitlementDidChange")
    static let entitlementStatusDidChange = Notification.Name("EntitlementStatusDidChange")
}
