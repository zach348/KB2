// KB2/VHAManager.swift
// Created: [Current Date]
// Role: Manages Visual, Haptic, and Audio (VHA) stimulation systems

import SpriteKit
import CoreHaptics
import AVFoundation

protocol VHAManagerDelegate: AnyObject {
    func hapticEngineStopped(reason: CHHapticEngine.StoppedReason)
    func audioEngineStopped(error: Error?)
}

class VHAManager {
    // MARK: - Properties
    
    weak var delegate: VHAManagerDelegate?
    
    // Visual references
    private var balls: [Ball] = []
    
    // Pulse timing
    private var precisionTimer: PrecisionTimer?
    private var currentTimerFrequency: Double = 5.0 {
        didSet {
            if currentTimerFrequency <= 0 { currentTimerFrequency = 1.0 }
            precisionTimer?.frequency = currentTimerFrequency
        }
    }
    
    // Haptic properties
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?
    private var breathingHapticPlayer: CHHapticPatternPlayer?
    private var hapticsReady: Bool = false
    public var hapticOffset: TimeInterval = 0.020
    
    // Audio properties
    private var audioPulser: PreciseAudioPulser?
    private var audioReady: Bool = false
    private var currentTargetAudioFrequency: Float = 440.0
    private var currentAudioAmplitude: Float = 0.5
    private var currentAudioSquareness: Float = 0.5
    private var currentAudioPulseRate: Double = 4.0
    public var audioOffset: TimeInterval = 0.040
    
    // Breathing settings
    private var currentBreathingInhaleDuration: TimeInterval = 4.0
    private var currentBreathingHold1Duration: TimeInterval = 1.5
    private var currentBreathingExhaleDuration: TimeInterval = 6.0
    private var currentBreathingHold2Duration: TimeInterval = 1.0
    
    // External state flag
    private var isFlashSequenceRunning: Bool = false
    private var flashCooldownEndTime: TimeInterval = 0.0
    
    // MARK: - Initialization
    
    init() {
        setupHaptics()
        setupAudio()
        setupTimer()
    }
    
    // MARK: - Ball Management
    
    func updateBallReferences(_ balls: [Ball]) {
        self.balls = balls
    }
    
    // MARK: - Timer Setup
    
    private func setupTimer() {
        precisionTimer = PrecisionTimer()
        precisionTimer?.frequency = currentTimerFrequency
        precisionTimer?.onVisualTick = { [weak self] in
            self?.handleTimedPulse()
        }
        precisionTimer?.onHapticTick = nil
        precisionTimer?.onAudioTick = nil
    }
    
    func startTimer() {
        precisionTimer?.start()
    }
    
    func stopTimer() {
        precisionTimer?.stop()
    }
    
    // MARK: - Parameter Updates
    
    func updateParameters(frequency: Double, 
                          audioFrequency: Float,
                          audioAmplitude: Float,
                          audioSquareness: Float,
                          audioPulseRate: Double) {
        // Update timer frequency
        self.currentTimerFrequency = frequency
        
        // Update audio parameters
        self.currentTargetAudioFrequency = audioFrequency
        self.currentAudioAmplitude = audioAmplitude
        self.currentAudioSquareness = audioSquareness
        self.currentAudioPulseRate = audioPulseRate
        
        // Apply audio parameter updates
        updateAudioParameters()
    }
    
    func updateBreathingParameters(inhaleDuration: TimeInterval,
                                  hold1Duration: TimeInterval,
                                  exhaleDuration: TimeInterval,
                                  hold2Duration: TimeInterval) {
        // Store new durations
        self.currentBreathingInhaleDuration = inhaleDuration
        self.currentBreathingHold1Duration = hold1Duration
        self.currentBreathingExhaleDuration = exhaleDuration
        self.currentBreathingHold2Duration = hold2Duration
    }
    
    func updateFlashSequenceStatus(isRunning: Bool, cooldownEndTime: TimeInterval) {
        self.isFlashSequenceRunning = isRunning
        self.flashCooldownEndTime = cooldownEndTime
    }
    
    // MARK: - Pulse Handling
    
    private func handleTimedPulse() {
        let now = CACurrentMediaTime()
        
        // Skip visual pulse during flash sequence
        if !isFlashSequenceRunning || now > flashCooldownEndTime {
            executePulse()
        }
    }
    
