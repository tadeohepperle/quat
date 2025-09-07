#import utils.wgsl

const GIZMOS_MODE_WORLD: u32 = 0u;
const GIZMOS_MODE_UI : u32 = 1u;
var<push_constant> gizmos_mode: u32;

struct Vertex {
    @location(0) pos:      Vec2,
    @location(1) color:    Vec4,
}

struct VertexOutput{
    @builtin(position) clip_position: Vec4,
    @location(0) color: Vec4,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    switch gizmos_mode {
        case GIZMOS_MODE_WORLD: {
            out.clip_position = world_2d_pos_to_clip_pos(vertex.pos);
        }
        case GIZMOS_MODE_UI, default: {
            out.clip_position = screen_pos_to_clip_pos(vertex.pos);
        }
    }
    out.color = vertex.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) Vec4  {
    return in.color;
}
