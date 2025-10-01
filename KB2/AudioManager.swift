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
import AVFoundation
import SpriteKit // For CGFloat if used by helper methods, though aiming for AVFoundation focus.

//====================================================================================================
// MARK: - AUDIO BUFFER CACHE (Moved from GameScene.swift)
//====================================================================================================
class VHAAudioBufferCache {
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]
    private let format: AVAudioFormat
    private let sampleRate: Float
    private let bufferDuration: Float = 0.1
    private let granularity: Float = 1.0
    
    init?(format: AVAudioFormat) {
        guard format.sampleRate > 0 else { return nil }
        self.format = format
        self.sampleRate = Float(format.sampleRate)
    }
    
    func precomputeBuffers(minFrequency: Float, maxFrequency: Float, arousalLevels: [CGFloat]) {
        print("VHAAudioBufferCache: Pre-computing audio buffers...")
        bufferCache.removeAll()
        for arousal in arousalLevels {
            let audioFreqRange = maxFrequency - minFrequency
            let frequency = minFrequency + (audioFreqRange * Float(arousal))
            let roundedFrequency = round(frequency / granularity) * granularity
            let key = cacheKey(frequency: roundedFrequency, arousal: arousal)
            if bufferCache[key] == nil {
                if let buffer = generateBuffer(frequency: roundedFrequency, arousal: arousal) {
                    bufferCache[key] = buffer
                }
            }
        }
        print("VHAAudioBufferCache: Completed pre-computing \(bufferCache.count) audio buffers")
    }
    
    func getBuffer(frequency: Float, arousal: CGFloat) -> AVAudioPCMBuffer? {
        let roundedFrequency = round(frequency / granularity) * granularity
        let key = cacheKey(frequency: roundedFrequency, arousal: arousal)
        if let cachedBuffer = bufferCache[key] {
            return cachedBuffer
        }
        // print("VHAAudioBufferCache: Cache miss for frequency: \(frequency), arousal: \(arousal)")
        if let buffer = generateBuffer(frequency: frequency, arousal: arousal) {
            bufferCache[key] = buffer // Add to cache on miss
            return buffer
        }
        return nil
    }
    
    private func cacheKey(frequency: Float, arousal: CGFloat) -> String {
        return "\(frequency)_\(Int(arousal * 100))"
    }
    
    private func generateBuffer(frequency: Float, arousal: CGFloat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * bufferDuration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        
        let angularFrequency = 2 * .pi * frequency / sampleRate
        let minAmplitude: Float = 0.3
        let maxAmplitude: Float = 0.7
        let amplitudeRange = maxAmplitude - minAmplitude
        let clampedArousal = max(0.0, min(arousal, 1.0))
        let calculatedAmplitude = minAmplitude + (amplitudeRange * Float(clampedArousal))
        let squarenessFactor = Float(clampedArousal)
        
        let angularFreq3 = 3.0 * angularFrequency
        let amplitude3 = (calculatedAmplitude / 3.0) * squarenessFactor
        let angularFreq5 = 5.0 * angularFrequency
        let amplitude5 = (calculatedAmplitude / 5.0) * squarenessFactor
        let angularFreq7 = 7.0 * angularFrequency
        let amplitude7 = (calculatedAmplitude / 7.0) * squarenessFactor
        
        for frame in 0..<Int(frameCount) {
            let time = Float(frame)
            let fundamentalValue = sin(time * angularFrequency) * calculatedAmplitude
            let harmonic3Value = sin(time * angularFreq3) * amplitude3
            let harmonic5Value = sin(time * angularFreq5) * amplitude5
            let harmonic7Value = sin(time * angularFreq7) * amplitude7
            channelData[frame] = fundamentalValue + harmonic3Value + harmonic5Value + harmonic7Value
        }
        return buffer
    }
    
    func clearCache() {
        bufferCache.removeAll()
    }
}

//====================================================================================================
// MARK: - AUDIO MANAGER
//====================================================================================================
class AudioManager {
    private let gameConfiguration: GameConfiguration
    
