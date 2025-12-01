import SwiftUI

struct EmojiView: View {
    @State private var currentEmoji: String = ""
    @State private var scale: CGFloat = 0.0
    @State private var opacity: Double = 0.0
    @State private var rotation: Double = 0.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var changeTimer: Timer?
    @State private var lastAudioLevel: Float = 0.0
    @State private var lastAudioIntensity: Float = 0.0
    
    // Happy/positive emojis
    let happyEmojis = ["😊", "😄", "😃", "😁", "😆", "😍", "🥰", "😘", "🤗", "😉", "😋", "😎", "🤩", "🥳", "😇", "🙂", "😌", "😏", "😊", "😄", "😃", "😁", "😆", "😍", "🥰", "😘", "😉", "😋", "😎", "🤩", "🥳", "😇", "🙂", "😌", "😏", "🤗", "😊", "😄", "😃", "😁", "😆", "😍", "🥰", "😘", "😉", "😋", "😎", "🤩", "🥳", "😇", "🙂", "😌", "😏", "🤗", "😊", "😄", "😃", "😁", "😆", "😍", "🥰", "😘", "😉", "😋", "😎", "🤩", "🥳", "😇", "🙂", "😌", "😏", "🤗", "😊", "😄", "😃", "😁", "😆", "😍", "🥰", "😘", "😉", "😋", "😎", "🤩", "🥳", "😇", "🙂", "😌", "😏", "🤗"]
    
    // Too loud emojis
    let tooLoudEmojis = ["😱", "😰", "🤯", "😵", "😮", "😲", "🤭", "😳", "😱", "😰", "🤯", "😵", "😮", "😲", "🤭", "😳", "😱", "😰", "🤯", "😵", "😮", "😲", "🤭", "😳"]
    
    var onTap: (() -> Void)?
    
    var body: some View {
        ZStack {
            if !currentEmoji.isEmpty {
                Text(currentEmoji)
                    .font(.system(size: 30)) // Half the size (was 60)
                    .scaleEffect(scale * pulseScale)
                    .opacity(opacity)
                    .rotationEffect(.degrees(rotation))
                    .animation(.easeInOut(duration: 0.3), value: scale)
                    .animation(.easeInOut(duration: 0.3), value: opacity)
                    .animation(.easeInOut(duration: 0.3), value: rotation)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseScale)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowEmoji"))) { _ in
            showRandomEmoji()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AudioLevelChanged"))) { notification in
            if let level = notification.object as? Float {
                handleAudioLevel(level)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AudioIntensityChanged"))) { notification in
            if let intensity = notification.object as? Float {
                handleAudioIntensity(intensity)
            }
        }
    }
    
    func handleAudioLevel(_ level: Float) {
        lastAudioLevel = level
    }
    
    func handleAudioIntensity(_ intensity: Float) {
        lastAudioIntensity = intensity
        
        // If level > 0.7, show "too loud" emojis
        if lastAudioLevel > 0.7 {
            if currentEmoji.isEmpty || !tooLoudEmojis.contains(currentEmoji) {
                showEmoji(from: tooLoudEmojis)
            }
        }
        // If intensity > 0.2, show happy emojis
        else if intensity > 0.2 {
            if currentEmoji.isEmpty || !happyEmojis.contains(currentEmoji) {
                showEmoji(from: happyEmojis)
            }
        }
    }
    
    func showRandomEmoji() {
        showEmoji(from: lastAudioLevel > 0.7 ? tooLoudEmojis : happyEmojis)
    }
    
    func showEmoji(from emojiList: [String]) {
        // Cancel any existing timer
        changeTimer?.invalidate()
        
        // Choose random emoji from the list
        currentEmoji = emojiList.randomElement() ?? "😊"
        
        // Reset rotation for spin-in effect
        rotation = 0.0
        scale = 0.0
        opacity = 0.0
        
        // Spin into existence with scale and fade
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            scale = 1.0
            opacity = 1.0
            rotation = 720.0 // Spin 2 full rotations
        }
        
        // Start pulsing animation after spin-in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
            }
            
            // Slow continuous rotation after spin-in
            withAnimation(.linear(duration: 10.0).repeatForever(autoreverses: false)) {
                rotation = 1080.0 // Continue rotating
            }
        }
        
        // Fade out after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            hideEmoji()
        }
    }
    
    func hideEmoji() {
        // Fade out
        withAnimation(.easeOut(duration: 0.5)) {
            opacity = 0.0
            scale = 0.0
        }
        
        // Clear emoji after fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            currentEmoji = ""
            changeTimer?.invalidate()
        }
    }
}

