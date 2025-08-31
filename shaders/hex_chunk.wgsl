#import utils.wgsl
#import noise.wgsl
#import hex.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d_array<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) pos:              vec2<f32>,
    @location(1) old_indices:      vec3<u32>, // indices into texture array
    @location(2) new_indices:      vec3<u32>, // indices into texture array
    @location(3) weights:          vec3<f32>,
    @location(4) new_fact_and_vis: vec2<f32>,
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
    var hex_pos: i2;
    let a: Tile = get_data(a_idx_in_chunk);
    let c: Tile = get_data(a_idx_in_chunk + 1 + CHUNK_SIZE_PADDED);

    switch idx_in_quad {
        // first triangle:
        case 0u, default: {
            // a
            hex_pos = i2(i32(x), i32(y));
            let b: Tile = get_data(a_idx_in_chunk + 1);

            out.weights = v3(1.0, 0.0, 0.0);
            out.new_fact_and_vis = a.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, b.old_ter, c.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, b.new_ter, c.new_ter);
        }
        case 1u: {
            // b
            hex_pos = i2(i32(x+1), i32(y));
            let b: Tile = get_data(a_idx_in_chunk + 1);
            out.weights = v3(0.0, 1.0, 0.0);
            out.new_fact_and_vis = b.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, b.old_ter, c.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, b.new_ter, c.new_ter);
        }
        case 2u: {
            // c
            hex_pos = i2(i32(x+1), i32(y+1));
            let b: Tile = get_data(a_idx_in_chunk + 1);
            
            out.weights = v3(0.0, 0.0, 1.0);
            out.new_fact_and_vis = c.new_fact_and_vis;
            out.old_indices = vec3<u32>(a.old_ter, b.old_ter, c.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, b.new_ter, c.new_ter);
        }  
        // second triangle:
        case 3u: {
            // a
            hex_pos = i2(i32(x), i32(y));
            let d: Tile = get_data(a_idx_in_chunk + CHUNK_SIZE_PADDED);

            out.weights = v3(1.0, 0.0, 0.0);
            out.new_fact_and_vis = a.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, c.old_ter, d.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, c.new_ter, d.new_ter);
        }
        case 4u: {
            // c
            hex_pos = i2(i32(x+1), i32(y+1));
            let d: Tile = get_data(a_idx_in_chunk + CHUNK_SIZE_PADDED);

            out.weights = v3(0.0, 1.0, 0.0);
            out.new_fact_and_vis = c.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, c.old_ter, d.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, c.new_ter, d.new_ter);
        }  
        case 5u: {
            // d
            hex_pos = i2(i32(x), i32(y+1));
            let d: Tile = get_data(a_idx_in_chunk + CHUNK_SIZE_PADDED);

            out.weights = v3(0.0, 0.0, 1.0);
            out.new_fact_and_vis = d.new_fact_and_vis;

            out.old_indices = vec3<u32>(a.old_ter, c.old_ter, d.old_ter);
            out.new_indices = vec3<u32>(a.new_ter, c.new_ter, d.new_ter);
        }
    }
    // discard triangle if all indices are 0
    let w_pos = hex_to_world_pos(hex_pos + hex_chunk_terrain.chunk_pos * CHUNK_SIZE_I);
    out.pos = w_pos;
    // let old_and_new_index_sum: u32 = out.old_indices.x + out.old_indices.y + out.old_indices.z + out.new_indices.x + out.new_indices.y + out.new_indices.z;
    // if (old_and_new_index_sum == 0u) {
    //     out.clip_position = vec4<f32>(0.0);
    //     return out;
    // }
    out.clip_position = world_2d_pos_to_ndc(vec2(w_pos.x, w_pos.y));
    return out;
}


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

const BLUR: f32 = 0.5;
const GRID_WIDTH: f32 = 0.03;
const GRID_STREGTH: f32 = 2.0;
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let sample_uv = v2(in.pos.x, -in.pos.y) * 0.4; 

    let new_fact = in.new_fact_and_vis.x;
    let vis = in.new_fact_and_vis.y;
    // let new_fact = globals.xxx.y;
    // let new_fact = globals.xxx.x;
    // let vis = mix(0.0, 1.0, new_fact);

    var weights = in.weights;


    // let bary_noise = noise_based_on_indices(in.pos, in.new_indices, WAVELENGTH, AMPLITUDE, SEED);
    // var noisy_weights = weights + bary_noise;
    // noisy_weights /= noisy_weights.x + noisy_weights.y + noisy_weights.z;
    // let weighted_vis : v3 = in.visibility * noisy_weights;
    // let vis : f32 = weighted_vis.x + weighted_vis.y + weighted_vis.z;

    let old_color = terrain_color(in.old_indices, weights, sample_uv);
    let new_color = terrain_color(in.new_indices, weights, sample_uv);
    let color = mix(old_color, new_color, new_fact);

    let vis_n =  vis_noised(vis, in.pos);
    let vis_final = mix(vis, vis_n, globals.xxx.y);

    // let dotted = v4(step(0.95, max(max(weights.x, weights.y), weights.z))) * RED;
    let a = weights.x;
    let b = weights.y;
    let c = weights.z;
    let dotted = step(0.95, max(max(a, b), c)) * RED;

    let on_grid: bool = abs(a-b) < GRID_WIDTH && a+b > c*2 || abs(b-c) < GRID_WIDTH && b+c > a*2 || abs(a-c) < GRID_WIDTH && a+c > b*2;
    let vis_border_f = (0.5 - abs(vis_n- 0.5)) *2.0;
    var grid_f: f32 = select(0.0, 1.0, on_grid) * (vis_final - 0.5) * GRID_STREGTH;
    // let strength = 
    // if on_grid {
    //     grid_f = (vis_n + (noise + 2.0) * 0.2) * GRID_STREGTH;
    // } else {
    //     grid_f = 0.0;
    // }
    // let dotted = v4(1.0 -step(0.01, min(min(a, b), c))) * RED;
    let color_width_grid = mix(color,mix(color, BLACK, 0.7), grid_f);
    return mix(BLACK, color_width_grid, clamp(vis_final + 0.3, 0.0,1.0)) ;


    // return v4(v3(vis), 1.0);
    // return color;
}

fn vis_noised(vis: f32, w_pos: vec2<f32>) -> f32 {
    let vis_noise_stregth = 1.0 - vis;
    let noise = noise2(w_pos * 1.3  + globals.time_secs *0.3) + noise2((w_pos + globals.time_secs*0.5) * 3.127) - 2.0;
    return clamp(vis + vis_noise_stregth * noise, 0.0, 1.0);
}

fn sum(v: v3) -> f32{
    return v.x + v.y + v.z;
}

const VOID_COLOR: vec4<f32> = RED; // v4(0.0)
fn texture_rgb(sample_uv: vec2f, idx: u32) ->vec4f{
    let uv = select(sample_uv, sample_uv * 0.5, idx == 1);
    return select(textureSample(t_diffuse, s_diffuse, uv, idx-1).rgba, VOID_COLOR, idx == 0);
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