import SwiftUI
import MetalKit
import AppKit

struct ContentView: View {
    @EnvironmentObject var audioAnalyzer: AudioAnalyzer
    @State private var renderer: MetalRenderer?
    
    var body: some View {
        ZStack {
            MetalView(renderer: $renderer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    renderer = MetalRenderer()
                    audioAnalyzer.start()
                }
                .onChange(of: audioAnalyzer.audioLevel) { newLevel in
                    renderer?.updateAudioLevel(newLevel)
                }
            // Invisible draggable overlay with touch reaction
            DraggableArea(onTap: {
                renderer?.triggerTouchReaction()
            })
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DraggableArea: NSViewRepresentable {
    var onTap: (() -> Void)?
    
    func makeNSView(context: Context) -> NSView {
        let view = DraggableNSView()
        view.onTap = onTap
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let draggableView = nsView as? DraggableNSView {
            draggableView.onTap = onTap
        }
    }
}

class DraggableNSView: NSView {
    var onTap: (() -> Void)?
    private var mouseDownLocation: NSPoint?
    private let dragThreshold: CGFloat = 3.0 // Pixels to move before considering it a drag
    
    override var mouseDownCanMoveWindow: Bool {
        return false // We'll handle dragging manually
    }
    
    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        // Play touch sound on click
        SoundManager.shared.playTouch()
        // Trigger visual reaction
        onTap?()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = mouseDownLocation else { return }
        let currentLocation = event.locationInWindow
        let distance = sqrt(pow(currentLocation.x - startLocation.x, 2) + pow(currentLocation.y - startLocation.y, 2))
        
        // If moved far enough, it's a drag
        if distance > dragThreshold {
            window?.performDrag(with: event)
            mouseDownLocation = nil
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
    }
}

struct MetalView: NSViewRepresentable {
    @Binding var renderer: MetalRenderer?
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
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

struct TransparentBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

