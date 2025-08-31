#import utils.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

struct SpriteInstance {
    @location(0) pos: vec2<f32>,
    @location(1) size: vec2<f32>,
    @location(2) color: vec4<f32>,
    @location(3) uv: vec4<f32>, // aabb
    @location(4) rotation: f32, 
    @location(5) z: f32,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
}

@vertex
fn vs_depth(@builtin(vertex_index) vertex_index: u32, instance: SpriteInstance) -> VertexOutput {
    let vertex = sprite_vertex(vertex_index, instance);
    var out: VertexOutput;
    out.clip_position = world_2d_pos_to_ndc_with_z(vertex.pos, vertex.z); 
    out.color = instance.color;
    out.uv = vertex.uv;
    return out;
}

@vertex
fn vs_simple(@builtin(vertex_index) vertex_index: u32, instance: SpriteInstance) -> VertexOutput {
    let vertex = sprite_vertex(vertex_index, instance);
    var out: VertexOutput;
    out.clip_position = world_2d_pos_to_ndc(vertex.pos);
    out.color = instance.color; 
    out.uv = vertex.uv;
    return out;
}

const CUTOUT_ALPHA_THRESHOLD : f32 = 0.5;
@fragment
fn fs_cutout(in: VertexOutput) -> @location(0) vec4<f32> {
    let color = textureSample(t_diffuse, s_diffuse, in.uv) * in.color;
    if color.a < CUTOUT_ALPHA_THRESHOLD {
        discard;
    }
    return color;
    // return v4(in.color.rgb, 1.0);
}

@fragment
fn fs_transparent(in: VertexOutput) -> @location(0) vec4<f32> {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    return image_color * in.color;
}

@fragment
fn fs_shine(in: VertexOutput) -> @location(0) vec4<f32> {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    let default_color = image_color * in.color;
    let lightness :f32 = (default_color.r + default_color.g + default_color.b) /3.0;
    return  vec4<f32>( (1.0 - default_color.rgb) *0.6, default_color.a * 0.3);
}

@fragment
fn fs_simple(in: VertexOutput) -> @location(0) vec4<f32> {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    return image_color * in.color;
}

struct SpriteVertex {
    pos: vec2<f32>,
    uv: vec2<f32>,
    z: f32 // height
}

fn sprite_vertex(vertex_index: u32, instance: SpriteInstance) -> SpriteVertex {
    var out: SpriteVertex;
    let size = instance.size;
    let size_half = size / 2.0;
    var u_uv = unit_uv_from_idx(vertex_index);
    out.uv = map_unit_uv(u_uv, instance.uv);
    
    let pos = (u_uv * size) - size_half;
    let pos_rotated = rotate(pos, instance.rotation);
    out.z = pos_rotated.y+ instance.z; // do this to let sprite size affect z: + size_half.y;
    out.pos = pos_rotated + instance.pos;
    return out;
}

fn more_contrast(color: vec4<f32>, contrast: f32) -> vec4<f32> {
    let midpoint: f32 = 0.5;
    let adjusted_rgb = vec3<f32>(midpoint) + (color.rgb - vec3<f32>(midpoint)) * contrast;

    let smoothed_rgb = adjusted_rgb * adjusted_rgb * (3.0 - 2.0 * adjusted_rgb);
    return vec4<f32>(smoothed_rgb, color.a);
}

