// Copyright 2025 Training State, LLC. All rights reserved.
//
//  AppDelegate.swift
//  KB2
//
//  Created by Cutler, Zachary on 4/6/25.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // --- Configure DataLogger for Cloud Upload ---
        // URL for the Velo backend function
        let veloURL = "https://kalibrate.me/_functions/sessionData"
        
        // API key stored in Wix Secrets Manager
        let apiKey = "OPkKiCS6$z2CD$jR!&oyZPikFUZnD&oJq@7ZrbzZ"
        
        DataLogger.shared.configureCloudExport(endpointURL: veloURL, apiKey: apiKey)
        DataLogger.shared.startNetworkMonitoring() // To handle offline queuing
        
        // Pre-warm network stack to prevent first-upload audio interference
        DataLogger.shared.prewarmNetworkStack { success in
            print("APP: Network stack pre-warming \(success ? "completed" : "failed")")
        }
        
        // --- Store / Entitlement bootstrap (Phase 1) ---
        if #available(iOS 15.0, *) {
            Task {
                await StoreManager.shared.loadProducts()
                await StoreManager.shared.refreshEntitlements()
                StoreManager.shared.startTransactionListener()
            }
        }
        // Wire QA bypass flag from GameConfiguration -> EntitlementManager
        let config = GameConfiguration()
        EntitlementManager.shared.entitlementBypassEnabled = config.entitlementBypassEnabled
        // Optional QA: force non‑entitled override (useful to see paywall even with an active StoreKit subscription)
        EntitlementManager.shared.forceNonEntitledOverride = config.forceNonEntitledOnLaunch

        // Optional QA: clear entitlement keychain (simulates fresh install)
        if config.clearEntitlementKeychainOnLaunch {
            _ = KeychainManager.shared.delete(forKey: "trial_start_date")
            print("[App] Cleared entitlement Keychain (trial_start_date)")
        }
        // Optional QA: simulate expired trial
        if config.simulateTrialExpiredOnLaunch {
            let expired = Date().addingTimeInterval(-60 * 60 * 24 * 8) // 8 days ago
            _ = KeychainManager.shared.setDate(expired, forKey: "trial_start_date")
            print("[App] Simulated trial expired by setting trial_start_date to \(expired)")
        }
        
        EntitlementManager.shared.start()
        EntitlementManager.shared.startTrialIfNeededOnFirstLaunch()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        
        // Phase 4.5: Save ADM state when app becomes inactive
        NotificationCenter.default.post(name: Notification.Name("SaveADMState"), object: nil)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        
        // Phase 4.5: Save ADM state when entering background
        NotificationCenter.default.post(name: Notification.Name("SaveADMState"), object: nil)
        
        // Suspend VHA stimulation when app enters background
        suspendVHAStimulation()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        
        // Resume VHA stimulation when app enters foreground
        resumeVHAStimulation()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    // MARK: - VHA Control Helper Methods
    
    /// Suspends VHA stimulation by forwarding to the GameViewController
    private func suspendVHAStimulation() {
        print("AppDelegate: Suspending VHA stimulation...")
        if let gameViewController = window?.rootViewController as? GameViewController {
            gameViewController.suspendVHA()
        } else {
            print("AppDelegate: Warning - Could not access GameViewController for VHA suspension")
        }
    }
    
    /// Resumes VHA stimulation by forwarding to the GameViewController
    private func resumeVHAStimulation() {
        print("AppDelegate: Resuming VHA stimulation...")
        if let gameViewController = window?.rootViewController as? GameViewController {
            gameViewController.resumeVHA()
        } else {
            print("AppDelegate: Warning - Could not access GameViewController for VHA resumption")
        }
    }


}
