package quat

import wgpu "vendor:wgpu"

TritexVertex :: struct {
	pos:     Vec2, // per vertex
	indices: UVec3, // per triangle (same for all vertices in each triangle)
	weights: Vec3, // per vertex
}

TritexMesh :: struct {
	vertices:      [dynamic]TritexVertex,
	vertex_buffer: DynamicBuffer(TritexVertex),
}

tritex_mesh_create :: proc(
	vertices: [dynamic]TritexVertex,
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> (
	mesh: TritexMesh,
) {
	mesh.vertices = vertices
	mesh.vertex_buffer.usage = {.Vertex}
	dynamic_buffer_write(&mesh.vertex_buffer, vertices[:], device, queue)
	return mesh
}

tritex_mesh_destroy :: proc(tritex_mesh: ^TritexMesh) {
	delete(tritex_mesh.vertices)
	dynamic_buffer_destroy(&tritex_mesh.vertex_buffer)
}

TritexRenderer :: struct {
	device:   wgpu.Device,
	queue:    wgpu.Queue,
	pipeline: RenderPipeline,
}

tritex_renderer_create :: proc(rend: ^TritexRenderer, platform: ^Platform) {
	rend.device = platform.device
	rend.queue = platform.queue
	rend.pipeline.config = tritex_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
		rgba_texture_array_bind_group_layout_cached(platform.device),
	)
	render_pipeline_create_panic(&rend.pipeline, &platform.shader_registry)
}

tritex_renderer_destroy :: proc(rend: ^TritexRenderer) {
	render_pipeline_destroy(&rend.pipeline)
}

tritex_renderer_render :: proc(
	rend: ^TritexRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	meshes: []^TritexMesh,
	textures: TextureArrayHandle,
	assets: AssetManager,
) {
	if len(meshes) == 0 {
		return
	}
	if textures == 0 {
		print("warning! wants to draw tritex meshes, but TextureArrayHandle is 0!")
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)

	texture_array_bindgroup := assets_get_texture_array_bind_group(assets, textures)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_array_bindgroup)
	for mesh in meshes {
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass,
			0,
			mesh.vertex_buffer.buffer,
			0,
			mesh.vertex_buffer.size,
		)
		wgpu.RenderPassEncoderDraw(render_pass, u32(mesh.vertex_buffer.length), 1, 0, 0)
	}
}

tritex_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
	tritex_textures_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "tritex",
		vs_shader = "tritex",
		vs_entry_point = "vs_main",
		fs_shader = "tritex",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = TritexVertex,
			attributes = {
				{format = .Float32x2, offset = offset_of(TritexVertex, pos)},
				{format = .Uint32x3, offset = offset_of(TritexVertex, indices)},
				{format = .Float32x3, offset = offset_of(TritexVertex, weights)},
			},
		},
		instance = {},
		bind_group_layouts = {globals_layout, tritex_textures_layout},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}


tritex_textures_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	@(static) layout: wgpu.BindGroupLayout
	if layout == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2DArray,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Fragment},
				sampler = wgpu.SamplerBindingLayout{type = .Filtering},
			},
		}
		layout = wgpu.DeviceCreateBindGroupLayout(
			device,
			&wgpu.BindGroupLayoutDescriptor {
				entryCount = uint(len(entries)),
				entries = &entries[0],
			},
		)
	}
	return layout
}
