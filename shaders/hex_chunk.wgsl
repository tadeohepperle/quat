#import globals.wgsl
#import noise.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d_array<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

const CHUNK_SIZE : u32 = 64;
const CHUNK_SIZE_I : i32 = i32(CHUNK_SIZE);
const CHUNK_SIZE_PADDED : u32 = CHUNK_SIZE+2;
const ARRAY_LEN : u32 = (CHUNK_SIZE_PADDED*CHUNK_SIZE_PADDED)/4;
struct HexChunkTerrainData {
    // completely retarded: wgpu forces alignment 16 on arrays in uniform buffers,
    // so instead of storing (CHUNK_SIZE+2)^2 u32 values, we need to batch them into vec4<u32>s
    data: array<vec4<u32>, ARRAY_LEN>, 
}
struct HexChunkVisibilityData {
    data: array<vec4<f32>, ARRAY_LEN>,
}
@group(2) @binding(0) var<uniform> hex_chunk_terrain : HexChunkTerrainData;
@group(2) @binding(1) var<uniform> hex_chunk_visibility : HexChunkVisibilityData;

alias IVec2 = vec2<i32>;
struct ChunkPushConstants {
    chunk_pos: IVec2,
}
var<push_constant> push: ChunkPushConstants;

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) pos:         vec2<f32>,
    @location(1) tex_indices: vec3<u32>, // indices into texture array
    @location(2) weights:     vec3<f32>,
    @location(3) visibility:  vec3<f32>,
}

fn get_terrain(idx_in_chunk: u32) -> u32 {
    let idx : u32 = idx_in_chunk / 4;
    let component : u32 = idx_in_chunk % 4;
    return hex_chunk_terrain.data[idx][component];
}
fn get_visibility(idx_in_chunk: u32) -> f32 {
    let idx : u32 = idx_in_chunk / 4;
    let component : u32 = idx_in_chunk % 4;
    return hex_chunk_visibility.data[idx][component];
}

const HEX_TO_WORLD_POS_MAT : mat2x2f = mat2x2f(1.5, 0, -0.75, 1.5);
fn hex_to_world_pos(hex_pos: IVec2) -> v2{
    return HEX_TO_WORLD_POS_MAT * v2(f32(hex_pos.x), f32(hex_pos.y));
}

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {


    // first, convert the idx to the quad idx (0..<CHUNK_SIZE*CHUNKS_SIZE) and the vertex idx (0..<6) in that quad 
    let quad_idx    = idx / 6;
    let idx_in_quad = idx % 6;

    // then convert the quad idx to the x and y position in the chunk:
    // example if CHUNK_SIZE would be 4:
    // quad idx   ->  x,y
    // 0          ->  0,0
    // 1          ->  1,0
    // 2          ->  2,0
    // 3          ->  3,0
    // 4          ->  0,1
    // 5          ->  1,1
    let y : u32 = quad_idx / CHUNK_SIZE;
    let x : u32 = quad_idx % CHUNK_SIZE;
    let idx_in_chunk : u32 = x + 1 + (y + 1) * CHUNK_SIZE_PADDED; 

    // calculate the world position of the vertex:
/* 

two triangles for each hex pos in chunk (without padding): abc, acd
idx_in_quad: 0->a, 1->b, 2->c, 3->a, 4->c, 5->d
a is the center of the hex at {x,y}
b is the center of the hex at {x+1,y}
c is the center of the hex at {x+1,y+1}
d is the center of the hex at {x,y+1}

       d
       |\             
       |   \          
       |      \  
       |         \  c             
       |       /  |              
       |   /      |              
       |/         |               
      a  \        |                 
            \     |                    
               \  |                       
                 \
                    b
*/



    var out: VertexOutput;
    var hex_pos: IVec2;
    let c_idx_in_chunk: u32 = idx_in_chunk + 1 + CHUNK_SIZE_PADDED;
    let a_ter: u32 = get_terrain(idx_in_chunk);
    let c_ter: u32 = get_terrain(c_idx_in_chunk);
    let a_vis: f32 = get_visibility(idx_in_chunk);
    let c_vis: f32 = get_visibility(c_idx_in_chunk);

    switch idx_in_quad {
        // first triangle:
        case 0u, default: {
            hex_pos = IVec2(i32(x), i32(y));
            out.weights = v3(1.0, 0.0, 0.0);
            let b_ter: u32 = get_terrain(idx_in_chunk + 1);
            let b_vis: f32 = get_visibility(idx_in_chunk + 1);
            out.tex_indices = vec3<u32>(a_ter, b_ter, c_ter);
            out.visibility = v3(a_vis, b_vis, c_vis);
        }
        case 1u: {
            hex_pos = IVec2(i32(x+1), i32(y));
            out.weights = v3(0.0, 1.0, 0.0);
            let b_ter: u32 = get_terrain(idx_in_chunk + 1);
            let b_vis: f32 = get_visibility(idx_in_chunk + 1);
            out.tex_indices = vec3<u32>(a_ter, b_ter, c_ter);
            out.visibility = v3(a_vis, b_vis, c_vis);
        }
        case 2u: {
            hex_pos = IVec2(i32(x+1), i32(y+1));
            out.weights = v3(0.0, 0.0, 1.0);
            let b_ter: u32 = get_terrain(idx_in_chunk + 1);
            let b_vis: f32 = get_visibility(idx_in_chunk + 1);
            out.tex_indices = vec3<u32>(a_ter, b_ter, c_ter);
            out.visibility = v3(a_vis, b_vis, c_vis);
        }  
        // second triangle:
        case 3u: {
            hex_pos = IVec2(i32(x), i32(y));
            out.weights = v3(1.0, 0.0, 0.0);
            let d_ter: u32 = get_terrain(idx_in_chunk + CHUNK_SIZE_PADDED);
            let d_vis: f32 = get_visibility(idx_in_chunk + CHUNK_SIZE_PADDED);
            out.tex_indices = vec3<u32>(a_ter, c_ter, d_ter);
            out.visibility = v3(a_vis, c_vis, d_vis);
        }
        case 4u: {
            hex_pos = IVec2(i32(x+1), i32(y+1));
            out.weights = v3(0.0, 1.0, 0.0);
            let d_ter: u32 = get_terrain(idx_in_chunk + CHUNK_SIZE_PADDED);
            let d_vis: f32 = get_visibility(idx_in_chunk + CHUNK_SIZE_PADDED);
            out.tex_indices = vec3<u32>(a_ter, c_ter, d_ter);
            out.visibility = v3(a_vis, c_vis, d_vis);
        }  
        case 5u: {
            hex_pos = IVec2(i32(x), i32(y+1));
            out.weights = v3(0.0, 0.0, 1.0);
            let d_ter: u32 = get_terrain(idx_in_chunk + CHUNK_SIZE_PADDED);
            let d_vis: f32 = get_visibility(idx_in_chunk + CHUNK_SIZE_PADDED);
            out.tex_indices = vec3<u32>(a_ter, c_ter, d_ter);
            out.visibility = v3(a_vis, c_vis, d_vis);
        }
    }

    let w_pos = hex_to_world_pos(hex_pos + push.chunk_pos * CHUNK_SIZE_I);
    out.pos = w_pos;
    out.clip_position = world_pos_to_ndc(vec2(w_pos.x, w_pos.y));
    return out;
}



