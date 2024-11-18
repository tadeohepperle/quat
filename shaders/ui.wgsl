#import globals.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

struct GlyphInstance {
	@location(0) pos:    vec2<f32>,
	@location(1) size:   vec2<f32>,
	@location(2) uv:     vec4<f32>, // aabb
	@location(3) color:  vec4<f32>,
	@location(4) shadow: f32,
}

struct Vertex {
	@location(0) pos:           vec2<f32>,
	@location(1) size:          vec2<f32>,
	@location(2) uv:            vec2<f32>,
	@location(3) color:         vec4<f32>,
	@location(4) border_color:  vec4<f32>,
	@location(5) border_radius: vec4<f32>, // top left, top right, bottom right, bottom left
	@location(6) border_width: vec4<f32>, // todo!
	@location(7) flags: u32,
}

// Vertex flags:
const TEXTURED: u32 = 1u;
const RIGHT_VERTEX: u32 = 2u;
const BOTTOM_VERTEX: u32 = 4u;
const BORDER: u32 = 8u;



@vertex
fn vs_rect(vertex: Vertex) -> VsRectOut {
	var out: VsRectOut;
	out.clip_position = ui_layout_pos_to_ndc(vertex.pos);
	var rel_pos = 0.5 * vertex.size;
    if (vertex.flags & RIGHT_VERTEX) == 0u {
        rel_pos.x *= -1.;
    }
    if (vertex.flags & BOTTOM_VERTEX) == 0u {
        rel_pos.y *= -1.;
    }
    out.rel_pos = rel_pos;
	out.size = vertex.size;
	out.color = vertex.color;
	out.border_color = vertex.border_color;
	out.border_radius = vertex.border_radius;
	out.border_width = vertex.border_width;
	out.flags = vertex.flags;
	return out;
}

//  @interpolate(flat)

struct VsRectOut {
    @builtin(position) clip_position:              vec4<f32>,
    @location(0) rel_pos:                          vec2<f32>, // pos relative to center of rect with size.
	@location(1) size:          vec2<f32>, 
	@location(2) uv:                               vec2<f32>,
	@location(3) color:                            vec4<f32>,
	@location(4) border_color:                     vec4<f32>,
    @location(5) border_radius: vec4<f32>, // top left, top right, bottom right, bottom left
	@location(6) border_width:  vec4<f32>, // todo!
	@location(7) flags:         u32,
}

// @interpolate(flat) 
// @interpolate(flat) 
// @interpolate(flat) 

const softness_factor :f32 = SCREEN_REFERENCE_SIZE.y;

@fragment
fn fs_rect(in: VsRectOut) -> @location(0) vec4<f32> {

	let softness = softness_factor / globals.screen_size.y;
     
	let texture_color: vec4<f32> = textureSample(t_diffuse, s_diffuse, in.uv);
    var external_distance = rounded_box_sdf(in.rel_pos, in.size, in.border_radius);
    external_distance += min(in.border_width.x, 0.0); // little hack that allows you to set a negative border width, to essentially disable smoothing on external edge.
    // (this hack was important for color gradient meshes that are a bunch of small squares)
    let internal_distance = inset_rounded_box_sdf(in.rel_pos, in.size, in.border_radius, in.border_width);
	let not_ext_factor = smoothstep(softness,-softness, external_distance);  //  //select(1.0 - step(0.0, border_distance), antialias(border_distance), external_distance < internal_distance);
	let in_factor = smoothstep(softness, -softness, internal_distance);

	let color  = mix(in.border_color, in.color, in_factor);
	let t_color = select(color, color * texture_color, enabled(in.flags, TEXTURED));
		
	return vec4(t_color.rgb, saturate(color.a * not_ext_factor));
}

fn enabled(flags: u32, mask: u32) -> bool {
    return (flags & mask) != 0u;
}

