// KB2/PreciseAudioPulser.swift
// Created: [Current Date]
// Role: Provides sample-accurate audio synthesis with precise isochronic pulsing capabilities.

import AVFoundation
import CoreAudio

class PreciseAudioPulser {
    // MARK: - Properties
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var mainMixer: AVAudioMixerNode?
    
    // Audio parameters
    private(set) var frequency: Float = 440.0
    private(set) var amplitude: Float = 0.5
    private(set) var squarenessFactor: Float = 0.5
    private(set) var pulseRate: Double = 5.0
    private(set) var isRunning: Bool = false
    
    // Sample tracking
    private var currentPhase: Float = 0.0
    private var sampleRate: Float = 44100.0
    private var currentTime: Double = 0.0
    private var lastPulseTime: Double = 0.0
    private var pulseDuration: Double = 0.1
    private var channelCount: AVAudioChannelCount = 2
    
    // Sync Mode Properties
    private var syncMode: Bool = true // true = external sync, false = internal timing
    private var pendingPulse: Bool = false
    private var pulseStartTime: Double = 0.0
    private var pulseEndTime: Double = 0.0
    private var baseTime: CFTimeInterval = 0.0
    private var debugPulseCounter: Int = 0
    
    // ADDED: Anti-jitter enhancements
    private var pulseEnvelopeValue: Float = 0.0 // Current envelope value for smooth transitions
    private var attackTime: Float = 0.005  // 5ms attack
    private var releaseTime: Float = 0.010 // 10ms release
    private var pulseQueue: [(startTime: Double, endTime: Double)] = [] // Queue for upcoming pulses
    private var maxQueueLength = 4 // Maximum number of queued pulses to prevent memory issues
    private var lastRenderTime: Double = 0.0
    
    // Thread safety - use a concurrent queue instead of a lock for better performance
    private let audioQueue = DispatchQueue(label: "com.kalibrate.AudioQueue", qos: .userInteractive, attributes: .concurrent)
    
    // Audio session interruption handling
    private var audioSessionInterruptionObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption: Bool = false
    
    // MARK: - Initialization
    init(useExternalSync: Bool = true) {
        self.syncMode = useExternalSync
        self.baseTime = CACurrentMediaTime()
        
        // Set up audio engine with high quality settings
        let engine = AVAudioEngine()
        self.audioEngine = engine
        self.mainMixer = engine.mainMixerNode
        
        // Optimize mixer settings
        engine.mainMixerNode.outputVolume = 1.0
        
        // We can't modify the output format directly, so we'll just set our desired channel count
        // for the source node when we create it
        
        // Calculate pulse duration for 50% duty cycle based on initial pulse rate
        pulseDuration = min(0.1, 0.5 / pulseRate)
        
        // Create source node with optimized render block
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: channelCount)
        
