package quat

import wgpu "vendor:wgpu"

// a mesh where each triangle merges 3 textures
TritexVertex :: struct {
	pos:     Vec2, // per vertex
	indices: UVec3, // per triangle (same for all vertices in each triangle)
	weights: Vec3, // per vertex
}

TritexMesh :: struct {
	vertices:      []TritexVertex,
	vertex_buffer: DynamicBuffer(TritexVertex),
}
tritex_mesh_sync :: proc(mesh: ^TritexMesh) {
	dynamic_buffer_write(&mesh.vertex_buffer, mesh.vertices[:])
}
tritex_mesh_create :: proc(vertices: []TritexVertex) -> (mesh: TritexMesh) {
	mesh.vertices = vertices
	dynamic_buffer_init(&mesh.vertex_buffer, {.Vertex})
	dynamic_buffer_write(&mesh.vertex_buffer, vertices[:])
	return mesh
}
tritex_mesh_drop :: proc(tritex_mesh: ^TritexMesh) {
	delete(tritex_mesh.vertices)
	dynamic_buffer_destroy(&tritex_mesh.vertex_buffer)
}

tritex_mesh_render :: proc(
	pipeline: wgpu.RenderPipeline,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	meshes: []TritexMesh,
	textures: TextureArrayHandle,
) {
	if len(meshes) == 0 {
		return
	}
	if textures == {} {
		print("warning! wants to draw tritex meshes, but TextureArrayHandle is 0!")
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)

	texture_array_bindgroup := assets_get(textures).bind_group
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_array_bindgroup)
	for mesh in meshes {
		wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size)
		wgpu.RenderPassEncoderDraw(render_pass, u32(mesh.vertex_buffer.length), 1, 0, 0)
	}
}

tritex_mesh_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "tritex",
		vs_shader = "tritex",
		vs_entry_point = "vs_main",
		fs_shader = "tritex",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = TritexVertex,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(TritexVertex, pos)},
				{format = .Uint32x3, offset = offset_of(TritexVertex, indices)},
				{format = .Float32x3, offset = offset_of(TritexVertex, weights)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			globals_bind_group_layout_cached(),
			tritex_textures_bind_group_layout_cached(),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}

tritex_textures_bind_group_layout_cached :: proc() -> wgpu.BindGroupLayout {
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
			PLATFORM.device,
			&wgpu.BindGroupLayoutDescriptor{entryCount = uint(len(entries)), entries = &entries[0]},
		)
	}
	return layout
}