fn rounded_box_sdf(offset: vec2<f32>, size: vec2<f32>, border_radius: vec4<f32>) -> f32 {
    let r = select(border_radius.xw, border_radius.yz, offset.x > 0.0);
    let r2 = select(r.x, r.y, offset.y > 0.0);
    let q: vec2<f32> = abs(offset) - size / 2.0 + vec2<f32>(r2);
    let q2: f32 = min(max(q.x, q.y), 0.0);
    let l = length(max(q, vec2(0.0)));
    return q2 + l - r2;
}

fn inset_rounded_box_sdf(rel_pos: vec2<f32>, size: vec2<f32>, radius: vec4<f32>, inset: vec4<f32>) -> f32 {
    let inner_size = size - inset.xy - inset.zw;
    let inner_center = inset.xy + 0.5 * inner_size - 0.5 * size;
    let inner_point = rel_pos - inner_center;
    var r: vec4<f32> = radius;
    r.x = r.x - max(inset.x, inset.y); // top left corner
    r.y = r.y - max(inset.z, inset.y); // top right corner 
    r.z = r.z - max(inset.z, inset.w); // bottom right corner
    r.w = r.w - max(inset.x, inset.w); // bottom left corner
    let half_size = inner_size * 0.5;
    let min_size = min(half_size.x, half_size.y);
    r = min(max(r, vec4(0.0)), vec4<f32>(min_size));
    return rounded_box_sdf(inner_point, inner_size, r);
}

// get alpha for antialiasing for sdf
fn antialias(distance: f32) -> f32 {
    return clamp(0.0, 1.0, 0.5 - 2.0 * distance);
}

// /////////////////////////////////////////////////////////////////////////////
// SECTION: Glyphs
// /////////////////////////////////////////////////////////////////////////////


fn screen_size_r() -> vec2<f32> {
	return vec2(SCREEN_REFERENCE_SIZE.y * globals.screen_size.x / globals.screen_size.y, SCREEN_REFERENCE_SIZE.y);
}

@vertex
fn vs_glyph(@builtin(vertex_index) vertex_index: u32, instance: GlyphInstance) -> VsGlyphOut {
    let u_uv: vec2<f32> = unit_uv_from_idx(vertex_index);
	let uv = ((1.0 - u_uv) * instance.uv.xy + u_uv * instance.uv.zw);
	let v_pos: vec2<f32> = instance.pos + u_uv * instance.size;
	var out: VsGlyphOut;
	out.clip_position = ui_layout_pos_to_ndc(v_pos);
	out.color = instance.color;
	out.uv = uv;
	out.shadow_intensity = instance.shadow; 
	return out;
}

struct VsGlyphOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) shadow_intensity: f32,
}

@fragment
fn fs_glyph(in: VsGlyphOut) -> @location(0) vec4<f32> {
	let sdf: f32 = textureSample(t_diffuse, s_diffuse, in.uv).r;
    var sz : vec2<u32> = textureDimensions(t_diffuse, 0);
    var dx : f32 = dpdx(in.uv.x) * f32(sz.x);
    var dy : f32 = dpdy(in.uv.y) * f32(sz.y);
    var to_pixels : f32 = 32.0 * inverseSqrt(dx * dx + dy * dy);
    let inside_factor = clamp((sdf - 0.5) * to_pixels + 0.5, 0.0, 1.0);
    
    // smoothstep(0.5 - smoothing, 0.5 + smoothing, sample);
    let shadow_alpha = (1.0 - (pow(1.0 - sdf, 2.0)) )* in.shadow_intensity * in.color.a;
    let shadow_color = vec4(0.0,0.0,0.0, shadow_alpha);
    let color = mix(shadow_color, in.color, inside_factor);
    return color; // * vec4(1.0,1.0,1.0,5.0);
}

fn unit_uv_from_idx(idx: u32) -> vec2<f32> {
    return vec2<f32>(
        f32(((idx << 1) & 2) >> 1),
        f32((idx & 2) >> 1)
    );
}
