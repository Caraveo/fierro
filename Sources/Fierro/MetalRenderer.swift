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
    
    var quadVertexBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!
    
    let particleCount = 1000
    var particleBuffer: MTLBuffer!
    
    struct Uniforms {
        var time: Float
        var audioLevel: Float
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
            float2 resolution;
        };
        
        vertex VertexOut vertexShader(
            const device float4* vertices [[buffer(0)]],
            uint vid [[vertex_id]]
        ) {
            VertexOut out;
            float4 vertex = vertices[vid];
            out.position = float4(vertex.xy, 0.0, 1.0);
            out.uv = vertex.zw;
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
            float2 resolution = uniforms.resolution;
            
            float2 coord = (uv - 0.5) * 2.0;
            coord.x *= resolution.x / resolution.y;
            
            float dist = length(coord);
            
            float density = 0.0;
            int sampleCount = min(200, 1000);
            for (int i = 0; i < sampleCount; i += 5) {
                float2 particlePos = particles[i];
                float2 diff = coord - particlePos;
                float particleDist = length(diff);
                density += exp(-particleDist * 12.0) * 0.005;
            }
            
            float noise = 0.0;
            float2 p = coord * 3.0;
            for (int i = 0; i < 4; i++) {
                noise += sin(p.x + time * 0.5) * cos(p.y + time * 0.3) * 0.5;
                p *= 2.0;
                noise *= 0.5;
            }
            
            float baseRadius = 0.4 + audioLevel * 0.15;
            float blob = 1.0 - smoothstep(baseRadius, baseRadius + 0.3, dist + noise * 0.15 + density * 2.0);
            
            float spikes = 0.0;
            float angle = atan2(coord.y, coord.x);
            for (int i = 0; i < 12; i++) {
                float spikeAngle = (float(i) / 12.0) * 3.14159 * 2.0 + time * 0.5;
                float spikeDist = dist - baseRadius - 0.1;
                float spikeIntensity = sin((angle - spikeAngle) * 6.0 + time * 3.0) * 0.5 + 0.5;
                float spike = exp(-spikeDist * 8.0) * spikeIntensity * (0.3 + audioLevel * 0.4);
                spikes += spike;
            }
            spikes = smoothstep(0.2, 0.6, spikes);
            
            float shape = max(blob, spikes * 0.7);
            
            float eps = 0.01;
            float ddx = length(coord + float2(eps, 0.0)) - length(coord - float2(eps, 0.0));
            float ddy = length(coord + float2(0.0, eps)) - length(coord - float2(0.0, eps));
            float3 normal = normalize(float3(-ddx, -ddy, 1.0));
            
            float3 viewDir = normalize(float3(coord, 1.0));
            float fresnel = pow(1.0 - max(dot(viewDir, normal), 0.0), 2.0);
            
            float3 baseColor = float3(0.02, 0.02, 0.03);
            float3 highlightColor = float3(0.9, 0.95, 1.0) * fresnel;
            float3 color = mix(baseColor, highlightColor, fresnel * 0.6 + audioLevel * 0.4);
            
            float3 lightDir = normalize(float3(0.3, 0.5, 1.0));
            float specular = pow(max(dot(reflect(-lightDir, normal), viewDir), 0.0), 64.0);
            color += float3(1.0, 1.0, 1.0) * specular * (0.8 + audioLevel * 0.5);
            
            float rim = pow(1.0 - max(dot(viewDir, normal), 0.0), 3.0);
            color += float3(0.5, 0.6, 0.7) * rim * 0.3;
            
            float alpha = smoothstep(0.0, 0.1, shape) * 0.98;
            
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
            
            float attraction = 0.1 * (1.0 + uniforms.audioLevel * 2.0);
            float2 force = normalize(toCenter) * attraction * (1.0 - dist);
            
            float angle = atan2(pos.y, pos.x);
            float noise = sin(angle * 5.0 + uniforms.time * 2.0) * 
                          cos(dist * 8.0 + uniforms.time * 1.5) * 
                          uniforms.audioLevel * 0.2;
            force += float2(cos(angle + noise), sin(angle + noise)) * 0.05;
            
            float repulsion = 0.01;
            force -= normalize(pos) * repulsion * dist;
            
            pos += force * 0.01;
            
            if (length(pos) > 0.9) {
                pos = normalize(pos) * 0.9;
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
        
        // Update uniforms
        let uniforms = Uniforms(
            time: time,
            audioLevel: audioLevel,
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

