package quat

import "core:math"
import "core:mem"
import "core:slice"
import wgpu "vendor:wgpu"


MAX_WEIGHTS :: 2
SkinnedVertex :: struct {
	pos:     Vec2,
	uv:      Vec2,
	indices: [MAX_WEIGHTS]u32, // todo: would be sufficient as u16 or u8 probably, but there is no u8 or u16 in wgsl, so we would need bit masking and shifting there...
	weights: [MAX_WEIGHTS]f32,
}
SkinnedGeometryHandle :: Handle(SkinnedGeometry)
SkinnedGeometry :: struct {
	indices:         [dynamic]u32,
	index_buffer:    wgpu.Buffer, // index buffer of u32
	vertices:        [dynamic]SkinnedVertex,
	vertex_buffer:   wgpu.Buffer, // vertex buffer of SkinnedVertex
	reference_count: int,
	texture:         TextureHandle,
}

// multiple skinned mesh instances can share the same SkinnedMeshGeometry
SkinnedMesh :: struct {
	geometry:         SkinnedGeometryHandle,
	bones_buffer:     wgpu.Buffer, // storage buffer with bone_count * Affine2
	bones_bind_group: wgpu.BindGroup,
	bone_count:       int,
}
_skinned_mesh_drop :: proc(this: ^SkinnedMesh) {
	wgpu.BufferDestroy(this.bones_buffer)
	wgpu.BindGroupRelease(this.bones_bind_group)
}

