package quat

import "core:math"
import wgpu "vendor:wgpu"

GizmosVertex :: struct {
	pos:   Vec2,
	color: Color,
}

GizmosRenderer :: struct {
	pipeline:       RenderPipelineHandle,
	vertices:       [GizmosMode][dynamic]GizmosVertex,
	vertex_buffers: [GizmosMode]DynamicBuffer(GizmosVertex),
}

GizmosMode :: enum u32 {
	WORLD  = 0, //
	SCREEN = 1, // pixels on screen
}
GIZMOS_COLOR := Color{1, 0, 0, 1}

gizmos_renderer_create :: proc(rend: ^GizmosRenderer) {
	for mode in GizmosMode {
		dynamic_buffer_init(&rend.vertex_buffers[mode], {.Vertex})
	}
	rend.pipeline = make_render_pipeline(gizmos_pipeline_config())
}
gizmos_renderer_destroy :: proc(rend: ^GizmosRenderer) {
	for mode in GizmosMode {
		delete(rend.vertices[mode])
		dynamic_buffer_destroy(&rend.vertex_buffers[mode])
	}
}
gizmos_renderer_prepare :: proc(rend: ^GizmosRenderer) {
	for mode in GizmosMode {
		dynamic_buffer_write(&rend.vertex_buffers[mode], rend.vertices[mode][:])
		clear(&rend.vertices[mode])
	}
}
gizmos_renderer_render :: proc(
	rend: ^GizmosRenderer,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_2d_uniform: wgpu.BindGroup,
	mode: GizmosMode,
) {
	vertex_buffer := &rend.vertex_buffers[mode]
	if vertex_buffer.length == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, get_pipeline(rend.pipeline))
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_2d_uniform)
	wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, vertex_buffer.buffer, 0, vertex_buffer.size)
	mode := mode
	wgpu.RenderPassEncoderSetPushConstants(render_pass, {.Vertex}, 0, size_of(GizmosMode), &mode)
	wgpu.RenderPassEncoderDraw(render_pass, u32(vertex_buffer.length), 1, 0, 0)
}
gizmos_renderer_render_all_modes :: proc(
	rend: ^GizmosRenderer,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_2d_uniform: wgpu.BindGroup,
) {
	bound_pipeline_and_bind_group := false
	for mode in GizmosMode {
		mode := mode
		vertex_buffer := &rend.vertex_buffers[mode]
		if vertex_buffer.length == 0 {
			continue
		}
		if !bound_pipeline_and_bind_group {
			bound_pipeline_and_bind_group = true
			wgpu.RenderPassEncoderSetPipeline(render_pass, get_pipeline(rend.pipeline))
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_2d_uniform)
		}
		wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, vertex_buffer.buffer, 0, vertex_buffer.size)
		wgpu.RenderPassEncoderSetPushConstants(render_pass, {.Vertex}, 0, size_of(GizmosMode), &mode)
		wgpu.RenderPassEncoderDraw(render_pass, u32(vertex_buffer.length), 1, 0, 0)
	}
}

// todo: add .WORLD_SPACE / UI option
gizmos_renderer_add_circle :: #force_inline proc(
	rend: ^GizmosRenderer,
	center: Vec2,
	radius: f32,
	color := GIZMOS_COLOR,
	segments: int = 12,
	draw_inner_lines: bool = false,
	mode: GizmosMode = {},
) {
	last_p: Vec2 = center + Vec2{radius, 0}
	for i in 1 ..= segments {
		angle := f32(i) / f32(segments) * math.PI * 2.0
		p := center + Vec2{math.cos(angle), math.sin(angle)} * radius
		gizmos_renderer_add_line(rend, last_p, p, color, mode)
		if draw_inner_lines {
			gizmos_renderer_add_line(rend, center, p, color, mode)
		}
		last_p = p
	}
}

gizmos_renderer_add_triangle :: #force_inline proc(
	rend: ^GizmosRenderer,
	a, b, c: Vec2,
	color := GIZMOS_COLOR,
	mode: GizmosMode = {},
) {
	append(&rend.vertices[mode], GizmosVertex{a, color})
	append(&rend.vertices[mode], GizmosVertex{b, color})
	append(&rend.vertices[mode], GizmosVertex{b, color})
	append(&rend.vertices[mode], GizmosVertex{c, color})
	append(&rend.vertices[mode], GizmosVertex{c, color})
	append(&rend.vertices[mode], GizmosVertex{a, color})
}

gizmos_renderer_add_line :: #force_inline proc(
	rend: ^GizmosRenderer,
	from: Vec2,
	to: Vec2,
	color := GIZMOS_COLOR,
	mode: GizmosMode = {},
) {
	append(&rend.vertices[mode], GizmosVertex{from, color})
	append(&rend.vertices[mode], GizmosVertex{to, color})
}

gizmos_renderer_add_aabb :: proc(
	rend: ^GizmosRenderer,
	using aabb: Aabb,
	color := GIZMOS_COLOR,
	mode: GizmosMode = {},
) {
	a := min
	b := Vec2{min.x, max.y}
	c := max
	d := Vec2{max.x, min.y}
	gizmos_renderer_add_line(rend, a, b, color, mode)
	gizmos_renderer_add_line(rend, b, c, color, mode)
	gizmos_renderer_add_line(rend, c, d, color, mode)
	gizmos_renderer_add_line(rend, d, a, color, mode)
}

gizmos_renderer_add_coordinates :: proc(rend: ^GizmosRenderer) {
	gizmos_renderer_add_line(rend, {0, 0}, {1, 0}, ColorRed, .WORLD)
	gizmos_renderer_add_line(rend, {0, 0}, {0, 1}, ColorGreen, .WORLD)
}


gizmos_renderer_add_rect :: proc(
	rend: ^GizmosRenderer,
	center: Vec2,
	size: Vec2,
	color := GIZMOS_COLOR,
	mode: GizmosMode = {},
) {
	h := size / 2
	a := center + Vec2{-h.x, h.y}
	b := center + Vec2{h.x, h.y}
	c := center + Vec2{h.x, -h.y}
	d := center + Vec2{-h.x, -h.y}
	gizmos_renderer_add_line(rend, a, b, color, mode)
	gizmos_renderer_add_line(rend, b, c, color, mode)
	gizmos_renderer_add_line(rend, c, d, color, mode)
	gizmos_renderer_add_line(rend, d, a, color, mode)
}

gizmos_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "gizmos",
		vs_shader = "gizmos.wgsl",
		vs_entry_point = "vs_main",
		fs_shader = "gizmos.wgsl",
		fs_entry_point = "fs_main",
		topology = .LineList,
		vertex = {
			ty_id = GizmosVertex,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(GizmosVertex, pos)},
				{format = .Float32x4, offset = offset_of(GizmosVertex, color)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera2DUniformData),
		),
		push_constant_ranges = push_const_range(GizmosMode, {.Vertex}),
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}
