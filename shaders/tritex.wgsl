#import globals.wgsl
#import noise.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d_array<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

struct Vertex {
    @location(0) pos:        vec2<f32>,
    @location(1) indices: vec3<u32>,
    @location(2) weights: vec3<f32>,
}

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) pos:     vec2<f32>,
    @location(1) indices: vec3<u32>,
    @location(2) weights: vec3<f32>,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var pos = vertex.pos;
    // let n = perlinNoise2(pos *23.7) -0.5 ;
    // pos += n * 0.1  ; 
    var out: VertexOutput;
    out.clip_position = world_pos_to_ndc(vec2(pos.x, pos.y /1.0));
    out.pos = pos;
    out.indices = vertex.indices;
    out.weights = vertex.weights;
    return out;
}




const SQRT_3_HALF: f32 = 0.86602540378;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    let n = perlinNoise2(in.pos *0.7);

    var weights = in.weights;               



    // let min_weight = select(&weights[0], &weights[1], in.indices[0] > in.indices[1]);
    
    // let min_idx : u32 = min(min(in.indices[0], in.indices[1]), in.indices[2]);
    let idx_a = in.indices[0];
    let idx_b = in.indices[1];
    let idx_c = in.indices[2];
    let max_i: u32 = select(select(0u, 1u, idx_b > idx_a),2u, idx_c > max(idx_b, idx_a));

   
    let hex_dist = length(offset_hex_center(in.pos));
    let alter_factor = 1.0 - smoothstep(0.45,0.5, hex_dist);
              
    // weights[max_i]  *= (n + 0.5 )* alter_factor;
     weights = accentuate_weights_exp(weights,9.0);



    let sample_uv = in.pos * 0.2; // (in.pos  + (dir_2d * n * 0.2)) * 0.4;
    let color_0 = textureSample(t_diffuse, s_diffuse, sample_uv, in.indices[0]).rgb;
    let color_1 = textureSample(t_diffuse, s_diffuse, sample_uv, in.indices[1]).rgb;
    let color_2 = textureSample(t_diffuse, s_diffuse, sample_uv, in.indices[2]).rgb;
    var color: vec3<f32> = (color_0 * weights[0] + color_1 * weights[1] + color_2 * weights[2]);
    
    // color = textureSample(t_diffuse, s_diffuse, sample_uv, in.indices[max_i]).rgb;
    
    // color = (in.direction + 1.0) /2.0;
    // let l = smoothstep(0.3,0.4,length(dir_2d));
    // let l = length(weights);
    // color += vec3f(alter_factor) * 0.7; 
    return vec4(color,1.0) ;
}

const s: vec2<f32> = vec2<f32>(1, 1.7320508); // 1.7320508 = sqrt(3)
/// see: https://www.shadertoy.com/view/ll3yW7
fn offset_hex_center(pos: vec2f) -> vec2<f32>{
    let p = pos / 1.7320508;
    let hex_center: vec4<f32> = round(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy);
    let offset: vec4<f32> = vec4(p - hex_center.xy * s, p - (hex_center.zw + .5) * s);
    return select(offset.zw, offset.xy, dot(offset.xy, offset.xy) < dot(offset.zw, offset.zw));
}


fn accentuate_weights_exp(weights: vec3<f32>, exponent: f32) -> vec3<f32> {
    let pow_weights = vec3<f32>(
        pow(weights.x, exponent),
        pow(weights.y, exponent),
        pow(weights.z, exponent)
    );
    let sum = pow_weights.x + pow_weights.y + pow_weights.z;
    return pow_weights / sum;
}

fn accentuate_weights_exp_norm(weights: vec3<f32>, exponent: f32) -> vec3<f32> {
    let pow_weights = vec3<f32>(
        pow(weights.x, exponent),
        pow(weights.y, exponent),
        pow(weights.z, exponent)
    );
    return normalize(pow_weights);
}