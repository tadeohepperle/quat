#import globals.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

struct SpriteInstance {
    @location(0) pos:      vec2<f32>,
    @location(1) size:     vec2<f32>,
    @location(2) color:    vec4<f32>,
    @location(3) uv:       vec4<f32>, // aabb
    @location(4) rotation: f32,
}

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32, instance: SpriteInstance) -> VertexOutput {
    let pos_and_uv = pos_and_uv(vertex_index, instance);
    var out: VertexOutput;
    out.clip_position = world_pos_to_ndc(pos_and_uv.pos);
    out.color = instance.color;
    out.uv = pos_and_uv.uv;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    return image_color * in.color * 1.0;
}

struct PosAndUv{
    pos: vec2<f32>,
    uv: vec2<f32>,
}

fn pos_and_uv(vertex_index: u32, instance: SpriteInstance) -> PosAndUv{
    var out: PosAndUv;
    let size = instance.size;
    let size_half = size / 2.0;
    var u_uv = unit_uv_from_idx(vertex_index);
    out.uv =vec2<f32>(
       (1.0 - u_uv.x) * instance.uv.x +  u_uv.x * instance.uv.z,
        u_uv.y * instance.uv.y + (1.0 - u_uv.y) * instance.uv.w
    );
    
    let rot = instance.rotation;
    let pos = (u_uv * size) - size_half;
    let pos_rotated = vec2(
        cos(rot)* pos.x - sin(rot)* pos.y,
        sin(rot)* pos.x + cos(rot)* pos.y,     
    );
    out.pos = pos_rotated + instance.pos;
    return out;
}

fn unit_uv_from_idx(idx: u32) -> vec2<f32> {
    return vec2<f32>(
        f32(((idx << 1) & 2) >> 1),
        f32((idx & 2) >> 1)
    );
}