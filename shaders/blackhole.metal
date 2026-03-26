#include <metal_stdlib>
using namespace metal;

constant float M     = 1.0;
constant float RS    = 2.0;
constant int   STEPS = 600;
constant float DT    = 0.08;

struct Uniforms {
    float4x4 camInvView;
    float3   camPos;
    float    time;
    float    fov;
    float2   resolution;
    float    diskInner;
    float    diskOuter;
    float    gridOpacity;   // 0 = grille off, 1 = grille full
};

// ---- Accélération gravitationnelle ----
float3 geodesicAccel(float3 pos, float3 vel) {
    float r  = length(pos);
    float r2 = r * r;
    float r3 = r2 * r;
    float r5 = r3 * r2;
    float vr = dot(vel, pos) / r;

    return -(M / r3) * pos
           + (3.0 * M / r5) * dot(pos, vel) * pos
           - (2.0 * M / r3) * vel * r * vr;
}

// ---- Grille de courbure spatiotemporelle ----
// On projette une grille infinie dans le plan XZ
// et on mesure à quelle distance le rayon passe d'une ligne
float gridValue(float3 worldPos, float gridScale) {
    float2 gp   = worldPos.xz / gridScale;
    float2 grid = abs(fract(gp - 0.5) - 0.5);
    // Traits très fins, style Blender
    float lineW = 0.012;
    float2 lines = smoothstep(lineW, 0.0, grid);
    return max(lines.x, lines.y);
}

float3 gridColor(float3 worldPos, float distortion) {
    float r = length(worldPos);
    // Juste blanc/cyan très subtil, pas de rouge/orange
    float fade = exp(-r * 0.05);
    float3 col = mix(float3(0.0, 0.5, 0.7), float3(0.8, 0.95, 1.0), fade);
    return col * (0.3 + fade * 0.5);
}

// ---- Disque d'accrétion style Interstellar ----
float3 diskColor(float r, float phi, float time) {
    float rNorm = (r - 2.6) / (12.0 - 2.6);
    float temp  = pow(1.0 - rNorm * 0.85, 3.0);

    float3 white  = float3(1.00, 0.95, 0.85);
    float3 orange = float3(1.00, 0.55, 0.15);
    float3 red    = float3(0.60, 0.10, 0.02);

    float3 col = mix(red, orange, smoothstep(0.0, 0.4, temp));
    col        = mix(col, white,  smoothstep(0.4, 1.0, temp));

    float omega = 1.0 / pow(max(r, 2.7), 1.5);
    float angle = phi + omega * time * 0.4;
    float turb  = 0.75 + 0.25 * (
            sin(angle * 6.0 + r * 2.0) *
            sin(angle * 3.7 - r * 1.3)
    );

    float bright = mix(3.5, 0.8, rNorm);

    float doppler     = 1.0 + 0.5 * sin(angle);
    float3 dopplerTint = mix(
            float3(1.0, 0.7, 0.4),
            float3(1.0, 1.0, 0.9),
            clamp(doppler, 0.0, 1.0)
    );

    return col * dopplerTint * turb * bright;
}

// ---- Étoiles procédurales ----
float3 starfield(float3 dir) {
    float3 col = float3(0.0);
    for (int layer = 0; layer < 2; layer++) {
        float  scale = layer == 0 ? 150.0 : 400.0;
        float3 p     = dir * scale;
        float3 ip    = floor(p);
        float3 fp    = fract(p);
        for (int i = -1; i <= 1; i++)
            for (int j = -1; j <= 1; j++)
                for (int k = -1; k <= 1; k++) {
                    float3 id     = ip + float3(i, j, k);
                    float3 h      = fract(sin(id * float3(127.1, 311.7, 74.7)) * 43758.5);
                    float3 off    = h - 0.5 + float3(i, j, k);
                    float  d      = length(fp - (off + 0.5));
                    float  size   = layer == 0 ? 12.0 : 18.0;
                    float  bright = pow(max(0.0, 1.0 - d * size), 5.0);
                    float3 sc     = mix(float3(0.85, 0.90, 1.00),
                                        float3(1.00, 0.95, 0.85), h.z);
                    col += sc * bright * (0.5 + 0.5 * h.x) * (layer == 0 ? 1.0 : 0.3);
                }
    }
    return col;
}

