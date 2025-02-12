#import globals.wgsl
#import noise.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d_array<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

const CHUNK_SIZE : u32 = 64;
const CHUNK_SIZE_I : i32 = i32(CHUNK_SIZE);
const CHUNK_SIZE_PADDED : u32 = CHUNK_SIZE+2;
const ARRAY_LEN : u32 = (CHUNK_SIZE_PADDED*CHUNK_SIZE_PADDED)/2;
// completely retarded: wgpu forces alignment 16 on arrays in uniform buffers, so we need to store our 8 byte tiles grouped as vec4<u32>
// the data contains pairs of these packed tiles that are unpacked in the vertex shader:
// struct PackedTile { 
//     old_and_new_ter: u32,  // 2xu16 
//     new_fact_and_vis: u32, // 2xf16
// }
struct HexChunkData {
    // is actually array<vec2<PackedTile>> representing array<PackedTile> for 16 alignment
    data: array<vec4<u32>, ARRAY_LEN>, 
}
@group(2) @binding(0) var<uniform> hex_chunk_terrain : HexChunkData;

// very wasteful! probably 8 bytes would be enough per field...
struct PackedTile {
    old_and_new_ter: u32,  // 2xu16
    new_fact_and_vis: u32, // 2xf16
}
struct Tile {
    old_ter: u32,
    new_ter: u32,
    new_fact_and_vis: vec2<f32>,
}
fn get_data(idx_in_chunk: u32) -> Tile {
    let buf_idx = idx_in_chunk / 2;
    let comp_idx = (idx_in_chunk % 2) * 2; // 0 or 2
    let two_tiles: vec4<u32> = hex_chunk_terrain.data[buf_idx];
    
    var res: Tile;
    let old_and_new_ter: u32 = two_tiles[comp_idx];
    res.old_ter = old_and_new_ter & 0xFFFF;
    res.new_ter = old_and_new_ter >> 16;
    res.new_fact_and_vis = unpack2x16float(two_tiles[comp_idx + 1]);
    return res;
}

alias IVec2 = vec2<i32>;
struct ChunkPushConstants {
    chunk_pos: IVec2,
}
var<push_constant> push: ChunkPushConstants;

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) pos:              vec2<f32>,
    @location(1) old_indices:      vec3<u32>, // indices into texture array
    @location(2) new_indices:      vec3<u32>, // indices into texture array
    @location(3) weights:          vec3<f32>,
    @location(4) new_fact_and_vis: vec2<f32>,
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
    let a_idx_in_chunk : u32 = x + 1 + (y + 1) * CHUNK_SIZE_PADDED; 

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
    let a: Tile = get_data(a_idx_in_chunk);
    let c: Tile = get_data(a_idx_in_chunk + 1 + CHUNK_SIZE_PADDED);

    switch idx_in_quad {
        // first triangle:
        case 0u, default: {
            // a
            hex_pos = IVec2(i32(x), i32(y));
            let b: Tile = get_data(a_idx_in_chunk + 1);

            out.weights = v3(1.0, 0.0, 0.0);
            out.new_fact_and_vis = a.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, b.old_ter, c.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, b.new_ter, c.new_ter);
        }
        case 1u: {
            // b
            hex_pos = IVec2(i32(x+1), i32(y));
            let b: Tile = get_data(a_idx_in_chunk + 1);
            out.weights = v3(0.0, 1.0, 0.0);
            out.new_fact_and_vis = b.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, b.old_ter, c.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, b.new_ter, c.new_ter);
        }
        case 2u: {
            // c
            hex_pos = IVec2(i32(x+1), i32(y+1));
            let b: Tile = get_data(a_idx_in_chunk + 1);
            
            out.weights = v3(0.0, 0.0, 1.0);
            out.new_fact_and_vis = c.new_fact_and_vis;
            out.old_indices = vec3<u32>(a.old_ter, b.old_ter, c.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, b.new_ter, c.new_ter);
        }  
        // second triangle:
        case 3u: {
            // a
            hex_pos = IVec2(i32(x), i32(y));
            let d: Tile = get_data(a_idx_in_chunk + CHUNK_SIZE_PADDED);

            out.weights = v3(1.0, 0.0, 0.0);
            out.new_fact_and_vis = a.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, c.old_ter, d.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, c.new_ter, d.new_ter);
        }
        case 4u: {
            // c
            hex_pos = IVec2(i32(x+1), i32(y+1));
            let d: Tile = get_data(a_idx_in_chunk + CHUNK_SIZE_PADDED);

            out.weights = v3(0.0, 1.0, 0.0);
            out.new_fact_and_vis = c.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, c.old_ter, d.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, c.new_ter, d.new_ter);
        }  
        case 5u: {
            // d
            hex_pos = IVec2(i32(x), i32(y+1));
            let d: Tile = get_data(a_idx_in_chunk + CHUNK_SIZE_PADDED);

            out.weights = v3(0.0, 0.0, 1.0);
            out.new_fact_and_vis = d.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, c.old_ter, d.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, c.new_ter, d.new_ter);
        }
    }

    let w_pos = hex_to_world_pos(hex_pos + push.chunk_pos * CHUNK_SIZE_I);
    out.pos = w_pos;
    out.clip_position = world_pos_to_ndc(vec2(w_pos.x, w_pos.y));
    return out;
}

