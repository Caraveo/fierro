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
    var touchReaction: Float = 0.0 // Visual reaction to touch
    private var debugCounter = 0
    
    var quadVertexBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!
    
    let particleCount = 1000
    var particleBuffer: MTLBuffer!
    
    struct Uniforms {
        var time: Float
        var audioLevel: Float
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
        // Debug: print occasionally
        debugCounter += 1
        if debugCounter % 60 == 0 {
            print("Renderer received audio level: \(level)")
        }
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
            float touchReaction = uniforms.touchReaction;
            float2 resolution = uniforms.resolution;
            
            float2 coord = (uv - 0.5) * 2.0;
            coord.x *= resolution.x / resolution.y;
            
            // Scale down the orb to fit better in the window
            coord /= 0.32;
              
            // Very subtle fluid morphing with gentle frequencies
            float morphPhase = time * 0.25 + audioLevel * 0.5;
            float morph1 = sin(morphPhase) * 0.04;
            float morph2 = cos(morphPhase * 1.1) * 0.03;
            float morph3 = sin(morphPhase * 1.6 + 1.0) * 0.025;
            
            // Very subtle warp the coordinate space for gentle fluid flow
            float2 warpedCoord = coord;
            warpedCoord.x += sin(coord.y * 1.2 + time * 0.5) * 0.02 * (0.2 + audioLevel * 0.15);
            warpedCoord.y += cos(coord.x * 1.2 + time * 0.45) * 0.02 * (0.2 + audioLevel * 0.15);
            
            float dist = length(warpedCoord);
            float angle = atan2(warpedCoord.y, warpedCoord.x);
            
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
            
            // Very subtle dynamic base radius that gently morphs with audio and touch
            float baseRadius = 0.39 + audioLevel * 0.08 + morph1 * 0.03 + touchReaction * 0.15;
            
            // Very subtle radial distortion for gentle fluid waves - enhanced by touch
            float radialWave = sin(dist * 5.0 - time * 0.8) * 0.015 * (0.15 + audioLevel * 0.2 + touchReaction * 0.3);
            float angularWave = sin(angle * 3.0 + time * 0.6) * 0.012 * (0.15 + audioLevel * 0.2 + touchReaction * 0.25);
            
            // Main blob with subtle morphing
            float blobDist = dist + noise * 0.1 + density * 1.2 + radialWave + angularWave;
            float blob = 1.0 - smoothstep(baseRadius, baseRadius + 0.35, blobDist);
            
            // Very subtle dynamic spikes/tendrils that gently morph - always visible, audio and touch reactive
            float spikes = 0.0;
            int spikeCount = 6 + int(audioLevel * 2.5) + int(touchReaction * 4.0); // Increase with audio and touch
            for (int i = 0; i < spikeCount; i++) {
                float spikeAngle = (float(i) / float(spikeCount)) * 3.14159 * 2.0 + time * 0.3 + morph2;
                float spikeDist = dist - baseRadius - 0.12;
                
                // Gentle morphing spike intensity - always visible base, reacts to audio and touch
                float spikePhase = (angle - spikeAngle) * 5.0 + time * 1.5 + morph3;
                float spikeIntensity = sin(spikePhase) * 0.35 + 0.65;
                spikeIntensity = pow(spikeIntensity, 1.05 + audioLevel * 0.15 + touchReaction * 0.2);
                
                // Subtle variable spike length - reacts to audio and touch
                float spikeLength = 0.14 + audioLevel * 0.12 + touchReaction * 0.18 + sin(time * 0.9 + float(i)) * 0.03;
                // Make spikes visible even at low audio, but grow with audio and touch
                float spike = exp(-spikeDist * 4.5) * spikeIntensity * (0.35 + audioLevel * 0.25 + touchReaction * 0.4);
                
                // Subtle secondary tendrils - always visible, audio and touch reactive
                float tendrilAngle = spikeAngle + 0.2;
                float tendrilDist = dist - baseRadius - 0.14;
                float tendril = exp(-tendrilDist * 5.5) * 
                               (sin((angle - tendrilAngle) * 7.0 + time * 1.8) * 0.15 + 0.45) *
                               (0.18 + audioLevel * 0.15 + touchReaction * 0.25);
                
                spikes += spike + tendril;
            }
            spikes = smoothstep(0.18, 0.42, spikes);
            
            // Combine blob and spikes with subtle morphing blend - audio reactive
            float shape = max(blob, spikes * (0.48 + audioLevel * 0.12));
            
            // Very subtle surface ripples - audio and touch reactive
            float ripple = sin(dist * 10.0 - time * 1.2) * 
                          cos(angle * 5.0 + time * 1.0) * 
                          (audioLevel * 0.015 + touchReaction * 0.03);
            shape += ripple;
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
            
            // Very subtle dynamic color that gently shifts with morphing - audio and touch reactive
            float3 baseColor = float3(0.02, 0.02, 0.03);
            float3 highlightColor = float3(0.9, 0.95, 1.0) * fresnel;
            float colorShift = sin(time * 0.2) * 0.02;
            highlightColor += float3(colorShift, colorShift * 0.5, 0.0);
            float3 color = mix(baseColor, highlightColor, fresnel * 0.62 + audioLevel * 0.25 + touchReaction * 0.2);
            
            // Very subtle specular with gentle audio and touch reactivity
            float3 lightDir = normalize(float3(0.3, 0.5, 1.0));
            float specular = pow(max(dot(reflect(-lightDir, normal), viewDir), 0.0), 58.0 + audioLevel * 8.0 + touchReaction * 15.0);
            color += float3(1.0, 1.0, 1.0) * specular * (0.65 + audioLevel * 0.3 + touchReaction * 0.4);
            
            // Very subtle rim lighting - audio and touch reactive
            float rim = pow(1.0 - max(dot(viewDir, normal), 0.0), 3.0);
            color += float3(0.6, 0.7, 0.8) * rim * (0.25 + audioLevel * 0.15 + touchReaction * 0.2);
            
            // Alpha with smooth edges
            float alpha = smoothstep(0.0, 0.12, shape) * 0.98;
            
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

