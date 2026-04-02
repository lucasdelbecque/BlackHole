#pragma once
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <simd/simd.h>
#include "grid.hpp"

struct Uniforms {
    simd_float4x4 camInvView;
    simd_float3   camPos;
    float         time;
    float         fov;
    simd_float2   resolution;
    float         diskInner;
    float         diskOuter;
    float         gridOpacity;
    simd_float4   starPos;
};

class Renderer {
public:
    Renderer(CAMetalLayer* layer, int width, int height);
    void render(const Uniforms& uniforms, simd_float4x4 viewProj, bool gridOn);
    ~Renderer();

private:
    id<MTLDevice>              device;
    id<MTLCommandQueue>        cmdQueue;
    id<MTLComputePipelineState>pipeline;
    id<MTLTexture>             outputTex;
    id<MTLTexture>             depthTex;
    CAMetalLayer*              layer;
    Grid*                      grid;
    int width, height;
};