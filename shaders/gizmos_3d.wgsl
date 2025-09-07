#import utils.wgsl


struct Vertex {
    @location(0) pos:      Vec3,
    @location(1) color:    Vec4,
}

struct VertexOutput{
    @builtin(position) clip_position: Vec4,
    @location(0) color: Vec4,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = camera3d.view_proj * Vec4(vertex.pos, 1.0); //  
    out.color = vertex.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) Vec4  {
    return in.color;
}
