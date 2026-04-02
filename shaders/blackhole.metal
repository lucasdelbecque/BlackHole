#include <metal_stdlib>
using namespace metal;

constant float RS    = 2.0;   // rayon de Schwarzschild (unités géom., M=1)
constant int   STEPS = 1500;
constant float DT    = 0.07;

struct Uniforms {
    float4x4 camInvView;
    float3   camPos;
    float    time;
    float    fov;
    float2   resolution;
    float    diskInner;
    float    diskOuter;
    float    gridOpacity;
    float4   starPos;    // xyz = position, w = rayon
};

// ---- Rayon en coordonnées sphériques ----
struct RaySph {
    float r, theta, phi;
    float dr, dtheta, dphi;
    float E, L;
};

RaySph initRay(float3 pos, float3 dir) {
    RaySph ray;
    ray.r     = length(pos);
    ray.theta = acos(clamp(pos.y / ray.r, -1.0, 1.0));
    ray.phi   = atan2(pos.z, pos.x);

    float st = sin(ray.theta), ct = cos(ray.theta);
    float sp = sin(ray.phi),   cp = cos(ray.phi);

    ray.dr     =  st*cp*dir.x + st*sp*dir.z + ct*dir.y;
    ray.dtheta = (ct*cp*dir.x + ct*sp*dir.z - st*dir.y) / ray.r;
    ray.dphi   = (-sp*dir.x   + cp*dir.z) / (ray.r * st);

    ray.L = ray.r * ray.r * st * ray.dphi;
    float f    = 1.0 - RS / ray.r;
    float dtdL = sqrt((ray.dr*ray.dr)/f
                      + ray.r*ray.r*(ray.dtheta*ray.dtheta
                                     + st*st*ray.dphi*ray.dphi));
    ray.E = f * dtdL;
    return ray;
}

// ---- Équations géodésiques nulles de Schwarzschild ----
void geodesicRHS(RaySph ray, thread float3& d1, thread float3& d2) {
    float r   = ray.r,  theta = ray.theta;
    float dr  = ray.dr, dth   = ray.dtheta, dph = ray.dphi;
    float f   = 1.0 - RS / r;
    float dtdL = ray.E / f;
    float st  = sin(theta), ct = cos(theta);

    d1 = float3(dr, dth, dph);

    d2.x = -(RS / (2.0*r*r)) * f * dtdL*dtdL
           +(RS / (2.0*r*r*f)) * dr*dr
           + r * (dth*dth + st*st*dph*dph);
    d2.y = -2.0*dr*dth/r + st*ct*dph*dph;
    d2.z = -2.0*dr*dph/r - 2.0*(ct/st)*dth*dph;
}

// ---- Intégrateur RK4 (remplace l'Euler d'avant) ----
void stepRK4(thread RaySph& ray, float dL) {
    float3 k1a, k1b;
    geodesicRHS(ray, k1a, k1b);

    RaySph r2 = ray;
    r2.r      += dL*0.5*k1a.x; r2.theta  += dL*0.5*k1a.y; r2.phi    += dL*0.5*k1a.z;
    r2.dr     += dL*0.5*k1b.x; r2.dtheta += dL*0.5*k1b.y; r2.dphi   += dL*0.5*k1b.z;
    float3 k2a, k2b;
    geodesicRHS(r2, k2a, k2b);

    RaySph r3 = ray;
    r3.r      += dL*0.5*k2a.x; r3.theta  += dL*0.5*k2a.y; r3.phi    += dL*0.5*k2a.z;
    r3.dr     += dL*0.5*k2b.x; r3.dtheta += dL*0.5*k2b.y; r3.dphi   += dL*0.5*k2b.z;
    float3 k3a, k3b;
    geodesicRHS(r3, k3a, k3b);

    RaySph r4 = ray;
    r4.r      += dL*k3a.x; r4.theta  += dL*k3a.y; r4.phi    += dL*k3a.z;
    r4.dr     += dL*k3b.x; r4.dtheta += dL*k3b.y; r4.dphi   += dL*k3b.z;
    float3 k4a, k4b;
    geodesicRHS(r4, k4a, k4b);

    float inv6 = dL / 6.0;
    ray.r      += inv6 * (k1a.x + 2*k2a.x + 2*k3a.x + k4a.x);
    ray.theta  += inv6 * (k1a.y + 2*k2a.y + 2*k3a.y + k4a.y);
    ray.phi    += inv6 * (k1a.z + 2*k2a.z + 2*k3a.z + k4a.z);
    ray.dr     += inv6 * (k1b.x + 2*k2b.x + 2*k3b.x + k4b.x);
    ray.dtheta += inv6 * (k1b.y + 2*k2b.y + 2*k3b.y + k4b.y);
    ray.dphi   += inv6 * (k1b.z + 2*k2b.z + 2*k3b.z + k4b.z);
}

