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
    
    // Thread safety
    private let parameterLock = NSLock()
    
    // MARK: - Initialization
    init() {
        let engine = AVAudioEngine()
        self.audioEngine = engine
        self.mainMixer = engine.mainMixerNode
        
        // Calculate pulse duration for 50% duty cycle based on initial pulse rate
        pulseDuration = min(0.1, 0.5 / pulseRate) // Use minimum of 100ms or half the pulse period
        
        // Create source node with render block
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: channelCount)
        
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            // Lock parameters during rendering to prevent changes mid-buffer
            self.parameterLock.lock()
            let currentFrequency = self.frequency
            let currentAmplitude = self.amplitude
            let currentSquareness = self.squarenessFactor
            let currentPulseRate = self.pulseRate
            let currentPulseDuration = self.pulseDuration
            self.parameterLock.unlock()
            
            // Calculate samples
            for frame in 0..<Int(frameCount) {
                // Update time tracking (crucial for pulse timing)
                let sampleDuration = 1.0 / Double(self.sampleRate)
                self.currentTime += sampleDuration
                
                // Calculate pulse envelope (0.0-1.0)
                let pulseEnvelope: Float
                if currentPulseRate > 0.01 {
                    let pulsePeriod = 1.0 / currentPulseRate
                    let timeSinceLastPulse = self.currentTime - self.lastPulseTime
                    
                    // Check if we need to start a new pulse
                    if timeSinceLastPulse >= pulsePeriod {
                        self.lastPulseTime = self.currentTime
                    }
                    
                    // Calculate envelope (1.0 during pulse, 0.0 between pulses)
                    if timeSinceLastPulse < currentPulseDuration {
                        pulseEnvelope = 1.0
                    } else {
                        pulseEnvelope = 0.0
                    }
                } else {
                    // No pulsing, continuous tone
                    pulseEnvelope = 1.0
                }
                
                // Calculate the sine wave
                let phaseIncrement = currentFrequency / self.sampleRate
                self.currentPhase += phaseIncrement
                if self.currentPhase > 1.0 {
                    self.currentPhase -= 1.0
                }
                
                // Generate basic sine wave sample
                var sample = sin(2.0 * Float.pi * self.currentPhase)
                
                // Apply "squareness" factor (used for harmonic richness at higher arousal)
                if currentSquareness > 0 {
                    // Simple wave shaping to make the sine more "square-like"
                    // The higher the squareness factor, the more the wave gets "squared"
                    sample = tanh(sample * (1.0 + currentSquareness * 3.0)) // Soft clipping
                }
                
                // Apply amplitude with soft attack/decay for clicks prevention
                let finalSample = sample * currentAmplitude * pulseEnvelope
                
                // Copy the same value to all channels
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
            
            // Set up audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            try engine.start()
            isRunning = true
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
        
        // Clean up audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("ERROR: Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Parameter Setting Methods
    func setFrequency(_ newFrequency: Float) {
        parameterLock.lock()
        frequency = max(20.0, min(newFrequency, 20000.0))
        parameterLock.unlock()
    }
    
    func setAmplitude(_ newAmplitude: Float) {
        parameterLock.lock()
        amplitude = max(0.0, min(newAmplitude, 1.0))
        parameterLock.unlock()
    }
    
    func setSquarenessFactor(_ newFactor: Float) {
        parameterLock.lock()
        squarenessFactor = max(0.0, min(newFactor, 1.0))
        parameterLock.unlock()
    }
    
    func setPulseRate(_ newRate: Double) {
        parameterLock.lock()
        pulseRate = max(0.1, min(newRate, 20.0))
        // Update pulse duration to maintain 50% duty cycle or use fixed duration
        pulseDuration = min(0.1, 0.5 / pulseRate) // Use minimum of 100ms or half the pulse period
        parameterLock.unlock()
    }
    
    // Update all parameters at once to avoid multiple lock acquisitions
    func updateParameters(frequency: Float, amplitude: Float, squarenessFactor: Float, pulseRate: Double) {
        parameterLock.lock()
        self.frequency = max(20.0, min(frequency, 20000.0))
        self.amplitude = max(0.0, min(amplitude, 1.0))
        self.squarenessFactor = max(0.0, min(squarenessFactor, 1.0))
        self.pulseRate = max(0.1, min(pulseRate, 20.0))
        self.pulseDuration = min(0.1, 0.5 / pulseRate)
        parameterLock.unlock()
    }
    
    // MARK: - Methods to Fix Compilation Errors
    
    // This method updates the audio frequency
    func updateFrequency(_ newFrequency: Float) {
        setFrequency(newFrequency)
    }
    
    // This method updates the amplitude
    func updateAmplitude(_ newAmplitude: Float) {
        setAmplitude(newAmplitude)
    }
    
    // This method updates the squareness factor for timbre variation
    func updateSquarenessFactor(_ newFactor: Float) {
        setSquarenessFactor(newFactor)
    }
    
    // This method updates the pulse frequency
    func updatePulseFrequency(_ newRate: Double) {
        setPulseRate(newRate)
    }
} 