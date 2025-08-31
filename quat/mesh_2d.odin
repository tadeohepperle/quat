package quat
import wgpu "vendor:wgpu"

Mesh2dVertex :: struct {
	pos:   Vec2,
	uv:    Vec2,
	color: Color,
}

Mesh2dRenderer :: struct {
	pipeline:        ^RenderPipeline,
	vertices:        [dynamic]Mesh2dVertex,
	vertex_buffer:   DynamicBuffer(Mesh2dVertex),
	triangles:       [dynamic]Triangle,
	index_buffer:    DynamicBuffer(Triangle),
	texture_regions: [dynamic]TextureRegion,
}
// we don't bother with batching, the API is just: set_texture, add indices + vertices, set next texture, add indices + vertices, ...
TextureRegion :: struct {
	start_tri_idx: u32,
	end_tri_idx:   u32,
	texture:       TextureHandle,
}

mesh_2d_renderer_create :: proc(rend: ^Mesh2dRenderer) {
	dynamic_buffer_init(&rend.vertex_buffer, {.Vertex})
	dynamic_buffer_init(&rend.index_buffer, {.Index})
	pipeline_config := mesh_2d_pipeline_config()
	rend.pipeline = make_render_pipeline(pipeline_config)
}

mesh_2d_renderer_destroy :: proc(rend: ^Mesh2dRenderer) {
	delete(rend.vertices)
	delete(rend.triangles)
	delete(rend.texture_regions)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
}

mesh_2d_renderer_prepare :: proc(rend: ^Mesh2dRenderer) {
	dynamic_buffer_write(&rend.vertex_buffer, rend.vertices[:])
	dynamic_buffer_write(&rend.index_buffer, rend.triangles[:])
	clear(&rend.vertices)
	clear(&rend.triangles)
}

mesh_2d_renderer_set_texture :: proc(rend: ^Mesh2dRenderer, texture: TextureHandle) {
	reg_count := len(rend.texture_regions)
	tri_count := u32(len(rend.triangles))
	if reg_count > 0 {
		last := &rend.texture_regions[reg_count - 1]
		if last.texture == texture {
			return // no need to start new region if texture is the same
		}
		last.end_tri_idx = tri_count
	}
	append(&rend.texture_regions, TextureRegion{start_tri_idx = tri_count, texture = texture})
}

mesh_2d_renderer_render :: proc(
	rend: ^Mesh2dRenderer,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_2d_uniform: wgpu.BindGroup,
) {
	tri_count := u32(rend.index_buffer.length)
	reg_count := len(rend.texture_regions)
	if tri_count == 0 {
		clear(&rend.texture_regions)
		return
	}
	if reg_count > 0 {
		rend.texture_regions[reg_count - 1].end_tri_idx = tri_count
	} else {
		append(
			&rend.texture_regions,
			TextureRegion{texture = DEFAULT_TEXTURE, start_tri_idx = 0, end_tri_idx = u32(tri_count)},
		)
	}

	textures := assets_get_map(Texture)
	wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)

	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_2d_uniform)

	wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, rend.vertex_buffer.buffer, 0, rend.vertex_buffer.size)
	wgpu.RenderPassEncoderSetIndexBuffer(render_pass, rend.index_buffer.buffer, .Uint32, 0, rend.index_buffer.size)
	for reg in rend.texture_regions {
		if reg.end_tri_idx <= reg.start_tri_idx do continue
		bind_group := slotmap_get(textures, reg.texture).bind_group
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, bind_group)
		index_count := (reg.end_tri_idx - reg.start_tri_idx) * 3
		first_index := reg.start_tri_idx * 3
		wgpu.RenderPassEncoderDrawIndexed(render_pass, index_count, 1, first_index, 0, 0)
	}
	clear(&rend.texture_regions)
}

mesh_2d_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "mesh_2d",
		vs_shader = "mesh_2d",
		vs_entry_point = "vs_main",
		fs_shader = "mesh_2d",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = Mesh2dVertex,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(Mesh2dVertex, pos)},
				{format = .Float32x2, offset = offset_of(Mesh2dVertex, uv)},
				{format = .Float32x4, offset = offset_of(Mesh2dVertex, color)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera2DUniformData),
			rgba_bind_group_layout_cached(),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}