    private var customAudioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioBuffer: AVAudioPCMBuffer?
    private var audioFormat: AVAudioFormat?
    private var audioReady: Bool = false
    private var currentBufferFrequency: Float?
    
    private var audioBufferCache: VHAAudioBufferCache?
    private var audioPulser: PreciseAudioPulser?
    private var usingPreciseAudio: Bool
    
    // Visual pulse duration tracking for audio pulse width
    private var lastVisualPulseDuration: TimeInterval = 0.0
    
    // Diagnostic counters
    private var audioTickCounter = 0

    init(gameConfiguration: GameConfiguration, initialArousal: CGFloat, initialTimerFrequency: Double, initialTargetAudioFrequency: Float) {
        self.gameConfiguration = gameConfiguration
        // Assuming GameConfiguration will have a 'usePreciseAudio' flag
        self.usingPreciseAudio = gameConfiguration.usePreciseAudio 
        
        print("AudioManager: Initializing...")
        setupAudio(initialArousal: initialArousal, initialTimerFrequency: initialTimerFrequency, initialTargetAudioFrequency: initialTargetAudioFrequency)
        activateAudioSession()
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            print("AudioManager: Audio session activated.")
        } catch {
            print("AudioManager: Failed to set up audio session: \(error.localizedDescription)")
        }
    }

    private func setupAudio(initialArousal: CGFloat, initialTimerFrequency: Double, initialTargetAudioFrequency: Float) {
        print("AudioManager: Setting up audio with usingPreciseAudio=\(usingPreciseAudio)")
        
        if usingPreciseAudio {
            // Create PreciseAudioPulser with external sync mode
            audioPulser = PreciseAudioPulser(useExternalSync: true) 
            if let pulser = audioPulser {
                print("AudioManager: PreciseAudioPulser created successfully in external sync mode.")
                
                // Calculate visual pulse duration for audio pulse width matching
                lastVisualPulseDuration = 1.0 / initialTimerFrequency * gameConfiguration.visualPulseOnDurationRatio
                pulser.setPulseDuration(lastVisualPulseDuration)
                
                updatePulserParameters(pulser: pulser, arousal: initialArousal, timerFrequency: initialTimerFrequency, targetAudioFrequency: initialTargetAudioFrequency)
                // pulser.start() is called by self.startEngine()
                audioReady = true 
                print("AudioManager: PreciseAudioPulser initialized.")
            } else {
                print("AudioManager ERROR: Failed to create PreciseAudioPulser, falling back to traditional method.")
                usingPreciseAudio = false 
            }
        }
        
        if !usingPreciseAudio {
            print("AudioManager: Setting up traditional audio.")
            customAudioEngine = AVAudioEngine()
            audioPlayerNode = AVAudioPlayerNode()
            guard let engine = customAudioEngine, let playerNode = audioPlayerNode else {
                print("AudioManager ERROR: Could not create traditional audio engine/node.")
                audioReady = false; return
            }
            
            engine.attach(playerNode)
            audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)
            guard let format = audioFormat else {
                print("AudioManager ERROR: Could not create audio format.")
                audioReady = false; return
            }

            self.audioBufferCache = VHAAudioBufferCache(format: format)
            if let cache = self.audioBufferCache {
                var arousalLevels: [CGFloat] = []
                for level in stride(from: 0.0, through: 1.0, by: 0.01) { arousalLevels.append(level) }
                for level in stride(from: 0.67, through: 0.78, by: 0.005) { arousalLevels.append(level) }
                arousalLevels = Array(Set(arousalLevels)).sorted()
                
                cache.precomputeBuffers(
                    minFrequency: gameConfiguration.minAudioFrequency,
                    maxFrequency: gameConfiguration.maxAudioFrequency,
                    arousalLevels: arousalLevels
                )
                self.audioBuffer = cache.getBuffer(frequency: initialTargetAudioFrequency, arousal: initialArousal)
                self.currentBufferFrequency = initialTargetAudioFrequency
            } else {
                print("AudioManager ERROR: Failed to initialize audio buffer cache.")
                self.audioBuffer = generateAudioBuffer(frequency: initialTargetAudioFrequency, arousalLevel: initialArousal)
                self.currentBufferFrequency = initialTargetAudioFrequency
            }
            
            guard self.audioBuffer != nil else {
                print("AudioManager ERROR: Initial audio buffer generation failed for traditional audio.")
                audioReady = false; return
            }

            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            do {
                try engine.prepare()
                audioReady = true
                print("AudioManager: Traditional audio setup complete and ready.")
            } catch {
                print("AudioManager ERROR: Traditional audio engine prepare failed: \(error.localizedDescription)")
                audioReady = false
            }
        }
    }

    private func updatePulserParameters(pulser: PreciseAudioPulser, arousal: CGFloat, timerFrequency: Double, targetAudioFrequency: Float) {
        let minAmplitude: Float = gameConfiguration.audioMinAmplitude // Assuming these are in GameConfiguration
        let maxAmplitude: Float = gameConfiguration.audioMaxAmplitude
        let amplitudeRange = maxAmplitude - minAmplitude
        let clampedArousal = max(0.0, min(arousal, 1.0))
        let calculatedAmplitude = minAmplitude + (amplitudeRange * Float(clampedArousal))
        let squareness = Float(clampedArousal)
        
        // Calculate visual pulse duration for audio pulse width matching
        lastVisualPulseDuration = 1.0 / timerFrequency * gameConfiguration.visualPulseOnDurationRatio
        pulser.setPulseDuration(lastVisualPulseDuration)
        
        // In external sync mode, we don't need to set the pulseRate as we'll manually trigger pulses
        // But we'll keep it as a fallback in case we switch modes
        let pulseRate = timerFrequency * gameConfiguration.audioPulseRateFactor 

        pulser.updateParameters(
            frequency: targetAudioFrequency,
            amplitude: calculatedAmplitude,
            squarenessFactor: squareness,
            pulseRate: pulseRate,
            lowPassCutoff: gameConfiguration.audioLowPassCutoff
        )
    }

    private func generateAudioBuffer(frequency: Float, arousalLevel: CGFloat) -> AVAudioPCMBuffer? {
        guard let format = self.audioFormat, format.sampleRate > 0 else {
            print("AudioManager ERROR: generateAudioBuffer - audioFormat not set or invalid.")
            return nil
        }
        let sampleRate = Float(format.sampleRate)
        let duration: Float = 0.1 
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let angularFrequency = 2 * .pi * frequency / sampleRate
        let minAmplitude: Float = gameConfiguration.audioMinAmplitude
        let maxAmplitude: Float = gameConfiguration.audioMaxAmplitude
        let amplitudeRange = maxAmplitude - minAmplitude
        let clampedArousal = max(0.0, min(arousalLevel, 1.0))
        let calculatedAmplitude = minAmplitude + (amplitudeRange * Float(clampedArousal))
        let squarenessFactor = Float(clampedArousal)

        let angularFreq3 = 3.0 * angularFrequency; let amplitude3 = (calculatedAmplitude / 3.0) * squarenessFactor
        let angularFreq5 = 5.0 * angularFrequency; let amplitude5 = (calculatedAmplitude / 5.0) * squarenessFactor
        let angularFreq7 = 7.0 * angularFrequency; let amplitude7 = (calculatedAmplitude / 7.0) * squarenessFactor

        for frame in 0..<Int(frameCount) {
            let time = Float(frame)
            let fundamentalValue = sin(time * angularFrequency) * calculatedAmplitude
            let harmonic3Value = sin(time * angularFreq3) * amplitude3
            let harmonic5Value = sin(time * angularFreq5) * amplitude5
            let harmonic7Value = sin(time * angularFreq7) * amplitude7
            channelData[frame] = fundamentalValue + harmonic3Value + harmonic5Value + harmonic7Value
        }
        return buffer
    }

    func startEngine() {
        startEngine(withFadeIn: false)
    }
    
    func startEngine(withFadeIn: Bool) {
        if !audioReady {
            print("AudioManager: StartEngine called but audio not ready. Engine not starting.")
            return
        }

        if usingPreciseAudio {
            if withFadeIn {
                let fadeInDuration = gameConfiguration.audioFadeInDuration
                if let startResult = audioPulser?.start(withFadeIn: true, fadeInDuration: fadeInDuration), !startResult {
                    print("AudioManager WARNING: PreciseAudioPulser failed to start with fade-in")
                }
            } else {
                if let startResult = audioPulser?.start(), !startResult {
                    print("AudioManager WARNING: PreciseAudioPulser failed to start")
                }
            }
        } else {
            // Traditional audio doesn't support fade-in currently
            guard let engine = customAudioEngine, audioReady else {
                print("AudioManager: StartEngine (traditional) - Aborted. Engine nil or not ready.")
                return
            }
            if !engine.isRunning {
                do {
                    try engine.start()
                    print("AudioManager: Traditional audio engine started.")
                } catch {
                    print("AudioManager ERROR: Traditional audio engine start failed: \(error.localizedDescription)")
                }
            }
        }
        
        let fadeMsg = withFadeIn ? " with fade-in" : ""
        print("AudioManager: Engine start process completed (usingPreciseAudio: \(usingPreciseAudio))\(fadeMsg).")
    }

    func stopEngine() {
        if usingPreciseAudio {
            audioPulser?.stop()
        } else {
            customAudioEngine?.stop()
        }
        print("AudioManager: Engine stop process completed (usingPreciseAudio: \(usingPreciseAudio)).")
    }
    
    func cleanup() {
        print("AudioManager: Cleaning up...")
        stopEngine()
        audioBufferCache?.clearCache()
        audioBufferCache = nil
        audioPulser = nil
        audioPlayerNode = nil // Ensure AVAudioPlayerNode is released
        customAudioEngine = nil // Ensure AVAudioEngine is released
        audioBuffer = nil
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("AudioManager: Audio session deactivated.")
        } catch {
            print("AudioManager ERROR: Deactivating audio session: \(error.localizedDescription)")
        }
        audioReady = false
        print("AudioManager: Cleanup finished.")
    }

    func updateAudioParameters(newArousal: CGFloat, newTimerFrequency: Double, newTargetAudioFrequency: Float) {
        if usingPreciseAudio {
            if let pulser = audioPulser {
                updatePulserParameters(pulser: pulser, arousal: newArousal, timerFrequency: newTimerFrequency, targetAudioFrequency: newTargetAudioFrequency)
            }
        } else {
            // For traditional audio, new buffers will be fetched/generated in handleAudioTick based on these updated parameters.
            // We might want to trigger a pre-fetch here for the newTargetAudioFrequency if it's significantly different.
            if let cache = self.audioBufferCache, abs((currentBufferFrequency ?? 0) - newTargetAudioFrequency) > 1.0 {
                 DispatchQueue.global(qos: .utility).async { // Use utility for potentially longer task
                    print("AudioManager: Pre-fetching buffer for new target frequency \(newTargetAudioFrequency)")
                    _ = cache.getBuffer(frequency: newTargetAudioFrequency, arousal: newArousal)
                }
            }
        }
    }

    func handleAudioTick(visualTickTime: CFTimeInterval, currentArousal: CGFloat, currentTargetAudioFreq: Float, audioOffset: TimeInterval, sceneCurrentState: GameState) {
        // Check if audio is globally enabled by the user
        guard UserSettings.isAudioEnabled else { return }
        
        // Only proceed if in a state that plays rhythmic audio
        guard (sceneCurrentState == .tracking || sceneCurrentState == .identifying || sceneCurrentState == .breathing) else { return }
        
        if usingPreciseAudio {
            guard let pulser = audioPulser, pulser.isRunning else { 
                print("AudioManager: handleAudioTick - Pulser not ready or running")
                return 
            }
            
            // Calculate the time when the audio pulse should start
            let audioStartTime = visualTickTime + audioOffset
            
            // Periodically log the timing details (only in debug builds)
            audioTickCounter += 1
            #if DEBUG
            if audioTickCounter % 240 == 0 {
                // Capture counter value to avoid self reference in closure
                let currentTickCount = audioTickCounter
                // Use async dispatch to avoid blocking the calling thread
                DispatchQueue.global(qos: .utility).async {
                    let currentTime = CACurrentMediaTime()
                    print("AudioManager: Audio tick #\(currentTickCount) - now: \(String(format: "%.3f", currentTime)), " +
                          "visualTick: \(String(format: "%.3f", visualTickTime)), " +
                          "audioStart: \(String(format: "%.3f", audioStartTime))")
                }
            }
            #endif
            
            // Trigger pulse at the exact scheduled time
            pulser.triggerPulse(at: audioStartTime)
            return
        }
        
        // Traditional audio handling logic (unchanged)
        guard audioReady, let engine = customAudioEngine, let playerNode = audioPlayerNode else { return }
        guard engine.isRunning else { return }

        let audioStartTime = visualTickTime + audioOffset 
        let currentTime = CACurrentMediaTime()
        let delayUntilStartTime = max(0, audioStartTime - currentTime)

        DispatchQueue.main.asyncAfter(deadline: .now() + delayUntilStartTime) { [weak self] in
            guard let self = self else { return }
            // Re-check state and readiness as it might have changed during async delay
            guard self.audioReady,
                  (sceneCurrentState == .tracking || sceneCurrentState == .identifying || sceneCurrentState == .breathing),
                  let currentEngine = self.customAudioEngine, currentEngine.isRunning,
                  let _ = self.audioPlayerNode else { return }

            var bufferToPlay: AVAudioPCMBuffer?

            if let cache = self.audioBufferCache {
                bufferToPlay = cache.getBuffer(frequency: currentTargetAudioFreq, arousal: currentArousal)
                // Update currentBufferFrequency if the target frequency has changed significantly
                if bufferToPlay != nil && (self.currentBufferFrequency == nil || abs(self.currentBufferFrequency! - currentTargetAudioFreq) > 1.0) {
                    self.currentBufferFrequency = currentTargetAudioFreq
                }
            } else { // Fallback if cache is nil (should not happen if setup was correct)
                if self.currentBufferFrequency == nil || abs(self.currentBufferFrequency! - currentTargetAudioFreq) > 1.0 {
                    self.audioBuffer = self.generateAudioBuffer(frequency: currentTargetAudioFreq, arousalLevel: currentArousal)
                    self.currentBufferFrequency = currentTargetAudioFreq
                }
                bufferToPlay = self.audioBuffer
            }
            
            guard let finalBufferToPlay = bufferToPlay else {
                return
            }
            
            self.audioPlayerNode?.scheduleBuffer(finalBufferToPlay, at: nil, options: .interrupts) { /* Completion handler */ }
            if !(self.audioPlayerNode?.isPlaying ?? false) { self.audioPlayerNode?.play() }
        }
    }
}

// Assume PreciseAudioPulser is defined elsewhere or will be.
// For now, a placeholder if it's not in another file yet for self-containment of this step:
/*
class PreciseAudioPulser {
    func updateParameters(frequency: Float, amplitude: Float, squarenessFactor: Float, pulseRate: Double) {}
    func start() {}
    func stop() {}
    init() {}
}
*/
// GameConfiguration placeholder for required audio properties
/*
extension GameConfiguration {
    var usePreciseAudio: Bool { return true } // Example
    var minAudioFrequency: Float { return 100.0 }
    var maxAudioFrequency: Float { return 600.0 }
    var audioMinAmplitude: Float { return 0.3 }
    var audioMaxAmplitude: Float { return 0.7 }
    var audioPulseRateFactor: Double { return 0.8 }
}
*/
