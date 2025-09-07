@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

// var<push_constant> world_transform: UiWorldTransform;
var<push_constant> legacy_ui_scaling_factor: f32;

var<push_constant> push_const: WorldUiPushConst;
struct WorldUiPushConst {
    ui_px_pos_to_clip_pos : Mat4,
	// at z = 0
	ui_px_per_screen_px_at_near_plane: f32,
	// at z = 1
	ui_px_per_screen_px_at_far_plane:  f32,
	_pad:                               Vec2,
}


// struct UiWorldTransform {
//     rot_scale : mat2x2<f32>,
//     offset:        Vec2,
// }

struct GlyphInstance {
	@location(0) pos:    Vec2,
	@location(1) size:   Vec2,
	@location(2) uv:     Vec4, // aabb
	@location(3) color:  Vec4,
	@location(4) shadow_and_bias: Vec2,
}

struct Vertex {
	@location(0) pos:           Vec2,
	@location(1) size:          Vec2,
	@location(2) uv:            Vec2,
	@location(3) color:         Vec4,
	@location(4) border_color:  Vec4,
	@location(5) border_radius: Vec4, // top left, top right, bottom right, bottom left
	@location(6) border_width:  Vec4, // todo!
	@location(7) flags: u32,
}

// Vertex flags:
// const TEXTURED: u32 = 1u; // not used anymore, just say all triangles are textured and set the white 1px texture as default
const RIGHT_VERTEX: u32 = 2u;
const BOTTOM_VERTEX: u32 = 4u;
const BORDER: u32 = 8u;


// uses the legacy_ui_scaling_factor push const
fn px_pos_to_screen_layout_clip_pos(layout_pos: Vec2) -> Vec4 {
    let legacy_ui_scaling_factor : f32= legacy_ui_scaling_factor;
    let ndc = (layout_pos * legacy_ui_scaling_factor) / frame.screen_size * 2.0  -1.0;
    return vec4(ndc.x, -ndc.y, 0.0, 1.0);
}

// uses the WorldUiPushConst push const containing a mvp matrix
fn px_pos_to_clip_pos(layout_pos: Vec2) -> Vec4{
    let ext = Vec4(layout_pos.x, layout_pos.y, 1.0, 1.0);
    // let screen_size = frame.screen_size;
    // let xs = 2.0/screen_size.x;
    // let ys = 2.0/screen_size.y;
    // let mvp = Mat4(
    //     xs    ,0    ,0    ,0      ,
    //     0     ,-ys  ,0    ,0      ,
    //     0     ,0    ,1    ,0      ,
    //     -1    ,1    ,0   ,1      ,
    // );
    // return mvp * ext;
    return push_const.ui_px_pos_to_clip_pos * ext;
}

@vertex
fn vs_rect_legacy_screen_render(vertex: Vertex) -> VsRectOut {
    let clip_pos =  px_pos_to_screen_layout_clip_pos(vertex.pos);
	return _vs_rect(vertex, clip_pos);
}
@vertex
fn vs_rect(vertex: Vertex) -> VsRectOut {
    let clip_pos: Vec4 = px_pos_to_clip_pos(vertex.pos);
	return _vs_rect(vertex, clip_pos);
}

fn _vs_rect(vertex: Vertex, clip_pos: Vec4) -> VsRectOut {
	var out: VsRectOut;
    out.clip_position = clip_pos;
	var rel_pos = 0.5 * vertex.size;
    if (vertex.flags & RIGHT_VERTEX) == 0u {
        rel_pos.x *= -1.;
    }
    if (vertex.flags & BOTTOM_VERTEX) == 0u {
        rel_pos.y *= -1.;
    }
    out.uv = vertex.uv;
    out.rel_pos = rel_pos;
	out.size = vertex.size;
	out.color = vertex.color;
	out.border_color = vertex.border_color;
	out.border_radius = vertex.border_radius;
	out.border_width = vertex.border_width;
	out.flags = vertex.flags;
	return out;
}

struct VsRectOut {
    @builtin(position) clip_position:              Vec4,
    @location(0) rel_pos:                          Vec2, // pos relative to center of rect with size.
	@location(1) size:          Vec2, 
	@location(2) uv:                               Vec2,
	@location(3) color:                            Vec4,
	@location(4) border_color:                     Vec4,
    @location(5) border_radius: Vec4, // top left, top right, bottom right, bottom left
	@location(6) border_width:  Vec4, // todo!
	@location(7) flags:         u32,
}

