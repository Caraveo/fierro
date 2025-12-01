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
            // Invisible draggable overlay
            DraggableArea()
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableNSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
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

