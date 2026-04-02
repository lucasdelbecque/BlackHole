#pragma once
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <simd/simd.h>
#include <vector>
#include <cmath>

// Vertex simple : position 3D
struct GridVertex {
    simd_float3 pos;
};

class Grid {
public:
    // Paramètres
    int   N         = 40;       // lignes dans chaque direction
    float size      = 50.0f;  // taille totale (grande pour effet infini)
    float RS        = 2.0f;    // rayon de Schwarzschild

    id<MTLDevice>              device;
    id<MTLBuffer>              vertexBuf;
    id<MTLBuffer>              uniformBuf;
    id<MTLRenderPipelineState> pipeline;
    id<MTLDepthStencilState>   depthState;

    int lineCount = 0;

    Grid(id<MTLDevice> dev, MTLPixelFormat colorFmt) : device(dev) {
        buildPipeline(colorFmt);
        buildDepthState();
        update(); // génère le mesh initial
    }

    // Déplace les vertices selon la courbure -RS/r (puits gravitationnel)
    void update() {
        std::vector<GridVertex> verts;
        verts.reserve(N * N * 4 * 2);

        float step = size / float(N - 1);
        float half = size * 0.5f;

        // Grille de points avec déplacement vertical
        // y = -RS / r (approximation Newtonnienne du puits)
        auto warpY = [&](float x, float z) -> float {
            float r = std::sqrt(x*x + z*z);
            float minR = RS * 1.2f;
            r = std::max(r, minR);
            return -RS / r * 2.5f;  // profondeur du puits
        };

        // Lignes dans la direction X (parallèles à X)
        for (int i = 0; i < N; ++i) {
            float z = -half + i * step;
            for (int j = 0; j < N-1; ++j) {
                float x0 = -half + j * step;
                float x1 = -half + (j+1) * step;
                verts.push_back({{ x0, warpY(x0, z), z }});
                verts.push_back({{ x1, warpY(x1, z), z }});
            }
        }

        // Lignes dans la direction Z (parallèles à Z)
        for (int i = 0; i < N; ++i) {
            float x = -half + i * step;
            for (int j = 0; j < N-1; ++j) {
                float z0 = -half + j * step;
                float z1 = -half + (j+1) * step;
                verts.push_back({{ x, warpY(x, z0), z0 }});
                verts.push_back({{ x, warpY(x, z1), z1 }});
            }
        }

        lineCount = (int)verts.size() / 2;

        NSUInteger sz = verts.size() * sizeof(GridVertex);
        vertexBuf = [device newBufferWithBytes:verts.data()
                                        length:sz
                                       options:MTLResourceStorageModeShared];
    }

    void draw(id<MTLCommandBuffer> cmdBuf,
              id<MTLTexture>       colorTex,
              id<MTLTexture>       depthTex,
              simd_float4x4        viewProj)
    {
        MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture     = colorTex;
        pass.colorAttachments[0].loadAction  = MTLLoadActionLoad;   // ne pas effacer
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.depthAttachment.texture         = depthTex;
        pass.depthAttachment.loadAction      = MTLLoadActionClear;
        pass.depthAttachment.storeAction     = MTLStoreActionDontCare;
        pass.depthAttachment.clearDepth      = 1.0;

        id<MTLRenderCommandEncoder> enc =
            [cmdBuf renderCommandEncoderWithDescriptor:pass];

        [enc setRenderPipelineState:pipeline];
        [enc setDepthStencilState:depthState];
        [enc setVertexBuffer:vertexBuf offset:0 atIndex:0];
        [enc setVertexBytes:&viewProj length:sizeof(viewProj) atIndex:1];
        [enc drawPrimitives:MTLPrimitiveTypeLine
                vertexStart:0
                vertexCount:lineCount * 2];
        [enc endEncoding];
    }

private:
    void buildPipeline(MTLPixelFormat colorFmt) {
        // Shader inline (vertex + fragment pour la grille)
        NSString* src = @R"(
#include <metal_stdlib>
using namespace metal;

struct GridVertex { float3 pos; };
struct VertOut {
    float4 pos [[position]];
    float  dist;    // distance au centre (pour la couleur)
};

vertex VertOut gridVert(
    uint vid [[vertex_id]],
    device const GridVertex* verts [[buffer(0)]],
    constant float4x4& mvp [[buffer(1)]])
{
    VertOut o;
    float3 p = verts[vid].pos;
    o.pos  = mvp * float4(p, 1.0);
    o.dist = length(p.xz);
    return o;
}

fragment float4 gridFrag(VertOut in [[stage_in]])
{
    // Blanc-silver, légèrement chaud près du trou noir
    float heat  = exp(-in.dist * 0.10);
    float3 far  = float3(0.55, 0.58, 0.65);   // gris-bleu froid
    float3 near = float3(1.00, 0.88, 0.65);   // or chaud près de l'horizon

    float3 col  = mix(far, near, smoothstep(0.0, 1.0, heat));
    float alpha = 0.35 + heat * 0.45;

    return float4(col, alpha);
}
)";

        NSError* err = nil;
        id<MTLLibrary> lib = [device newLibraryWithSource:src
                                                  options:nil
                                                    error:&err];
        if (!lib) {
            NSLog(@"Grid shader error: %@", err);
            return;
        }

        MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction   = [lib newFunctionWithName:@"gridVert"];
        desc.fragmentFunction = [lib newFunctionWithName:@"gridFrag"];
        desc.colorAttachments[0].pixelFormat          = colorFmt;
        desc.colorAttachments[0].blendingEnabled      = YES;
        desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        desc.colorAttachments[0].destinationRGBBlendFactor
                                                      = MTLBlendFactorOneMinusSourceAlpha;
        desc.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorOne;
        desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorZero;
        desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

        pipeline = [device newRenderPipelineStateWithDescriptor:desc error:&err];
        if (!pipeline) NSLog(@"Grid pipeline error: %@", err);
    }

    void buildDepthState() {
        MTLDepthStencilDescriptor* d = [[MTLDepthStencilDescriptor alloc] init];
        d.depthCompareFunction = MTLCompareFunctionLess;
        d.depthWriteEnabled    = YES;
        depthState = [device newDepthStencilStateWithDescriptor:d];
    }
};