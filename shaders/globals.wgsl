struct Globals{
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
	return vec4<f32>(ndc.x, ndc.y, 0.0,1.0);
}

fn world_pos_to_ndc_with_z(world_pos: vec2<f32>, z: f32) -> vec4<f32> {
    let world_pos_3 = vec3<f32>(world_pos, 1.0);
	let ndc = globals.camera_proj * world_pos_3;
	return vec4<f32>(ndc.x, ndc.y, calc_depth(z), 1.0);
}

const BUFFER_ZONE_FACTOR : f32 = 0.5;
// input z is the world z coordinate, the output depth in screen space 0 to 1, 0 is far, 1 is close
fn calc_depth(z: f32) -> f32 {
    return (globals.camera_pos.y-z) * BUFFER_ZONE_FACTOR/globals.camera_height + 0.5;
}

// the offset is in world z coordinates, the output depth in screen space 0 to 1
fn calc_depth_offset(z_from_0_to_1: f32) -> f32 {
    // z_from_0_to_1 needs to be mapped to the scale -1,1
    return  (z_from_0_to_1 * 2.0 - 1) * BUFFER_ZONE_FACTOR / globals.camera_height;
}

const SCREEN_REFERENCE_SIZE: vec2<f32> = vec2<f32>(1920, 1080);
fn ui_layout_pos_to_ndc(ui_layout_pos: vec2<f32>) -> vec4<f32>{
	let screen_size_r = vec2(SCREEN_REFERENCE_SIZE.y * globals.screen_size.x / globals.screen_size.y, SCREEN_REFERENCE_SIZE.y);
	let ndc = ui_layout_pos / screen_size_r * 2.0  -1.0;
    return  vec4(ndc.x, -ndc.y, 0.0, 1.0);
}

const RED : vec4<f32> = vec4<f32>(1.0,0.0,0.0,1.0);
const GREEN : vec4<f32> = vec4<f32>(0.0,1.0,0.0,1.0);
const BLUE : vec4<f32> = vec4<f32>(0.0,0.0,1.0,1.0);
const BLACK : vec4<f32> = vec4<f32>(0.0,0.0,0.0,1.0);


fn osc(speed: f32, low: f32, high: f32) -> f32 {
    let half_diff = (high-low)/2.0;
    return sin(globals.time_secs * speed) * half_diff + low + half_diff;
}