        sourceNode = AVAudioSourceNode { [weak self] _, timeStamp, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let now = CACurrentMediaTime()
            
            // Capture current parameters to avoid lock during sample generation
            let (currentFrequency, currentAmplitude, currentSquareness, 
                 isSyncMode, currentPulses, currentAttackTime, 
                 currentReleaseTime) = self.audioQueue.sync { () -> (Float, Float, Float, Bool, [(startTime: Double, endTime: Double)], Float, Float) in
                
                // Clean up expired pulses from the queue
                self.pulseQueue = self.pulseQueue.filter { $0.endTime > now }
                
                return (
                    self.frequency,
                    self.amplitude,
                    self.squarenessFactor,
                    self.syncMode,
                    self.pulseQueue, // Get a copy of the current pulse queue
                    self.attackTime,
                    self.releaseTime
                )
            }
            
            // Calculate actual frame timing information
            let outputPresentationTimeStamp = timeStamp.pointee.mSampleTime
            let outputSampleTime = Double(outputPresentationTimeStamp)
            let outputTime = outputSampleTime / Double(self.sampleRate)
            
            // Track buffer timing for diagnostics
            self.lastRenderTime = outputTime
            
            // Calculate samples with minimal locking
            for frame in 0..<Int(frameCount) {
                let frameSampleTime = outputSampleTime + Double(frame)
                let frameTime = frameSampleTime / Double(self.sampleRate)
                
                // Determine pulseEnvelope value from pulse queue
                var targetEnvelope: Float = 0.0
                if isSyncMode {
                    // Check if any pulse is active at this exact frame time
                    let frameAbsoluteTime = now + (frameTime - outputTime)
                    for pulse in currentPulses {
                        if frameAbsoluteTime >= pulse.startTime && frameAbsoluteTime < pulse.endTime {
                            targetEnvelope = 1.0
                            break
                        }
                    }
                } else {
                    // Original internal timing mode
                    let pulsePeriod = 1.0 / self.pulseRate
                    let timeSinceLastPulse = frameTime - self.lastPulseTime
                    
                    // Check if we need to start a new pulse
                    if timeSinceLastPulse >= pulsePeriod {
                        self.lastPulseTime = frameTime - (timeSinceLastPulse.truncatingRemainder(dividingBy: pulsePeriod))
                    }
                    
                    // Calculate envelope
                    if timeSinceLastPulse < self.pulseDuration {
                        targetEnvelope = 1.0
                    }
                }
                
                // Apply attack/release for smoother transitions (anti-click)
                if targetEnvelope > self.pulseEnvelopeValue {
                    // Attack phase - ramp up
                    self.pulseEnvelopeValue += 1.0 / (currentAttackTime * self.sampleRate)
                    if self.pulseEnvelopeValue > targetEnvelope {
                        self.pulseEnvelopeValue = targetEnvelope
                    }
                } else if targetEnvelope < self.pulseEnvelopeValue {
                    // Release phase - ramp down
                    self.pulseEnvelopeValue -= 1.0 / (currentReleaseTime * self.sampleRate)
                    if self.pulseEnvelopeValue < 0 {
                        self.pulseEnvelopeValue = 0
                    }
                }
                
                // Generate wave
                let phaseIncrement = currentFrequency / self.sampleRate
                self.currentPhase += phaseIncrement
                if self.currentPhase > 1.0 {
                    self.currentPhase -= 1.0
                }
                
                // Generate basic sine wave sample
                var sample = sin(2.0 * Float.pi * self.currentPhase)
                
                // Apply "squareness" factor (harmonic richness)
                if currentSquareness > 0 {
                    sample = tanh(sample * (1.0 + currentSquareness * 3.0))
                }
                
                // Apply amplitude with envelope for clicks prevention
                let finalSample = sample * currentAmplitude * self.pulseEnvelopeValue
                
                // Write to all channels
                for buffer in ablPointer {
                    let bufferPointer = UnsafeMutableBufferPointer<Float>(
                        start: buffer.mData?.assumingMemoryBound(to: Float.self),
                        count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    )
                    bufferPointer[frame] = finalSample
                }
            }
            
            return noErr
        }
        
