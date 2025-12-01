import AVFoundation
import Accelerate

class AudioAnalyzer: ObservableObject {
    @Published var audioLevel: Float = 0.0
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    func start() {
        // For macOS 13.0+, the system will prompt for microphone permission
        // when we try to access it. Just setup the engine directly.
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap to get audio data
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }
        
        // Calculate RMS (Root Mean Square) for audio level
        var rms: Float = 0.0
        vDSP_rmsqv(channelDataValueArray, 1, &rms, vDSP_Length(channelDataValueArray.count))
        
        // Normalize and smooth the audio level
        let normalizedLevel = min(rms * 10.0, 1.0)
        
        DispatchQueue.main.async { [weak self] in
            // Smooth transition
            if let currentLevel = self?.audioLevel {
                self?.audioLevel = currentLevel * 0.7 + normalizedLevel * 0.3
            } else {
                self?.audioLevel = normalizedLevel
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

