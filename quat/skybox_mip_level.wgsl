@group(0)
@binding(0)
var src: texture_2d_array<f32>;

@group(0)
@binding(1)
var dst: texture_storage_2d_array<rgba32float, write>;

alias UVec2 = vec2<u32>;
alias IVec2 = vec2<i32>;
alias UVec3 = vec3<u32>;
alias Vec2 = vec2<f32>;
alias Vec4 = vec4<f32>;

// invoke for each pixel of destination image, assuming dst image is half the size of src image
@compute
@workgroup_size(16, 16, 1)
fn compute_mip_level(
    @builtin(global_invocation_id)
    gid: UVec3,
) {
    let src_size = textureDimensions(src);
    let src_sizei = IVec2(src_size);
    let dst_size = textureDimensions(dst);

    let dst_pos: UVec2 = gid.xy;
    let src_pos0: UVec2 = dst_pos * 2;
    if dst_pos.x >= dst_size.x || dst_pos.y >= dst_size.y {
        return;
    }

    let face: u32 = gid.z;

    var dst_pixel : Vec4 = Vec4(0.0);
    var weight_sum: f32 = 0.0;

    let R: i32 = 2;
    let max_d = length(Vec2(f32(R), f32(R)));

    for (var x: i32 = -R; x <= R+1; x+=1) {
        for (var y: i32 = -1; y <=2; y+=1) {
            let offset = IVec2(x,y);
            let src_pos: IVec2 = IVec2(src_pos0) + offset;
            if src_pos.x < 0 || src_pos.x >= src_sizei.x || src_pos.y < 0 || src_pos.y >= src_sizei.y {
                continue;
            }
            let d_norm = length(Vec2(offset) - Vec2(0.5,0.5)) / max_d;
            let weight = 1.0 -d_norm;
            dst_pixel += textureLoad(src, src_pos             , face, 0) * weight;
            weight_sum += weight;
        }
    }

    dst_pixel /= weight_sum;

    // // just average over 4 pixels in src
    // let dst_pixel = ( textureLoad(src, src_pos             , face, 0) 
    //                 + textureLoad(src, src_pos + UVec2(1,0), face, 0) 
    //                 + textureLoad(src, src_pos + UVec2(0,1), face, 0) 
    //                 + textureLoad(src, src_pos + UVec2(1,1), face, 0)
    //                 ) / 4.0;



    textureStore(dst, dst_pos, face, dst_pixel);
}
