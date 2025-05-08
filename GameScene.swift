// NeuroGlide/GameScene.swift
// Created: [Previous Date]
// Updated: [Current Date] - Step 11 FIX 10 (COMPLETE FILE - Debug ID Taps)
// Role: Main scene. Debugging ID tap registration.

import SpriteKit
import GameplayKit
import CoreHaptics
import AVFoundation

// --- Game State Enum ---
internal enum GameState { case tracking, identifying, paused, breathing }

// --- Breathing Phase Enum ---
internal enum BreathingPhase { case idle, inhale, holdAfterInhale, exhale, holdAfterExhale }

class GameScene: SKScene, SKPhysicsContactDelegate {

    // --- Configuration ---
    internal let gameConfiguration = GameConfiguration()

    // --- Properties ---
    internal var currentState: GameState = .tracking
    private var _currentArousalLevel: CGFloat = 0.75 // Backing variable
    internal var currentArousalLevel: CGFloat {
        get { return _currentArousalLevel }
        set {
            let oldValue = _currentArousalLevel
            let clampedValue = max(0.0, min(newValue, 1.0))
            if clampedValue != _currentArousalLevel {
                _currentArousalLevel = clampedValue
                print("DIAGNOSTIC: Arousal Level Changed to \(String(format: "%.2f", _currentArousalLevel))")
                checkStateTransition(oldValue: oldValue, newValue: _currentArousalLevel)
                updateParametersFromArousal()
                checkBreathingFade()
            }
        }
    }
    internal var currentBreathingPhase: BreathingPhase = .idle
    internal var breathingAnimationActionKey = "breathingAnimation"
    internal var precisionTimer: PrecisionTimer?
    internal var targetShiftTimerActionKey = "targetShiftTimer"
    internal var identificationTimerActionKey = "identificationTimer"
    internal var identificationTimeoutActionKey = "identificationTimeout"
    internal var isFlashSequenceRunning: Bool = false
    internal var flashCooldownEndTime: TimeInterval = 0.0
    internal var identificationCheckNeeded: Bool = false
    internal var timeUntilNextShift: TimeInterval = 0
    internal var timeUntilNextIDCheck: TimeInterval = 0
    internal var currentMinShiftInterval: TimeInterval = 5.0
    internal var currentMaxShiftInterval: TimeInterval = 10.0
    internal var currentMinIDInterval: TimeInterval = 10.0
    internal var currentMaxIDInterval: TimeInterval = 15.0
    internal var balls: [Ball] = []
    internal var motionSettings = MotionSettings()
    internal var currentTargetCount: Int = GameConfiguration().maxTargetsAtLowTrackingArousal
    internal var currentIdentificationDuration: TimeInterval = GameConfiguration().identificationDuration
    internal var activeTargetColor: SKColor = GameConfiguration().targetColor_LowArousal
    internal var activeDistractorColor: SKColor = GameConfiguration().distractorColor_LowArousal
    internal var targetsToFind: Int = 0
    internal var targetsFoundThisRound: Int = 0
    internal var score: Int = 0

    // Make these methods internal for testing
    internal func assignNewTargets(flashNewTargets: Bool) {
        // ... existing implementation ...
    }

    internal func checkStateTransition(oldValue: CGFloat, newValue: CGFloat) {
        // ... existing implementation ...
    }

    internal func updateParametersFromArousal() {
        // ... existing implementation ...
    }

    internal func checkBreathingFade() {
        // ... existing implementation ...
    }

    // ... rest of the existing code ...
} 