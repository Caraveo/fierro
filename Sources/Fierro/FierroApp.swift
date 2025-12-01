import SwiftUI
import AppKit

@main
struct FierroApp: App {
    @StateObject private var audioAnalyzer = AudioAnalyzer()
    
    init() {
        // Play startup sound
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            SoundManager.shared.playStart()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioAnalyzer)
                .background(TransparentBackground())
                .frame(width: 567, height: 567)
                .background(WindowAccessor())
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 567, height: 567)
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                setupWindow(window)
            } else {
                // Try again after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = view.window {
                        setupWindow(window)
                    }
                }
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    private func setupWindow(_ window: NSWindow) {
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.styleMask = [.borderless, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true // Make entire window draggable
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.masksToBounds = false // Don't clip content
        
        // Position at bottom right
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowSize = NSSize(width: 600, height: 600)
            let x = screenRect.maxX - windowSize.width - 20
            let y = screenRect.minY + 20
            window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: windowSize), display: true)
        }
        
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

