package quat
import wgpu "vendor:wgpu"


HEX_TO_WORLD_POS_MAT :: matrix[2, 2]f32{
	1.5, 0,
	-0.75, 1.5,
}
hex_to_world_pos :: proc "contextless" (hex_pos: [2]i32) -> Vec2 {
	return HEX_TO_WORLD_POS_MAT * Vec2{f32(hex_pos.x), f32(hex_pos.y)}
}

CHUNK_SIZE :: 32
CHUNK_SIZE_PADDED :: CHUNK_SIZE + 2
// This data has 1 padding on each side

// could probably be compressed to 1/2 or 1/4th of this size. Very wasteful.
// but that is a concern for later
HexTileData :: struct {
	old_terrain:    u8,
	new_terrain:    u8,
	old_visibility: u8, // 0 is invisible, 255 is visible
	new_visibility: u8, // 0 is invisible, 255 is visible
	new_factor:     f32,
}

HexChunkUniformData :: struct {
	chunk_pos: [2]i32,
	_pad:      [2]u32, // such that the tiles are aligned to 16 bytes (wgpu wants it)
	tiles:     [CHUNK_SIZE_PADDED * CHUNK_SIZE_PADDED]HexTileData,
}

HexChunkUniform :: struct {
	chunk_pos:  [2]i32,
	data:       wgpu.Buffer, // of type HexChunkData
	bind_group: wgpu.BindGroup,
}
hex_chunk_uniform_destroy :: proc(this: ^HexChunkUniform) {
	wgpu.BindGroupRelease(this.bind_group)
	wgpu.BufferRelease(this.data)
}

hex_chunk_uniform_write_data :: proc(this: ^HexChunkUniform, terrain_data: ^HexChunkUniformData) {
	assert(PLATFORM.queue != nil)
	wgpu.QueueWriteBuffer(PLATFORM.queue, this.data, 0, terrain_data, size_of(HexChunkUniformData))
}
hex_chunk_uniform_create :: proc(chunk_pos: [2]i32) -> (uniform: HexChunkUniform) {
	uniform.chunk_pos = chunk_pos
	buffer_usage := wgpu.BufferUsageFlags{.CopyDst, .Uniform}
	uniform.data = wgpu.DeviceCreateBuffer(
		PLATFORM.device,
		&wgpu.BufferDescriptor{usage = buffer_usage, size = size_of(HexChunkUniformData), mappedAtCreation = false},
	)
	uniform.bind_group = wgpu.DeviceCreateBindGroup(
		PLATFORM.device,
		&wgpu.BindGroupDescriptor {
			layout = uniform_bind_group_layout_cached(HexChunkUniformData),
			entryCount = 1,
			entries = &wgpu.BindGroupEntry {
				binding = 0,
				buffer = uniform.data,
				offset = 0,
				size = u64(size_of(HexChunkUniformData)),
			},
		},
	)
	return uniform
}

hex_chunks_render :: proc(
	pipeline: wgpu.RenderPipeline,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_2d_uniform: wgpu.BindGroup,
	textures: TextureArrayHandle,
	chunks: []HexChunkUniform,
) {
	if len(chunks) == 0 {
		return
	}
	if textures == {} {
		print("warning! wants to draw tritex meshes, but TextureArrayHandle is 0!")
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_2d_uniform)

	texture_array, ok := assets_get(textures)
	if !ok {
		print("warning! texture array not found!")
	}

	texture_array_bindgroup := texture_array.bind_group
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, texture_array_bindgroup)
	for chunk in chunks {
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 3, chunk.bind_group)
		push_const := HexChunkPushConstants{chunk.chunk_pos}
		// wgpu.RenderPassEncoderSetPushConstants(
		// 	render_pass,
		// 	{.Vertex},
		// 	0,
		// 	size_of(HexChunkPushConstants),
		// 	&push_const,
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
hex_chunk_pipeline_config :: proc() -> RenderPipelineConfig {
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
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera2DUniformData),
			tritex_textures_bind_group_layout_cached(),
			uniform_bind_group_layout_cached(HexChunkUniformData),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DepthConfig{depth_write_enabled = true, depth_compare = .GreaterEqual},
	}
}
