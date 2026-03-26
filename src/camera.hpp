#pragma once
#include <simd/simd.h>
#include <cmath>
#include <algorithm>

struct Camera {
    float theta = 1.2f;
    float phi   = 0.0f;
    float dist  = 20.0f;
    float fov   = 0.8f;
    bool gridOn = true;

    simd_float3 position() const {
        return {
            dist * std::sin(theta) * std::cos(phi),
            dist * std::cos(theta),
            dist * std::sin(theta) * std::sin(phi)
        };
    }

    simd_float4x4 invViewMatrix() const {
        simd_float3 pos = position();
        simd_float3 fwd = simd_normalize(simd_make_float3(-pos.x, -pos.y, -pos.z));

        simd_float3 worldUp = (std::abs(std::cos(theta)) > 0.99f)
            ? simd_make_float3(0.0f, 0.0f, 1.0f)
            : simd_make_float3(0.0f, 1.0f, 0.0f);

        simd_float3 rgt = simd_normalize(simd_cross(fwd, worldUp));
        simd_float3 up  = simd_cross(rgt, fwd);

        return simd_float4x4{{
            { rgt.x,  rgt.y,  rgt.z, 0.0f },
            { up.x,   up.y,   up.z,  0.0f },
            {-fwd.x, -fwd.y, -fwd.z, 0.0f },
            { 0.0f,   0.0f,   0.0f,  1.0f }
        }};
    }

    // Trackpad : drag dans n'importe quelle direction
    void orbit(float dx, float dy) {
        phi   += dx * 0.008f;
        theta  = std::clamp(theta + dy * 0.008f, 0.05f, 3.09f);
    }

    void zoom(float delta) {
        dist = std::clamp(dist - delta * 0.8f, 4.5f, 80.0f);
    }
};