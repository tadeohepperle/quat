package quat

import "core:math"
import wgpu "vendor:wgpu"

Gizmos3DVertex :: struct {
	pos:   Vec3,
	color: Color,
}

IndexLine :: [2]u32

Gizmos3DRenderer :: struct {
	pipeline:      RenderPipelineHandle,
	vertices:      [dynamic]Gizmos3DVertex,
	lines:         [dynamic]IndexLine,
	vertex_buffer: DynamicBuffer(Gizmos3DVertex),
	index_buffer:  DynamicBuffer(IndexLine),
}

gizmos_3d_renderer_create :: proc(rend: ^Gizmos3DRenderer) {
	dynamic_buffer_init(&rend.vertex_buffer, {.Vertex})
	dynamic_buffer_init(&rend.index_buffer, {.Index})
	rend.pipeline = make_render_pipeline(gizmos_3d_pipeline_config())
}
gizmos_3d_renderer_destroy :: proc(rend: ^Gizmos3DRenderer) {
	delete(rend.vertices)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
}
gizmos_3d_renderer_prepare :: proc(rend: ^Gizmos3DRenderer) {
	dynamic_buffer_write(&rend.vertex_buffer, rend.vertices[:])
	dynamic_buffer_write(&rend.index_buffer, rend.lines[:])
	clear(&rend.vertices)
	clear(&rend.lines)
}
gizmos_3d_renderer_render :: proc(
	rend: ^Gizmos3DRenderer,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_3d_uniform: wgpu.BindGroup,
) {

	if rend.vertex_buffer.length == 0 || rend.index_buffer.length == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, get_pipeline(rend.pipeline))
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_3d_uniform)
	wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, rend.vertex_buffer.buffer, 0, rend.vertex_buffer.size)
	wgpu.RenderPassEncoderSetIndexBuffer(render_pass, rend.index_buffer.buffer, .Uint32, 0, rend.index_buffer.size)
	wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(rend.index_buffer.length * 2), 1, 0, 0, 0)
}

gizmos_3d_renderer_add_triangle :: #force_inline proc(rend: ^Gizmos3DRenderer, a, b, c: Vec3, color := GIZMOS_COLOR) {
	start := u32(len(rend.vertices))
	append_elems(&rend.vertices, Gizmos3DVertex{a, color}, Gizmos3DVertex{a, color}, Gizmos3DVertex{a, color})
	append_elems(
		&rend.lines,
		IndexLine{start, start + 1},
		IndexLine{start + 1, start + 2},
		IndexLine{start + 2, start},
	)
}

gizmos_3d_renderer_add_line :: #force_inline proc(
	rend: ^Gizmos3DRenderer,
	from: Vec3,
	to: Vec3,
	color := GIZMOS_COLOR,
) {
	start := u32(len(rend.vertices))
	append_elems(&rend.vertices, Gizmos3DVertex{from, color}, Gizmos3DVertex{to, color})
	append(&rend.lines, IndexLine{start, start + 1})
}

Aabb3D :: struct {
	min: Vec3,
	max: Vec3,
}

gizmos_3d_renderer_add_coordinates :: proc(rend: ^Gizmos3DRenderer) {
	gizmos_3d_renderer_add_line(rend, Vec3{}, Vec3{1, 0, 0}, ColorRed)
	gizmos_3d_renderer_add_line(rend, Vec3{}, Vec3{0, 1, 0}, ColorGreen)
	gizmos_3d_renderer_add_line(rend, Vec3{}, Vec3{0, 0, 1}, ColorBlue)
}


gizmos_3d_renderer_add_aabb :: proc(rend: ^Gizmos3DRenderer, using aabb: Aabb3D, color := GIZMOS_COLOR) {
	start := u32(len(rend.vertices))
	append_elems(
		&rend.vertices,
		Gizmos3DVertex{Vec3{min.x, min.y, min.z}, color},
		Gizmos3DVertex{Vec3{max.x, min.y, min.z}, color},
		Gizmos3DVertex{Vec3{max.x, min.y, max.z}, color},
		Gizmos3DVertex{Vec3{min.x, min.y, max.z}, color},
		Gizmos3DVertex{Vec3{min.x, max.y, min.z}, color},
		Gizmos3DVertex{Vec3{max.x, max.y, min.z}, color},
		Gizmos3DVertex{Vec3{max.x, max.y, max.z}, color},
		Gizmos3DVertex{Vec3{min.x, max.y, max.z}, color},
	)
	append_elems(
		&rend.lines,
		// bottom lines:
		IndexLine{0, 1} + start,
		IndexLine{1, 2} + start,
		IndexLine{2, 3} + start,
		IndexLine{3, 0} + start,
		// top lines:
		IndexLine{4, 5} + start,
		IndexLine{5, 6} + start,
		IndexLine{6, 7} + start,
		IndexLine{7, 4} + start,
		// side lines:
		IndexLine{0, 4} + start,
		IndexLine{1, 5} + start,
		IndexLine{2, 6} + start,
		IndexLine{3, 7} + start,
	)
}
gizmos_3d_renderer_add_sphere :: proc(rend: ^Gizmos3DRenderer, center: Vec3, radius: f32, color := GIZMOS_COLOR) {
	unimplemented()
}
gizmos_3d_renderer_add_box :: proc(rend: ^Gizmos3DRenderer, center: Vec3, size: Vec3, color := GIZMOS_COLOR) {
	gizmos_3d_renderer_add_aabb(rend, Aabb3D{center - size / 2, center + size / 2}, color)
}

gizmos_3d_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "gizmos_3d",
		vs_shader = "gizmos_3d.wgsl",
		vs_entry_point = "vs_main",
		fs_shader = "gizmos_3d.wgsl",
		fs_entry_point = "fs_main",
		topology = .LineList,
		vertex = {
			ty_id = Gizmos3DVertex,
			attributes = vert_attributes(
				{format = .Float32x3, offset = offset_of(Gizmos3DVertex, pos)},
				{format = .Float32x4, offset = offset_of(Gizmos3DVertex, color)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera3DUniformData),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}