@fragment
fn fs_rect_legacy_screen_render(in: VsRectOut) -> @location(0) Vec4 {
    // todo!
    // let screen_ui_pixels_on_screen = globals.screen_ui_layout_extent.y;
    // let softness = screen_ui_pixels_on_screen / globals.screen_size.y;
    let softness : f32 = legacy_ui_scaling_factor;
    return _fs_rect(in, softness);
}

@fragment
fn fs_rect(in: VsRectOut) -> @location(0) Vec4 {
    // todo: when adding 3d interpolate softness in fragment shader between near and far plane
    let softness : f32 = push_const.ui_px_per_screen_px_at_near_plane;
    return _fs_rect(in, softness);
}

// @fragment
// fn fs_rect_world(in: VsRectOut) -> @location(0) Vec4 {
//     // I have no idea if 8.0 is the right value here, but it looks fine visually.
//     // let softness = inverseSqrt(globals.camera_height);// globals.screen_ui_layout_extent.y / globals.screen_size.y / extra_factor;
    
//     // todo!
//     // let world_ui_pixels_on_screen = globals.world_ui_px_per_unit * globals.camera_height;
//     // let softness = world_ui_pixels_on_screen / globals.screen_size.y;


//     let softness : f32 = 1.0;
//     return fs_rect_both(in, softness);
// }

// softness is border softness
fn _fs_rect(in: VsRectOut, softness: f32) -> Vec4{
	let texture_color: Vec4 = textureSample(t_diffuse, s_diffuse, in.uv);
    var external_distance = rounded_box_sdf(in.rel_pos, in.size, in.border_radius);
    external_distance += min(in.border_width.x, 0.0); // little hack that allows you to set a negative border width, to essentially disable smoothing on external edge.
    // (this hack was important for color gradient meshes that are a bunch of small squares)
    let internal_distance = inset_rounded_box_sdf(in.rel_pos, in.size, in.border_radius, in.border_width);
	let not_ext_factor = smoothstep(softness,-softness, external_distance);  //  //select(1.0 - step(0.0, border_distance), antialias(border_distance), external_distance < internal_distance);
	let in_factor = smoothstep(softness, -softness, internal_distance);

	var solid_color = mix(in.border_color, in.color, in_factor);
    solid_color.a = saturate(solid_color.a * not_ext_factor);
    let final_color = color_texture_mix(solid_color, texture_color);

	return final_color;

    // return Vec4(legacy_ui_scaling_factor, legacy_ui_scaling_factor,legacy_ui_scaling_factor, 1.0);
}


fn color_texture_mix(color: Vec4, texture: Vec4) -> Vec4 {

    return color * texture;

    // if texture.a is 1  -> color * texture
    // if texture.a is 0  -> color
    // let rbg : Vec3 = mix(color.rgb, color.rgb * texture.rgb, texture.a);
    // return Vec4(rbg, color.a);
}

fn enabled(flags: u32, mask: u32) -> bool {
    return (flags & mask) != 0u;
}

fn rounded_box_sdf(offset: Vec2, size: Vec2, border_radius: Vec4) -> f32 {
    let r = select(border_radius.xw, border_radius.yz, offset.x > 0.0);
    let r2 = select(r.x, r.y, offset.y > 0.0);
    let q: Vec2 = abs(offset) - size / 2.0 + Vec2(r2);
    let q2: f32 = min(max(q.x, q.y), 0.0);
    let l = length(max(q, vec2(0.0)));
    return q2 + l - r2;
}

fn inset_rounded_box_sdf(rel_pos: Vec2, size: Vec2, radius: Vec4, inset: Vec4) -> f32 {
    let inner_size = size - inset.xy - inset.zw;
    let inner_center = inset.xy + 0.5 * inner_size - 0.5 * size;
    let inner_point = rel_pos - inner_center;
    var r: Vec4 = radius;
    r.x = r.x - max(inset.x, inset.y); // top left corner
    r.y = r.y - max(inset.z, inset.y); // top right corner 
    r.z = r.z - max(inset.z, inset.w); // bottom right corner
    r.w = r.w - max(inset.x, inset.w); // bottom left corner
    let half_size = inner_size * 0.5;
    let min_size = min(half_size.x, half_size.y);
    r = min(max(r, vec4(0.0)), Vec4(min_size));
    return rounded_box_sdf(inner_point, inner_size, r);
}

// get alpha for antialiasing for sdf
fn antialias(distance: f32) -> f32 {
    return clamp(0.0, 1.0, 0.5 - 2.0 * distance);
}

