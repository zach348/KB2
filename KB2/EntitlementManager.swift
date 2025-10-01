// Copyright 2025 Training State, LLC. All rights reserved.
// KB2/EntitlementManager.swift
// Centralized entitlement logic: active subscription OR 7-day trial window

import Foundation

final class EntitlementManager {
    static let shared = EntitlementManager()
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreEntitlementChanged(_:)),
            name: .storeEntitlementDidChange,
            object: nil
        )
    }
    
    // Feature flag to avoid blocking flows until Phase 2 paywall is in
    var entitlementGateEnabled: Bool = true
    
    // QA override: bypass entitlement system entirely (always treat as entitled)
    // Recommended only for local development and UI testing. Default: false.
    var entitlementBypassEnabled: Bool = false
    
    // QA override: force app to treat user as NOT entitled regardless of StoreKit or trial
    // Use ONLY for local development and manual QA. Default: false.
    var forceNonEntitledOverride: Bool = false
    
    // Trial configuration
    private let trialKey = "trial_start_date"
    private let trialLengthDays: Int = 7
    
    // Cache updated by StoreManager notifications
    private var hasActiveSubscriptionCache: Bool = false
    
    // MARK: - Public
    
    func start() {
        // No-op for now; reserved for future observers or timers.
        postEntitlementStatus()
    }
    
    func startTrialIfNeededOnFirstLaunch() {
        if KeychainManager.shared.getDate(forKey: trialKey) == nil {
            let now = Date()
            _ = KeychainManager.shared.setDate(now, forKey: trialKey)
            print("[EntitlementManager] Initialized trial_start_date at \(now)")
        }
        postEntitlementStatus()
    }
    
    var isEntitled: Bool {
        if entitlementBypassEnabled { return true }
        if forceNonEntitledOverride { return false }
        return hasActiveSubscriptionCache || isWithinTrialWindow()
    }
    
    func isWithinTrialWindow(now: Date = Date()) -> Bool {
        guard let start = KeychainManager.shared.getDate(forKey: trialKey) else {
            return false
        }
        guard let expiry = Calendar.current.date(byAdding: .day, value: trialLengthDays, to: start) else {
            return false
        }
        return now < expiry
    }
    
    // MARK: - Private
    
    @objc private func handleStoreEntitlementChanged(_ note: Notification) {
        if let active = note.userInfo?["isEntitled"] as? Bool {
            hasActiveSubscriptionCache = active
            print("[EntitlementManager] Store entitlement changed. Active sub: \(active)")
        } else {
            // If userInfo missing, pessimistically refresh via cached value
            print("[EntitlementManager] Store entitlement change received without userInfo")
        }
        postEntitlementStatus()
    }
    
    private func postEntitlementStatus() {
        let entitled = isEntitled
        NotificationCenter.default.post(
            name: .entitlementStatusDidChange,
            object: nil,
            userInfo: ["isEntitled": entitled]
        )
    }
}
