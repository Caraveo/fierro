# FIERRO - Pure Metal Shader

An animated fluid dynamic orb with a black, glossy, magnet-goo, ferrofluid-style animation using SwiftUI + Metal.

## Features

- **Pure Metal Shaders**: High-performance GPU-accelerated rendering
- **Audio Reactive**: Responds to microphone input in real-time
- **Transparent Background**: Seamlessly blends with your desktop
- **Bottom Right Positioning**: Automatically positions at bottom right of screen
- **Ferrofluid Animation**: Realistic magnetic fluid dynamics with spikes and tendrils

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

1. Launch the app
2. Grant microphone permission when prompted
3. The ferrofluid orb will appear at the bottom right of your screen
4. Speak, play music, or make sounds to see the orb react in real-time

## Technical Details

- **Metal Compute Shaders**: Fluid dynamics simulation
- **Metal Vertex/Fragment Shaders**: Rendering with glossy reflections
- **AVAudioEngine**: Real-time audio analysis
- **SwiftUI**: Modern UI framework
- **Transparent Window**: NSWindow with clear background

## Customization

You can adjust the following parameters in the code:

- `particleCount`: Number of particles in the simulation (default: 1000)
- Window size: Change frame dimensions in `FierroApp.swift`
- Audio sensitivity: Modify the normalization factor in `AudioAnalyzer.swift`

