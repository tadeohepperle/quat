#import globals.wgsl

@group(1) @binding(0)
var<storage, read> bones_buffer: array<Affine2>;

@group(2) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(2) @binding(1)
var s_diffuse: sampler;

struct SkinnedPushConstants {
    color: vec4<f32>,
    pos: vec2<f32>,
    _pad: vec2<f32>, 
}
var<push_constant> push: SkinnedPushConstants;

struct Affine2 {
    m: mat2x2<f32>,
    offset: vec2<f32>,
    _pad: vec2<f32>, // because in Odin {m: Mat2, offeset: Vec2} has size 32 and align 16.
    // we could get around that though later, optimizing the Odin side to not use Mat2 there anymore 
}

struct Vertex {
    @location(0) pos: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) indices: vec2<u32>, // max weights 2, can be extended to 4 later
    @location(3) weights: vec2<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

fn apply(affine: Affine2, p: vec2<f32>) -> vec2<f32> {
    return affine.m * p + affine.offset;
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    // let pos1: vec2<f32> = apply(bones_buffer[vertex.indices[0]], vertex.pos) * vertex.weights[0];
    // let pos2: vec2<f32> = apply(bones_buffer[vertex.indices[1]], vertex.pos) * vertex.weights[1];
    // let pos = pos1 + pos2 + push.pos;
    let pos = apply(bones_buffer[vertex.indices[0]], vertex.pos) * vertex.weights[0] + apply(bones_buffer[vertex.indices[1]], vertex.pos) * vertex.weights[1];
    let z: f32 = 1.0; // placeholder, add depth logic later
    var out: VertexOutput;
    out.clip_position = world_pos_to_ndc_with_z(pos, z);
    out.uv = vertex.uv;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    return image_color * push.color;
    // return  image_color; //  vec4<f32>(1.0,0.0,1.0,1.0);
}