const BLUR: f32 = 0.7;
fn terrain_color(indices: vec3<u32>, weights: vec3<f32>, uv: vec2<f32>) -> vec4<f32>{
    let color_0 =  texture_rgb(uv, indices[0]);
    let color_1 =  texture_rgb(uv, indices[1]);
    let color_2 =  texture_rgb(uv, indices[2]);
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
    return color;
}


const GRID_WIDTH: f32 = 0.05;
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let sample_uv = v2(in.pos.x, -in.pos.y) * 0.3; 

    let xxx = globals.xxx.x;
    // let new_fact = in.new_fact_and_vis.x;
    let new_fact = xxx;
    let vis = mix(in.new_fact_and_vis.y, 1.0, xxx);

    var weights = in.weights;
    let old_color = terrain_color(in.old_indices, weights, sample_uv);
    let new_color = terrain_color(in.new_indices, weights, sample_uv);
    let color = mix(old_color, new_color, new_fact);

    // let noise = noise_based_on_indices(in.pos, in.tex_indices, WAVELENGTH, AMPLITUDE, SEED);
    // var noisy_weights = weights;//+ noise;
    // noisy_weights /= noisy_weights.x + noisy_weights.y + noisy_weights.z;
    // let weighted_vis : v3 = in.visibility * noisy_weights;
    // let vis : f32 = weighted_vis.x + weighted_vis.y + weighted_vis.z;

    let noise_stregth = 1.0 - vis;
    
    let noise = noise2(in.pos * 1.3  + globals.time_secs *0.3) + noise2((in.pos+ globals.time_secs*0.5) * 3.127) - 2.0;
    let vis_noised =  clamp(vis + noise_stregth * noise, 0.0, 1.0);
    // let vis = noise_stregth; //sum((in.weights) * in.visibility) + noise2(in.pos) - 1.0;

    // let dotted = v4(step(0.95, max(max(weights.x, weights.y), weights.z))) * RED;
    let a = weights.x;
    let b = weights.y;
    let c = weights.z;
    // let dotted = step(0.95, max(max(a, b), c)) * RED;

    let on_grid: bool = abs(a-b) < GRID_WIDTH && a+b > c*2 || abs(b-c) < GRID_WIDTH && b+c > a*2 || abs(a-c) < GRID_WIDTH && a+c > b*2;
    var grid_f: f32;
    if  on_grid {
        grid_f = (vis_noised + (noise + 2.0) * 0.2) *0.7;
    } else {
        grid_f = 0.0;
    }
    // let dotted = v4(1.0 -step(0.01, min(min(a, b), c))) * RED;
    let color_width_grid = mix(color,mix(color, BLACK, 0.7), grid_f);
    return mix(BLACK, color_width_grid, clamp(vis_noised + 0.5, 0.0,1.0));
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