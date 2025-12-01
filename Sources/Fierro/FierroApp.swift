import SwiftUI
import AppKit

@main
struct FierroApp: App {
    @StateObject private var audioAnalyzer = AudioAnalyzer()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioAnalyzer)
                .background(TransparentBackground())
                .frame(width: 300, height: 300)
                .onAppear {
                    setupWindow()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 300, height: 300)
    }
    
    private func setupWindow() {
        if let window = NSApplication.shared.windows.first {
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            // Position at bottom right
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let windowRect = window.frame
                let x = screenRect.maxX - windowRect.width - 20
                let y = screenRect.minY + 20
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
    }
}

