# FIERRO - Pure Metal Shader

An animated fluid dynamic orb with a black, glossy, magnet-goo, ferrofluid-style animation using SwiftUI + Metal.

## Features

- **Pure Metal Shaders**: High-performance GPU-accelerated rendering
- **Audio Reactive**: Responds to microphone input in real-time with dynamic color changes
- **Dynamic Emoji Reactions**: Emojis appear based on audio intensity and level
- **Transparent Background**: Seamlessly blends with your desktop
- **Click-Through Window**: Clicks outside the orb pass through to the desktop
- **Bottom Right Positioning**: Automatically positions at bottom right of screen
- **Ferrofluid Animation**: Realistic magnetic fluid dynamics with spikes and tendrils
- **Draggable Window**: Move the orb anywhere on your screen
- **Subtle Morphing**: Gentle fluid dynamics that continuously transform the orb
- **Waveform Transformation**: Orb morphs from sphere to non-symmetrical shapes to waveforms based on audio
- **Dynamic Color System**: Single dominant color transitions through spectrum based on frequency and volume
- **Sound Effects**: Startup sound and touch feedback

## Requirements

- macOS 13.0 or later
- Metal-capable GPU
- Microphone access (for audio reactivity)

## Building

Build using Swift Package Manager:

```bash
# Debug build
swift build

# Release build (recommended)
swift build -c release

# Run the app
swift run -c release
```

The executable will be located at `.build/release/Fierro` after building.

## Usage

1. Launch the app (you'll hear a startup sound)
2. Grant microphone permission when prompted (or in System Settings > Privacy & Security > Microphone)
3. The ferrofluid orb will appear at the bottom right of your screen
4. Speak, play music, or make sounds to see the orb react in real-time:
   - **Color changes** based on frequency and volume
   - **Shape morphing** from sphere to waveforms
   - **Emojis appear** when audio intensity > 0.2 (happy) or level > 0.7 (too loud)
5. **Tap the orb** to trigger a touch reaction and see an emoji
6. **Drag the window** to move it anywhere on your screen
7. Clicks outside the orb pass through to your desktop

## Technical Details

- **Metal Compute Shaders**: Fluid dynamics simulation with particle interactions
- **Metal Vertex/Fragment Shaders**: Rendering with glossy reflections, morphing, and dynamic borders
- **AVAudioEngine**: Real-time audio analysis (RMS, frequency bands, intensity)
- **SwiftUI**: Modern UI framework
- **Transparent Window**: NSWindow with clear background and click-through support
- **Audio Analysis**: Real-time frequency and intensity detection for color mapping
- **Emoji System**: Dynamic emoji display with spin-in animations

## Troubleshooting

### Audio Not Working

If audio detection isn't working:

1. **Check microphone permission**: System Settings > Privacy & Security > Microphone > Enable for Fierro
2. **Check console output**: The app will show detailed error messages if audio fails
3. **Fake audio fallback**: If microphone isn't available, the app will use simulated audio for testing

### Build Issues

- Ensure you're using macOS 13.0 or later
- Make sure you have a Metal-capable GPU
- Check that Swift Package Manager can access all resources (start.wav, touch.wav)

## Customization

You can adjust the following parameters in the code:

- **Window size**: Change frame dimensions in `FierroApp.swift`
- **Audio sensitivity**: Modify the normalization factor in `AudioAnalyzer.swift` (currently 50.0)
- **Orb scale**: Adjust the coordinate scaling in `MetalRenderer.swift` (currently `/0.32`)
- **Color transitions**: Modify color phase speed and audio smoothing in shader
- **Emoji thresholds**: Change audio intensity/level thresholds in `EmojiView.swift`

## License

Copyright © 2024 Jonathan Caraveo

This software is free for **non-commercial use only**. 

**Non-commercial use** includes:
- Personal projects
- Educational purposes
- Open source projects
- Non-profit organizations

**Commercial use** requires explicit written permission from the copyright holder.

For commercial licensing inquiries, please contact the copyright holder.

## Disclaimer

This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose and noninfringement.
