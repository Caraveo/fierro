import AVFoundation
import Accelerate

class AudioAnalyzer: ObservableObject {
    @Published var audioLevel: Float = 0.0
    @Published var audioFrequency: Float = 0.0 // Dominant frequency (0-1, normalized)
    @Published var audioIntensity: Float = 0.0 // Overall intensity
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var debugCounter = 0
    private var isStarted = false // Prevent multiple starts
    private var fakeAudioTimer: Timer? // Keep reference to fake audio timer
    
    func start() {
        // Prevent multiple starts - only start once
        guard !isStarted else {
            print("⚠️ Audio analyzer already started, skipping duplicate start")
            return
        }
        
        isStarted = true
        print("🎤 Starting audio analyzer...")
        
        // Request microphone permission explicitly before setting up audio engine
        requestMicrophonePermission { [weak self] granted in
            guard let self = self else { return }
            if granted {
                self.setupAudioEngine()
            } else {
                print("❌ Microphone permission denied")
                print("   Please grant microphone access in System Settings > Privacy & Security > Microphone")
                self.startFakeAudio()
            }
        }
    }
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        // Check current authorization status
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            // Already authorized
            completion(true)
        case .notDetermined:
            // Request permission - this will show system prompt
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            // Permission denied or restricted
            print("⚠️ Microphone permission denied or restricted")
            print("   Current status: \(status == .denied ? "denied" : "restricted")")
            print("   Please enable in System Settings > Privacy & Security > Microphone")
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func setupAudioEngine() {
        // Clean up any existing audio engine first (but keep isStarted = true)
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        fakeAudioTimer?.invalidate()
        fakeAudioTimer = nil
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ Failed to create audio engine")
            startFakeAudio()
            return
        }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            print("❌ Failed to get input node")
            startFakeAudio()
            return
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("✅ Audio format: \(recordingFormat)")
        print("   Sample rate: \(recordingFormat.sampleRate)")
        print("   Channel count: \(recordingFormat.channelCount)")
        
        // Install tap to get audio data
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            // Prepare the audio engine before starting
            audioEngine.prepare()
            try audioEngine.start()
            print("✅ Audio engine started successfully - listening for audio input")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
            print("   Error details: \(error.localizedDescription)")
            print("   This might be due to missing microphone permission.")
            print("   Please grant microphone access in System Settings > Privacy & Security > Microphone")
            print("   Falling back to fake audio for testing...")
            // Start fake audio for testing
            startFakeAudio()
        }
    }
    
    private func startFakeAudio() {
        // Stop any existing fake audio timer
        fakeAudioTimer?.invalidate()
        
        print("⚠️ Using fake audio - real microphone not available")
        // Create a timer that simulates audio input for testing
        var time: Float = 0
        fakeAudioTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            time += 0.016
            // Create a pulsing pattern that varies
            let baseLevel: Float = 0.3
            let variation = sin(time * 3.0) * 0.3 + cos(time * 5.0) * 0.2
            let fakeLevel = max(0.1, min(1.0, baseLevel + variation))
            let fakeFreq = (sin(time * 2.0) * 0.5 + 0.5)
            let fakeIntensity = (fakeLevel + fakeFreq) * 0.5
            
            DispatchQueue.main.async {
                self?.audioLevel = fakeLevel
                self?.audioFrequency = fakeFreq
                self?.audioIntensity = fakeIntensity
                // Debug: print every second
                if Int(time) % 1 == 0 && time.truncatingRemainder(dividingBy: 1.0) < 0.1 {
                    print("📊 Fake Audio - Level: \(fakeLevel), Freq: \(fakeFreq), Intensity: \(fakeIntensity)")
                }
            }
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        guard buffer.frameLength > 0 else { return }
        
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        let stride = Int(buffer.stride)
        
        var channelDataValueArray: [Float] = []
        for i in 0..<frameLength {
            if i * stride < frameLength {
                channelDataValueArray.append(channelDataValue[i * stride])
            }
        }
        
        guard !channelDataValueArray.isEmpty else { return }
        
        // Calculate RMS (Root Mean Square) for audio level
        var rms: Float = 0.0
        vDSP_rmsqv(channelDataValueArray, 1, &rms, vDSP_Length(channelDataValueArray.count))
        
        // Calculate frequency characteristics (simple high-frequency detection)
        var highFreqEnergy: Float = 0.0
        var lowFreqEnergy: Float = 0.0
        let frameCount = channelDataValueArray.count
        
        // More sophisticated frequency analysis: detect high vs low frequency content
        // Use FFT-like approach by analyzing different frequency bands
        let midPoint = frameCount / 3
        let highPoint = frameCount * 2 / 3
        
        for i in 0..<min(frameCount, 512) {
            let sample = abs(channelDataValueArray[i])
            if i > highPoint {
                // High frequency band
                highFreqEnergy += sample * 1.5 // Boost high frequencies
            } else if i > midPoint {
                // Mid frequency band
                highFreqEnergy += sample * 0.7
                lowFreqEnergy += sample * 0.3
            } else {
                // Low frequency band
                lowFreqEnergy += sample * 1.2 // Boost low frequencies
            }
        }
        
        let totalFreqEnergy = highFreqEnergy + lowFreqEnergy
        let frequencyRatio = totalFreqEnergy > 0.001 ? highFreqEnergy / totalFreqEnergy : 0.4 // Default to slightly mid-range
        
        // Normalize and smooth the audio level - increased sensitivity for voice
        let normalizedLevel = min(rms * 50.0, 1.0) // Much higher sensitivity for voice
        let normalizedFrequency = min(frequencyRatio * 1.5, 1.0) // Normalize frequency ratio
        
        DispatchQueue.main.async { [weak self] in
            // Smooth transition - very fast response for rapid color transitions
            if let currentLevel = self?.audioLevel {
                self?.audioLevel = currentLevel * 0.2 + normalizedLevel * 0.8 // Very fast response for quick color changes
            } else {
                self?.audioLevel = normalizedLevel
            }
            
            // Much faster frequency response for rapid color transitions
            if let currentFreq = self?.audioFrequency {
                self?.audioFrequency = currentFreq * 0.15 + normalizedFrequency * 0.85 // Very fast response for quick transitions
            } else {
                self?.audioFrequency = normalizedFrequency
            }
            
            // Audio intensity (combination of level and frequency)
            self?.audioIntensity = (normalizedLevel + normalizedFrequency) * 0.5
            
            // Debug: print occasionally
            self?.debugCounter += 1
            if let counter = self?.debugCounter, counter % 100 == 0 {
                print("📊 Real Audio - Level: \(String(format: "%.3f", normalizedLevel)), Freq: \(String(format: "%.3f", normalizedFrequency)), Intensity: \(String(format: "%.3f", self?.audioIntensity ?? 0))")
            }
        }
    }
    
    func stop() {
        isStarted = false
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        fakeAudioTimer?.invalidate()
        fakeAudioTimer = nil
    }
    
    deinit {
        stop()
    }
}

