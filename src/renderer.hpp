// renderer.hpp
#pragma once
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <simd/simd.h>

struct Uniforms {
    simd_float4x4 camInvView;
    simd_float3   camPos;
    float         time;
    float         fov;
    simd_float2   resolution;
    float         diskInner;
    float         diskOuter;
    float         gridOpacity;
};

class Renderer {
public:
    Renderer(CAMetalLayer* layer, int width, int height);
    void render(const Uniforms& uniforms);
    ~Renderer();
private:
    id<MTLDevice>              device;
    id<MTLCommandQueue>        cmdQueue;
    id<MTLComputePipelineState>pipeline;
    id<MTLTexture>             outputTex;
    CAMetalLayer*              layer;
    int width, height;
};