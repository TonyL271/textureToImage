#include <metal_stdlib>
using namespace metal;

// Vertex shader outputs and fragment shader inputs
struct RasterizerData {
    float4 position [[position]];
    float2 texCoord;
};

// 2D Vertex shader
vertex RasterizerData vertex2DShader(uint vertexID [[vertex_id]],
                                  constant float2 *positions [[buffer(0)]]) {
    RasterizerData out;
    
    // Convert 2D position to clip space position (4D)
    out.position = float4(positions[vertexID], 0.0, 1.0);
    
    // Convert from clip space to texture coordinates
    out.texCoord = float2((positions[vertexID].x + 1.0) * 0.5,
                         1.0 - (positions[vertexID].y + 1.0) * 0.5);
    return out;
}

// 2D Fragment shader
fragment float4 fragment2DShader(RasterizerData in [[stage_in]],
                             texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return texture.sample(textureSampler, in.texCoord);
}
