// renderer.mm
#import "renderer.hpp"
#import <Metal/Metal.h>
#include <stdexcept>
#include <string>

Renderer::Renderer(CAMetalLayer* layer_, int w, int h)
        : layer(layer_), width(w), height(h)
{
    device   = MTLCreateSystemDefaultDevice();
    cmdQueue = [device newCommandQueue];
    layer.device = device;

    // Charger le .metallib compilé
    NSString* libPath = [[NSBundle mainBundle]
            pathForResource:@"blackhole" ofType:@"metallib"];
    if (!libPath) {
        // En mode développement, chercher à côté de l'exécutable
        NSString* execDir = [[[NSBundle mainBundle] executablePath]
                stringByDeletingLastPathComponent];
        libPath = [execDir stringByAppendingPathComponent:@"blackhole.metallib"];
    }

    NSError* err = nil;
    id<MTLLibrary> lib = [device newLibraryWithFile:libPath error:&err];
    if (!lib) throw std::runtime_error("Impossible de charger blackhole.metallib");

    id<MTLFunction> fn = [lib newFunctionWithName:@"blackholeRender"];
    pipeline = [device newComputePipelineStateWithFunction:fn error:&err];

    // Texture de sortie
    MTLTextureDescriptor* desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                         width:w height:h mipmapped:NO];
    desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    outputTex  = [device newTextureWithDescriptor:desc];
}

void Renderer::render(const Uniforms& uniforms) {
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) return;

    id<MTLCommandBuffer>      cmdb   = [cmdQueue commandBuffer];
    id<MTLComputeCommandEncoder> enc = [cmdb computeCommandEncoder];

    [enc setComputePipelineState:pipeline];
    [enc setTexture:outputTex atIndex:0];
    [enc setBytes:&uniforms length:sizeof(Uniforms) atIndex:0];

    MTLSize threadgroup = MTLSizeMake(16, 16, 1);
    MTLSize grid = MTLSizeMake(
            (width  + 15) / 16,
            (height + 15) / 16, 1);
    [enc dispatchThreadgroups:grid threadsPerThreadgroup:threadgroup];
    [enc endEncoding];

    // Blit outputTex → drawable
    id<MTLBlitCommandEncoder> blit = [cmdb blitCommandEncoder];
    [blit copyFromTexture:outputTex
              sourceSlice:0 sourceLevel:0
             sourceOrigin:MTLOriginMake(0,0,0)
               sourceSize:MTLSizeMake(width,height,1)
                toTexture:drawable.texture
         destinationSlice:0 destinationLevel:0
        destinationOrigin:MTLOriginMake(0,0,0)];
    [blit endEncoding];

    [cmdb presentDrawable:drawable];
    [cmdb commit];
}

Renderer::~Renderer() {}