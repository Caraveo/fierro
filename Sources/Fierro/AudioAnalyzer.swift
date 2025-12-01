import AVFoundation
import Accelerate

class AudioAnalyzer: ObservableObject {
    @Published var audioLevel: Float = 0.0
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var debugCounter = 0
    
    func start() {
        // Try to setup real audio engine first
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("Failed to create audio engine")
            return
        }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            print("Failed to get input node")
            return
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("Audio format: \(recordingFormat)")
        
        // Install tap to get audio data
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            print("Audio engine started successfully")
        } catch {
            print("Failed to start audio engine: \(error)")
            // Start fake audio for testing
            startFakeAudio()
        }
    }
    
    private func startFakeAudio() {
        // Create a timer that simulates audio input for testing
        var time: Float = 0
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            time += 0.016
            // Create a pulsing pattern that varies
            let baseLevel: Float = 0.3
            let variation = sin(time * 3.0) * 0.3 + cos(time * 5.0) * 0.2
            let fakeLevel = max(0.1, min(1.0, baseLevel + variation))
            
            DispatchQueue.main.async {
                self?.audioLevel = fakeLevel
                // Debug: print every second
                if Int(time) % 1 == 0 && time.truncatingRemainder(dividingBy: 1.0) < 0.1 {
                    print("Audio level: \(fakeLevel)")
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
        
        // Normalize and smooth the audio level - increased sensitivity
        let normalizedLevel = min(rms * 30.0, 1.0) // Increased sensitivity even more
        
        DispatchQueue.main.async { [weak self] in
            // Smooth transition
            if let currentLevel = self?.audioLevel {
                self?.audioLevel = currentLevel * 0.5 + normalizedLevel * 0.5 // Even faster response
            } else {
                self?.audioLevel = normalizedLevel
            }
            
            // Debug: print occasionally
            self?.debugCounter += 1
            if let counter = self?.debugCounter, counter % 100 == 0 {
                print("Real audio level: \(normalizedLevel), smoothed: \(self?.audioLevel ?? 0)")
            }
        }
    }
    
    func stop() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
    }
    
    deinit {
        stop()
    }
}