const BLUR: f32 = 0.7;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let sample_uv = in.pos * 0.3; 

    var weights = in.weights;
    let color_0 =  texture_rgb(sample_uv, in.tex_indices[0]);
    let color_1 =  texture_rgb(sample_uv, in.tex_indices[1]);
    let color_2 =  texture_rgb(sample_uv, in.tex_indices[2]);
    let col_1_2 = mix(
        color_1,
        color_2,
        smoothstep(BLUR, -BLUR, weights.y - weights.z)
    );
    let color = mix(
        col_1_2,
        color_0,
        smoothstep(BLUR, -BLUR, max(weights.y, weights.z) - weights.x)
    );

    // let noise = noise_based_on_indices(in.pos, in.tex_indices, WAVELENGTH, AMPLITUDE, SEED);
    // var noisy_weights = weights;//+ noise;
    // noisy_weights /= noisy_weights.x + noisy_weights.y + noisy_weights.z;
    // let weighted_vis : v3 = in.visibility * noisy_weights;
    // let vis : f32 = weighted_vis.x + weighted_vis.y + weighted_vis.z;


    let vis_avg : f32 = (in.visibility.x + in.visibility.y + in.visibility.z) /3.0;

    let vis = sum(in.weights * in.visibility);
    let noise_stregth = 1.0 - vis;
    let noise = noise2(in.pos * 1.3) + noise2(in.pos * 3.127) - 2.0;
    let vis_noised =  clamp(vis + noise_stregth * noise, 0.0, 1.0);
    // let vis = noise_stregth; //sum((in.weights) * in.visibility) + noise2(in.pos) - 1.0;



    let dotted = v4(step(0.95, max(max(weights.x, weights.y), weights.z))) * RED;
    // return v4(v3(in.visibility * in.visibility * in.visibility), 1.0) + dotted;
    // return v4(v3(vis), 1.0) + dotted;
    
    // let n2 = noise2(in.pos * 0.177) * 0.1;
    // let color_faded = mix(color, vec4<f32>(0.0, 0.0, 0.0, 1.0), 0.97);
    return mix(BLACK, color, vis_noised);
}

fn sum(v: v3) -> f32{
    return v.x + v.y + v.z;
}

fn texture_rgb(sample_uv: vec2f, idx: u32) ->vec4f{
    return select(textureSample(t_diffuse, s_diffuse, sample_uv, idx-1).rgba, vec4f(0.0), idx == 0);
}

const WAVELENGTH: f32 = 0.3;
const AMPLITUDE: f32 = 0.15;
const SEED: f32 = 234.2;
fn noise_based_on_indices(pos: vec2f, indices: vec3<u32>, wavelength: f32, amplitude: f32, seed: f32) -> vec3f {
    let offset = pos / wavelength ;
    // let offset = (pos + globals.time_secs * 0.05)/ wavelength ;
    let off_a = offset + (f32(indices[0]) + seed);
    let off_b = offset + (f32(indices[1]) + seed);
    let off_c = offset + (f32(indices[2]) + seed);
    let noise_val : vec3f = vec3f(
        noise2(off_a),
        noise2(off_b),
        noise2(off_c),
    );
    return noise_val * amplitude;
}