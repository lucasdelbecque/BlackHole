#pragma once
#include <array>

// Masse du trou noir en unités géométriques (G=c=1)
// Rayon de Schwarzschild : rs = 2M
struct BlackHoleParams {
    float mass       = 1.0f;   // M
    float spin       = 0.0f;   // a (0 = Schwarzschild, <M = Kerr)
    float accDiskMin = 2.6f;   // rayon interne disque (ISCO ≈ 6M pour a=0)
    float accDiskMax = 5.0f;  // rayon externe disque
};

// État d'un rayon : position (r,theta,phi) + vitesses
struct RayState {
    float r, theta, phi;
    float dr, dtheta, dphi;
};

// Intègre un rayon de photon sur 'steps' pas
// Retourne false si le rayon tombe dans le trou noir
bool integrateGeodesic(RayState& ray, const BlackHoleParams& bh, int steps, float dt);