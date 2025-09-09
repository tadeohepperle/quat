#import utils.wgsl

@group(2) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(2) @binding(1)
var s_diffuse: sampler;

struct Vertex {
    @location(0) pos:   Vec3,
    @location(1) normal: Vec3,
    @location(2) uv:    Vec2,
    @location(3) color: Vec4,
    @location(4) tangent: Vec3,
}

struct Instance {
    @location(5) transform_col_0:   Vec4,
    @location(6) transform_col_1:   Vec4,
    @location(7) transform_col_2:   Vec4,
    @location(8) transform_col_3:   Vec4,
}

struct VertexOutput{
    @builtin(position) clip_position: Vec4,
    @location(0) normal: Vec3,
    @location(1) uv:     Vec2,
    @location(2) color:  Vec4,
}

@vertex
fn vs_main(vertex: Vertex, instance: Instance) -> VertexOutput {
    var out: VertexOutput;

    let transform : Mat4 = Mat4(instance.transform_col_0, instance.transform_col_1, instance.transform_col_2, instance.transform_col_3);
    out.clip_position = camera3d.view_proj * transform * Vec4(vertex.pos,1.0);
    out.color = Vec4(1,0,0,1);
    out.uv = vertex.uv;
    out.normal = vertex.normal;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) Vec4  {
    let light = max(dot(LIGHT_DIR, in.normal), 0.0) + 0.1;
    return Vec4(light, light, light, 1.0);
}
