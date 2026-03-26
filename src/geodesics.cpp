#include "geodesics.hpp"
#include <cmath>

// Équations des géodésiques de Schwarzschild (coordonnées sphériques)
// On suit le formalisme Hamilton avec constantes du mouvement E, L, Q
// Référence : MTW "Gravitation" ou Luminet 1979

static float rs(const BlackHoleParams& bh) { return 2.0f * bh.mass; }

// Dérivées du système (r, theta, phi, dr/dlambda, dtheta/dlambda, dphi/dlambda)
// lambda = paramètre affine le long du rayon
static std::array<float,6> derivatives(
        const std::array<float,6>& s, const BlackHoleParams& bh)
{
    float r     = s[0];
    float theta = s[1];
    // float phi   = s[2]; // non utilisé dans les dérivées
    float dr    = s[3];
    float dth   = s[4];
    float dph   = s[5];

    float R  = rs(bh);
    float r2 = r * r;
    float sin_th  = std::sin(theta);
    float sin2_th = sin_th * sin_th;
    float cos_th  = std::cos(theta);

    // Constantes du mouvement (conservées)
    // L = moment angulaire, b = paramètre d'impact
    float L  = r2 * sin2_th * dph;           // moment angulaire / énergie
    float L2 = L * L;

    // Équation radiale : d²r/dlambda² = ...
    // d²theta/dlambda² = ...
    // d²phi/dlambda²   = ... (trivial avec L conservé)

    float d2r = -(R / (2.0f * r2)) * (1.0f - R/r) * dr * dr
                + r * (1.0f - R/r) * (dth*dth + sin2_th * dph*dph)
                - (R / (2.0f * r2)) / (1.0f - R/r) * dr * dr
                + (r - 1.5f*R) / (r2*r2) * L2 / sin2_th;

    // Simplification directe des géodésiques nulles (ds²=0)
    // d²r/dlambda² (équation de Schwarzschild)
    float M  = bh.mass;
    d2r = (M*(2.0f*M - r))/(r2*r2) * (r2*(dth*dth) + sin2_th*L2)
          - M/(r2*(r - 2.0f*M)) * dr*dr
          + (r - 2.0f*M) * (dth*dth + sin2_th*dph*dph) * (-M/r2);

    // Recalcul propre (Blandford & McKee style)
    // Potentiel effectif V_eff
    float V  = (1.0f - 2.0f*M/r) * (1.0f + L2 / (r2 * sin2_th));
    float dV = (2.0f*M/r2) * (1.0f + L2/(r2*sin2_th))
               + (1.0f - 2.0f*M/r) * (-2.0f*L2/(r2*r*sin2_th));
    d2r = -0.5f * dV;

    float d2theta = sin_th * cos_th * dph*dph - 2.0f/r * dr * dth;

    float d2phi = -2.0f * (dr/r + cos_th/sin_th * dth) * dph;

    return {dr, dth, dph, d2r, d2theta, d2phi};
}

// Intégrateur RK4
bool integrateGeodesic(RayState& ray, const BlackHoleParams& bh, int steps, float dt)
{
    std::array<float,6> s = {
            ray.r, ray.theta, ray.phi,
            ray.dr, ray.dtheta, ray.dphi
    };

    float R = rs(bh);

    for (int i = 0; i < steps; ++i) {
        // Condition de capture
        if (s[0] < R * 1.01f) return false;
        // Condition d'échappement
        if (s[0] > 100.0f) break;

        auto k1 = derivatives(s, bh);
        std::array<float,6> s2;
        for (int j = 0; j < 6; ++j) s2[j] = s[j] + 0.5f*dt*k1[j];

        auto k2 = derivatives(s2, bh);
        std::array<float,6> s3;
        for (int j = 0; j < 6; ++j) s3[j] = s[j] + 0.5f*dt*k2[j];

        auto k3 = derivatives(s3, bh);
        std::array<float,6> s4;
        for (int j = 0; j < 6; ++j) s4[j] = s[j] + dt*k3[j];

        auto k4 = derivatives(s4, bh);
        for (int j = 0; j < 6; ++j)
            s[j] += dt/6.0f * (k1[j] + 2*k2[j] + 2*k3[j] + k4[j]);
    }

    ray.r      = s[0]; ray.theta  = s[1]; ray.phi    = s[2];
    ray.dr     = s[3]; ray.dtheta = s[4]; ray.dphi   = s[5];
    return true;
}