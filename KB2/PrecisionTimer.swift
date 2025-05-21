// KB2/PrecisionTimer.swift
// Created: [Current Date]
// Role: Provides a high-precision timer synchronized with screen refresh (CADisplayLink)
//       for triggering time-sensitive events (visual, haptic, audio).

import Foundation
import QuartzCore // For CADisplayLink

class PrecisionTimer {

    // --- Configuration ---
    public var frequency: Double = 10.0 // Default frequency in Hz (cycles per second)
    public var isRunning: Bool { displayLink != nil }
    public var visualPulseDuration: CFTimeInterval = 0.02 // Default, will be updated based on game config

    // --- Callbacks ---
    // Closures that GameScene (or another manager) will provide to handle ticks
    var onVisualTick: (() -> Void)?
    var onHapticTick: ((_ targetTime: CFTimeInterval) -> Void)? // Passes target time for scheduling
    var onAudioTick: ((_ targetTime: CFTimeInterval) -> Void)?  // Passes target time for scheduling

    // --- Timing State (Internal) ---
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0.0
    private var accumulatedTime: CFTimeInterval = 0.0
    
    // --- Synchronization Tracking ---
    private var tickCount: UInt = 0
    private var nextScheduledTickTime: CFTimeInterval = 0.0
    private var maxLatency: CFTimeInterval = 0.0
    private var debugLogFrequency: UInt = 60 // Log timing stats every N ticks (0 = disabled)

    // --- Public Methods ---

    /// Starts the timer. Creates and schedules the CADisplayLink.
    func start() {
        guard !isRunning else { return } // Don't start if already running

        // Create the display link, targeting the update method
        displayLink = CADisplayLink(target: self, selector: #selector(update))

        // Reset timing state
        lastTimestamp = 0.0
        accumulatedTime = 0.0
        tickCount = 0
        nextScheduledTickTime = 0.0
        maxLatency = 0.0

        // Add to the main run loop to start receiving updates
        displayLink?.add(to: .main, forMode: .common)

        print("PrecisionTimer started with frequency: \(frequency) Hz")
    }

    /// Stops the timer. Invalidates and releases the CADisplayLink.
    func stop() {
        guard isRunning else { return } // Don't stop if not running

        displayLink?.invalidate() // Stop receiving updates and remove from run loop
        displayLink = nil
        
        // Log final timing stats
        if maxLatency > 0 {
            print("PrecisionTimer stopped. Max latency observed: \(String(format: "%.3f", maxLatency * 1000))ms")
        } else {
            print("PrecisionTimer stopped.")
        }
    }
    
    /// Update the visual pulse duration based on configuration
    func updateVisualPulseDuration(newDuration: CFTimeInterval) {
        visualPulseDuration = max(0.01, min(newDuration, 0.2)) // Sanity limits between 10ms-200ms
    }

    // --- Internal CADisplayLink Update Method ---

    /// Called by CADisplayLink for every frame refresh.
    @objc private func update(link: CADisplayLink) {
        if lastTimestamp == 0.0 {
            // First frame after starting or resetting
            lastTimestamp = link.timestamp
            nextScheduledTickTime = link.timestamp
            return // Don't process the first frame, just establish baseline time
        }

        let elapsedTime = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        accumulatedTime += elapsedTime

        // Calculate the desired interval between ticks based on frequency
        let tickInterval = 1.0 / frequency

        // Check if enough time has accumulated to trigger a tick
        while accumulatedTime >= tickInterval {
            // A tick is due!
            tickCount += 1
            
            // Calculate the exact time this tick should ideally occur
            // This is important for precise scheduling of haptics/audio
            nextScheduledTickTime += tickInterval
            
            // If we're very far behind (e.g., after app suspension), reset timing
            if link.timestamp - nextScheduledTickTime > 0.1 {
                nextScheduledTickTime = link.timestamp
            }
            
            // Calculate latency for diagnostics
            let currentLatency = abs(link.timestamp - nextScheduledTickTime)
            maxLatency = max(maxLatency, currentLatency)
            
            // Log timing information periodically if enabled
            if debugLogFrequency > 0 && tickCount % debugLogFrequency == 0 {
                print("PrecisionTimer: [\(tickCount)] latency = \(String(format: "%.3f", currentLatency * 1000))ms, max = \(String(format: "%.3f", maxLatency * 1000))ms")
            }

            // --- Trigger Callbacks ---
            // Call the registered closures (if they exist)
            onVisualTick?()

            // For haptics and audio, pass the target time for scheduling
            onHapticTick?(nextScheduledTickTime)
            onAudioTick?(nextScheduledTickTime)

            // Subtract one interval's worth of time
            accumulatedTime -= tickInterval

            // Safety break: prevent potential infinite loops in edge cases
            if tickInterval <= 0 { break }
        }
    }

    // Deinitializer to ensure timer stops if the object is destroyed
    deinit {
        stop()
        print("PrecisionTimer deinitialized.")
    }
}
