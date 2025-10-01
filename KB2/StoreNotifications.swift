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
// KB2/StoreNotifications.swift
// Centralized Notification.Name constants for Store/Entitlement events

import Foundation

public extension Notification.Name {
    static let storeProductsDidLoad = Notification.Name("StoreProductsDidLoad")
    static let storeEntitlementDidChange = Notification.Name("StoreEntitlementDidChange")
    static let entitlementStatusDidChange = Notification.Name("EntitlementStatusDidChange")
}
