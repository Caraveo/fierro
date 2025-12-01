import AVFoundation

class SoundManager {
    static let shared = SoundManager()
    
    private var startPlayer: AVAudioPlayer?
    private var touchPlayer: AVAudioPlayer?
    private var beepPlayer: AVAudioPlayer?
    
    private init() {
        setupAudioSession()
        loadSounds()
    }
    
    private func setupAudioSession() {
        // AVAudioSession is not available on macOS, skip setup
    }
    
    private func loadSounds() {
        // Load from bundle (SPM resources)
        let bundle = Bundle.main
        
        // For SPM executables, resources are in Fierro_Fierro.bundle
        // Try main bundle first
        if let startURL = bundle.url(forResource: "start", withExtension: "wav") {
            loadStartSound(from: startURL)
        }
        
        if let touchURL = bundle.url(forResource: "touch", withExtension: "wav") {
            loadTouchSound(from: touchURL)
        }
        
        if let beepURL = bundle.url(forResource: "beep", withExtension: "wav") {
            loadBeepSound(from: beepURL)
        }
        
        // Try to find the bundle directory
        let executablePath = bundle.executablePath ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        let bundlePath = executableDir + "/Fierro_Fierro.bundle"
        
        // Try loading from the SPM bundle
        if FileManager.default.fileExists(atPath: bundlePath) {
            let startPath = bundlePath + "/start.wav"
            let touchPath = bundlePath + "/touch.wav"
            let beepPath = bundlePath + "/beep.wav"
            
            if FileManager.default.fileExists(atPath: startPath) {
                loadStartSound(from: URL(fileURLWithPath: startPath))
            }
            
            if FileManager.default.fileExists(atPath: touchPath) {
                loadTouchSound(from: URL(fileURLWithPath: touchPath))
            }
            
            if FileManager.default.fileExists(atPath: beepPath) {
                loadBeepSound(from: URL(fileURLWithPath: beepPath))
            }
        }
        
        // Fallback: try direct paths
        if startPlayer == nil {
            let fallbackPaths = [
                executableDir + "/start.wav",
                bundle.resourcePath.map { ($0 as NSString).appendingPathComponent("start.wav") }
            ].compactMap { $0 }
            
            for path in fallbackPaths {
                if FileManager.default.fileExists(atPath: path) {
                    loadStartSound(from: URL(fileURLWithPath: path))
                    break
                }
            }
        }
        
        if touchPlayer == nil {
            let fallbackPaths = [
                executableDir + "/touch.wav",
                bundle.resourcePath.map { ($0 as NSString).appendingPathComponent("touch.wav") }
            ].compactMap { $0 }
            
            for path in fallbackPaths {
                if FileManager.default.fileExists(atPath: path) {
                    loadTouchSound(from: URL(fileURLWithPath: path))
                    break
                }
            }
        }
    }
    
    private func loadStartSound(from url: URL) {
        do {
            startPlayer = try AVAudioPlayer(contentsOf: url)
            startPlayer?.prepareToPlay()
        } catch {
            print("Failed to load start.wav: \(error)")
        }
    }
    
    private func loadTouchSound(from url: URL) {
        do {
            touchPlayer = try AVAudioPlayer(contentsOf: url)
            touchPlayer?.prepareToPlay()
        } catch {
            print("Failed to load touch.wav: \(error)")
        }
    }
    
    private func loadBeepSound(from url: URL) {
        do {
            beepPlayer = try AVAudioPlayer(contentsOf: url)
            beepPlayer?.prepareToPlay()
        } catch {
            print("Failed to load beep.wav: \(error)")
        }
    }
    
    func playStart() {
        if let player = startPlayer {
            player.currentTime = 0
            player.play()
            print("Playing start.wav")
        } else {
            print("Error: startPlayer is nil")
        }
    }
    
    func playTouch() {
        if let player = touchPlayer {
            player.currentTime = 0
            player.play()
            print("Playing touch.wav")
        } else {
            print("Error: touchPlayer is nil")
        }
    }
    
    func playBeep() {
        if let player = beepPlayer {
            player.currentTime = 0
            player.play()
            print("Playing beep.wav")
        } else {
            print("Error: beepPlayer is nil")
        }
    }
}

