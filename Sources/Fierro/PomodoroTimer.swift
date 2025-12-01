import Foundation
import Combine

class PomodoroTimer: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var progress: Float = 0.0 // 0.0 to 1.0
    @Published var duration: TimeInterval = 0 // Total duration in seconds
    @Published var remaining: TimeInterval = 0 // Remaining time in seconds
    @Published var completionFlash: Float = 0.0 // 0.0 to 1.0, fades out after completion
    
    private var timer: Timer?
    private var startTime: Date?
    private var completionFlashTimer: Timer?
    
    func start(duration: TimeInterval) {
        stop() // Stop any existing timer
        
        self.duration = duration
        self.remaining = duration
        self.progress = 0.0
        self.isRunning = true
        self.startTime = Date()
        
        // Play beep sound when timer starts
        SoundManager.shared.playBeep()
        
        // Update every 0.1 seconds for smooth animation
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.update()
        }
        
        print("🍅 Pomodoro started: \(Int(duration / 60)) minutes")
    }
    
    func stop() {
        let wasCompleted = remaining <= 0
        timer?.invalidate()
        timer = nil
        isRunning = false
        startTime = nil
        
        if wasCompleted {
            print("🍅 Pomodoro completed!")
            // Play beep sound when timer completes
            SoundManager.shared.playBeep()
            
            // Start completion flash - red orb for a few seconds
            completionFlash = 1.0
            completionFlashTimer?.invalidate()
            
            // Fade out over 5 seconds
            completionFlashTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                self.completionFlash = max(0.0, self.completionFlash - 0.01) // Fade out over 5 seconds
                if self.completionFlash <= 0.0 {
                    timer.invalidate()
                    self.completionFlashTimer = nil
                }
            }
        } else {
            // Reset flash if stopped early
            completionFlash = 0.0
            completionFlashTimer?.invalidate()
            completionFlashTimer = nil
        }
    }
    
    private func update() {
        guard let startTime = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        remaining = max(0, duration - elapsed)
        progress = duration > 0 ? Float(elapsed / duration) : 0.0
        
        if remaining <= 0 {
            stop()
        }
    }
    
    deinit {
        timer?.invalidate()
        completionFlashTimer?.invalidate()
    }
}

