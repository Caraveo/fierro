import SwiftUI
import MetalKit
import AppKit

struct ContentView: View {
    @EnvironmentObject var audioAnalyzer: AudioAnalyzer
    @StateObject private var pomodoroTimer = PomodoroTimer()
    @State private var renderer: MetalRenderer?
    
    var body: some View {
        ZStack {
            MetalView(renderer: $renderer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    renderer = MetalRenderer()
                    // Audio analyzer is started in FierroApp body.onAppear
                    // This ensures it starts once when the first window appears
                }
                .onChange(of: audioAnalyzer.audioLevel) { newLevel in
                    renderer?.updateAudioLevel(newLevel)
                }
                .onChange(of: audioAnalyzer.audioFrequency) { newFreq in
                    renderer?.updateAudioFrequency(newFreq)
                }
                .onChange(of: audioAnalyzer.audioIntensity) { newIntensity in
                    renderer?.updateAudioIntensity(newIntensity)
                    // Notify emoji view of audio intensity changes
                    NotificationCenter.default.post(name: NSNotification.Name("AudioIntensityChanged"), object: newIntensity)
                }
                .onChange(of: audioAnalyzer.audioLevel) { newLevel in
                    // Notify emoji view of audio level changes
                    NotificationCenter.default.post(name: NSNotification.Name("AudioLevelChanged"), object: newLevel)
                }
                .onChange(of: pomodoroTimer.progress) { progress in
                    renderer?.updateTimerProgress(progress)
                }
                .onChange(of: pomodoroTimer.completionFlash) { flash in
                    renderer?.updateTimerCompletionFlash(flash)
                }
            
            // Emoji overlay in center
            EmojiView()
                .allowsHitTesting(false)
            
            // Invisible draggable overlay with touch reaction and pomodoro timer
            DraggableArea(
                onTap: {
                    renderer?.triggerTouchReaction()
                    // Show emoji on tap
                    NotificationCenter.default.post(name: NSNotification.Name("ShowEmoji"), object: nil)
                },
                onHoldComplete: { duration in
                    pomodoroTimer.start(duration: duration)
                }
            )
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DraggableArea: NSViewRepresentable {
    var onTap: (() -> Void)?
    var onHoldComplete: ((TimeInterval) -> Void)? // Duration in seconds
    
    func makeNSView(context: Context) -> NSView {
        let view = DraggableNSView()
        view.onTap = onTap
        view.onHoldComplete = onHoldComplete
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let draggableView = nsView as? DraggableNSView {
            draggableView.onTap = onTap
            draggableView.onHoldComplete = onHoldComplete
        }
    }
}

class DraggableNSView: NSView {
    var onTap: (() -> Void)?
    var onHoldComplete: ((TimeInterval) -> Void)?
    
    private var mouseDownLocation: NSPoint?
    private var mouseDownTime: Date?
    private var holdTimer: Timer?
    private let dragThreshold: CGFloat = 3.0 // Pixels to move before considering it a drag
    
    override var mouseDownCanMoveWindow: Bool {
        return false // We'll handle dragging manually
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Calculate distance from center
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let distance = sqrt(pow(point.x - center.x, 2) + pow(point.y - center.y, 2))
        let maxRadius = min(bounds.width, bounds.height) * 0.4 // Orb is roughly 40% of window
        
        // Only accept clicks within the orb area
        if distance <= maxRadius {
            return super.hitTest(point)
        }
        
        // Pass through clicks outside the orb
        return nil
    }
    
    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        mouseDownTime = Date()
        
        // Play touch sound on click
        SoundManager.shared.playTouch()
        // Trigger visual reaction
        onTap?()
        
        // Start tracking hold time
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkHoldTime()
        }
    }
    
    private func checkHoldTime() {
        // This function can be used for visual feedback during hold if needed
        // Currently not needed, but kept for future enhancements
    }
    
    private func calculateDuration(fromHoldTime holdTime: TimeInterval) -> TimeInterval {
        // 1 click (no hold) = 10 minutes
        // 1 second = 20 minutes
        // 2 seconds = 25 minutes
        // 3 seconds = 30 minutes
        // 4 seconds = 35 minutes
        // 5 seconds = 40 minutes
        // 6 seconds = 45 minutes
        // 7 seconds = 50 minutes
        // 8 seconds = 55 minutes
        // 9+ seconds = 60 minutes (1 hour max)
        
        let seconds = Int(holdTime)
        
        switch seconds {
        case 0:
            return 10 * 60 // 10 minutes
        case 1:
            return 20 * 60 // 20 minutes
        case 2:
            return 25 * 60 // 25 minutes
        case 3:
            return 30 * 60 // 30 minutes
        case 4:
            return 35 * 60 // 35 minutes
        case 5:
            return 40 * 60 // 40 minutes
        case 6:
            return 45 * 60 // 45 minutes
        case 7:
            return 50 * 60 // 50 minutes
        case 8:
            return 55 * 60 // 55 minutes
        default:
            return 60 * 60 // 60 minutes (1 hour max)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = mouseDownLocation else { return }
        let currentLocation = event.locationInWindow
        let distance = sqrt(pow(currentLocation.x - startLocation.x, 2) + pow(currentLocation.y - startLocation.y, 2))
        
        // If moved far enough, it's a drag - cancel hold timer
        if distance > dragThreshold {
            holdTimer?.invalidate()
            holdTimer = nil
            mouseDownTime = nil
            window?.performDrag(with: event)
            mouseDownLocation = nil
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        holdTimer = nil
        
        // Calculate final duration and start pomodoro if held
        if let startTime = mouseDownTime {
            let holdDuration = Date().timeIntervalSince(startTime)
            let duration = calculateDuration(fromHoldTime: holdDuration)
            
            // Only start if held for at least a brief moment (to distinguish from quick tap)
            if holdDuration > 0.05 {
                onHoldComplete?(duration)
            }
        }
        
        mouseDownLocation = nil
        mouseDownTime = nil
    }
}

struct MetalView: NSViewRepresentable {
    @Binding var renderer: MetalRenderer?
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = ClickThroughMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = false
        mtkView.layer?.isOpaque = false
        mtkView.autoresizingMask = [.width, .height] // Fill the parent view
        mtkView.layer?.masksToBounds = false // Don't clip rendering
        
        if let renderer = renderer {
            renderer.setup(view: mtkView)
        }
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        if let renderer = renderer {
            renderer.setup(view: nsView)
        }
        nsView.layer?.masksToBounds = false
    }
}

class ClickThroughMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Calculate distance from center
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let distance = sqrt(pow(point.x - center.x, 2) + pow(point.y - center.y, 2))
        let maxRadius = min(bounds.width, bounds.height) * 0.4 // Orb is roughly 40% of window
        
        // Only accept clicks within the orb area
        if distance <= maxRadius {
            return super.hitTest(point)
        }
        
        // Pass through clicks outside the orb
        return nil
    }
}

struct TransparentBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

