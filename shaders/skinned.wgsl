#import utils.wgsl

@group(2) @binding(0)
var<storage, read> bones_buffer: array<Affine2>;

@group(3) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(3) @binding(1)
var s_diffuse: sampler;

struct SkinnedPushConstants {
    color: Vec4,
    pos: Vec2,
    _pad: Vec2, 
}
var<push_constant> push: SkinnedPushConstants;

struct Affine2 {
      m: mat2x2<f32>,
    offset: Vec2,
    _pad: Vec2, // because in Odin {m: Mat2, offeset: Vec2} has size 32 and align 16.
    // we could get around that though later, optimizing the Odin side to not use Mat2 there anymore 
}

struct Vertex {
    @location(0) pos: Vec2,
    @location(1) uv: Vec2,
    @location(2) indices: vec2<u32>, // max weights 2, can be extended to 4 later
    @location(3) weights: Vec2,
}

struct VertexOutput {
    @builtin(position) clip_position: Vec4,
    @location(0) uv: Vec2,
}

fn apply(affine: Affine2, p: Vec2) -> Vec2 {
    return affine.m * p + affine.offset;
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    // let pos1: Vec2 = apply(bones_buffer[vertex.indices[0]], vertex.pos) * vertex.weights[0];
    // let pos2: Vec2 = apply(bones_buffer[vertex.indices[1]], vertex.pos) * vertex.weights[1];
    // let pos = pos1 + pos2 + push.pos;

    let bone_0 = bones_buffer[vertex.indices[0]];
    let bone_1 = bones_buffer[vertex.indices[1]];
    let pos = apply(bone_0, vertex.pos) * vertex.weights[0] + apply(bone_1, vertex.pos) * vertex.weights[1];
    let z: f32 = 0.5; // placeholder, add depth logic later
    var out: VertexOutput;
    out.clip_position = world_2d_pos_to_clip_pos_with_z(pos, z);
    out.uv = vertex.uv;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) Vec4 {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    return image_color * push.color;
    // return  image_color; //  Vec4(1.0,0.0,1.0,1.0);
}
