package quat
import "core:math"
import "core:math/linalg"
import "core:slice"
import "vendor:wgpu"

Mesh3dVertex :: struct {
	pos:    Vec3,
	_pad1:  f32,
	normal: Vec3,
	_pad2:  f32,
	uv:     Vec2,
	color:  Vec4,
}

Mesh3d :: struct {
	diffuse_texture: TextureHandle,
	vertices:        [dynamic]Mesh3dVertex,
	triangles:       [dynamic]Triangle,
	vertex_buffer:   DynamicBuffer(Mesh3dVertex),
	index_buffer:    DynamicBuffer(Triangle),
}

Mesh3dHexChunkMasked :: struct {
	using mesh:           Mesh3d,
	hex_chunk_bind_group: wgpu.BindGroup,
}

mesh_3d_create :: proc(diffuse_texture: TextureHandle = DEFAULT_TEXTURE) -> (this: Mesh3d) {
	this.diffuse_texture = diffuse_texture
	dynamic_buffer_init(&this.vertex_buffer, {.Vertex})
	dynamic_buffer_init(&this.index_buffer, {.Index})
	return this
}
mesh_3d_clone :: proc(this: Mesh3d) -> Mesh3d {
	return Mesh3d {
		diffuse_texture = this.diffuse_texture,
		vertices = slice.clone_to_dynamic(this.vertices[:]),
		triangles = slice.clone_to_dynamic(this.triangles[:]),
		vertex_buffer = {},
		index_buffer = {},
	}
}
mesh_3d_destroy :: proc(this: ^Mesh3d) {
	dynamic_buffer_destroy(&this.vertex_buffer)
	dynamic_buffer_destroy(&this.index_buffer)
	delete(this.vertices)
	delete(this.triangles)
}
mesh_3d_sync :: proc(this: ^Mesh3d) {
	dynamic_buffer_write(&this.vertex_buffer, this.vertices[:])
	dynamic_buffer_write(&this.index_buffer, this.triangles[:])
}

mesh_3d_unshare_vertices :: proc(this: ^Mesh3d) {
	n_vertices := len(this.triangles) * 3
	new_vertices := make([dynamic]Mesh3dVertex, n_vertices, n_vertices)
	for &tri, tri_idx in this.triangles {
		va := this.vertices[tri[0]]
		vb := this.vertices[tri[1]]
		vc := this.vertices[tri[2]]

		normal := linalg.normalize(linalg.cross(vb.pos - va.pos, vc.pos - va.pos))
		va.normal = normal
		vb.normal = normal
		vc.normal = normal

		a_idx := u32(tri_idx * 3)
		b_idx := a_idx + 1
		c_idx := a_idx + 2

		new_vertices[a_idx] = va
		new_vertices[b_idx] = vb
		new_vertices[c_idx] = vc

		tri = Triangle{a_idx, b_idx, c_idx}
	}
	clear(&this.vertices)
	old_vertices := this.vertices
	this.vertices = new_vertices
	delete(old_vertices)
}

mesh_3d_clear :: proc(this: ^Mesh3d) {
	clear(&this.vertices)
	clear(&this.triangles)
}
mesh_3d_access_buffers :: proc(
	this: ^Mesh3d,
) -> (
	vertices: ^[dynamic]Mesh3dVertex,
	tris: ^[dynamic]Triangle,
	start: u32,
) {
	return &this.vertices, &this.triangles, u32(len(this.vertices))
}

mesh_3d_rotate_around_z_axis :: proc(this: ^Mesh3d, angle: f32, center: Vec2) {
	mat := rotation_mat_2d(angle)
	for &v in this.vertices {
		v.pos.xy = mat * (v.pos.xy - center) + center
	}
}

mesh_3d_renderer_render :: proc(
	pipeline: wgpu.RenderPipeline,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_2d_uniform: wgpu.BindGroup,
	meshes: []Mesh3d,
) {
	if len(meshes) == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_2d_uniform)

	last_texture_handle := TextureHandle{max(u32)}

	textures := assets_get_map(Texture)
	for mesh in meshes {
		if mesh.diffuse_texture != last_texture_handle {
			diffuse_bind_group := slotmap_get(textures, mesh.diffuse_texture).bind_group
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, diffuse_bind_group)
			last_texture_handle = mesh.diffuse_texture
		}
		wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size)
		wgpu.RenderPassEncoderSetIndexBuffer(render_pass, mesh.index_buffer.buffer, .Uint32, 0, mesh.index_buffer.size)
		wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(mesh.index_buffer.length * 3), 1, 0, 0, 0)
	}
}


mesh_3d_renderer_render_hex_chunk_masked :: proc(
	pipeline: wgpu.RenderPipeline,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_2d_uniform: wgpu.BindGroup,
	meshes: []Mesh3dHexChunkMasked,
) {
	if len(meshes) == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_2d_uniform)

	last_texture_handle := TextureHandle{max(u32)}
	last_hex_chunk_bind_group: wgpu.BindGroup = nil
	textures := assets_get_map(Texture)
	for mesh in meshes {
		if mesh.diffuse_texture != last_texture_handle {
			diffuse_bind_group := slotmap_get(textures, mesh.diffuse_texture).bind_group
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, diffuse_bind_group)
			last_texture_handle = mesh.diffuse_texture
		}
		if mesh.hex_chunk_bind_group != last_hex_chunk_bind_group {
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 3, mesh.hex_chunk_bind_group)
			last_hex_chunk_bind_group = mesh.hex_chunk_bind_group
		}
		wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, mesh.vertex_buffer.buffer, 0, mesh.vertex_buffer.size)
		wgpu.RenderPassEncoderSetIndexBuffer(render_pass, mesh.index_buffer.buffer, .Uint32, 0, mesh.index_buffer.size)
		wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(mesh.index_buffer.length * 3), 1, 0, 0, 0)
	}
}


mesh_3d_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "mesh_3d",
		vs_shader = "mesh_3d",
		vs_entry_point = "vs_main",
		fs_shader = "mesh_3d",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = Mesh3dVertex,
			attributes = vert_attributes(
				{format = .Float32x3, offset = offset_of(Mesh3dVertex, pos)},
				{format = .Float32x3, offset = offset_of(Mesh3dVertex, normal)},
				{format = .Float32x2, offset = offset_of(Mesh3dVertex, uv)},
				{format = .Float32x4, offset = offset_of(Mesh3dVertex, color)},
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
		depth = DepthConfig{depth_compare = .GreaterEqual, depth_write_enabled = true},
	}
}

mesh_3d_hex_chunk_masked_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "mesh_3d",
		vs_shader = "mesh_3d",
		vs_entry_point = "vs_hex_mask",
		fs_shader = "mesh_3d",
		fs_entry_point = "fs_hex_mask",
		topology = .TriangleList,
		vertex = {
			ty_id = Mesh3dVertex,
			attributes = vert_attributes(
				{format = .Float32x3, offset = offset_of(Mesh3dVertex, pos)},
				{format = .Float32x3, offset = offset_of(Mesh3dVertex, normal)},
				{format = .Float32x2, offset = offset_of(Mesh3dVertex, uv)},
				{format = .Float32x4, offset = offset_of(Mesh3dVertex, color)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera2DUniformData),
			rgba_bind_group_layout_cached(),
			uniform_bind_group_layout_cached(HexChunkUniformData),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DepthConfig{depth_compare = .GreaterEqual, depth_write_enabled = true},
	}
}
