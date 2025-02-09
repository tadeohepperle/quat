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

// same right handed coordinate system as in blender, x and y on the plane, z for height of e.g. walls
const SCENE_MAX_HEIGHT: f32 = 10.0;
const WORLD_Z_SQUASH_FACTOR: f32 = 0.5;
fn world_pos_to_ndc_3d(pos3: vec3<f32>) -> vec4<f32> {
    // military projection, every z step up, gets you half a y step:
    let extended_pos2 = vec3<f32>(pos3.x, pos3.y + pos3.z * WORLD_Z_SQUASH_FACTOR, 1.0);
	let ndc = globals.camera_proj * extended_pos2;
	return vec4<f32>(ndc.x, ndc.y, pos3.z/SCENE_MAX_HEIGHT,1.0);
}