float3 sphToCart(RaySph ray) {
    float st = sin(ray.theta), ct = cos(ray.theta);
    float sp = sin(ray.phi),   cp = cos(ray.phi);
    return ray.r * float3(st*cp, ct, st*sp);
}

// ---- Disque d'accrétion ----
float3 diskColor(float r, float phi, float time) {
    float rNorm = clamp((r - 2.6) / (12.0 - 2.6), 0.0, 1.0);

    // Gradient de température : blanc chaud au bord interne → orange → rouge
    float temp    = pow(1.0 - rNorm * 0.85, 3.0);
    float3 white  = float3(1.00, 0.97, 0.88);
    float3 orange = float3(1.00, 0.48, 0.08);
    float3 red    = float3(0.60, 0.08, 0.01);

    float3 col = mix(red,  orange, smoothstep(0.0,  0.45, temp));
    col        = mix(col,  white,  smoothstep(0.45, 1.0,  temp));

    // Vitesse orbitale képlérienne → tourbillon animé
    float omega = 1.0 / pow(max(r, 2.7), 1.5);
    float angle = phi + omega * time * 0.5;

    // Filaments turbulents multi-échelles
    float turb = 0.60 + 0.40 * sin(angle*7.0  + r*2.5)
                              * sin(angle*4.1  - r*1.7);
    turb      *= 0.80 + 0.20 * sin(angle*13.0 - r*3.1);

    // Luminosité : très brillant au bord interne (ISCO)
    float bright = mix(6.5, 0.5, rNorm) * exp(-rNorm * 1.5);

    // Décalage Doppler relativiste
    float  doppler = 1.0 + 0.55 * sin(angle);
    float3 dtint   = mix(float3(1.0, 0.55, 0.25),
                         float3(1.0, 1.00, 0.95),
                         clamp(doppler, 0.0, 1.0));

    return col * dtint * turb * bright;
}

// ---- Ciel étoilé + bande galactique ----
float3 starfield(float3 dir) {
    float3 col = float3(0.0);

    // Trois couches de densité (proches, lointaines, très lointaines)
    for (int layer = 0; layer < 3; layer++) {
        float  s  = layer == 0 ? 110.0 : (layer == 1 ? 320.0 : 800.0);
        float  sh = layer == 0 ? 12.0  : (layer == 1 ? 18.0  : 28.0);
        float  br = layer == 0 ? 1.0   : (layer == 1 ? 0.28  : 0.10);

        float3 p  = dir * s;
        float3 ip = floor(p);
        float3 fp = fract(p);

        for (int i = -1; i <= 1; i++)
        for (int j = -1; j <= 1; j++)
        for (int k = -1; k <= 1; k++) {
            float3 id  = ip + float3(i, j, k);
            float3 h   = fract(sin(id * float3(127.1, 311.7, 74.7)) * 43758.5);
            float3 off = h - 0.5 + float3(i, j, k);
            float  d   = length(fp - (off + 0.5));
            float  b   = pow(max(0.0, 1.0 - d * sh), 5.0);

            // Couleur : bleu-blanc, jaune chaud, géante rouge
            float3 sc = mix(float3(0.80, 0.90, 1.00),
                            float3(1.00, 0.95, 0.75), h.z);
            sc = mix(sc, float3(1.0, 0.35, 0.25), step(0.96, h.x));

            col += sc * b * (0.35 + 0.65 * h.y) * br;
        }
    }

    // Voie Lactée
    float band      = abs(dir.y);
    float milkyCore = exp(-band * band * 6.0);
    float milkyWide = exp(-band * band * 20.0);
    float bnoise    = fract(sin(dot(floor(dir * 35.0),
                                    float3(127.1, 311.7, 74.7))) * 43758.5);
    float3 bandCol  = mix(float3(0.45, 0.50, 0.85),
                          float3(0.80, 0.70, 0.55), milkyCore);
    col += bandCol * (milkyCore * 0.18 + milkyWide * 0.06) * (0.6 + 0.4 * bnoise);

    // Teinte nébuleuse violette
    col += float3(0.10, 0.04, 0.18) * exp(-band * band * 2.0) * 0.05;

    return col;
}