// queues a write of new bone transforms into the bone buffer, can be done every frame e.g. for the bone transforms between two keyframes in an animation
skinned_mesh_update_bones :: proc(handle: SkinnedMeshHandle, bones: []Affine2) {
	mesh: ^SkinnedMesh = assets_get_ref(handle)
	assert(len(bones) == mesh.bone_count)
	wgpu.QueueWriteBuffer(PLATFORM.queue, mesh.bones_buffer, 0, raw_data(bones), uint(len(bones) * size_of(Affine2)))
}
// creates new buffer for the bones we can write to seperately, but points to the same verts + indices as the cloned mesh
skinned_mesh_clone :: proc(handle: SkinnedMeshHandle) -> SkinnedMeshHandle {
	mesh: SkinnedMesh = assets_get(handle)
	_geometry_clone(mesh.geometry) // increases the reference count
	// create a new buffer with unit transforms for all the bones:
	mesh.bones_buffer, mesh.bones_bind_group = _create_bones_buffer_and_bind_group(
		PLATFORM.device,
		PLATFORM.queue,
		mesh.bone_count,
	)
	return assets_insert(mesh)
}
skinned_mesh_deregister :: proc(handle: SkinnedMeshHandle) {
	mesh: SkinnedMesh = assets_remove(handle) or_else panic("skinned mesh not found!")
	_geometry_deregister(mesh.geometry)
	_skinned_mesh_drop(&mesh)
}
skinned_mesh_register :: proc(
	triangles: []Triangle,
	vertices: []SkinnedVertex,
	bone_count: int,
	texture: TextureHandle,
) -> SkinnedMeshHandle {
	geometry := _geometry_register(triangles_to_u32s(triangles), vertices, texture)
	bones_buffer, bones_bind_group := _create_bones_buffer_and_bind_group(PLATFORM.device, PLATFORM.queue, bone_count)
	skinned_mesh := SkinnedMesh {
		geometry         = geometry,
		bones_buffer     = bones_buffer,
		bones_bind_group = bones_bind_group,
		bone_count       = bone_count,
	}
	return assets_insert(skinned_mesh)
}
_create_bones_buffer_and_bind_group :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	bone_count: int,
) -> (
	wgpu.Buffer,
	wgpu.BindGroup,
) {
	bones_buffer_size := u64(bone_count * size_of(Affine2))
	bones_buffer := wgpu.DeviceCreateBuffer(
		device,
		&wgpu.BufferDescriptor{usage = {.CopyDst, .Storage}, size = bones_buffer_size},
	)
	unit_transforms := tmp_slice(Affine2, bone_count)
	for &b in unit_transforms {
		b = AFFINE2_UNIT
	}
	wgpu.QueueWriteBuffer(queue, bones_buffer, 0, raw_data(unit_transforms), uint(bones_buffer_size))
	bind_group_descriptor := wgpu.BindGroupDescriptor {
		layout     = bones_storage_buffer_bind_group_layout_cached(),
		entryCount = 1,
		entries    = &wgpu.BindGroupEntry{binding = 0, buffer = bones_buffer, size = bones_buffer_size},
	}
	bones_bind_group := wgpu.DeviceCreateBindGroup(device, &bind_group_descriptor)
	return bones_buffer, bones_bind_group
}
_geometry_clone :: proc(handle: SkinnedGeometryHandle) {
	geom: ^SkinnedGeometry = assets_get_ref(handle)
	geom.reference_count += 1
}
_geometry_register :: proc(
	indices: []u32,
	vertices: []SkinnedVertex,
	texture: TextureHandle,
) -> SkinnedGeometryHandle {
	geom := _geometry_create(indices, vertices, texture, PLATFORM.device, PLATFORM.queue)
	return assets_insert(geom)
}
_geometry_deregister :: proc(handle: SkinnedGeometryHandle) {
	geom: ^SkinnedGeometry = assets_get_ref(handle)
	assert(geom.reference_count > 0)
	geom.reference_count -= 1
	if geom.reference_count == 0 {
		geom_removed := assets_remove(handle)
		_geometry_drop(&geom_removed)
	}
}
_geometry_create :: proc(
	indices: []u32,
	vertices: []SkinnedVertex,
	texture: TextureHandle,
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> SkinnedGeometry {
	i_buffer_size := u64(size_of(u32) * len(indices))
	index_buffer := wgpu.DeviceCreateBuffer(
		device,
		&wgpu.BufferDescriptor{usage = {.CopyDst, .Index}, size = i_buffer_size},
	)
	v_buffer_size := u64(size_of(SkinnedVertex) * len(vertices))
	vertex_buffer := wgpu.DeviceCreateBuffer(
		device,
		&wgpu.BufferDescriptor{usage = {.CopyDst, .Vertex}, size = v_buffer_size},
	)
	wgpu.QueueWriteBuffer(queue, index_buffer, 0, raw_data(indices), uint(i_buffer_size))
	wgpu.QueueWriteBuffer(queue, vertex_buffer, 0, raw_data(vertices), uint(v_buffer_size))
	return SkinnedGeometry {
		indices = slice.clone_to_dynamic(indices),
		index_buffer = index_buffer,
		vertices = slice.clone_to_dynamic(vertices),
		vertex_buffer = vertex_buffer,
		reference_count = 1,
		texture = texture,
	}
}
_geometry_drop :: proc(geometry: ^SkinnedGeometry) {
	wgpu.BufferDestroy(geometry.index_buffer)
	delete(geometry.indices)
	wgpu.BufferDestroy(geometry.vertex_buffer)
	delete(geometry.vertices)
}


// Idea: 
// right now every skinned mesh has its own bones buffer allocated. This could be improved by 
// having just one big bones buffer we index into and then 
// every mesh just gets a region of that big buffer.
// for meshes with the same geometry but different bone transforms we can then 
// use instanced rendering, where the instance contains a start idx, that is added to the bone_idx stored per vertex.
// 
// we could just have one big instances buffer for the entire renderer, 
// that sorted by z and batched into regions that share the same geometry (vertices + indices)
// each of those regions has its own storage buffer of M * bone_count Affine2 structs in it,
// we can render all of them in a single instanced draw call by giving each instance
// an offset into this buffer.
// 
// but lets keep it simple for now (Tadeo Hepperle 2024-12-21)
SkinnedRenderCommand :: struct {
	pos:   Vec2,
	color: Color,
	mesh:  SkinnedMeshHandle,
}
skinned_mesh_render :: proc(
	pipeline: wgpu.RenderPipeline,
	commands: []SkinnedRenderCommand,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
) {
	if len(commands) == 0 {
		return
	}
	// todo: maybe sort and batch the commands here by their z or whatever, like for sprites???
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)


	textures := assets_get_map(Texture)
	skinned_meshes := assets_get_map(SkinnedMesh)
	skinned_geometries := assets_get_map(SkinnedGeometry)

	for command in commands {
		mesh: SkinnedMesh = slotmap_get(skinned_meshes, command.mesh)
		geom: SkinnedGeometry = slotmap_get(skinned_geometries, mesh.geometry)
		texture_bind_group := slotmap_get(textures, geom.texture).bind_group
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, mesh.bones_bind_group)
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, texture_bind_group)
		wgpu.RenderPassEncoderSetPushConstants(
			render_pass,
			{.Vertex, .Fragment},
			0,
			size_of(SkinnedRendererPushConstants),
			&SkinnedRendererPushConstants{pos = command.pos, color = command.color},
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			render_pass,
			geom.index_buffer,
			.Uint32,
			0,
			u64(len(geom.indices) * size_of(u32)),
		)
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass,
			0,
			geom.vertex_buffer,
			0,
			u64(len(geom.vertices) * size_of(SkinnedVertex)),
		)
		wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(len(geom.indices)), 1, 0, 0, 0)
	}
}
// maybe move to instances in instanced rendering instead later...
SkinnedRendererPushConstants :: struct {
	color: Color,
	pos:   Vec2,
	// todo: add rotation, scale, etc. maybe too... or add to instances directly...
	// one instance buffer for the entire renderer that we write into might actually be easier than seperate draw calls all the time.
	// requires that all bone transforms are also in one big storage buffer...
}
skinned_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "skinned",
		vs_shader = "skinned",
		vs_entry_point = "vs_main",
		fs_shader = "skinned",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = SkinnedVertex,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(SkinnedVertex, pos)},
				{format = .Float32x2, offset = offset_of(SkinnedVertex, uv)},
				{format = .Uint32x2, offset = offset_of(SkinnedVertex, indices)},
				{format = .Float32x2, offset = offset_of(SkinnedVertex, weights)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			shader_globals_bind_group_layout_cached(),
			bones_storage_buffer_bind_group_layout_cached(),
			rgba_bind_group_layout_cached(),
		),
		push_constant_ranges = push_const_ranges(
			wgpu.PushConstantRange {
				stages = {.Vertex, .Fragment},
				start = 0,
				end = size_of(SkinnedRendererPushConstants),
			},
		),
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}

bones_storage_buffer_bind_group_layout_cached :: proc() -> wgpu.BindGroupLayout {
	@(static) layout: wgpu.BindGroupLayout
	if layout == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Vertex},
				buffer = wgpu.BufferBindingLayout {
					type = .ReadOnlyStorage,
					hasDynamicOffset = b32(false),
					minBindingSize = 0,
				},
			},
		}
		layout = wgpu.DeviceCreateBindGroupLayout(
			PLATFORM.device,
			&wgpu.BindGroupLayoutDescriptor{entryCount = uint(len(entries)), entries = &entries[0]},
		)
	}
	return layout
}