// ---- Shader principal ----
kernel void blackholeRender(
        texture2d<float, access::write> output [[texture(0)]],
        constant Uniforms& u                   [[buffer(0)]],
uint2 gid                              [[thread_position_in_grid]])
{
uint2 size = uint2(u.resolution);
if (gid.x >= size.x || gid.y >= size.y) return;

float2 uv = (float2(gid) - float2(size) * 0.5) / float(size.y);

float3 rayDir = normalize(float3(uv.x, uv.y, -1.0 / tan(u.fov * 0.5)));
rayDir = normalize((u.camInvView * float4(rayDir, 0.0)).xyz);

float3 pos   = u.camPos;
float3 vel   = rayDir;

float3 color       = float3(0.0);
float3 diskAccum   = float3(0.0);
float  diskOpacity = 0.0;

// Accumulation de la grille
float3 gridAccum   = float3(0.0);
float  gridAlpha   = 0.0;

// Échelle de la grille (espacement des lignes en unités monde)
float gridScale = 2.0;

for (int i = 0; i < STEPS; ++i) {
float r = length(pos);

// Capturé
if (r < RS * 1.01) {
color = float3(0.0);
break;
}

// Échappé
if (r > 100.0) {
color = starfield(normalize(vel));
break;
}

// ---- Grille dans le plan XZ (plan équatorial) ----
// On détecte le passage du rayon dans le plan y ≈ 0
float3 nextPos = pos + vel * DT;

if (u.gridOpacity > 0.0 && abs(pos.y) < 0.12 && r > RS * 1.5 && r < 50.0) {
float planeW = exp(-pos.y * pos.y / 0.008);  // plan plus fin

if (planeW > 0.01) {
float gv = gridValue(pos, gridScale);
if (gv > 0.01) {
float3 gc  = gridColor(pos, 0.0);
float  fade  = 1.0 - smoothstep(15.0, 45.0, r);
float  alpha = gv * planeW * fade * u.gridOpacity * 0.6
               * (1.0 - gridAlpha);
gridAccum += gc * alpha;
gridAlpha += alpha * 0.5;
gridAlpha  = min(gridAlpha, 1.0);
}
}
}

// ---- Disque d'accrétion ----
if (pos.y * nextPos.y < 0.0 && diskOpacity < 0.98) {
float  t   = -pos.y / vel.y;
float3 hp  = pos + vel * t;
float  rd  = length(hp.xz);

if (rd > u.diskInner && rd < u.diskOuter) {
float  phi = atan2(hp.z, hp.x);
float3 dc  = diskColor(rd, phi, u.time);
float  alpha = clamp(dc.r * 0.4 + 0.3, 0.0, 1.0)
               * (1.0 - diskOpacity);
diskAccum   += dc * alpha;
diskOpacity += alpha;
}
}

// ---- RK4 ----
float3 a1 = geodesicAccel(pos, vel);
float3 p2 = pos + 0.5*DT*vel,  v2 = vel + 0.5*DT*a1;
float3 a2 = geodesicAccel(p2, v2);
float3 p3 = pos + 0.5*DT*v2,   v3 = vel + 0.5*DT*a2;
float3 a3 = geodesicAccel(p3, v3);
float3 p4 = pos + DT*v3,        v4 = vel + DT*a3;
float3 a4 = geodesicAccel(p4, v4);

pos += (DT/6.0) * (vel + 2.0*v2 + 2.0*v3 + v4);
vel += (DT/6.0) * (a1  + 2.0*a2 + 2.0*a3 + a4);
}

// ---- Composition ----
// 1. Fond étoilé + disque
float3 final = color * (1.0 - diskOpacity) + diskAccum;

// 2. Grille par-dessus (additive, elle brille)
final += gridAccum * (1.0 - diskOpacity * 0.5);

// 3. Halo de la photon sphere
/*float screenR  = length(uv);
float shadowR  = 3.0 * sqrt(3.0) * M / length(u.camPos);
float halo     = exp(-pow((screenR - shadowR * 0.9) / 0.015, 2.0)) * 0.4;
final         += float3(1.0, 0.45, 0.05) * halo;*/

// 4. Tone mapping ACES
float a = 2.51, b = 0.03, c2 = 2.43, d = 0.59, e = 0.14;
final = clamp((final*(a*final+b))/(final*(c2*final+d)+e), 0.0, 1.0);

// 5. Gamma
final = pow(final, float3(1.0 / 2.2));

// 6. Vignette
float vign = 1.0 - 0.25 * dot(uv * 1.5, uv * 1.5);
final *= clamp(vign, 0.0, 1.0);

output.write(float4(final, 1.0), gid);
}