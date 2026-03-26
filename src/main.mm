#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#include "renderer.hpp"
#include "camera.hpp"
#include <simd/simd.h>
#include <cmath>

// ---- Vue Metal avec trackpad ----
@interface MetalView : NSView
@property (nonatomic) Camera* camera;
@end

@implementation MetalView

- (BOOL)acceptsFirstResponder { return YES; }

// Trackpad : deux doigts = zoom, un doigt = orbite
- (void)scrollWheel:(NSEvent*)e {
    if (e.phase != NSEventPhaseNone || e.momentumPhase != NSEventPhaseNone) {
        // Geste trackpad deux doigts (scroll)
        _camera->zoom((float)e.deltaY * 0.3f);
    }
}

- (void)mouseDragged:(NSEvent*)e {
    _camera->orbit((float)e.deltaX, (float)e.deltaY);
}

// Trackpad : pinch zoom
- (void)magnifyWithEvent:(NSEvent*)e {
    _camera->zoom(-(float)e.magnification * 15.0f);
}

- (void)keyDown:(NSEvent*)e {
    if (e.keyCode == 5) {   // touche G
        _camera->gridOn = !_camera->gridOn;
    }
}

@end

// ---- Delegate principal ----
@interface AppDelegate : NSObject<NSApplicationDelegate>
@property (nonatomic, strong) NSWindow*   window;
@property (nonatomic, strong) MetalView*  view;
@property (nonatomic, strong) CAMetalLayer* metalLayer;
@property (nonatomic)         Renderer*   renderer;
@property (nonatomic)         Camera      camera;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)n {
    int W = 1280, H = 720;

    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(200, 200, W, H)
        styleMask:NSWindowStyleMaskTitled |
                  NSWindowStyleMaskResizable |
                  NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    [_window setTitle:@"Black Hole — Interstellar"];
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_window.contentView];

    _view = [[MetalView alloc] initWithFrame:_window.contentView.bounds];
    _view.wantsLayer = YES;
    _view.camera     = &_camera;
    [_window.contentView addSubview:_view];
    [_window makeFirstResponder:_view];

    // Activer les gestes trackpad
    [_view setAllowedTouchTypes:NSTouchTypeMaskIndirect];

    _metalLayer = [CAMetalLayer layer];
    _metalLayer.frame       = _view.bounds;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = NO;
    [_view.layer addSublayer:_metalLayer];

    _renderer = new Renderer(_metalLayer, W, H);
    _camera   = Camera{};

    [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
        target:self selector:@selector(renderFrame:)
        userInfo:nil repeats:YES];
}

- (void)renderFrame:(NSTimer*)t {
    static float time = 0.0f;
    time += 1.0f / 60.0f;

    simd_float3 pos = _camera.position();

    Uniforms u;
    u.camPos     = pos;
    u.camInvView = _camera.invViewMatrix();
    u.time       = time;
    u.fov        = _camera.fov;
    u.resolution = {1280, 720};
    u.diskInner  = 2.6f;
    u.diskOuter  = 12.0f;
    u.gridOpacity = 1.0f;
    u.gridOpacity = _camera.gridOn ? 1.0f : 0.0f;

    _renderer->render(u);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)a {
    return YES;
}

@end

int main() {
    NSApplication* app = [NSApplication sharedApplication];
    AppDelegate*   del = [[AppDelegate alloc] init];
    [app setDelegate:del];
    [app run];
    return 0;
}