package quat
import wgpu "vendor:wgpu"

CHUNK_SIZE :: 64

CHUNK_SIZE_PADDED :: CHUNK_SIZE + 2
// This data has 1 padding on each side
HexChunkTerrainData :: [CHUNK_SIZE_PADDED * CHUNK_SIZE_PADDED]u32 // sadly u32 bc of wgpu and i dont wan t tp unpack in the shader
HexChunkVisibilityData :: [CHUNK_SIZE_PADDED * CHUNK_SIZE_PADDED]f32

HexChunkTerrainUniform :: UniformBuffer(HexChunkTerrainData)
HexChunkVisibilityUniform :: UniformBuffer(HexChunkTerrainData)


HEX_TO_WORLD_POS_MAT :: matrix[2, 2]f32{
	1.5, 0, 
	-0.75, 1.5, 
}
hex_to_world_pos :: proc "contextless" (hex_pos: [2]i32) -> Vec2 {
	return HEX_TO_WORLD_POS_MAT * Vec2{f32(hex_pos.x), f32(hex_pos.y)}
}

// HexChunkVertex :: struct {
// 	indices: [3]u16, // indices into HexChunkTerrainData and HexChunkVisibilityData, used for barycentric coords
// 	_pad:    u16,
// }
// HexChunkVertexBuffer :: struct {
// 	num_vertices: u64,
// 	buffer:       wgpu.Buffer, // contains    CHUNK_SIZE*CHUNK_SIZE*2    [3]u16 triangles
// }
// hex_chunk_vertex_buffer :: proc(device: wgpu.Device) -> HexChunkVertexBuffer {
// 	assert(CHUNK_SIZE_PADDED * CHUNK_SIZE_PADDED < max(u16))
// 	TriangleU16 :: [3]u16
// 	vertices := make([]HexChunkVertex, CHUNK_SIZE * CHUNK_SIZE * 6) // 1 quad = 2 triangles = 6 vertices per tile.
// 	idx := 0
// 	for y in 1 ..= u16(CHUNK_SIZE) {
// 		for x in 1 ..= u16(CHUNK_SIZE) {
// 			a := x + CHUNK_SIZE_PADDED * y
// 			b := a + 1
// 			c := a + CHUNK_SIZE_PADDED + 1
// 			d := a + CHUNK_SIZE_PADDED
// 			vertices[idx] = HexChunkVertex{{a, b, c}, 0}
// 			vertices[idx + 1] = HexChunkVertex{{c, a, b}, 0}
// 			vertices[idx + 2] = HexChunkVertex{{b, c, a}, 0}
// 			vertices[idx + 3] = {{a, c, d}, 0}
// 			vertices[idx + 4] = {{d, a, c}, 0}
// 			vertices[idx + 5] = {{c, d, a}, 0}
// 			idx += 6
// 		}
// 	}
// 	vertex_buffer := wgpu.DeviceCreateBufferWithDataSlice(
// 		device,
// 		&wgpu.BufferWithDataDescriptor {
// 			label = "hex_chunk_index_buffer",
// 			usage = {.CopyDst, .Vertex},
// 		},
// 		vertices,
// 	)
// 	return HexChunkVertexBuffer{u64(len(vertices)), vertex_buffer}

// }

HexChunkUniform :: struct {
	chunk_pos:       [2]i32,
	device:          wgpu.Device,
	queue:           wgpu.Queue,
	terrain_data:    wgpu.Buffer, // of type HexChunkTerrainData
	visibility_data: wgpu.Buffer, //
	bind_group:      wgpu.BindGroup,
}
hex_chunk_uniform_destroy :: proc(this: ^HexChunkUniform) {
	this.device = nil
	this.queue = nil
	wgpu.BindGroupRelease(this.bind_group)
	wgpu.BufferDestroy(this.terrain_data)
	wgpu.BufferDestroy(this.visibility_data)
}

hex_chunk_uniform_write_terrain_data :: proc(
	this: ^HexChunkUniform,
	terrain_data: ^HexChunkTerrainData,
) {
	assert(this.queue != nil)
	wgpu.QueueWriteBuffer(
		this.queue,
		this.terrain_data,
		0,
		terrain_data,
		size_of(HexChunkTerrainData),
	)
}
hex_chunk_uniform_write_visibility_data :: proc(
	this: ^HexChunkUniform,
	visibility_data: ^HexChunkVisibilityData,
) {
	assert(this.queue != nil)
	wgpu.QueueWriteBuffer(
		this.queue,
		this.visibility_data,
		0,
		visibility_data,
		size_of(HexChunkVisibilityData),
	)
}

