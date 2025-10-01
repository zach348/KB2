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
// KB2/StoreManager.swift
// StoreKit 2 subscription management

import Foundation
import StoreKit

@available(iOS 15.0, *)
public enum PurchaseResult {
    case success
    case userCancelled
    case pending
    case failed(Error)
}

@available(iOS 15.0, *)
actor StoreManager {
    static let shared = StoreManager()
    
    // Confirmed product IDs
    private let productIDs: Set<String> = [
        "com.kalibrate.kb2.monthly",
        "com.kalibrate.kb2.annual"
    ]
    
    private(set) var products: [Product] = []
    private(set) var hasActiveSubscription: Bool = false
    
    // MARK: - Public API
    
    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Array(productIDs))
            self.products = loaded
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .storeProductsDidLoad, object: nil)
            }
            print("[StoreManager] Loaded products: \(loaded.map { $0.id })")
        } catch {
            print("[StoreManager] Failed to load products: \(error)")
        }
    }
    
    func refreshEntitlements() async {
        var active = false
        do {
            for await result in Transaction.currentEntitlements {
                switch result {
                case .verified(let transaction):
                    // Treat auto-renewable verified and not expired/revoked as active
                    if transaction.productType == .autoRenewable,
                       transaction.revocationDate == nil,
                       (transaction.expirationDate == nil || (transaction.expirationDate ?? .distantPast) > Date()) {
                        active = true
                    }
                case .unverified(_, let error):
                    print("[StoreManager] Unverified entitlement: \(error)")
                }
            }
        }
        
        self.hasActiveSubscription = active
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .storeEntitlementDidChange,
                object: nil,
                userInfo: ["isEntitled": active]
            )
        }
        print("[StoreManager] Entitlement refreshed. Active: \(active)")
    }
    
    func startTransactionListener() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                await self.process(transactionVerificationResult: update)
            }
        }
        print("[StoreManager] Transaction listener started")
    }
    
    func purchase(productID: String) async -> PurchaseResult {
        do {
            let product = try await productFor(id: productID)
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                    return .success
                case .unverified(_, let error):
                    print("[StoreManager] Unverified purchase: \(error)")
                    return .failed(error)
                }
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed(NSError(domain: "StoreManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown purchase result"]))
            }
        } catch {
            print("[StoreManager] Purchase failed: \(error)")
            return .failed(error)
        }
    }
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            print("[StoreManager] AppStore.sync() failed: \(error)")
        }
        await refreshEntitlements()
    }
    
    func currentEntitlementActive() -> Bool {
        hasActiveSubscription
    }
    
    // MARK: - Helpers
    
    private func productFor(id: String) async throws -> Product {
        if let found = products.first(where: { $0.id == id }) {
            return found
        }
        // Lazy-load if not present
        try await loadProducts()
        if let found = products.first(where: { $0.id == id }) {
            return found
        }
        throw NSError(domain: "StoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Product not found: \(id)"])
    }
    
    // Returns a localized display price for the given product ID, if available
    func displayPrice(for productID: String) async -> String? {
        do {
            let product = try await productFor(id: productID)
            return product.displayPrice
        } catch {
            print("[StoreManager] displayPrice error for \(productID): \(error)")
            return nil
        }
    }
    
    private func process(transactionVerificationResult result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            print("[StoreManager] Verified transaction update for \(transaction.productID)")
            // Finish and refresh entitlements
            await transaction.finish()
            await refreshEntitlements()
        case .unverified(_, let error):
            print("[StoreManager] Unverified transaction update: \(error)")
        }
    }
}
