package quat
import wgpu "vendor:wgpu"

ColorMesh2DVertex :: struct {
	pos:   Vec2,
	color: Color,
}

ColorMesh2DRenderer :: struct {
	pipeline:      ^RenderPipeline,
	vertices:      [dynamic]ColorMesh2DVertex,
	vertex_buffer: DynamicBuffer(ColorMesh2DVertex),
	triangles:     [dynamic]Triangle, // index buffer
	index_buffer:  DynamicBuffer(Triangle),
}

color_mesh_2d_renderer_create :: proc(rend: ^ColorMesh2DRenderer) {
	dynamic_buffer_init(&rend.vertex_buffer, {.Vertex})
	dynamic_buffer_init(&rend.index_buffer, {.Index})
	rend.pipeline = make_render_pipeline(color_mesh_2d_pipeline_config())
}

color_mesh_2d_renderer_destroy :: proc(rend: ^ColorMesh2DRenderer) {
	delete(rend.vertices)
	delete(rend.triangles)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
}

color_mesh_2d_renderer_prepare :: proc(rend: ^ColorMesh2DRenderer) {
	dynamic_buffer_write(&rend.vertex_buffer, rend.vertices[:])
	dynamic_buffer_write(&rend.index_buffer, rend.triangles[:])
	clear(&rend.vertices)
	clear(&rend.triangles)
}

color_mesh_2d_renderer_render :: proc(
	rend: ^ColorMesh2DRenderer,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_2d_uniform: wgpu.BindGroup,
) {

	if rend.index_buffer.length == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_2d_uniform)

	wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, rend.vertex_buffer.buffer, 0, rend.vertex_buffer.size)
	wgpu.RenderPassEncoderSetIndexBuffer(render_pass, rend.index_buffer.buffer, .Uint32, 0, rend.index_buffer.size)
	wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(rend.index_buffer.length) * 3, 1, 0, 0, 0)
}

color_mesh_2d_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "color_mesh_2d",
		vs_shader = "color_mesh_2d",
		vs_entry_point = "vs_main",
		fs_shader = "color_mesh_2d",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = ColorMesh2DVertex,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(ColorMesh2DVertex, pos)},
				{format = .Float32x4, offset = offset_of(ColorMesh2DVertex, color)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera2DUniformData),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DepthConfig{depth_compare = .GreaterEqual, depth_write_enabled = true},
	}
}

color_mesh_2d_add :: proc {
	color_mesh_2d_add_vertices,
	color_mesh_2d_add_indexed_single_color,
	color_mesh_2d_add_indexed,
}


color_mesh_2d_add_vertices :: proc(rend: ^ColorMesh2DRenderer, vertices: []ColorMesh2DVertex) {
	start_idx := u32(len(rend.vertices))
	assert(len(vertices) % 3 == 0)
	append(&rend.vertices, ..vertices)
	for t_idx in 0 ..< u32(len(vertices) / 3) {
		i := t_idx * 3 + start_idx
		append(&rend.triangles, Triangle{i, i + 1, i + 2})
	}
}

color_mesh_2d_add_indexed :: proc(rend: ^ColorMesh2DRenderer, vertices: []ColorMesh2DVertex, triangles: []Triangle) {
	start_idx := u32(len(rend.vertices))
	append(&rend.vertices, ..vertices)
	for t in triangles {
		append(&rend.triangles, t + start_idx)
	}
}

color_mesh_2d_add_indexed_single_color :: proc(
	rend: ^ColorMesh2DRenderer,
	positions: []Vec2,
	triangles: []Triangle,
	color: Color = ColorRed,
) {
	start_idx := u32(len(rend.vertices))
	for pos in positions {
		append(&rend.vertices, ColorMesh2DVertex{pos = pos, color = color})
	}
	for t in triangles {
		append(&rend.triangles, t + start_idx)
	}
}
