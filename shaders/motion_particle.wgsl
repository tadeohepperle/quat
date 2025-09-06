#import utils.wgsl

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

struct FlipbookData {
	time:         f32,
	_unused:      f32,
	n_tiles:      u32,       // how many tiles there are in total
	n_x_tiles:    u32,       // how many tiles there are in x direction
	start_uv:     vec2<f32>, // diffuse and motion image start uv pos of first flipbook tile in atlas
	uv_tile_size: vec2<f32>, // size per tile!
}

var<push_constant> flipbook: FlipbookData;

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color:         vec4<f32>,
    @location(1) uv_one:        vec2<f32>,
    @location(2) uv_two:        vec2<f32>,
    @location(3) uv_two_factor: f32,
}

// tile idx can be out of range, will loop around
fn tile_idx_to_start_uv(tile_idx: u32) -> vec2<f32> {
    let idx: u32  = tile_idx % flipbook.n_tiles;
    let y_idx: u32 = idx / flipbook.n_x_tiles;
    let x_idx: u32 = idx % flipbook.n_x_tiles;
    return flipbook.start_uv + flipbook.uv_tile_size * vec2<f32>(f32(x_idx), f32(y_idx));
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
    let w_pos = pos_rotated + instance.pos;

    let time = flipbook.time*f32(flipbook.n_tiles) + instance.lifetime_and_t_offset.y; // frame.total_time * 40.0  
    let tile_idx_one = u32(time);
    let tile_idx_two = u32(time) + 1;
    let uv_one_start = tile_idx_to_start_uv(tile_idx_one);
    let uv_two_start = tile_idx_to_start_uv(tile_idx_two);

    var out: VertexOutput;
    out.uv_two_factor = fract(time);
    out.uv_one = map_unit_uv(u_uv, vec4<f32>(uv_one_start, uv_one_start + flipbook.uv_tile_size));
    out.uv_two = map_unit_uv(u_uv, vec4<f32>(uv_two_start, uv_two_start + flipbook.uv_tile_size));

    out.clip_position = world_2d_pos_to_clip_pos_with_z(w_pos, w_z); 
    out.color = instance.color; 
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // inspired by: https://www.klemenlozar.com/frame-blending-with-motion-vectors/
    let motion_rg = textureSample(t_motion, s_sampler, in.uv_two).rg;
    var motion: vec2<f32> = (motion_rg - 0.5) * 2.0;
    motion *= flipbook.uv_tile_size * 0.25 ; // the 0.05 here is kinda dubious but seems to work. 0.5 comes from normalizing the 2.0 above?? and then maybe texture has made to have a a shift of 1/10 of image uv to be full 0 or 255 already?? or 1/20th?


    let f = in.uv_two_factor; // frame.xxx.x; // 
    
    // let tex_color_one = textureSample(t_diffuse, s_sampler, in.uv_one + f * -motion);
    // let tex_color_two = textureSample(t_diffuse, s_sampler, in.uv_two + (1.0 -f) * motion);
    // let tex_color = mix(tex_color_one, tex_color_two, f);
    // return tex_color * in.color;

    if frame.xxx.x < 0.33 {
        let tex_color_one = textureSample(t_diffuse, s_sampler, in.uv_one + f * -motion);
        let tex_color_two = textureSample(t_diffuse, s_sampler, in.uv_two + (1.0 -f) * motion);
        let tex_color = mix(tex_color_one, tex_color_two, f);
        return tex_color;
    } else if frame.xxx.x < 0.9 {
        let tex_color_one = textureSample(t_diffuse, s_sampler, in.uv_one);
        let tex_color_two = textureSample(t_diffuse, s_sampler, in.uv_two);
        let tex_color = mix(tex_color_one, tex_color_two, f);
        return tex_color;
    } else {
        return textureSample(t_diffuse, s_sampler, in.uv_one);
    }
}