    private func executePulse() {
        // --- Visual Pulse ---
        let cycleDuration = 1.0 / (precisionTimer?.frequency ?? currentTimerFrequency) 
        let onDuration = cycleDuration * 0.2 // TODO: Read visualPulseOnDurationRatio from config
        guard onDuration > 0.001 else { return }

        for ball in balls {
            let setBorderOn = SKAction.run { ball.lineWidth = Ball.pulseLineWidth }
            let setBorderOff = SKAction.run { ball.lineWidth = 0 }
            let waitOn = SKAction.wait(forDuration: onDuration)
            let sequence = SKAction.sequence([setBorderOn, waitOn, setBorderOff])
            ball.run(sequence, withKey: "visualPulse") // Run action on the ball
        }
        
        // --- Haptic Pulse ---
        if hapticsReady, let player = hapticPlayer {
            DispatchQueue.main.asyncAfter(deadline: .now() + hapticOffset) {
                try? player.start(atTime: CHHapticTimeImmediate)
            }
        }
        
        // Audio is now handled by the PreciseAudioPulser directly
        // No need for any audio code here as it's sample-accurate and 
        // continuously running based on the parameters we set
    }
    
    // MARK: - Haptic Engine
    
    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { 
            hapticsReady = false
            return 
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.playsHapticsOnly = false
            
            hapticEngine?.stoppedHandler = { [weak self] reason in
                print("Haptic stopped: \(reason)")
                self?.hapticsReady = false
                self?.delegate?.hapticEngineStopped(reason: reason)
            }
            
            hapticEngine?.resetHandler = { [weak self] in
                print("Haptic reset.")
                self?.hapticsReady = false
                self?.startHapticEngine()
            }
            
            // Create a basic transient event for the timer pulse
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            let transientEvent = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            let transientPattern = try CHHapticPattern(events: [transientEvent], parameters: [])
            hapticPlayer = try hapticEngine?.makePlayer(with: transientPattern)
            
            // Generate initial breathing pattern & player
            if let initialPattern = generateBreathingHapticPattern(
                inhaleDuration: currentBreathingInhaleDuration,
                hold1Duration: currentBreathingHold1Duration,
                exhaleDuration: currentBreathingExhaleDuration,
                hold2Duration: currentBreathingHold2Duration) {
                
                breathingHapticPlayer = try hapticEngine?.makePlayer(with: initialPattern)
            } else {
                print("ERROR: Failed to create initial breathing haptic pattern.")
            }
            
            hapticsReady = true
            
        } catch {
            print("DIAGNOSTIC: setupHaptics - Error: \(error.localizedDescription)")
            hapticsReady = false
        }
    }
    
    func startHapticEngine() {
        guard hapticsReady, let engine = hapticEngine else { 
            print("DIAGNOSTIC: startHapticEngine - Aborted. Ready:\(hapticsReady), Engine:\(self.hapticEngine != nil).")
            return 
        }
        
        do {
            try engine.start()
        } catch {
            print("DIAGNOSTIC: startHapticEngine - Error: \(error.localizedDescription)")
            hapticsReady = false
        }
    }
    
    func stopHapticEngine() {
        guard let engine = hapticEngine else { return }
        
        engine.stop { error in 
            if let err = error {
                print("Error stopping haptic: \(err.localizedDescription)")
            }
        }
        
        hapticsReady = false
    }
    
    func startBreathingHaptics() {
        guard hapticsReady, let player = breathingHapticPlayer else { return }
        
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("ERROR: Failed to start breathing haptics: \(error.localizedDescription)")
        }
    }
    
    func stopBreathingHaptics() {
        guard hapticsReady, let player = breathingHapticPlayer else { return }
        
        do {
            try player.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("ERROR: Failed to stop breathing haptics: \(error.localizedDescription)")
        }
    }
    
    private func updateBreathingHaptics() {
        guard hapticsReady, let engine = hapticEngine else { return }

        // Removed diagnostic logging for updating breathing pattern
        // Stop the current player
        try? breathingHapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        breathingHapticPlayer = nil // Release old player

        // Generate new pattern with current durations
        guard let newPattern = generateBreathingHapticPattern(
            inhaleDuration: currentBreathingInhaleDuration,
            hold1Duration: currentBreathingHold1Duration,
            exhaleDuration: currentBreathingExhaleDuration,
            hold2Duration: currentBreathingHold2Duration) else {
                
            print("ERROR: Failed to generate new breathing haptic pattern during update.")
            return
        }

        // Create and start a new player
        do {
            breathingHapticPlayer = try engine.makePlayer(with: newPattern)
            // Try starting immediately - might cause slight jump if called mid-cycle
            try? breathingHapticPlayer?.start(atTime: CHHapticTimeImmediate)
            // Removed diagnostic logging for successful haptic player update
        } catch {
            print("ERROR: Failed to create or start new breathing haptic player: \(error.localizedDescription)")
        }

        needsHapticPatternUpdate = false // Reset flag
    }
    
    // MARK: - Audio Engine
    
    private func setupAudio() {
        print("AUDIO: Setting up audio system...")
        
        // Setup AVAudioSourceNode based system
        audioPulser = PreciseAudioPulser()
        audioReady = true
        print("AUDIO: Precise audio system setup complete")
    }
    
    func startAudioEngine() {
        guard audioReady else { return }
        
        if let audioPulser = audioPulser {
            let success = audioPulser.start()
            print("AUDIO: Precise audio engine start \(success ? "succeeded" : "failed")")
            
            // Initialize audio parameters
            updateAudioParameters()
        }
    }
    
    func stopAudioEngine() {
        audioPulser?.stop()
        print("AUDIO: Precise audio engine stopped")
    }
    
    private func updateAudioParameters() {
        if let pulser = audioPulser {
            pulser.updateParameters(
                frequency: currentTargetAudioFrequency,
                amplitude: currentAudioAmplitude,
                squarenessFactor: currentAudioSquareness,
                pulseRate: currentAudioPulseRate
            )
            
            // Debug logs for problematic arousal ranges
            let clampedArousal = 0.5 + (currentTargetAudioFrequency - 440.0) / (1000.0 - 200.0) // Rough estimation
            if clampedArousal >= 0.67 && clampedArousal <= 0.78 {
                print("AUDIO DEBUG: Precise audio params at critical calculated arousal \(String(format: "%.2f", clampedArousal)): Freq=\(String(format: "%.1f", currentTargetAudioFrequency))Hz, Pulse=\(String(format: "%.1f", currentAudioPulseRate))Hz")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    // Parameterized function to generate haptic breathing pattern
    private func generateBreathingHapticPattern(
        inhaleDuration: TimeInterval, 
        hold1Duration: TimeInterval, 
        exhaleDuration: TimeInterval, 
        hold2Duration: TimeInterval) -> CHHapticPattern? {
            
        guard let engine = hapticEngine else { return nil }
        
        var allBreathingEvents: [CHHapticEvent] = []
        var phaseStartTime: TimeInterval = 0.0
        var inhaleEventTimes: [TimeInterval] = []

        // Default haptic parameters - should be made configurable
        let hapticIntensity: Float = 0.8 
        let sharpnessMin: Float = 0.35
        let sharpnessMax: Float = 0.8
        let accelFactor: Double = 0.13

        // Inhale Phase
        var relativeTime: TimeInterval = 0
        var currentDelayFactor: Double = 1.0
        let baseInhaleDelay = inhaleDuration / 23.0
        let sharpnessRangeInhale = sharpnessMax - sharpnessMin
        
        while relativeTime < inhaleDuration - 0.01 {
            let absoluteTime = phaseStartTime + relativeTime
            inhaleEventTimes.append(absoluteTime)
            
            let fraction = relativeTime / inhaleDuration
            let sharpness = sharpnessMax - (sharpnessRangeInhale * Float(fraction))
            
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: hapticIntensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            
            allBreathingEvents.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: absoluteTime
            ))
            
            let delay = baseInhaleDelay / currentDelayFactor
            relativeTime += delay
            currentDelayFactor += accelFactor
        }
        
        let minimumDelay = inhaleEventTimes.count > 1 ? 
            (inhaleEventTimes.last! - inhaleEventTimes[inhaleEventTimes.count-2]) : 0.05
        
        phaseStartTime += inhaleDuration

        // Hold After Inhale Phase
        relativeTime = 0
        
        while relativeTime < hold1Duration - 0.01 {
            let absoluteTime = phaseStartTime + relativeTime
            
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: hapticIntensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpnessMin)
            
            allBreathingEvents.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: absoluteTime
            ))
            
            relativeTime += minimumDelay
        }
        
        phaseStartTime += hold1Duration

        // Exhale Phase
        relativeTime = 0
        let baseExhaleDelay = exhaleDuration / 23.0
        let numSteps = inhaleEventTimes.count
        let maxFactor = 1.0 + accelFactor * Double(numSteps)
        currentDelayFactor = maxFactor
        let sharpnessRangeExhale = sharpnessMax - sharpnessMin
        
        while relativeTime < exhaleDuration - 0.01 {
            let absoluteTime = phaseStartTime + relativeTime
            
            let fraction = relativeTime / exhaleDuration
            let sharpness = sharpnessMin + (sharpnessRangeExhale * Float(fraction))
            
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: hapticIntensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            
            allBreathingEvents.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: absoluteTime
            ))
            
            let delay = baseExhaleDelay / max(0.1, currentDelayFactor)
            relativeTime += delay
            currentDelayFactor -= accelFactor
            
            if currentDelayFactor < 1.0 {
                currentDelayFactor = 1.0
            }
        }
        
        // No Hold2 Events (could add them if needed)

        // Sort events by time and create pattern
        allBreathingEvents.sort { $0.relativeTime < $1.relativeTime }
        
        guard !allBreathingEvents.isEmpty else { return nil }
        
        do {
            let breathingPattern = try CHHapticPattern(events: allBreathingEvents, parameters: [])
            return breathingPattern
        } catch { 
            print("Error creating breathing haptic pattern: \(error.localizedDescription)")
            return nil 
        }
    }
    
    func isEngineRunning() -> Bool {
        return hapticsReady && audioReady && (precisionTimer?.isRunning ?? false)
    }
} 