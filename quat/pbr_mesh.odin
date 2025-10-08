package quat

import "core:math/linalg"

import "vendor:wgpu"


PbrVertex :: struct {
	pos:     Vec3,
	normal:  Vec3,
	uv:      Vec2,
	color:   Color,
	tangent: Vec3,
}
#assert(size_of(PbrVertex) == 60)


PbrMesh :: struct {
	vertex_buffer:   DynamicBuffer(PbrVertex),
	index_buffer:    DynamicBuffer(Triangle),
	instance_buffer: DynamicBuffer(PbrInstance),
	texture:         TextureHandle,
}

PbrInstance :: struct {
	transform: Mat4,
}

pbr_mesh_create :: proc(vertices: []PbrVertex, triangles: []Triangle) -> (res: PbrMesh) {
	dynamic_buffer_init(&res.index_buffer, {.Index})
	dynamic_buffer_init(&res.vertex_buffer, {.Vertex})
	dynamic_buffer_init(&res.instance_buffer, {.Vertex})

	dynamic_buffer_write_exact(&res.vertex_buffer, vertices)
	dynamic_buffer_write_exact(&res.index_buffer, triangles)

	res.texture = DEFAULT_TEXTURE
	return res
}

pbr_mesh_set_instances :: proc(mesh: ^PbrMesh, instances: []PbrInstance) {
	dynamic_buffer_write(&mesh.instance_buffer, instances)
}

pbr_mesh_render :: proc(
	pass: wgpu.RenderPassEncoder,
	pipeline: wgpu.RenderPipeline,
	mesh: PbrMesh,
	frame_uniform: wgpu.BindGroup,
	camera_3d_uniform: wgpu.BindGroup,
) {
	if mesh.instance_buffer.length == 0 || mesh.index_buffer.length == 0 {
		return
	}

	textures := get_map(Texture)
	wgpu.RenderPassEncoderSetPipeline(pass, pipeline)

	wgpu.RenderPassEncoderSetBindGroup(pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(pass, 1, camera_3d_uniform)

	wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size)
	wgpu.RenderPassEncoderSetVertexBuffer(pass, 1, mesh.instance_buffer.buffer, 0, mesh.instance_buffer.size)
	wgpu.RenderPassEncoderSetIndexBuffer(pass, mesh.index_buffer.buffer, .Uint32, 0, mesh.index_buffer.size)


	tex_bind_group := slotmap_get(textures, mesh.texture).bind_group
	wgpu.RenderPassEncoderSetBindGroup(pass, 2, tex_bind_group)
	index_count := u32(mesh.index_buffer.length * 3)
	instance_count := u32(mesh.instance_buffer.length)
	wgpu.RenderPassEncoderDrawIndexed(pass, index_count, instance_count, 0, 0, 0)
}


PbrMeshPushConsts :: struct {
	transform: Mat4,
	sun_light: SunLight,
}


SunLight :: struct {
	light_dir:   Vec3,
	light_color: Color,
}

pbr_mesh_render_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "pbr_mesh",
		vs_shader = "pbr_mesh.wgsl",
		vs_entry_point = "vs_main",
		fs_shader = "pbr_mesh.wgsl",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		cull_mode = .Back,
		vertex = {
			ty_id = PbrVertex,
			attributes = vert_attributes(
				{format = .Float32x3, offset = offset_of(PbrVertex, pos)},
				{format = .Float32x3, offset = offset_of(PbrVertex, normal)},
				{format = .Float32x2, offset = offset_of(PbrVertex, uv)},
				{format = .Float32x4, offset = offset_of(PbrVertex, color)},
				{format = .Float32x3, offset = offset_of(PbrVertex, tangent)},
			),
		},
		instance = {
			ty_id = PbrInstance,
			attributes = vert_attributes(
				{format = .Float32x4, offset = offset_of(PbrInstance, transform)},
				{format = .Float32x4, offset = offset_of(PbrInstance, transform) + 16},
				{format = .Float32x4, offset = offset_of(PbrInstance, transform) + 32},
				{format = .Float32x4, offset = offset_of(PbrInstance, transform) + 48},
			),
		},
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
