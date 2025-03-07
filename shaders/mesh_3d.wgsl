#import globals.wgsl
#import noise.wgsl
#import hex.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

struct Vertex {
    @location(0) pos:    vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv:     vec2<f32>,
    @location(3) color:  vec4<f32>,
}

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) pos:    vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv:     vec2<f32>,
    @location(3) color:  vec4<f32>,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = world_pos_to_ndc_3d(vertex.pos);
    out.pos = vertex.pos;
    out.normal = vertex.normal;
    out.color = vertex.color;
    out.uv = vertex.uv;
    return out;
}


@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    let color = calculate_color(in.color, in.normal, in.pos.z);
    return color;
}

const LIGHT_DIR : v3 = v3(0.0,0.5,1.3);
const TERRAIN_NORMAL : v3 = v3(0.0,0.0,1.0);
const BLEND_UNTIL_HEIGHT : f32 = 0.01;
fn calculate_color(color: vec4<f32>, normal: vec3<f32>, pos_z: f32) -> vec4<f32> {
    let blend =  smoothstep(0.0, BLEND_UNTIL_HEIGHT, pos_z);
    // let blend : f32 = 1.0 - (blend_rev * blend_rev * blend_rev *blend_rev);
    
    let normal_blended = mix(TERRAIN_NORMAL, normal, blend);
    let light: f32 = max(dot(normal_blended,normalize(LIGHT_DIR)),0.05);
    var color_w_light = color.rgb * light;

    return v4(color_w_light, blend);
}

@vertex
fn vs_hex_mask(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;

  
    // let flat_pos = v3(vertex.pos.x, vertex.pos.y, 0.0);
    out.clip_position = world_pos_to_ndc_3d(vertex.pos);
    out.pos = vertex.pos;
    out.normal = vertex.normal;
    out.color = vertex.color;
    out.uv = vertex.uv;
    return out;
}



const OUT_OF_BOUNDS : u32 = CHUNK_SIZE_PADDED * CHUNK_SIZE_PADDED;
fn local_pos_to_chunk_idx(local_pos: i2) -> u32 {
    // out of this chunk is -1
    if local_pos.x < -1 || local_pos.y < -1 || local_pos.x > CHUNK_SIZE_I || local_pos.y > CHUNK_SIZE_I {
        return OUT_OF_BOUNDS;
    } else {
        return u32(local_pos.x + 1) + u32(local_pos.y + 1) * CHUNK_SIZE_PADDED;
    }
}


fn world_pos_to_hex_visibility(w_pos: vec2<f32>) -> f32 {
    let hex_pos_float = world_to_hex_pos(w_pos);

    let hex_pos = i2(i32(floor(hex_pos_float.x)), i32(floor(hex_pos_float.y)));
    let a_local_pos : i2 = hex_pos - hex_chunk_terrain.chunk_pos * CHUNK_SIZE_I;
    let c_local_pos : i2 = a_local_pos + i2(1,1);
    let a_idx : u32 = local_pos_to_chunk_idx(a_local_pos);
    let c_idx : u32 = local_pos_to_chunk_idx(c_local_pos);
    let a_vis : f32 = select(get_visibility(a_idx), 0.0, a_idx == OUT_OF_BOUNDS);
    let c_vis : f32 = select(get_visibility(c_idx), 0.0, c_idx == OUT_OF_BOUNDS);
    /*

    barycentric coordinates: p = aA + bB + cC    or   p = aA + cC + dD
    so in the ABC triangle: 
        x = a*0 + 1*b + 1*c    -> b = x - c    -> b = x - y
        y = a*0 + 0*b + 1*c                    -> c = y
        a = 1 - b - c                          -> a = 1 - x

    in the ACD triangle:
        x = a*0 + 1*c + 0*d                           ->  c = x
        y = a*0 + 1*c + 1*d    -> y = c + d = x + d   ->  d = y - x
        a = 1 - c - d          -> a = 1 - x - (y-x)   ->  a = 1 - y

               
    D _________ C
     |       / |
     |     /   |
     |   /     |     p is in one of the triangles ABC or ACD
     | /       |
     -----------
    A            B

    */
    let x = fract(hex_pos_float.x);
    let y = fract(hex_pos_float.y);
    if x > y {
        let b_local_pos : i2 = a_local_pos + i2(1,0);
        let b_idx : u32 = local_pos_to_chunk_idx(b_local_pos);
        let b_vis : f32 = select(get_visibility(b_idx), 0.0, b_idx == OUT_OF_BOUNDS);
        // calculate barycentric vis interpolation for ABC triangle
        let vis = (1 - x) * a_vis + (x - y) * b_vis + y * c_vis;
        return vis;
    } else {
        let d_local_pos : i2 = a_local_pos + i2(0,1);
        let d_idx : u32 = local_pos_to_chunk_idx(d_local_pos);
        let d_vis : f32 = select(get_visibility(d_idx), 0.0, d_idx == OUT_OF_BOUNDS);

        // calculate barycentric vis interpolation for ACD triangle
        let vis = (1 - y) * a_vis + x * c_vis + (y - x) * d_vis;
        return vis;
    }
}


@fragment
fn fs_hex_mask(in: VertexOutput) -> @location(0) vec4<f32>  {

    // let blend_rev = smoothstep(1.5,0.0, in.pos.z);
    // let blend : f32 = 1.0 - (blend_rev * blend_rev * blend_rev *blend_rev);
    
    // let normal = mix(TERRAIN_NORMAL, in.normal, blend);
    // let light: f32 = max(dot(normal,normalize(LIGHT_DIR)),0.05);
    // var color_w_light = in.color.rgb * light;

    // return vec4f(vec3f(in.pos.z), 1.0);

    // let vis = world_pos_to_hex_visibility(in.pos.xy);
    let vis = 1.0;

    var center = globals.xxx.zw;
    center = world_to_hex_pos(center);
    center = hex_to_world_pos(i2(i32(center.x), i32(center.y)));

    var grad = dist_gradient(in.pos.xy, center);
    grad.a = 0.3;

    let vis_col = v3(vis) * 2.0 -1.0;
    let vis_n = vis_noised(vis, in.pos.xy);

    let color = calculate_color(in.color, in.normal, in.pos.z);
    let fading_color = v4(color.rgb, color.a * vis_n);
    return fading_color;
    // return v4(v3(vis), 0.9);
}

fn vis_noised(vis: f32, w_pos: vec2<f32>) -> f32 {
    let vis_noise_stregth = 1.0 - vis;
    let noise = noise2(w_pos * 1.3  + globals.time_secs *0.3) + noise2((w_pos + globals.time_secs*0.5) * 3.127) - 2.0;
    return clamp(vis + vis_noise_stregth * noise, 0.0, 1.0);
}
