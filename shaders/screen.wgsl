alias Vec2  = vec2<f32>;
alias Vec4  = vec4<f32>;

struct VertexOutput {
    @location(0) uv: Vec2,
    @builtin(position) clip_position: Vec4,
};

@vertex
fn vs_main(
    @builtin(vertex_index) vi: u32,
) -> VertexOutput {
    var out: VertexOutput;
    // Generate a triangle that covers the whole screen
    out.uv = Vec2(
        f32((vi << 1u) & 2u),
        f32(vi & 2u),
    );
    out.clip_position = Vec4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    // // invert y coordinate so the image is not upside down:
    out.uv.y = 1.0 - out.uv.y;
    return out;
}
