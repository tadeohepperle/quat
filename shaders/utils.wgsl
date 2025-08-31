@group(0) @binding(0) var<uniform> frame: Frame;
struct Frame {
	screen_size:                  vec2<f32>,
	cursor_pos:                   vec2<f32>,
	xxx:                          vec4<f32>, // experimental values
    total_time:                   f32,
	space_ctrl_shift_alt_pressed: u32, // (bool, bool, bool, bool)
}

@group(1) @binding(0) var<uniform> camera: Camera2D;
struct Camera2D {
    proj:             mat3x3<f32>, // note: padded like this: (f,f,f,_,  f,f,f,_,  f,f,f,_)
    pos:              vec2<f32>,
    height:           f32, 
}

alias v4 = vec4<f32>;
alias v3 = vec3<f32>;
alias v2 = vec2<f32>;
alias i2 = vec2<i32>;

fn world_2d_pos_to_ndc(world_pos: vec2<f32>) -> vec4<f32> {
    let world_pos_3 = vec3<f32>(world_pos, 1.0);
    let ndc = camera.proj * world_pos_3;
    return vec4<f32>(ndc.x, ndc.y, 0.0, 1.0);
}

// same as world_2d_pos_to_ndc_3d but the z value has no effect on the screen coordinates, just used for depth buffer (height in z space (orthogonal to ground plane))
// fn world_2d_pos_to_ndc_with_z(world_pos: vec2<f32>, z: f32) -> vec4<f32> {
//     let world_pos_3 = vec3<f32>(world_pos, 1.0);
//     let ndc = camera.proj * world_pos_3;
//     return vec4<f32>(ndc.x, ndc.y, z_to_depth(z), 1.0);
// }
// same right handed coordinate system as in blender, x and y on the plane, z for height of e.g. walls
const WORLD_UI_Z_SQUASH_FACTOR: f32 = 0.5;

// fn world_2d_pos_to_ndc_3d(pos3: vec3<f32>) -> vec4<f32> {
//     // military projection, every z step up, gets you half a y step:
//     let extended_pos2 = vec3<f32>(pos3.x, pos3.y + pos3.z * WORLD_UI_Z_SQUASH_FACTOR, 1.0);
// 	let ndc = camera.proj * extended_pos2;
// 	return vec4<f32>(ndc.x, ndc.y, z_to_depth(pos3.z),1.0);
// }


const MAX_SCENE_HEIGHT: f32 = 20.0;
const MAX_SCENE_HEIGHT_2: f32 = MAX_SCENE_HEIGHT * 2.0;
fn z_to_depth(z: f32) -> f32 {
    return z / MAX_SCENE_HEIGHT_2 + 0.5;
}

fn screen_pos_to_ndc(screen_pos: vec2<f32>) -> vec4<f32> {
    let ndc = screen_pos / frame.screen_size * 2.0  -1.0;
    return  vec4(ndc.x, -ndc.y, 0.0, 1.0);
}

// fn ui_layout_pos_to_ndc(ui_layout_pos: vec2<f32>) -> vec4<f32> {
//     let ndc = ui_layout_pos / globals.screen_ui_layout_extent * 2.0  -1.0;
//     return  vec4(ndc.x, -ndc.y, 0.0, 1.0);
// }

const RED : vec4<f32> = vec4<f32>(1.0, 0.0, 0.0, 1.0);
const GREEN : vec4<f32> = vec4<f32>(0.0, 1.0, 0.0, 1.0);
const BLUE : vec4<f32> = vec4<f32>(0.0, 0.0, 1.0, 1.0);
const BLACK : vec4<f32> = vec4<f32>(0.0, 0.0, 0.0, 1.0);

fn osc(speed: f32, low: f32, high: f32) -> f32 {
    let half_diff = (high - low) / 2.0;
    return sin(frame.total_time * speed) * half_diff + low + half_diff;
}

fn dist_gradient(pt: vec2f, center: vec2f) -> vec4f {
    let frequency = 20.0;
    let d = length(pt - center); // Compute distance to the target point
    let t = 0.5 + 0.5 * cos(d * frequency); // Create a repeating gradient with cosine
    return vec4f(t, t * 0.5, 1.0 - t, 1.0); // Map to a color gradient (blue to cyan)
}

fn unit_uv_from_idx(idx: u32) -> vec2<f32> {
    return vec2<f32>(
        f32(((idx << 1) & 2) >> 1),
        f32((idx & 2) >> 1)
    );
}

fn map_unit_uv(u_uv: vec2<f32>, uv_aabb: vec4<f32>) -> vec2<f32> {
    return vec2<f32>(
        (1.0 - u_uv.x) * uv_aabb.x + u_uv.x * uv_aabb.z,
        u_uv.y * uv_aabb.y + (1.0 - u_uv.y) * uv_aabb.w
    );
}

fn rotate(pos: vec2<f32>, rot: f32) -> vec2<f32>{
    let s = sin(rot);
    let c = cos(rot);
    return vec2<f32>(
        c * pos.x - s * pos.y,
        s * pos.x + c * pos.y,
    );
}