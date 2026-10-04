#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Environment transmission approximates clear jelly without a screen-space refraction pass.
// It keeps the animated, intersecting body pieces depth-tested, avoiding visible interior shells.
static float2 jellyEnvironmentUV(float3 direction) {
    return float2(atan2(direction.z, direction.x) / (2.0f * M_PI_F) + 0.5f,
                  acos(clamp(direction.y, -1.0f, 1.0f)) / M_PI_F);
}

[[visible]]
void gummiJellySurface(realitykit::surface_parameters params) {
    const float3 normal = normalize(params.geometry().normal());
    const float3 view = normalize(params.geometry().view_direction());
    const float facing = saturate(dot(normal, view));
    const float fresnel = 0.028f + 0.972f * pow(1.0f - facing, 5.0f);

    // Beer-Lambert absorption: longer paths lose red and blue, leaving a rich green center.
    // The normal supplies an inexpensive rounded-volume thickness estimate that follows wobble.
    const float thickness = 0.22f + 0.88f * pow(facing, 0.65f);
    const float3 absorption = exp(-float3(1.65f, 0.32f, 4.6f) * thickness);
    const float3 refracted = refract(-view, normal, 1.0f / 1.38f);
    constexpr sampler roomSampler(coord::normalized, s_address::repeat, t_address::clamp_to_edge,
                                   filter::linear, mip_filter::linear);
    // Transmission is blurred slightly by the jelly; the clearcoat's window reflections stay crisp.
    const float3 room = float3(params.textures().custom().sample(roomSampler, jellyEnvironmentUV(refracted), level(4.0f)).rgb);
    // Light bent back into the candy creates a narrow bright meniscus near the silhouette.
    const float rim = pow(1.0f - facing, 3.0f);
    const float3 transmission = (room * 1.1f + float3(0.16f, 0.21f, 0.05f)) * absorption;
    const float3 internalRim = float3(0.16f, 0.34f, 0.018f) * rim * (1.0f - fresnel);

    auto surface = params.surface();
    surface.set_base_color(half3(0.008h, 0.018h, 0.001h));
    surface.set_metallic(0.0h);
    surface.set_roughness(0.115h);
    surface.set_specular(0.6h);
    surface.set_clearcoat(1.0h);
    surface.set_clearcoat_roughness(0.045h);
    surface.set_emissive_color(half3(transmission * (1.0f - fresnel) + internalRim));
    surface.set_opacity(half(mix(params.uniforms().custom_parameter().x, 1.0f, fresnel)));
}
