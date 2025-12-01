import MetalKit
import Metal
import simd

class MetalRenderer: NSObject, MTKViewDelegate {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var renderPipelineState: MTLRenderPipelineState!
    var computePipelineState: MTLComputePipelineState!
    
    var time: Float = 0
    var audioLevel: Float = 0
    var audioFrequency: Float = 0.0
    var audioIntensity: Float = 0.0
    var touchReaction: Float = 0.0 // Visual reaction to touch
    private var debugCounter = 0
    
    var quadVertexBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!
    
    let particleCount = 1000
    var particleBuffer: MTLBuffer!
    
    struct Uniforms {
        var time: Float
        var audioLevel: Float
        var audioFrequency: Float
        var audioIntensity: Float
        var touchReaction: Float
        var resolution: simd_float2
    }
    
    override init() {
        super.init()
        setupMetal()
    }
    
    func setup(view: MTKView) {
        view.delegate = self
        view.device = device
    }
    
    func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        guard let device = device else {
            fatalError("Metal is not supported on this device")
        }
        
        commandQueue = device.makeCommandQueue()
        
        // Load Metal shader library
        let library: MTLLibrary
        if let defaultLibrary = device.makeDefaultLibrary() {
            library = defaultLibrary
        } else {
            // Fallback: Load shader source and compile
            guard let shaderSource = loadShaderSource() else {
                fatalError("Failed to load Metal shader source")
            }
            do {
                library = try device.makeLibrary(source: shaderSource, options: nil)
            } catch {
                fatalError("Failed to compile Metal shader: \(error)")
            }
        }
        
        // Setup compute shader
        if let computeFunction = library.makeFunction(name: "ferrofluidCompute") {
            do {
                computePipelineState = try device.makeComputePipelineState(function: computeFunction)
            } catch {
                fatalError("Failed to create compute pipeline: \(error)")
            }
        }
        
