// Heat-map shading for the brain point cloud (BrainCloud.swift).
//
// Each cell is a triangle whose three vertices share the cell's position; the corner offset
// lives in uv0 and the cell's running firing rate in the vertex colour's red channel. The
// geometry modifier grows the triangle with heat, the surface shader colours it like a
// thermal camera: dark violet when quiet, through red and orange to white when hot.
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Inferno-like ramp, five stops, cheap enough to run per fragment on a phone.
static half3 heat_colour(half t) {
    const half3 c0 = half3(0.05, 0.02, 0.14);
    const half3 c1 = half3(0.45, 0.06, 0.45);
    const half3 c2 = half3(0.90, 0.20, 0.20);
    const half3 c3 = half3(1.00, 0.65, 0.10);
    const half3 c4 = half3(1.00, 1.00, 0.85);
    t = clamp(t, half(0), half(1));
    if (t < 0.25h) return mix(c0, c1, t / 0.25h);
    if (t < 0.5h)  return mix(c1, c2, (t - 0.25h) / 0.25h);
    if (t < 0.75h) return mix(c2, c3, (t - 0.5h) / 0.25h);
    return mix(c3, c4, (t - 0.75h) / 0.25h);
}

[[visible]]
void brainGeometry(realitykit::geometry_parameters params) {
    float heat = params.geometry().color().r;
    float2 corner = params.geometry().uv0();
    // Quiet cells stay tiny dust; a hot cell is up to four times the size.
    float size = 0.0016 + 0.0045 * heat;
    // Billboard: grow the triangle in the camera's plane, whatever the orbit, so the cloud
    // reads the same from every side instead of thinning edge-on. Rotations only, so the
    // transpose is the inverse.
    float4x4 m2v = params.uniforms().model_to_view();
    float3x3 model_to_view = float3x3(m2v[0].xyz, m2v[1].xyz, m2v[2].xyz);
    float3 view_offset = float3(corner * size, 0.0);
    params.geometry().set_model_position_offset(transpose(model_to_view) * view_offset);
}

[[visible]]
void brainSurface(realitykit::surface_parameters params) {
    half heat = half(params.geometry().color().r);
    // A soft disc inside the triangle: uv0 is the corner offset, so its length is the
    // distance from the cell's centre. Alpha falls off towards the edge, which turns a hard
    // triangle into a glowing soma; hot cells get a wider, brighter core.
    float2 corner = params.geometry().uv0();
    half d = half(length(corner));
    half core = 0.25h + 0.25h * heat;
    half alpha = 1.0h - smoothstep(core, 0.95h, d);
    half3 c = heat_colour(heat);
    params.surface().set_base_color(c);
    params.surface().set_emissive_color(c * (0.5h + 2.0h * heat));
    params.surface().set_opacity(alpha * (0.35h + 0.65h * heat));
    params.surface().set_roughness(1.0h);
}

// The brain's surface as glass: nearly clear face-on, a soft blue rim where the surface
// turns away from the camera. Drawn before the cells (ModelSortGroup) so it never dims them.
[[visible]]
void shellSurface(realitykit::surface_parameters params) {
    float3 n = normalize(params.geometry().normal());
    float3 v = normalize(params.geometry().view_direction());
    float rim = pow(1.0 - abs(dot(n, v)), 3.0);
    half3 tint = half3(0.55, 0.72, 1.0);
    params.surface().set_base_color(tint);
    params.surface().set_emissive_color(tint * half(0.15 + 0.6 * rim));
    params.surface().set_opacity(half(0.03 + 0.45 * rim));
    params.surface().set_roughness(0.4h);
}

// Arbors: a pastel hue per cell (vertex colour g), lit towards white by the cell's heat
// (vertex colour r). Lines are one pixel wide, so brightness and alpha carry the signal.
static half3 hue_colour(half h) {
    half3 k = half3(0.0h, 2.0h / 3.0h, 1.0h / 3.0h);
    half3 p = abs(fract(half3(h) + k) * 6.0h - 3.0h);
    return mix(half3(1.0h), clamp(p - 1.0h, 0.0h, 1.0h), 0.85h);   // saturation 0.85
}

[[visible]]
void wireSurface(realitykit::surface_parameters params) {
    half heat = half(params.geometry().color().r);
    half hue = half(params.geometry().color().g);
    half3 base = hue_colour(hue) * 0.9h;
    half3 c = mix(base, half3(1.0h, 0.95h, 0.8h), heat * heat);
    params.surface().set_base_color(c);
    params.surface().set_emissive_color(c * (0.35h + 1.6h * heat));
    params.surface().set_opacity(0.12h + 0.88h * heat);
    params.surface().set_roughness(1.0h);
}
