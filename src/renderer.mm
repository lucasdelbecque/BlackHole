#import "renderer.hpp"
#include <stdexcept>

Renderer::Renderer(CAMetalLayer* layer_, int w, int h)
    : layer(layer_), width(w), height(h)
{
    device   = MTLCreateSystemDefaultDevice();
    cmdQueue = [device newCommandQueue];
    layer.device      = device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    // Charger le compute shader
    NSString* execDir = [[[NSBundle mainBundle] executablePath]
        stringByDeletingLastPathComponent];
    NSString* libPath = [execDir stringByAppendingPathComponent:@"blackhole.metallib"];

    NSError* err = nil;
    id<MTLLibrary> lib = [device newLibraryWithFile:libPath error:&err];
    if (!lib) throw std::runtime_error("Impossible de charger blackhole.metallib");

    id<MTLFunction> fn = [lib newFunctionWithName:@"blackholeRender"];
    pipeline = [device newComputePipelineStateWithFunction:fn error:&err];

    // Texture de sortie (ray tracer)
    MTLTextureDescriptor* td = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
        width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageShaderWrite
             | MTLTextureUsageShaderRead
             | MTLTextureUsageRenderTarget;
    outputTex = [device newTextureWithDescriptor:td];

    // Texture depth (pour la grille)
    MTLTextureDescriptor* dd = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
        width:w height:h mipmapped:NO];
    dd.usage       = MTLTextureUsageRenderTarget;
    dd.storageMode = MTLStorageModePrivate;
    depthTex = [device newTextureWithDescriptor:dd];

    // Grille
    grid = new Grid(device, MTLPixelFormatBGRA8Unorm);
}

void Renderer::render(const Uniforms& uniforms,
                      simd_float4x4 viewProj,
                      bool gridOn)
{
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) return;

    id<MTLCommandBuffer> cmdb = [cmdQueue commandBuffer];

    // 1. Compute : ray tracer → outputTex
    {
        id<MTLComputeCommandEncoder> enc = [cmdb computeCommandEncoder];
        [enc setComputePipelineState:pipeline];
        [enc setTexture:outputTex atIndex:0];
        [enc setBytes:&uniforms length:sizeof(Uniforms) atIndex:0];
        MTLSize tg   = MTLSizeMake(16, 16, 1);
        MTLSize grid_= MTLSizeMake((width+15)/16, (height+15)/16, 1);
        [enc dispatchThreadgroups:grid_ threadsPerThreadgroup:tg];
        [enc endEncoding];
    }

    // 2. Grille 3D par-dessus outputTex
    if (gridOn) {
        grid->update();
        grid->draw(cmdb, outputTex, depthTex, viewProj);
    }

    // 3. Blit outputTex → drawable
    {
        id<MTLBlitCommandEncoder> blit = [cmdb blitCommandEncoder];
        [blit copyFromTexture:outputTex
                 sourceSlice:0 sourceLevel:0
                sourceOrigin:MTLOriginMake(0,0,0)
                  sourceSize:MTLSizeMake(width,height,1)
               toTexture:drawable.texture
        destinationSlice:0 destinationLevel:0
       destinationOrigin:MTLOriginMake(0,0,0)];
        [blit endEncoding];
    }

    [cmdb presentDrawable:drawable];
    [cmdb commit];
}

Renderer::~Renderer() {
    delete grid;
}