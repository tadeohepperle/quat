#import globals.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var t_motion: texture_2d<f32>;
@group(1) @binding(2)
var s_sampler: sampler;

struct MotionParticleInstance {
    @location(0) pos: vec2<f32>,
    @location(1) size: vec2<f32>,
    @location(2) color: vec4<f32>,
    @location(3) z_and_rotation: vec2<f32>, 
    @location(4) lifetime_and_t_offset: vec2<f32>, 
}
const MAX_N_MOTION_FRAMES : u32 = 14; // to keep total MotionFramesData at 128 bytes for push constant
struct MotionFramesData {
    time:      f32,
	n:         u32,
    uv_size:   vec2<f32>,
	start_uvs: array<vec2<f32>, MAX_N_MOTION_FRAMES>,
}
var<push_constant> frames: MotionFramesData;

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color:         vec4<f32>,
    @location(1) uv_one:        vec2<f32>,
    @location(2) uv_two:        vec2<f32>,
    @location(3) uv_two_factor: f32,
}
@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32, instance: MotionParticleInstance) -> VertexOutput {
    let size = instance.size;
    let size_half = size / 2.0;
    let u_uv = unit_uv_from_idx(vertex_index);

    let rot = instance.z_and_rotation.y;
    let pos = (u_uv * size) - size_half;
    let pos_rotated = rotate(pos, rot);
    let w_z = pos_rotated.y + instance.z_and_rotation.x + size_half.y;
    let w_pos =  pos_rotated + instance.pos;

    let time = globals.time_secs * 4.0; // todo: add instance time offset to this :)
    let uv_one_start = frames.start_uvs[u32(time) % frames.n];
    let uv_two_start = frames.start_uvs[(u32(time) + 1u) % frames.n];

    var out: VertexOutput;
    out.uv_two_factor = fract(time);
    out.uv_one = map_unit_uv(u_uv, vec4<f32>(uv_one_start, uv_one_start + frames.uv_size));
    out.uv_two = map_unit_uv(u_uv, vec4<f32>(uv_two_start, uv_two_start + frames.uv_size));

    out.clip_position = world_pos_to_ndc_with_z(w_pos, w_z); 
    out.color = instance.color; 
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let tex_color_one = textureSample(t_diffuse, s_sampler, in.uv_one);
    let tex_color_two = textureSample(t_diffuse, s_sampler, in.uv_two);
    let tex_color = mix(tex_color_one, tex_color_two, in.uv_two_factor);
    return tex_color * in.color;
}