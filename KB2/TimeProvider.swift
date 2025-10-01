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
//
//  TimeProvider.swift
//  KB2
//
//  Created by TimeProvider System
//

import Foundation
import QuartzCore

// MARK: - TimeProvider Protocol

protocol TimeProvider {
    func currentTime() -> TimeInterval
}

// MARK: - Real Implementation

class SystemTimeProvider: TimeProvider {
    func currentTime() -> TimeInterval {
        return CACurrentMediaTime()
    }
}

// MARK: - Mock Implementation for Testing

class MockTimeProvider: TimeProvider {
    private var mockTime: TimeInterval = 0
    
    func currentTime() -> TimeInterval {
        return mockTime
    }
    
    func setCurrentTime(_ time: TimeInterval) {
        mockTime = time
    }
    
    func advanceTime(by interval: TimeInterval) {
        mockTime += interval
    }
}
