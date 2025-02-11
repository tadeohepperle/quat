struct Globals {
    camera_proj: mat3x3<f32>, // note: padded like this: (f,f,f,_,  f,f,f,_,  f,f,f,_)
    camera_pos: vec2<f32>,
    camera_height: f32, 
    time_secs: f32,
    screen_size: vec2<f32>,
    cursor_pos: vec2<f32>,
}
@group(0) @binding(0)
var<uniform> globals: Globals;

alias v4 = vec4<f32>;
alias v3 = vec3<f32>;
alias v2 = vec2<f32>;

fn world_pos_to_ndc(world_pos: vec2<f32>) -> vec4<f32> {
    let world_pos_3 = vec3<f32>(world_pos, 1.0);
    let ndc = globals.camera_proj * world_pos_3;
    return vec4<f32>(ndc.x, ndc.y, 0.0, 1.0);
}

// same as world_pos_to_ndc_3d but the z value has no effect on the screen coordinates, just used for depth buffer (height in z space (orthogonal to ground plane))
fn world_pos_to_ndc_with_z(world_pos: vec2<f32>, z: f32) -> vec4<f32> {
    let world_pos_3 = vec3<f32>(world_pos, 1.0);
    let ndc = globals.camera_proj * world_pos_3;
    return vec4<f32>(ndc.x, ndc.y, z_to_depth(z), 1.0);
}
// same right handed coordinate system as in blender, x and y on the plane, z for height of e.g. walls
const WORLD_Z_SQUASH_FACTOR: f32 = 0.5;
fn world_pos_to_ndc_3d(pos3: vec3<f32>) -> vec4<f32> {
    // military projection, every z step up, gets you half a y step:
    let extended_pos2 = vec3<f32>(pos3.x, pos3.y + pos3.z * WORLD_Z_SQUASH_FACTOR, 1.0);
	let ndc = globals.camera_proj * extended_pos2;
	return vec4<f32>(ndc.x, ndc.y, z_to_depth(pos3.z),1.0);
}


const MAX_SCENE_HEIGHT: f32 = 20.0;
const MAX_SCENE_HEIGHT_2: f32 = MAX_SCENE_HEIGHT * 2.0;
fn z_to_depth(z: f32) -> f32 {
    return z / MAX_SCENE_HEIGHT_2 + 0.5;
}

const SCREEN_REFERENCE_SIZE: vec2<f32> = vec2<f32>(1920.0, 1080.0);
fn ui_layout_pos_to_ndc(ui_layout_pos: vec2<f32>) -> vec4<f32> {
    let screen_size_r = vec2(SCREEN_REFERENCE_SIZE.y * globals.screen_size.x / globals.screen_size.y, SCREEN_REFERENCE_SIZE.y);
    let ndc = ui_layout_pos / screen_size_r * 2.0  -1.0;
    return  vec4(ndc.x, -ndc.y, 0.0, 1.0);
}

const RED : vec4<f32> = vec4<f32>(1.0, 0.0, 0.0, 1.0);
const GREEN : vec4<f32> = vec4<f32>(0.0, 1.0, 0.0, 1.0);
const BLUE : vec4<f32> = vec4<f32>(0.0, 0.0, 1.0, 1.0);
const BLACK : vec4<f32> = vec4<f32>(0.0, 0.0, 0.0, 1.0);

fn osc(speed: f32, low: f32, high: f32) -> f32 {
    let half_diff = (high - low) / 2.0;
    return sin(globals.time_secs * speed) * half_diff + low + half_diff;
}
