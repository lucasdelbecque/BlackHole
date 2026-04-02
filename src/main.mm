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
    // Résolution du rendu GPU (pixelisé)
  int W = 640, H = 360;   // moyenne
  //int W = 480, H = 270;   // pixelisé (actuel)
  //int W = 320, H = 180;   // très pixelisé, GPU minimal

    // Taille de la fenêtre d'affichage (indépendante du rendu)
    int WW = 1280, HH = 720;

    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(200, 200, WW, HH)
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
    _metalLayer.frame        = _view.bounds;
    _metalLayer.pixelFormat  = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = NO;
    // Forcer le drawable à la résolution pixelisée — Core Animation upscale en nearest-neighbor
    _metalLayer.drawableSize        = CGSizeMake(W, H);
    _metalLayer.magnificationFilter = kCAFilterNearest;
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
    u.resolution = {640, 270};   // moyenne
  //u.resolution = {480, 270};   // pixelisé (actuel)
  //u.resolution = {320, 180};   // très pixelisé, GPU minimal
    u.diskInner  = 2.6f;
    u.diskOuter  = 12.0f;
    u.gridOpacity = 1.0f;

    // Étoile compagne qui orbite lentement dans le plan équatorial
    float starAngle = time * 0.12f;
    float starOrbitR = 28.0f;
    u.starPos = { starOrbitR * cosf(starAngle), 0.0f,
                  starOrbitR * sinf(starAngle), 2.2f };

    // Matrice viewProj pour la grille (même caméra)
    simd_float3 target = {0, 0, 0};
    simd_float3 up     = {0, 1, 0};

    // View matrix (look-at)
    simd_float3 fwd = simd_normalize(target - pos);
    simd_float3 rgt = simd_normalize(simd_cross(fwd, up));
    up = simd_cross(rgt, fwd);

    simd_float4x4 view = {{
        { rgt.x,  up.x, -fwd.x, 0},
        { rgt.y,  up.y, -fwd.y, 0},
        { rgt.z,  up.z, -fwd.z, 0},
        {-simd_dot(rgt,pos), -simd_dot(up,pos), simd_dot(fwd,pos), 1}
    }};

    // Projection matrix
    float aspect = 640.0f / 360.0f;   // moyenne
  //float aspect = 480.0f / 270.0f;   // pixelisé (actuel)
  //float aspect = 320.0f / 180.0f;   // très pixelisé, GPU minimal
    float fovY   = _camera.fov;
    float near   = 0.1f, far = 200.0f;
    float f      = 1.0f / tanf(fovY * 0.5f);
    simd_float4x4 proj = {{
        {f/aspect, 0,  0,                          0},
        {0,        f,  0,                          0},
        {0,        0,  (far+near)/(near-far),      -1},
        {0,        0,  (2*far*near)/(near-far),     0}
    }};

    // viewProj = proj * view
    simd_float4x4 viewProj = simd_mul(proj, view);

    _renderer->render(u, viewProj, _camera.gridOn);
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