        // Connect source node to mixer
        if let sourceNode = sourceNode, let format = format {
            engine.attach(sourceNode)
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
            
            // Save sample rate from current format
            sampleRate = Float(format.sampleRate)
        }
    }
    
    // MARK: - Control Methods
    func start() -> Bool {
        guard !isRunning, let engine = audioEngine else { return false }
        
        do {
            // Reset timing state
            currentTime = 0.0
            lastPulseTime = 0.0
            currentPhase = 0.0
            baseTime = CACurrentMediaTime()
            debugPulseCounter = 0
            pulseEnvelopeValue = 0.0
            pulseQueue.removeAll()
            
            // Optimize audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.005) // 5ms buffer for lower latency
            try AVAudioSession.sharedInstance().setActive(true)
            
            try engine.start()
            isRunning = true
            
            // Set up audio session interruption handling for resilience
            setupAudioSessionObservers()
            
            print("PreciseAudioPulser: Started successfully in \(syncMode ? "external sync" : "internal timing") mode")
            return true
        } catch {
            print("ERROR: Failed to start PreciseAudioPulser: \(error.localizedDescription)")
            return false
        }
    }
    
    func stop() {
        guard isRunning, let engine = audioEngine else { return }
        
        engine.stop()
        isRunning = false
        
        // Remove audio session observers
        removeAudioSessionObservers()
        
        // Clean up audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("ERROR: Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - External Sync Method
    
    /// Trigger a pulse at the specified time
    /// - Parameter scheduledTime: The absolute time when the pulse should start
    func triggerPulse(at scheduledTime: CFTimeInterval) {
        guard syncMode, isRunning else { return }
        
        // Periodically log that pulses are being triggered
        debugPulseCounter += 1
        if debugPulseCounter % 60 == 0 {
            print("PreciseAudioPulser: Triggered pulse #\(debugPulseCounter) at \(String(format: "%.3f", scheduledTime)), queue: \(pulseQueue.count)")
        }
        
        // Safe thread access via dispatch queue
        audioQueue.async(flags: .barrier) {
            // Calculate exact end time
            let endTime = scheduledTime + self.pulseDuration
            
            // Add the pulse to our queue for precise timing
            self.pulseQueue.append((startTime: scheduledTime, endTime: endTime))
            
            // Limit queue size
            if self.pulseQueue.count > self.maxQueueLength {
                self.pulseQueue.removeFirst()
            }
        }
    }
    
    // MARK: - Parameter Setting Methods
    func setFrequency(_ newFrequency: Float) {
        audioQueue.async(flags: .barrier) {
            self.frequency = max(20.0, min(newFrequency, 20000.0))
        }
    }
    
    func setAmplitude(_ newAmplitude: Float) {
        audioQueue.async(flags: .barrier) {
            self.amplitude = max(0.0, min(newAmplitude, 1.0))
        }
    }
    
    func setSquarenessFactor(_ newFactor: Float) {
        audioQueue.async(flags: .barrier) {
            self.squarenessFactor = max(0.0, min(newFactor, 1.0))
        }
    }
    
    func setPulseRate(_ newRate: Double) {
        audioQueue.async(flags: .barrier) {
            self.pulseRate = max(0.1, min(newRate, 20.0))
            // Update pulse duration to maintain 50% duty cycle or use fixed duration
            self.pulseDuration = min(0.1, 0.5 / self.pulseRate)
        }
    }
    
    func setSyncMode(_ externalSync: Bool) {
        audioQueue.async(flags: .barrier) {
            self.syncMode = externalSync
        }
    }
    
    func setPulseDuration(_ duration: Double) {
        audioQueue.async(flags: .barrier) {
            self.pulseDuration = max(0.01, min(duration, 0.5)) // Between 10ms and 500ms
            
            // Adjust attack/release times based on pulse duration to prevent overlap
            let maxTransitionTime = Float(self.pulseDuration * 0.2) // 20% of pulse for transitions
            self.attackTime = min(0.01, maxTransitionTime * 0.3) // 30% of transition for attack
            self.releaseTime = min(0.02, maxTransitionTime * 0.7) // 70% of transition for release
        }
    }
    
    // Update all parameters at once to avoid multiple queue operations
    func updateParameters(frequency: Float, amplitude: Float, squarenessFactor: Float, pulseRate: Double) {
        audioQueue.async(flags: .barrier) {
            self.frequency = max(20.0, min(frequency, 20000.0))
            self.amplitude = max(0.0, min(amplitude, 1.0))
            self.squarenessFactor = max(0.0, min(squarenessFactor, 1.0))
            self.pulseRate = max(0.1, min(pulseRate, 20.0))
            self.pulseDuration = min(0.1, 0.5 / self.pulseRate)
            
            // Update envelope parameters
            let maxTransitionTime = Float(self.pulseDuration * 0.2)
            self.attackTime = min(0.01, maxTransitionTime * 0.3)
            self.releaseTime = min(0.02, maxTransitionTime * 0.7)
        }
    }
    
    // MARK: - Helper Methods
    func updateFrequency(_ newFrequency: Float) {
        setFrequency(newFrequency)
    }
    
    func updateAmplitude(_ newAmplitude: Float) {
        setAmplitude(newAmplitude)
    }
    
    func updateSquarenessFactor(_ newFactor: Float) {
        setSquarenessFactor(newFactor)
    }
    
    func updatePulseFrequency(_ newRate: Double) {
        setPulseRate(newRate)
    }
    
    // MARK: - Audio Session Interruption Handling
    
    /// Set up audio session interruption observers for resilient audio
    private func setupAudioSessionObservers() {
        // Remove existing observer if any
        if let observer = audioSessionInterruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        audioSessionInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioSessionInterruption(notification)
        }
    }
    
    /// Handle audio session interruption events
    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("PreciseAudioPulser: Audio session interrupted")
            wasPlayingBeforeInterruption = isRunning
            if isRunning {
                // Audio engine will be stopped automatically by the system
                isRunning = false
            }
            
        case .ended:
            print("PreciseAudioPulser: Audio session interruption ended")
            if wasPlayingBeforeInterruption {
                // Attempt to restart audio after interruption
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.recoverFromInterruption()
                }
            }
            
        @unknown default:
            print("PreciseAudioPulser: Unknown audio session interruption type")
        }
    }
    
    /// Attempt to recover audio after interruption
    private func recoverFromInterruption() {
        guard !isRunning, let engine = audioEngine else { return }
        
        print("PreciseAudioPulser: Attempting audio recovery...")
        
        do {
            // Reactivate audio session
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Restart engine
            try engine.start()
            isRunning = true
            
            // Reset timing state
            baseTime = CACurrentMediaTime()
            pulseEnvelopeValue = 0.0
            pulseQueue.removeAll()
            
            print("PreciseAudioPulser: Audio recovery successful")
        } catch {
            print("PreciseAudioPulser: Audio recovery failed: \(error.localizedDescription)")
            // Try again in a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.recoverFromInterruption()
            }
        }
    }
    
    /// Clean up audio session observers
    private func removeAudioSessionObservers() {
        if let observer = audioSessionInterruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            audioSessionInterruptionObserver = nil
        }
    }
    
    deinit {
        removeAudioSessionObservers()
    }
}
