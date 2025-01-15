package quat
import wgpu "vendor:wgpu"

TexturedVertex :: struct {
	pos:   Vec2,
	uv:    Vec2,
	color: Color,
}

TexturedMeshRenderer :: struct {
	device:          wgpu.Device,
	queue:           wgpu.Queue,
	pipeline:        RenderPipeline,
	vertices:        [dynamic]TexturedVertex,
	vertex_buffer:   DynamicBuffer(TexturedVertex),
	triangles:       [dynamic]IdxTriangle,
	index_buffer:    DynamicBuffer(IdxTriangle),
	texture_regions: [dynamic]TextureRegion,
}
// we don't bother with batching, the API is just: set_texture, add indices + vertices, set next texture, add indices + vertices, ...
TextureRegion :: struct {
	start_tri_idx: u32,
	end_tri_idx:   u32,
	texture:       TextureHandle,
}

textured_mesh_renderer_create :: proc(rend: ^TexturedMeshRenderer, platform: ^Platform) {
	rend.device = platform.device
	rend.queue = platform.queue
	rend.vertex_buffer.usage = {.Vertex}
	rend.index_buffer.usage = {.Index}
	rend.pipeline.config = textured_mesh_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.pipeline, &platform.shader_registry)
}

textured_mesh_renderer_destroy :: proc(rend: ^TexturedMeshRenderer) {
	delete(rend.vertices)
	delete(rend.triangles)
	delete(rend.texture_regions)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
	render_pipeline_destroy(&rend.pipeline)
}

textured_mesh_renderer_prepare :: proc(rend: ^TexturedMeshRenderer) {
	dynamic_buffer_write(&rend.vertex_buffer, rend.vertices[:], rend.device, rend.queue)
	dynamic_buffer_write(&rend.index_buffer, rend.triangles[:], rend.device, rend.queue)
	clear(&rend.vertices)
	clear(&rend.triangles)
}

textured_mesh_renderer_set_texture :: proc(rend: ^TexturedMeshRenderer, texture: TextureHandle) {
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

textured_mesh_renderer_render :: proc(
	rend: ^TexturedMeshRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	assets: AssetManager,
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
			TextureRegion{texture = 0, start_tri_idx = 0, end_tri_idx = u32(tri_count)},
		)
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
	for reg in rend.texture_regions {
		if reg.end_tri_idx <= reg.start_tri_idx do continue
		wgpu.RenderPassEncoderSetBindGroup(
			render_pass,
			1,
			assets_get_texture_bind_group(assets, reg.texture),
		)
		index_count := (reg.end_tri_idx - reg.start_tri_idx) * 3
		first_index := reg.start_tri_idx * 3
		wgpu.RenderPassEncoderDrawIndexed(render_pass, index_count, 1, first_index, 0, 0)
	}
	clear(&rend.texture_regions)
}

textured_mesh_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "textured_mesh",
		vs_shader = "textured_mesh",
		vs_entry_point = "vs_main",
		fs_shader = "textured_mesh",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = TexturedVertex,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(TexturedVertex, pos)},
				{format = .Float32x2, offset = offset_of(TexturedVertex, uv)},
				{format = .Float32x4, offset = offset_of(TexturedVertex, color)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			globals_layout,
			rgba_bind_group_layout_cached(device),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}
