package quat
import wgpu "vendor:wgpu"


HEX_TO_WORLD_POS_MAT :: matrix[2, 2]f32{
	1.5, 0, 
	-0.75, 1.5, 
}
hex_to_world_pos :: proc "contextless" (hex_pos: [2]i32) -> Vec2 {
	return HEX_TO_WORLD_POS_MAT * Vec2{f32(hex_pos.x), f32(hex_pos.y)}
}


CHUNK_SIZE :: 64
CHUNK_SIZE_PADDED :: CHUNK_SIZE + 2
// This data has 1 padding on each side

// could probably be compressed to 1/2 or 1/4th of this size. Very wasteful.
// but that is a concern for later
HexTileData :: struct {
	old_terrain: u16,
	new_terrain: u16,
	new_factor:  f16,
	visibility:  f16,
}

HexChunkData :: [CHUNK_SIZE_PADDED * CHUNK_SIZE_PADDED]HexTileData

HexChunkUniform :: struct {
	chunk_pos:  [2]i32,
	device:     wgpu.Device,
	queue:      wgpu.Queue,
	data:       wgpu.Buffer, // of type HexChunkData
	bind_group: wgpu.BindGroup,
}
hex_chunk_uniform_destroy :: proc(this: ^HexChunkUniform) {
	this.device = nil
	this.queue = nil
	wgpu.BindGroupRelease(this.bind_group)
	wgpu.BufferDestroy(this.data)
}

hex_chunk_uniform_write_data :: proc(this: ^HexChunkUniform, terrain_data: ^HexChunkData) {
	assert(this.queue != nil)
	wgpu.QueueWriteBuffer(this.queue, this.data, 0, terrain_data, size_of(HexChunkData))
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
	uniform.data = wgpu.DeviceCreateBuffer(
		device,
		&wgpu.BufferDescriptor {
			usage = buffer_usage,
			size = size_of(HexChunkData),
			mappedAtCreation = false,
		},
	)
	uniform.bind_group = wgpu.DeviceCreateBindGroup(
		device,
		&wgpu.BindGroupDescriptor {
			layout = hex_chunk_data_bind_group_layout_cached(device),
			entryCount = 1,
			entries = &wgpu.BindGroupEntry {
				binding = 0,
				buffer = uniform.data,
				offset = 0,
				size = u64(size_of(HexChunkData)),
			},
		},
	)
	return uniform
}
hex_chunk_data_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	@(static) layout: wgpu.BindGroupLayout
	if layout == nil {
		entries := []wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Vertex, .Fragment},
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of(HexChunkData),
				},
			},
		}
		layout = wgpu.DeviceCreateBindGroupLayout(
			device,
			&wgpu.BindGroupLayoutDescriptor{entryCount = 1, entries = raw_data(entries)},
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
			hex_chunk_data_bind_group_layout_cached(device),
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
