package quat
import wgpu "vendor:wgpu"

ColorMeshVertex :: struct {
	pos:   Vec2,
	color: Color,
}

ColorMeshRenderer :: struct {
	device:        wgpu.Device,
	queue:         wgpu.Queue,
	pipeline:      RenderPipeline,
	vertices:      [dynamic]ColorMeshVertex,
	vertex_buffer: DynamicBuffer(ColorMeshVertex),
	triangles:     [dynamic]Triangle, // index buffer
	index_buffer:  DynamicBuffer(Triangle),
}

color_mesh_renderer_create :: proc(rend: ^ColorMeshRenderer, platform: ^Platform) {
	rend.device = platform.device
	rend.queue = platform.queue
	rend.vertex_buffer.usage = {.Vertex}
	rend.index_buffer.usage = {.Index}
	rend.pipeline.config = color_mesh_pipeline_config(platform.globals.bind_group_layout)
	render_pipeline_create_or_panic(&rend.pipeline, &platform.shader_registry)
}

color_mesh_renderer_destroy :: proc(rend: ^ColorMeshRenderer) {
	delete(rend.vertices)
	delete(rend.triangles)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
	render_pipeline_destroy(&rend.pipeline)
}

color_mesh_renderer_prepare :: proc(rend: ^ColorMeshRenderer) {
	dynamic_buffer_write(&rend.vertex_buffer, rend.vertices[:], rend.device, rend.queue)
	dynamic_buffer_write(&rend.index_buffer, rend.triangles[:], rend.device, rend.queue)
	clear(&rend.vertices)
	clear(&rend.triangles)
}

color_mesh_renderer_render :: proc(
	rend: ^ColorMeshRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
) {

	if rend.index_buffer.length == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)

	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		rend.vertex_buffer.buffer,
		0,
		rend.vertex_buffer.size,
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		render_pass,
		rend.index_buffer.buffer,
		.Uint32,
		0,
		rend.index_buffer.size,
	)
	wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(rend.index_buffer.length) * 3, 1, 0, 0, 0)
}

color_mesh_pipeline_config :: proc(globals_layout: wgpu.BindGroupLayout) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "color_mesh",
		vs_shader = "color_mesh",
		vs_entry_point = "vs_main",
		fs_shader = "color_mesh",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = ColorMeshVertex,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(ColorMeshVertex, pos)},
				{format = .Float32x4, offset = offset_of(ColorMeshVertex, color)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(globals_layout),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}

color_mesh_add :: proc {
	color_mesh_add_vertices,
	color_mesh_add_indexed_single_color,
	color_mesh_add_indexed,
}


color_mesh_add_vertices :: proc(rend: ^ColorMeshRenderer, vertices: []ColorMeshVertex) {
	start_idx := u32(len(rend.vertices))
	assert(len(vertices) % 3 == 0)
	append(&rend.vertices, ..vertices)
	for t_idx in 0 ..< u32(len(vertices) / 3) {
		i := t_idx * 3 + start_idx
		append(&rend.triangles, Triangle{i, i + 1, i + 2})
	}
}

color_mesh_add_indexed :: proc(
	rend: ^ColorMeshRenderer,
	vertices: []ColorMeshVertex,
	triangles: []Triangle,
) {
	start_idx := u32(len(rend.vertices))
	append(&rend.vertices, ..vertices)
	for t in triangles {
		append(&rend.triangles, t + start_idx)
	}
}

color_mesh_add_indexed_single_color :: proc(
	rend: ^ColorMeshRenderer,
	positions: []Vec2,
	triangles: []Triangle,
	color: Color = ColorRed,
) {
	start_idx := u32(len(rend.vertices))
	for pos in positions {
		append(&rend.vertices, ColorMeshVertex{pos = pos, color = color})
	}
	for t in triangles {
		append(&rend.triangles, t + start_idx)
	}
}
