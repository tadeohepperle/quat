#import globals.wgsl

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

const LIGHT_DIR : v3 = v3(0.0,0.5,1.3);
const TERRAIN_NORMAL : v3 = v3(0.0,0.0,1.0);
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    


    let blend_rev = smoothstep(1.5,0.0, in.pos.z);
    let blend : f32 = 1.0 - (blend_rev * blend_rev * blend_rev *blend_rev);
    
    let normal = mix(TERRAIN_NORMAL, in.normal, blend);
    let light: f32 = max(dot(normal,normalize(LIGHT_DIR)),0.05);
    var color_w_light = in.color.rgb * light;

    // return vec4f(vec3f(in.pos.z), 1.0);
    return v4(color_w_light, blend);
}

