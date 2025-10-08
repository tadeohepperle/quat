package quat
import wgpu "vendor:wgpu"

Mesh3DVertex :: struct {
	pos:   Vec3,
	color: Color,
	uv:    Vec2,
}

Mesh3DRenderer :: struct {
	pipeline:        RenderPipelineHandle,
	vertices:        [dynamic]Mesh3DVertex,
	vertex_buffer:   DynamicBuffer(Mesh3DVertex),
	triangles:       [dynamic]Triangle,
	index_buffer:    DynamicBuffer(Triangle),
	texture_regions: [dynamic]TextureRegion,
}
mesh_3d_renderer_create :: proc(rend: ^Mesh3DRenderer) {
	dynamic_buffer_init(&rend.vertex_buffer, {.Vertex})
	dynamic_buffer_init(&rend.index_buffer, {.Index})
	pipeline_config := mesh_3d_pipeline_config()
	rend.pipeline = make_render_pipeline(pipeline_config)
}

mesh_3d_renderer_destroy :: proc(rend: ^Mesh3DRenderer) {
	delete(rend.vertices)
	delete(rend.triangles)
	delete(rend.texture_regions)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
}

mesh_3d_renderer_prepare :: proc(rend: ^Mesh3DRenderer) {
	dynamic_buffer_write(&rend.vertex_buffer, rend.vertices[:])
	dynamic_buffer_write(&rend.index_buffer, rend.triangles[:])
	clear(&rend.vertices)
	clear(&rend.triangles)
}

mesh_3d_renderer_set_texture :: proc(rend: ^Mesh3DRenderer, texture: TextureHandle) {
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

mesh_3d_renderer_add :: proc(
	rend: ^Mesh3DRenderer,
	vertices: []Mesh3DVertex,
	triangles: []Triangle,
	texture: TextureHandle = DEFAULT_TEXTURE,
) {
	mesh_3d_renderer_set_texture(rend, texture)
	start := u32(len(rend.vertices))
	append_elems(&rend.vertices, ..vertices)
	for t in triangles {
		append(&rend.triangles, t + start)
	}
}

mesh_3d_renderer_render :: proc(
	rend: ^Mesh3DRenderer,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_3d_uniform: wgpu.BindGroup,
) {
	defer clear(&rend.texture_regions)
	tri_count := u32(rend.index_buffer.length)
	texture_region_count := len(rend.texture_regions)
	if tri_count == 0 {
		return
	}
	// set the end idx of the last texture region
	if texture_region_count > 0 {
		rend.texture_regions[texture_region_count - 1].end_tri_idx = tri_count
	} else {
		append(
			&rend.texture_regions,
			TextureRegion{texture = DEFAULT_TEXTURE, start_tri_idx = 0, end_tri_idx = u32(tri_count)},
		)
	}

	textures := get_map(Texture)
	wgpu.RenderPassEncoderSetPipeline(render_pass, get_pipeline(rend.pipeline))

	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_3d_uniform)

	wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, rend.vertex_buffer.buffer, 0, rend.vertex_buffer.size)
	wgpu.RenderPassEncoderSetIndexBuffer(render_pass, rend.index_buffer.buffer, .Uint32, 0, rend.index_buffer.size)

	// one draw call for each texture region:
	for reg in rend.texture_regions {
		if reg.end_tri_idx <= reg.start_tri_idx do continue
		bind_group := slotmap_get(textures, reg.texture).bind_group
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, bind_group)
		index_count := (reg.end_tri_idx - reg.start_tri_idx) * 3
		first_index := reg.start_tri_idx * 3
		wgpu.RenderPassEncoderDrawIndexed(render_pass, index_count, 1, first_index, 0, 0)
	}
}

mesh_3d_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "mesh_3d",
		vs_shader = "mesh_3d.wgsl",
		vs_entry_point = "vs_main",
		fs_shader = "mesh_3d.wgsl",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		cull_mode = .Back,
		vertex = {
			ty_id = Mesh3DVertex,
			attributes = vert_attributes(
				{format = .Float32x3, offset = offset_of(Mesh3DVertex, pos)},
				{format = .Float32x4, offset = offset_of(Mesh3DVertex, color)},
				{format = .Float32x2, offset = offset_of(Mesh3DVertex, uv)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera3DUniformData),
			rgba_bind_group_layout_cached(),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_CONFIG_3D,
	}
}

DEPTH_CONFIG_3D :: DepthConfig {
	depth_write_enabled = true,
	depth_compare       = wgpu.CompareFunction.Less,
}
