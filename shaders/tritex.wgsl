#import utils.wgsl
#import noise.wgsl

@group(2) @binding(0)
var t_diffuse: texture_2d_array<f32>;
@group(2) @binding(1)
var s_diffuse: sampler;

struct Vertex {
    @location(0) pos:     Vec2,
    @location(1) indices: vec3<u32>,
    @location(2) weights: Vec3,
}

struct VertexOutput{
    @builtin(position) clip_position: Vec4,
    @location(0) pos:     Vec2,
    @location(1) indices: vec3<u32>,
    @location(2) weights: Vec3,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var pos = vertex.pos;
    // let n = perlinNoise2(pos *23.7) -0.5 ;
    // pos += n * 0.1  ; 
    var out: VertexOutput;
    out.clip_position = world_2d_pos_to_clip_pos(vec2(pos.x, pos.y /1.0));
    out.pos = pos;
    out.indices = vertex.indices;
    out.weights = vertex.weights;
    return out;
}




fn noise_based_on_indices(pos: Vec2, indices: vec3<u32>, wavelength: f32, amplitude: f32, seed: f32) -> Vec3 {
    let offset = pos / wavelength ;
    // let offset = (pos + frame.total_time * 0.05)/ wavelength ;
    let off_a = offset + (f32(indices[0]) + seed);
    let off_b = offset + (f32(indices[1]) + seed);
    let off_c = offset + (f32(indices[2]) + seed);
    let noise_val : Vec3 = Vec3(
        noise2(off_a),
        noise2(off_b),
        noise2(off_c),
    );
    return noise_val * amplitude;
}

const SQRT_3_HALF: f32 = 0.86602540378;
const WAVELENGTH: f32 = 0.3;
const AMPLITUDE: f32 = 0.15;
const SEED: f32 = 1.2832;
const BLUR: f32 = 0.4;

fn texture_rgb(sample_uv: Vec2, idx: u32) ->Vec4{

    return select(textureSample(t_diffuse, s_diffuse, sample_uv, idx-1).rgba, Vec4(0.0), idx == 0);
}


const DEBUG_HEX_BORDERS : bool = false;
@fragment
fn fs_main(in: VertexOutput) -> @location(0) Vec4  {
    let n = perlinNoise2(in.pos *0.7);
    // let color_0 = RED.rgb;  
    // let color_1 = GREEN.rgb;
    // let color_2 = BLUE.rgb;  

    let sample_uv = in.pos * 0.1; 
    let color_0 =  texture_rgb(sample_uv, in.indices[0]);
    let color_1 =  texture_rgb(sample_uv, in.indices[1]);
    let color_2 =  texture_rgb(sample_uv, in.indices[2]);
    var weights = in.weights;
  
    // weights *= Vec3(color_0.a,color_1.a,color_2.a);       

    let noise_octave_1 = noise_based_on_indices(in.pos, in.indices, WAVELENGTH, AMPLITUDE, SEED);
    let noise_octave_2 = noise_based_on_indices(in.pos, in.indices, WAVELENGTH /2, AMPLITUDE /2,SEED);
    let noise_octave_3 = noise_based_on_indices(in.pos, in.indices, WAVELENGTH /4, AMPLITUDE /4, SEED);
    // let noise_octave_4 = noise_based_on_indices(in.pos, in.indices, WAVELENGTH /8, AMPLITUDE /8);
    let noise_total = noise_octave_1 + noise_octave_2 + noise_octave_3;
    let noise_mul_w = weights * noise_total;
    let noise_scalar = (noise_mul_w.x + noise_mul_w.y + noise_mul_w.z ) / 3.0;
    weights += noise_total;
    weights += 0.3;

    // weights /= length(weights);
    // OPTION 1:

    let blur = BLUR;

    let col_1_2 = mix(
        color_1,
        color_2,
        smoothstep(blur, -blur, weights.y - weights.z)
    );
    let color = mix(
        col_1_2,
        color_0,
        smoothstep(blur, -blur, max(weights.y, weights.z) - weights.x)
    );

    // OPTION 2:

    // weights = accentuate_weights_exp(weights, 10.0);
    // let color = weights[0] * color_0 + weights[1] * color_1 + weights[2] * color_2;

    // OPTION 3:

    // weights = accentuate_weights_exp(weights, 10.0);
    // let color = weights[0] * color_0 + weights[1] * color_1 + weights[2] * color_2;
 
    var mod_color = mix(Vec3(noise_scalar), color.rgb, color.a);
    if DEBUG_HEX_BORDERS{
  let val : f32 = max(in.weights.x, max(in.weights.z, in.weights.y)) + min(in.weights.x, min(in.weights.z, in.weights.y));
   if val < 0.6 {
        mod_color = Vec3(0.0);
   }
    }
 

    return vec4(mod_color, color.a) ;
}

fn blend_colors_with_blur(weights: Vec3, color_0: Vec3, color_1: Vec3, color_2: Vec3, blur: f32) -> Vec3 {
    // First blend between color_1 and color_2 based on their relative weights
    let col_1_2 = mix(
        color_1,
        color_2,
        smoothstep(blur, -blur, weights.y - weights.z)
    );
    
    // Then blend between color_0 and the previous blend result
    let final_color = mix(
        color_0,
        col_1_2,
        smoothstep(blur, -blur, weights.y - weights.x)
    );
    
    return final_color;
}

const s: Vec2 = Vec2(1, 1.7320508); // 1.7320508 = sqrt(3)
/// see: https://www.shadertoy.com/view/ll3yW7
fn offset_hex_center(pos: Vec2) -> Vec2{
    let p = pos / 1.7320508;
    let hex_center: Vec4 = round(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy);
    let offset: Vec4 = vec4(p - hex_center.xy * s, p - (hex_center.zw + .5) * s);
    return select(offset.zw, offset.xy, dot(offset.xy, offset.xy) < dot(offset.zw, offset.zw));
}

fn accentuate_weights_max(weights: Vec3) -> Vec3 {
    let max_weight = max(max(weights.x, weights.y), weights.z);
    return Vec3(
        select(0.0, 1.0, weights.x >= max_weight),
        select(0.0, 1.0, weights.y >= max_weight),
        select(0.0, 1.0, weights.z >= max_weight)
    );
}


fn accentuate_weights_exp(weights: Vec3, exponent: f32) -> Vec3 {
    let pow_weights = Vec3(
        pow(weights.x, exponent),
        pow(weights.y, exponent),
        pow(weights.z, exponent)
    );
    let sum = pow_weights.x + pow_weights.y + pow_weights.z;
    return pow_weights / sum;
}

fn accentuate_weights_exp_norm(weights: Vec3, exponent: f32) -> Vec3 {
    let pow_weights = Vec3(
        pow(weights.x, exponent),
        pow(weights.y, exponent),
        pow(weights.z, exponent)
    );
    return normalize(pow_weights);
}