// ---- Kernel principal ----
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

    RaySph ray    = initRay(u.camPos, rayDir);
    float3 color  = float3(0.0);
    float3 diskAccum = float3(0.0);
    float  diskOpac  = 0.0;
    float3 prevPos   = u.camPos;
    float  minR      = ray.r;  // pour le halo de la photon sphere
    bool   captured  = false;
    bool   hitStar   = false;

    for (int i = 0; i < STEPS; ++i) {
        // Capturé par l'horizon → trou noir = noir absolu
        if (ray.r < RS * 1.01) {
            color    = float3(0.0);
            captured = true;
            break;
        }
        // Échappé à l'infini
        if (ray.r > 80.0) {
            float st = sin(ray.theta), ct = cos(ray.theta);
            float sp = sin(ray.phi),   cp = cos(ray.phi);
            color = starfield(normalize(float3(st*cp, ct, st*sp)));
            break;
        }

        float3 curPos = sphToCart(ray);
        minR = min(minR, ray.r);

        // Test intersection segment [prevPos, curPos] avec l'étoile compagne
        {
            float3 starP = u.starPos.xyz;
            float  starR = u.starPos.w;
            float3 seg   = curPos - prevPos;
            float3 oc    = prevPos - starP;
            float  a     = dot(seg, seg);
            float  b     = 2.0 * dot(oc, seg);
            float  c     = dot(oc, oc) - starR * starR;
            float  disc  = b*b - 4.0*a*c;
            if (disc >= 0.0 && a > 1e-6) {
                float t = (-b - sqrt(disc)) / (2.0 * a);
                if (t >= 0.0 && t <= 1.0) {
                    color   = float3(1.0, 0.92, 0.75) * 8.0;
                    hitStar = true;
                    break;
                }
            }
        }

        // Détection croisement plan équatorial (disque d'accrétion)
        if (diskOpac < 0.98 && prevPos.y * curPos.y < 0.0) {
            float rd = length(curPos.xz);
            if (rd > u.diskInner && rd < u.diskOuter) {
                float phi3 = atan2(curPos.z, curPos.x);
                float3 dc  = diskColor(rd, phi3, u.time);
                float  a   = clamp(dc.r * 0.28 + 0.32, 0.0, 1.0) * (1.0 - diskOpac);
                diskAccum += dc * a;
                diskOpac  += a;
            }
        }

        prevPos = curPos;
        stepRK4(ray, DT);
    }

    // Halo de la sphère de photons — uniquement pour les rayons qui ont échappé
    // (pas pour les rayons capturés, sinon l'intérieur du trou noir devient blanc)
    if (!captured && !hitStar) {
        float proximity = clamp(1.0 - (minR - 1.5*RS) / (1.5*RS), 0.0, 1.0);
        float ringGlow  = pow(proximity, 7.0) * 0.9;
        float3 ringCol  = mix(float3(1.0, 0.65, 0.25), float3(1.0, 0.95, 0.80), proximity);
        diskAccum      += ringCol * ringGlow * (1.0 - diskOpac);
    }

    float3 final = color * (1.0 - diskOpac) + diskAccum;

    // Tone mapping ACES
    float a=2.51, b=0.03, c2=2.43, d=0.59, e=0.14;
    final = clamp((final*(a*final+b)) / (final*(c2*final+d)+e), 0.0, 1.0);

    // Correction gamma sRGB
    final = pow(max(final, 0.0), float3(1.0 / 2.2));

    // Vignette
    float vign = 1.0 - 0.28 * dot(uv * 1.5, uv * 1.5);
    final *= clamp(vign, 0.0, 1.0);

    output.write(float4(final, 1.0), gid);
}