        // Setup render pipeline
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline: \(error)")
        }
        
        // Create full-screen quad vertices
        let quadVertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,
             1.0, -1.0, 1.0, 1.0,
            -1.0,  1.0, 0.0, 0.0,
             1.0,  1.0, 1.0, 0.0
        ]
        
        quadVertexBuffer = device.makeBuffer(
            bytes: quadVertices,
            length: quadVertices.count * MemoryLayout<Float>.stride,
            options: []
        )
        
        // Create particle buffer for compute shader
        var particles: [simd_float2] = []
        for _ in 0..<particleCount {
            let angle = Float.random(in: 0...(2 * .pi))
            let radius = Float.random(in: 0.3...0.8)
            particles.append(simd_float2(
                cos(angle) * radius,
                sin(angle) * radius
            ))
        }
        
        particleBuffer = device.makeBuffer(
            bytes: particles,
            length: particles.count * MemoryLayout<simd_float2>.stride,
            options: []
        )
        
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: []
        )
    }
    
    func updateAudioLevel(_ level: Float) {
        audioLevel = level
    }
    
    func updateAudioFrequency(_ frequency: Float) {
        audioFrequency = frequency
    }
    
    func updateAudioIntensity(_ intensity: Float) {
        audioIntensity = intensity
    }
    
    func triggerTouchReaction() {
        // Trigger a visual pulse/reaction
        touchReaction = 1.0
    }
    
    private func loadShaderSource() -> String? {
        // Try to load from bundle first
        if let url = Bundle.main.url(forResource: "FerrofluidShader", withExtension: "metal"),
           let source = try? String(contentsOf: url) {
            return source
        }
        
        // Fallback: Embedded shader source
        return embeddedShaderSource
    }
    
    private var embeddedShaderSource: String {
        return """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };
        
        struct Uniforms {
            float time;
            float audioLevel;
            float audioFrequency;
            float audioIntensity;
            float touchReaction;
            float2 resolution;
        };
        
        vertex VertexOut vertexShader(
            const device float4* vertices [[buffer(0)]],
            uint vid [[vertex_id]]
        ) {
            VertexOut out;
            float4 vert = vertices[vid];
            out.position = float4(vert.xy, 0.0, 1.0);
            out.uv = vert.zw;
            return out;
        }
        
        fragment float4 fragmentShader(
            VertexOut in [[stage_in]],
            const device Uniforms& uniforms [[buffer(0)]],
            const device float2* particles [[buffer(1)]]
        ) {
            float2 uv = in.uv;
            float time = uniforms.time;
            float audioLevel = uniforms.audioLevel;
            float audioFrequency = uniforms.audioFrequency;
            float audioIntensity = uniforms.audioIntensity;
            float touchReaction = uniforms.touchReaction;
            float2 resolution = uniforms.resolution;
            
            float2 coord = (uv - 0.5) * 2.0;
            coord.x *= resolution.x / resolution.y;
            
            // Scale down the orb to fit better in the window
            coord /= 0.32;
            
            float angle = atan2(coord.y, coord.x);
            float dist = length(coord);
            
            // Audio-reactive transformation: Sphere -> Non-symmetrical -> Waveform
            float deformationIntensity = audioIntensity * 0.6 + touchReaction * 0.3;
            
            // Phase 1: Non-symmetrical sphere (moderate audio) - with pulsing
            float pulseMod = sin(time * 1.8 + audioLevel * 2.5) * 0.3 + 0.7;
            float nonSymPhase = time * 0.6 + audioLevel * 0.9;
            float nonSymDeform = min(deformationIntensity, 0.6) * pulseMod; // Limit to 60% for phase 1, with pulsing
            
            // Create non-symmetrical deformation
            float asymX = sin(angle * 2.0 + nonSymPhase) * 0.15 * nonSymDeform;
            float asymY = cos(angle * 2.5 + nonSymPhase * 1.2) * 0.15 * nonSymDeform;
            float asymRadial = sin(angle * 3.0 + nonSymPhase * 0.8) * 0.1 * nonSymDeform;
            
            // Phase 2: Waveform-based deformation (high audio)
            float waveformIntensity = max(0.0, deformationIntensity - 0.5) / 0.5; // 0-1 when audio > 50% (lower threshold)
            waveformIntensity = pow(waveformIntensity, 0.8); // Smooth transition
            
            // Create waveform patterns based on audio frequency and level
            float wavePhase = time * 0.6 + audioLevel * 1.2;
            float freqWave = sin(angle * audioFrequency * 10.0 + wavePhase) * waveformIntensity;
            float levelWave = cos(angle * 8.0 + audioLevel * 2.5 + wavePhase) * waveformIntensity;
            
            // Combine multiple waveform frequencies for complex patterns
            float waveform1 = sin(angle * 5.0 + wavePhase) * 0.25 * waveformIntensity;
            float waveform2 = cos(angle * 9.0 + wavePhase * 1.4) * 0.2 * waveformIntensity;
            float waveform3 = sin(angle * 13.0 + wavePhase * 0.8) * 0.15 * waveformIntensity;
            float waveform4 = cos(angle * 17.0 + wavePhase * 1.1) * 0.1 * waveformIntensity;
            
            // Radial waveform (like sound waves emanating from center) - more pronounced
            float radialWave = sin(dist * 10.0 - wavePhase * 2.5) * 0.2 * waveformIntensity;
            float radialWave2 = cos(dist * 15.0 - wavePhase * 2.0) * 0.15 * waveformIntensity;
            float radialWave3 = sin(dist * 20.0 - wavePhase * 1.5) * 0.1 * waveformIntensity;
            
            // Apply deformations progressively
            float2 deformedCoord = coord;
            
            // Non-symmetrical phase
            deformedCoord.x += asymX + asymRadial * cos(angle);
            deformedCoord.y += asymY + asymRadial * sin(angle);
            
            // Waveform phase (adds on top of non-symmetrical) - more pronounced
            float combinedWaveform = waveform1 + waveform2 + waveform3 + waveform4;
            deformedCoord.x += combinedWaveform * cos(angle) + (radialWave + radialWave2) * cos(angle);
            deformedCoord.y += combinedWaveform * sin(angle) + (radialWave + radialWave3) * sin(angle);
            
            // Add frequency-based waveform modulation - stronger effect
            float freqMod = audioFrequency * 0.4 * waveformIntensity;
            deformedCoord.x += sin(angle * 6.0 + audioFrequency * 12.0 + wavePhase) * freqMod;
            deformedCoord.y += cos(angle * 6.0 + audioFrequency * 12.0 + wavePhase) * freqMod;
            
            // Add level-based waveform modulation for more dynamic response
            float levelMod = audioLevel * 0.3 * waveformIntensity;
            deformedCoord.x += cos(angle * 4.0 + audioLevel * 8.0 + wavePhase * 0.7) * levelMod;
            deformedCoord.y += sin(angle * 4.0 + audioLevel * 8.0 + wavePhase * 0.7) * levelMod;
            
            // Very subtle fluid morphing with gentle frequencies
            float morphPhase = time * 0.25 + audioLevel * 0.5;
            float morph1 = sin(morphPhase) * 0.04;
            float morph2 = cos(morphPhase * 1.1) * 0.03;
            float morph3 = sin(morphPhase * 1.6 + 1.0) * 0.025;
            
            // Warp the coordinate space for fluid flow
            float2 warpedCoord = deformedCoord;
            warpedCoord.x += sin(deformedCoord.y * 1.2 + time * 0.5) * 0.02 * (0.2 + audioLevel * 0.15);
            warpedCoord.y += cos(deformedCoord.x * 1.2 + time * 0.45) * 0.02 * (0.2 + audioLevel * 0.15);
            
            // Calculate distance with progressive deformation
            dist = length(warpedCoord);
            // Make it less rounded when reactive (waveform phase makes it very non-rounded)
            float roundedness = 1.0 - (nonSymDeform * 0.25 + waveformIntensity * 0.5);
            dist = pow(dist, max(0.4, roundedness)); // More extreme deformation
            angle = atan2(warpedCoord.y, warpedCoord.x);
            
            // Sample particles for density field
            float density = 0.0;
            int sampleCount = min(200, 1000);
            for (int i = 0; i < sampleCount; i += 5) {
                float2 particlePos = particles[i];
                float2 diff = warpedCoord - particlePos;
                float particleDist = length(diff);
                density += exp(-particleDist * 10.0) * 0.008;
            }
            
            // Very subtle multi-octave noise for gentle organic fluid surface
            float noise = 0.0;
            float2 p = warpedCoord * 1.8;
            float noiseScale = 1.0;
            for (int i = 0; i < 3; i++) {
                float n = sin(p.x * noiseScale + time * (0.1 + i * 0.08)) * 
                          cos(p.y * noiseScale + time * (0.12 + i * 0.06));
                noise += n * (1.0 / noiseScale);
                p *= 1.5;
                noiseScale *= 1.5;
            }
            noise *= 0.08;
            
            // More reactive base radius that responds to voice/audio with deformation - stronger pulsing
            float pulsePhase = time * 2.0 + audioLevel * 3.0;
            float pulse = sin(pulsePhase) * 0.12 + cos(pulsePhase * 1.3) * 0.08;
            float baseRadius = 0.39 + audioLevel * 0.20 + morph1 * 0.03 + touchReaction * 0.15 + pulse * audioIntensity;
            // Adjust radius based on waveform deformation
            baseRadius += (waveformIntensity * 0.1 - nonSymDeform * 0.05);
            
            // Single ring effect - one radial wave, more reactive to audio with stronger pulsing
            float ringPulse = sin(time * 1.5 + audioLevel * 2.0) * 0.5 + 0.5;
            float ringWave = sin(dist * 1.2 - time * 0.8) * 0.025 * (0.2 + audioLevel * 0.6 + touchReaction * 0.4) * (0.7 + ringPulse * 0.3);
            float angularWave = sin(angle * 3.0 + time * 0.9) * 0.015 * (0.15 + audioLevel * 0.4 + touchReaction * 0.25) * (0.7 + ringPulse * 0.3);
            
            // Main blob with subtle morphing
            float blobDist = dist + noise * 0.1 + density * 1.2 + ringWave + angularWave;
            float blob = 1.0 - smoothstep(baseRadius, baseRadius + 0.35, blobDist);
            
            // More reactive spikes/tendrils that respond to voice - always visible, audio and touch reactive
            float spikes = 0.0;
            int spikeCount = 6 + int(audioLevel * 4.0) + int(touchReaction * 4.0); // More spikes with audio
            for (int i = 0; i < spikeCount; i++) {
                float spikeAngle = (float(i) / float(spikeCount)) * 3.14159 * 2.0 + time * 0.3 + morph2;
                float spikeDist = dist - baseRadius - 0.12;
                
                // Gentle morphing spike intensity - always visible base, reacts to audio and touch
                float spikePhase = (angle - spikeAngle) * 5.0 + time * 1.5 + morph3;
                float spikeIntensity = sin(spikePhase) * 0.35 + 0.65;
                spikeIntensity = pow(spikeIntensity, 1.05 + audioLevel * 0.15 + touchReaction * 0.2);
                
                // More reactive spike length - responds strongly to voice/audio
                float spikeLength = 0.14 + audioLevel * 0.20 + touchReaction * 0.18 + sin(time * 0.9 + float(i)) * 0.03;
                // Make spikes visible even at low audio, but grow more with audio and touch
                float spike = exp(-spikeDist * 4.5) * spikeIntensity * (0.35 + audioLevel * 0.40 + touchReaction * 0.4);
                
                // More reactive secondary tendrils - respond to voice
                float tendrilAngle = spikeAngle + 0.2;
                float tendrilDist = dist - baseRadius - 0.14;
                float tendril = exp(-tendrilDist * 5.5) * 
                               (sin((angle - tendrilAngle) * 7.0 + time * 1.8) * 0.15 + 0.45) *
                               (0.18 + audioLevel * 0.25 + touchReaction * 0.25);
                
                spikes += spike + tendril;
            }
            spikes = smoothstep(0.18, 0.42, spikes);
            
            // Combine blob and spikes with more reactive blend - responds to voice
            float shape = max(blob, spikes * (0.48 + audioLevel * 0.20));
            
            // Remove multiple surface ripples - keep it clean with just the single ring
            shape = clamp(shape, 0.0, 1.0);
            
            // Calculate surface normal with fluid distortion
            float eps = 0.015;
            float ddx = length(warpedCoord + float2(eps, 0.0)) - length(warpedCoord - float2(eps, 0.0));
            float ddy = length(warpedCoord + float2(0.0, eps)) - length(warpedCoord - float2(0.0, eps));
            float3 normal = normalize(float3(-ddx * 2.0, -ddy * 2.0, 1.0));
            
            // Very subtle normal perturbation for gentle fluid surface - audio reactive
            float3 normalNoise = float3(
                sin(coord.x * 3.5 + time * 0.6) * 0.02,
                cos(coord.y * 3.5 + time * 0.6) * 0.02,
                0.0
            ) * (0.25 + audioLevel * 0.15);
            normal = normalize(normal + normalNoise);
            
            float3 viewDir = normalize(float3(coord, 1.0));
            float fresnel = pow(1.0 - max(dot(viewDir, normal), 0.0), 2.0);
            
            // Single dominant color that transitions based on audio characteristics with more dynamism
            float3 baseColor = float3(0.0, 0.0, 0.0); // Darker base for more contrast
            
            // Add time-based variation to prevent getting stuck - faster when reactive
            float reactiveVariationSpeed = 1.0 + audioIntensity * 1.5;
            float timeVariation = sin(time * (0.5 + reactiveVariationSpeed * 0.5)) * 0.15;
            float dynamicFreq = clamp(audioFrequency + timeVariation, 0.0, 1.0);
            float dynamicLevel = clamp(audioLevel + timeVariation * 0.5, 0.0, 1.0);
            
            // Color mapping with more granular zones and smoother transitions:
            // High frequency + High volume = RED/PURPLE (intense, sharp sounds)
            // High frequency + Low volume = PINK/MAGENTA (whispers, high notes)
            // Medium frequency + High volume = BLUE/CYAN (mid-range, loud)
            // Medium frequency + Low volume = GREEN/TEAL (calm, mid tones)
            // Low frequency + High volume = ORANGE/YELLOW (bass, deep sounds)
            // Low frequency + Low volume = YELLOW/AMBER (warm, soft bass)
            
            float colorIntensity = audioIntensity * 0.9 + touchReaction * 0.2;
            
            // Select 3-4 colors simultaneously for gradient effect
            float3 color1 = float3(0.0);
            float3 color2 = float3(0.0);
            float3 color3 = float3(0.0);
            float3 color4 = float3(0.0);
            
            float freqWeight = dynamicFreq;
            float levelWeight = dynamicLevel;
            
            // High audio level (0.9+) = RED priority with gradient
            if (audioLevel >= 0.9) {
                float redIntensity = (audioLevel - 0.9) / 0.1;
                color1 = mix(float3(1.0, 0.1, 0.1), float3(1.0, 0.0, 0.0), redIntensity);
                color2 = float3(1.0, 0.3, 0.0); // Orange-red
                color3 = float3(0.9, 0.0, 0.5); // Deep pink
                color4 = float3(1.0, 0.0, 0.2); // Bright red
            } else {
                // Select multiple colors based on frequency and level
                if (freqWeight > 0.65 && levelWeight > 0.45) {
                    // High freq + High volume = RED/PURPLE gradient
                    color1 = float3(1.0, 0.0, 0.3); // Red
                    color2 = float3(0.9, 0.0, 1.0); // Purple
                    color3 = float3(1.0, 0.2, 0.6); // Pink
                    color4 = float3(0.8, 0.0, 0.8); // Magenta
                } else if (freqWeight > 0.65) {
                    // High freq + Low volume = PINK/MAGENTA gradient
                    color1 = float3(1.0, 0.5, 0.9); // Light pink
                    color2 = float3(1.0, 0.2, 1.0); // Magenta
                    color3 = float3(0.9, 0.3, 0.9); // Lavender
                    color4 = float3(1.0, 0.4, 0.8); // Rose
                } else if (freqWeight > 0.35 && levelWeight > 0.35) {
                    // Medium freq + High volume = BLUE/CYAN gradient
                    color1 = float3(0.2, 0.6, 1.0); // Blue
                    color2 = float3(0.0, 1.0, 1.0); // Cyan
                    color3 = float3(0.4, 0.8, 1.0); // Sky blue
                    color4 = float3(0.0, 0.8, 1.0); // Bright cyan
                } else if (freqWeight > 0.35) {
                    // Medium freq + Low volume = GREEN/TEAL gradient
                    color1 = float3(0.0, 1.0, 0.6); // Green
                    color2 = float3(0.0, 0.9, 0.9); // Teal
                    color3 = float3(0.3, 1.0, 0.7); // Mint
                    color4 = float3(0.0, 0.8, 0.8); // Aqua
                } else if (levelWeight > 0.35) {
                    // Low freq + High volume = ORANGE/YELLOW gradient
                    color1 = float3(1.0, 0.6, 0.0); // Orange
                    color2 = float3(1.0, 0.9, 0.2); // Yellow
                    color3 = float3(1.0, 0.7, 0.3); // Gold
                    color4 = float3(1.0, 0.8, 0.1); // Amber
                } else {
                    // Low freq + Low volume = YELLOW/AMBER gradient
                    float variation = sin(time * 0.8 + audioIntensity * 2.0) * 0.3;
                    color1 = mix(float3(1.0, 0.7, 0.1), float3(1.0, 0.5, 0.0), 0.5 + variation);
                    color2 = float3(1.0, 0.8, 0.2); // Light yellow
                    color3 = float3(1.0, 0.6, 0.0); // Orange-yellow
                    color4 = float3(1.0, 0.9, 0.3); // Pale yellow
                }
            }
            
            // Create gradient using multiple colors based on position and audio
            float gradientPhase = angle + time * 0.3 + audioIntensity * 0.5;
            float gradientPos = (sin(gradientPhase) * 0.5 + 0.5); // 0-1 gradient position
            
            // Blend 4 colors in gradient
            float3 color12 = mix(color1, color2, smoothstep(0.0, 0.33, gradientPos));
            float3 color23 = mix(color2, color3, smoothstep(0.33, 0.66, gradientPos));
            float3 color34 = mix(color3, color4, smoothstep(0.66, 1.0, gradientPos));
            
            float3 dominantColor = mix(color12, color23, smoothstep(0.0, 0.5, gradientPos));
            dominantColor = mix(dominantColor, color34, smoothstep(0.5, 1.0, gradientPos));
            
            // Add radial gradient component
            float radialGradient = smoothstep(0.3, 0.7, dist);
            float3 centerColor = mix(color1, color2, 0.5);
            float3 edgeColor = mix(color3, color4, 0.5);
            dominantColor = mix(centerColor, edgeColor, radialGradient * 0.4) * 0.6 + dominantColor * 0.4;
            
            // Cycle through color spectrum after choosing dominant color
            float reactiveSpeed = 1.0 + audioIntensity * 2.0; // Speed up when reactive
            float spectrumPhase = time * (0.6 + reactiveSpeed * 0.6) + audioIntensity * 1.2;
            
            // Create full spectrum cycle (HSV to RGB)
            float hue = fract(spectrumPhase * 0.3); // Cycle through 0-1 (full spectrum)
            float3 spectrumColor = float3(0.0);
            
            // HSV to RGB conversion for full spectrum
            float h = hue * 6.0;
            float c = 0.9 + audioIntensity * 0.1;
            float x = c * (1.0 - abs(fmod(h, 2.0) - 1.0));
            
            if (h < 1.0) spectrumColor = float3(c, x, 0.0);
            else if (h < 2.0) spectrumColor = float3(x, c, 0.0);
            else if (h < 3.0) spectrumColor = float3(0.0, c, x);
            else if (h < 4.0) spectrumColor = float3(0.0, x, c);
            else if (h < 5.0) spectrumColor = float3(x, 0.0, c);
            else spectrumColor = float3(c, 0.0, x);
            
            // Blend between dominant color and spectrum cycle based on audio intensity
            float spectrumBlend = audioIntensity * 0.6; // More spectrum cycling when more reactive
            float3 finalColor = mix(dominantColor, spectrumColor, spectrumBlend);
            
            // Add pulsing variation
            float colorPhase = time * (0.8 + reactiveSpeed * 0.8) + audioIntensity * 1.5 + audioFrequency * 1.2;
            float colorBlend = sin(colorPhase) * 0.25 + 0.75; // More variation and faster pulsing
            finalColor *= colorBlend;
            
            // Use the final cycled color
            dominantColor = finalColor;
            
            // Apply color based on audio intensity with more dynamism - darker contrast
            float3 gradientColor = mix(baseColor, dominantColor * colorBlend, colorIntensity);
            
            // Increase contrast by making non-highlighted areas darker
            float contrastBoost = 1.3;
            gradientColor = pow(gradientColor, float3(1.0 / contrastBoost)); // Darken shadows
            
            // Add fresnel highlights with dominant color - brighter for contrast
            float3 highlightColor = dominantColor * fresnel * (0.7 + audioIntensity * 0.6);
            float3 color = mix(gradientColor, highlightColor, fresnel * 0.65 + audioIntensity * 0.4 + touchReaction * 0.2);
            
            // More reactive specular with dominant color - brighter for contrast
            float3 lightDir = normalize(float3(0.3, 0.5, 1.0));
            float specular = pow(max(dot(reflect(-lightDir, normal), viewDir), 0.0), 58.0 + audioLevel * 12.0 + touchReaction * 15.0);
            color += dominantColor * specular * (0.8 + audioIntensity * 0.5 + touchReaction * 0.4);
            
            // More reactive rim lighting with dominant color - brighter for contrast
            float rim = pow(1.0 - max(dot(viewDir, normal), 0.0), 3.0);
            color += dominantColor * rim * (0.3 + audioIntensity * 0.4 + touchReaction * 0.2);
            
            // Increase overall contrast
            color = pow(color, float3(0.9)); // Slight darkening for more contrast
            
            // One pixel border that fades in and out in certain areas - stronger pulsing
            float borderPulse = sin(time * 2.0 + angle * 3.0) * 0.5 + 0.5; // Faster fade based on angle and time
            borderPulse *= sin(time * 2.5 + dist * 4.0) * 0.5 + 0.5; // Faster additional fade based on distance
            float borderFade = borderPulse * (0.4 + audioIntensity * 0.5 + touchReaction * 0.3); // Audio reactive with stronger pulsing
            
            // Detect edge (one pixel border)
            float edgeWidth = 0.01; // One pixel width
            float edgeDist = fwidth(shape); // Screen-space derivative for edge detection
            float border = smoothstep(edgeWidth * 0.5, edgeWidth * 1.5, edgeDist);
            
            // Make border appear in certain areas (waveform areas get more border)
            float borderIntensity = border * borderFade * (0.5 + waveformIntensity * 0.5);
            
            // Border color - pure white
            float3 borderColor = float3(1.0, 1.0, 1.0);
            color = mix(color, borderColor, borderIntensity * 0.6);
            
            // Less transparent alpha with smooth edges
            float alpha = smoothstep(0.0, 0.12, shape) * 0.9;
            
            return float4(color, alpha);
        }
        
        kernel void ferrofluidCompute(
            device float2* particles [[buffer(0)]],
            const device Uniforms& uniforms [[buffer(1)]],
            uint id [[thread_position_in_grid]]
        ) {
            if (id >= 1000) return;
            
            float2 pos = particles[id];
            
            float2 center = float2(0.0, 0.0);
            float2 toCenter = center - pos;
            float dist = length(toCenter);
            float angle = atan2(pos.y, pos.x);
            
            // Very subtle dynamic attraction that gently morphs with audio
            float attractionStrength = 0.095 * (1.0 + uniforms.audioLevel * 0.9);
            float2 force = normalize(toCenter) * attractionStrength * (1.0 - dist * 0.88);
            
            // Very gentle fluid flow patterns - audio reactive
            float flowPhase = uniforms.time * 0.5 + float(id) * 0.006;
            float flow1 = sin(angle * 2.0 + flowPhase) * 0.02;
            float flow2 = cos(angle * 3.5 + flowPhase * 1.05) * 0.018;
            float flow3 = sin(dist * 4.5 - flowPhase * 0.5) * 0.015;
            
            float2 flowForce = float2(
                cos(angle + flow1 + flow2) * (0.025 + uniforms.audioLevel * 0.03),
                sin(angle + flow1 + flow2) * (0.025 + uniforms.audioLevel * 0.03)
            );
            force += flowForce;
            
            // Very subtle vorticity for gentle swirling motion - audio reactive
            float vorticity = sin(angle * 2.5 + uniforms.time * 0.7) * 
                             cos(dist * 5.0 + uniforms.time * 0.55) * 
                             uniforms.audioLevel * 0.04;
            float2 vorticityForce = float2(-sin(angle + vorticity), cos(angle + vorticity)) * 0.015;
            force += vorticityForce;
            
            // Very gentle radial waves that push particles - audio reactive
            float radialWave = sin(dist * 7.0 - uniforms.time * 1.1) * 
                              uniforms.audioLevel * 0.03;
            force += normalize(pos) * radialWave;
            
            // Very subtle angular waves - audio reactive
            float angularWave = cos(angle * 5.0 + uniforms.time * 0.9) * 
                               uniforms.audioLevel * 0.02;
            force += float2(-sin(angle + angularWave), cos(angle + angularWave)) * 0.012;
            
            // Repulsion from center (prevents collapse)
            float repulsion = 0.015 * dist;
            force -= normalize(pos) * repulsion;
            
            // Inter-particle forces (simplified)
            float neighborForce = 0.0;
            for (int i = 0; i < 5; i++) {
                uint neighborId = (id + uint(i * 200)) % 1000;
                if (neighborId != id) {
                    float2 neighborPos = particles[neighborId];
                    float2 diff = pos - neighborPos;
                    float neighborDist = length(diff);
                    if (neighborDist > 0.01 && neighborDist < 0.3) {
                        neighborForce += 0.002 / (neighborDist * neighborDist);
                        force += normalize(diff) * neighborForce;
                    }
                }
            }
            
            // Apply forces with gentle damping - audio reactive speed
            float2 velocity = force * (0.01 + uniforms.audioLevel * 0.003);
            pos += velocity;
            
            // Boundary constraint with elastic response
            if (length(pos) > 0.85) {
                float overshoot = length(pos) - 0.85;
                pos = normalize(pos) * (0.85 - overshoot * 0.3);
            }
            
            // Keep particles from getting too close to center
            if (dist < 0.1) {
                pos = normalize(pos) * 0.1;
            }
            
            particles[id] = pos;
        }
        """
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderPipelineState = renderPipelineState else {
            return
        }
        
        time += 0.016 // ~60fps
        
        // Decay touch reaction over time
        touchReaction *= 0.92
        
        // Update uniforms
        let uniforms = Uniforms(
            time: time,
            audioLevel: audioLevel,
            audioFrequency: audioFrequency,
            audioIntensity: audioIntensity,
            touchReaction: touchReaction,
            resolution: simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )
        
        let uniformPointer = uniformBuffer.contents().bindMemory(to: Uniforms.self, capacity: 1)
        uniformPointer.pointee = uniforms
        
        // Compute pass for fluid dynamics
        if let computePipelineState = computePipelineState {
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                return
            }
            
            computeEncoder.setComputePipelineState(computePipelineState)
            computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(uniformBuffer, offset: 0, index: 1)
            
            let threadGroupSize = MTLSize(width: 256, height: 1, depth: 1)
            let threadGroups = MTLSize(
                width: (particleCount + threadGroupSize.width - 1) / threadGroupSize.width,
                height: 1,
                depth: 1
            )
            
            computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        // Render pass
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentBuffer(particleBuffer, offset: 0, index: 1)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