// /////////////////////////////////////////////////////////////////////////////
// SECTION: Glyphs
// /////////////////////////////////////////////////////////////////////////////

@vertex
fn vs_glyph_legacy_screen_render(@builtin(vertex_index) vertex_index: u32, instance: GlyphInstance) -> VsGlyphOut {
    let u_uv: Vec2 = unit_uv_from_idx(vertex_index);
	let uv = ((1.0 - u_uv) * instance.uv.xy + u_uv * instance.uv.zw);
	let vertex_pos: Vec2 = instance.pos + u_uv * instance.size;
	var out: VsGlyphOut;
    out.clip_position = px_pos_to_screen_layout_clip_pos(vertex_pos);
	out.color = instance.color;
	out.uv = uv;
	out.shadow_and_bias = instance.shadow_and_bias; 
	return out;
}


@vertex
fn vs_glyph(@builtin(vertex_index) vertex_index: u32, instance: GlyphInstance) -> VsGlyphOut {
    let u_uv: Vec2 = unit_uv_from_idx(vertex_index);
	let uv = ((1.0 - u_uv) * instance.uv.xy + u_uv * instance.uv.zw);
	let vertex_pos: Vec2 = instance.pos + u_uv * instance.size;
	var out: VsGlyphOut;
    let clip_pos: Vec4 = px_pos_to_clip_pos(vertex_pos);
    out.clip_position = clip_pos;
	out.color = instance.color;
	out.uv = uv;
	out.shadow_and_bias = instance.shadow_and_bias; 
	return out;
}

// copy of vs_glyph except for clip position, would be much nicer with some conditional compilation!!!
// @vertex
// fn vs_glyph_world(@builtin(vertex_index) vertex_index: u32, instance: GlyphInstance) -> VsGlyphOut {
//     let u_uv: Vec2 = unit_uv_from_idx(vertex_index);
// 	let uv = ((1.0 - u_uv) * instance.uv.xy + u_uv * instance.uv.zw);
// 	let v_pos: Vec2 = instance.pos + u_uv * instance.size;
// 	var out: VsGlyphOut;
//     out.clip_position = ui_world_2d_pos_to_clip_pos(v_pos); // ONLY DIFFERENCE!!
// 	out.color = instance.color;
// 	out.uv = uv;
// 	out.shadow_and_bias = instance.shadow_and_bias; 
// 	return out;
// }

struct VsGlyphOut {
    @builtin(position) clip_position: Vec4,
    @location(0) color: Vec4,
    @location(1) uv: Vec2,
    @location(2) shadow_and_bias: Vec2,
}

const SHARPNESS : f32 = 24.0;

@fragment
fn fs_glyph(in: VsGlyphOut) -> @location(0) Vec4 {
	let sdf: f32 = textureSample(t_diffuse, s_diffuse, in.uv).r;
    var sz : vec2<u32> = textureDimensions(t_diffuse, 0);
    var dx : f32 = dpdx(in.uv.x) * f32(sz.x);
    var dy : f32 = dpdy(in.uv.y) * f32(sz.y);
    var to_pixels : f32 = SHARPNESS * inverseSqrt(dx * dx + dy * dy);
    let inside_factor = clamp((sdf - 0.5) * to_pixels + 0.5 + in.shadow_and_bias.y, 0.0, 1.0);
    
    // smoothstep(0.5 - smoothing, 0.5 + smoothing, sample);
    let shadow_alpha = (1.0 - (pow(1.0 - sdf, 2.0)) )* in.shadow_and_bias.x * in.color.a ;
    let shadow_color = vec4(0.0,0.0,0.0,shadow_alpha);
    let color = mix(shadow_color, in.color, inside_factor);
    return color; // + Vec4(1,0,0,0.3); // * vec4(1.0,1.0,1.0,5.0);
}

// fn ui_world_2d_pos_to_clip_pos(ui_world_pos: Vec2) -> Vec4 {
//     let w_pos = ui_world_pos / globals.world_ui_px_per_unit;
//     let w_pos2 =  world_transform.rot_scale * Vec2(w_pos.x, -w_pos.y) + world_transform.offset;
//     let extended_w_pos = Vec3(w_pos2.x, w_pos2.y, 1.0);
// 	let ndc = globals.camera_proj * Vec3(w_pos2.x, w_pos2.y, 1.0);
//     return  vec4(ndc.x, ndc.y, 0.0, 1.0);
// }

#import utils.wgsl