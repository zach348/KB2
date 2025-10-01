// Copyright 2025 Training State, LLC. All rights reserved.
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
