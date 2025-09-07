#import utils.wgsl

@group(2) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(2) @binding(1)
var s_diffuse: sampler;

struct Vertex {
    @location(0) pos:   Vec2,
    @location(1) uv:    Vec2,
    @location(2) color: Vec4,
}

struct VertexOutput{
    @builtin(position) clip_position: Vec4,
    @location(0) uv:    Vec2,
    @location(1) color: Vec4,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = world_2d_pos_to_clip_pos(vertex.pos);
    out.uv = vertex.uv;
    out.color = vertex.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) Vec4  {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    return image_color * in.color;
}
