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

    // --- Callbacks ---
    // Closures that GameScene (or another manager) will provide to handle ticks
    var onVisualTick: (() -> Void)?
    var onHapticTick: ((_ targetTime: CFTimeInterval) -> Void)? // Passes target time for scheduling
    var onAudioTick: ((_ targetTime: CFTimeInterval) -> Void)?  // Passes target time for scheduling

    // --- Timing State (Internal) ---
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0.0
    private var accumulatedTime: CFTimeInterval = 0.0

    // --- Public Methods ---

    /// Starts the timer. Creates and schedules the CADisplayLink.
    func start() {
        guard !isRunning else { return } // Don't start if already running

        // Create the display link, targeting the update method
        displayLink = CADisplayLink(target: self, selector: #selector(update))

        // Reset timing state
        lastTimestamp = 0.0
        accumulatedTime = 0.0

        // Add to the main run loop to start receiving updates
        displayLink?.add(to: .main, forMode: .common)

        print("PrecisionTimer started with frequency: \(frequency) Hz")
    }

    /// Stops the timer. Invalidates and releases the CADisplayLink.
    func stop() {
        guard isRunning else { return } // Don't stop if not running

        displayLink?.invalidate() // Stop receiving updates and remove from run loop
        displayLink = nil
        print("PrecisionTimer stopped.")
    }

    // --- Internal CADisplayLink Update Method ---

    /// Called by CADisplayLink for every frame refresh.
    @objc private func update(link: CADisplayLink) {
        if lastTimestamp == 0.0 {
            // First frame after starting or resetting
            lastTimestamp = link.timestamp
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

            // Calculate the *exact* time this tick should ideally occur
            // This is important for scheduling haptics/audio precisely later
            // For now, we use the current timestamp as the visual trigger time.
            let targetTimestamp = link.timestamp // Could refine this calculation slightly

            // --- Trigger Callbacks ---
            // Call the registered closures (if they exist)
            onVisualTick?()

            // For haptics and audio, pass the target time for potential future scheduling
            // We'll implement the actual offset delays in Step 2
            onHapticTick?(targetTimestamp)
            onAudioTick?(targetTimestamp)


            // Subtract one interval's worth of time
            accumulatedTime -= tickInterval

            // Safety break: If frequency is extremely high or frame rate very low,
            // prevent potential infinite loops in edge cases.
             if tickInterval <= 0 { break }
        }
    }

    // Deinitializer to ensure timer stops if the object is destroyed
    deinit {
        stop()
        print("PrecisionTimer deinitialized.")
    }
}
