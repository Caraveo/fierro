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

// Vertex shader for full-screen quad
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

// Fragment shader - glossy black ferrofluid
fragment float4 fragmentShader(
    VertexOut in [[stage_in]],
    const device Uniforms& uniforms [[buffer(0)]],
    const device float2* particles [[buffer(1)]]
) {
    float2 uv = in.uv;
    float time = uniforms.time;
    float audioLevel = uniforms.audioLevel;
    float2 resolution = uniforms.resolution;
    
    // Convert UV to centered coordinates
    float2 coord = (uv - 0.5) * 2.0;
    coord.x *= resolution.x / resolution.y; // Aspect ratio correction
    
    float dist = length(coord);
    
    // Sample particles to create fluid density field (sample subset for performance)
    float density = 0.0;
    int sampleCount = min(200, 1000); // Sample subset for performance
    for (int i = 0; i < sampleCount; i += 5) {
        float2 particlePos = particles[i];
        float2 diff = coord - particlePos;
        float particleDist = length(diff);
        density += exp(-particleDist * 12.0) * 0.005;
    }
    
    // Create fluid blob shape with noise
    float noise = 0.0;
    float2 p = coord * 3.0;
    for (int i = 0; i < 4; i++) {
        noise += sin(p.x + time * 0.5) * cos(p.y + time * 0.3) * 0.5;
        p *= 2.0;
        noise *= 0.5;
    }
    
    // Base blob with audio reactivity and particle density
    float baseRadius = 0.4 + audioLevel * 0.15;
    float blob = 1.0 - smoothstep(baseRadius, baseRadius + 0.3, dist + noise * 0.15 + density * 2.0);
    
    // Add spikes/tendrils (ferrofluid spikes)
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
    
    // Combine blob and spikes
    float shape = max(blob, spikes * 0.7);
    
    // Calculate surface normal from gradient
    float eps = 0.01;
    float ddx = length(coord + float2(eps, 0.0)) - length(coord - float2(eps, 0.0));
    float ddy = length(coord + float2(0.0, eps)) - length(coord - float2(0.0, eps));
    float3 normal = normalize(float3(-ddx, -ddy, 1.0));
    
    // Glossy reflection
    float3 viewDir = normalize(float3(coord, 1.0));
    float fresnel = pow(1.0 - max(dot(viewDir, normal), 0.0), 2.0);
    
    // Metallic black with glossy highlights
    float3 baseColor = float3(0.02, 0.02, 0.03);
    float3 highlightColor = float3(0.9, 0.95, 1.0) * fresnel;
    float3 color = mix(baseColor, highlightColor, fresnel * 0.6 + audioLevel * 0.4);
    
    // Add specular highlights
    float3 lightDir = normalize(float3(0.3, 0.5, 1.0));
    float specular = pow(max(dot(reflect(-lightDir, normal), viewDir), 0.0), 64.0);
    color += float3(1.0, 1.0, 1.0) * specular * (0.8 + audioLevel * 0.5);
    
    // Add rim lighting
    float rim = pow(1.0 - max(dot(viewDir, normal), 0.0), 3.0);
    color += float3(0.5, 0.6, 0.7) * rim * 0.3;
    
    // Alpha based on shape with smooth edges
    float alpha = smoothstep(0.0, 0.1, shape) * 0.98;
    
    return float4(color, alpha);
}

// Compute shader for fluid dynamics
kernel void ferrofluidCompute(
    device float2* particles [[buffer(0)]],
    const device Uniforms& uniforms [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= 1000) return;
    
    float2 pos = particles[id];
    
    // Magnetic field forces
    float2 center = float2(0.0, 0.0);
    float2 toCenter = center - pos;
    float dist = length(toCenter);
    
    // Attraction to center with audio modulation
    float attraction = 0.1 * (1.0 + uniforms.audioLevel * 2.0);
    float2 force = normalize(toCenter) * attraction * (1.0 - dist);
    
    // Perlin-like noise for organic movement
    float angle = atan2(pos.y, pos.x);
    float noise = sin(angle * 5.0 + uniforms.time * 2.0) * 
                  cos(dist * 8.0 + uniforms.time * 1.5) * 
                  uniforms.audioLevel * 0.2;
    force += float2(cos(angle + noise), sin(angle + noise)) * 0.05;
    
    // Repulsion from other particles (simplified)
    float repulsion = 0.01;
    force -= normalize(pos) * repulsion * dist;
    
    // Update position
    pos += force * 0.01;
    
    // Boundary constraint
    if (length(pos) > 0.9) {
        pos = normalize(pos) * 0.9;
    }
    
    particles[id] = pos;
}