hex_chunk_uniform_create :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	chunk_pos: [2]i32,
) -> (
	uniform: HexChunkUniform,
) {
	uniform.device = device
	uniform.queue = queue
	uniform.chunk_pos = chunk_pos
	buffer_usage := wgpu.BufferUsageFlags{.CopyDst, .Uniform}
	uniform.terrain_data = wgpu.DeviceCreateBuffer(
		device,
		&wgpu.BufferDescriptor {
			usage = buffer_usage,
			size = size_of(HexChunkTerrainData),
			mappedAtCreation = false,
		},
	)
	uniform.visibility_data = wgpu.DeviceCreateBuffer(
		device,
		&wgpu.BufferDescriptor {
			usage = buffer_usage,
			size = size_of(HexChunkVisibilityData),
			mappedAtCreation = false,
		},
	)
	bind_group_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry {
			binding = 0,
			buffer = uniform.terrain_data,
			offset = 0,
			size = u64(size_of(HexChunkTerrainData)),
		},
		wgpu.BindGroupEntry {
			binding = 1,
			buffer = uniform.visibility_data,
			offset = 0,
			size = u64(size_of(HexChunkVisibilityData)),
		},
	}
	uniform.bind_group = wgpu.DeviceCreateBindGroup(
		device,
		&wgpu.BindGroupDescriptor {
			layout = hex_chunk_terrain_and_visibility_bind_group_layout_cached(device),
			entryCount = 2,
			entries = raw_data(bind_group_entries[:]),
		},
	)
	return uniform
}
hex_chunk_terrain_and_visibility_bind_group_layout_cached :: proc(
	device: wgpu.Device,
) -> wgpu.BindGroupLayout {
	@(static) layout: wgpu.BindGroupLayout
	if layout == nil {
		entries := []wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Vertex, .Fragment},
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of(HexChunkTerrainData),
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Vertex, .Fragment},
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of(HexChunkVisibilityData),
				},
			},
		}
		layout = wgpu.DeviceCreateBindGroupLayout(
			device,
			&wgpu.BindGroupLayoutDescriptor{entryCount = 2, entries = raw_data(entries)},
		)
	}
	return layout
}


hex_chunks_render :: proc(
	pipeline: wgpu.RenderPipeline,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	textures: TextureArrayHandle,
	chunks: []HexChunkUniform,
	assets: AssetManager,
) {
	if len(chunks) == 0 {
		return
	}
	if textures == 0 {
		print("warning! wants to draw tritex meshes, but TextureArrayHandle is 0!")
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)

	texture_array_bindgroup := assets_get_texture_array_bind_group(assets, textures)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_array_bindgroup)
	for chunk in chunks {
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, chunk.bind_group)
		push_const := HexChunkPushConstants{chunk.chunk_pos}
		wgpu.RenderPassEncoderSetPushConstants(
			render_pass,
			{.Vertex},
			0,
			size_of(HexChunkPushConstants),
			&push_const,
		)
		// wgpu.RenderPassEncoderSetVertexBuffer(
		// 	render_pass,
		// 	0,
		// 	vertex_buffer.buffer,
		// 	0,
		// 	vertex_buffer.num_vertices * size_of(HexChunkVertex),
		// )
		num_vertices := u32(CHUNK_SIZE * CHUNK_SIZE * 6)
		// num_vertices = 18
		wgpu.RenderPassEncoderDraw(render_pass, num_vertices, 1, 0, 0)
	}
}

// e.g. if CHUNK_SIZE == 64, the chunk with chunk_pos = 1,2 covers hexes with x: 32..<64, y: 64..<96
HexChunkPushConstants :: struct {
	chunk_pos: [2]i32, // the hex pos of the bottom left (non-border) tile in this chunk / CHUNK_SIZE
}
hex_chunk_pipeline_config :: proc(device: wgpu.Device) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "hex_chunk",
		vs_shader = "hex_chunk",
		vs_entry_point = "vs_main",
		fs_shader = "hex_chunk",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			globals_bind_group_layout_cached(device),
			tritex_textures_bind_group_layout_cached(device),
			hex_chunk_terrain_and_visibility_bind_group_layout_cached(device),
		),
		push_constant_ranges = push_const_ranges(
			wgpu.PushConstantRange {
				stages = {.Vertex},
				start = 0,
				end = size_of(HexChunkPushConstants),
			},
		),
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DepthConfig{depth_write_enabled = true, depth_compare = .GreaterEqual},
	}
}
