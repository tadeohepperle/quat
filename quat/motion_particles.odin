package quat

import "core:fmt"
import wgpu "vendor:wgpu"

MotionTexture :: struct {
	diffuse_size:    UVec2,
	diffuse_texture: wgpu.Texture,
	diffuse_view:    wgpu.TextureView,
	motion_texture:  wgpu.Texture,
	motion_size:     UVec2,
	motion_view:     wgpu.TextureView,
	sampler:         wgpu.Sampler,
	bind_group:      wgpu.BindGroup,
}

motion_texture_destroy :: proc(texture: ^MotionTexture) {
	print("DESTROY Motion texture:")
	wgpu.BindGroupRelease(texture.bind_group)
	wgpu.SamplerRelease(texture.sampler)
	wgpu.TextureViewRelease(texture.diffuse_view)
	wgpu.TextureRelease(texture.diffuse_texture)
	wgpu.TextureViewRelease(texture.motion_view)
	wgpu.TextureRelease(texture.motion_texture)
}

_motion_texture_create_1px_white :: proc() -> MotionTexture {
	texture := motion_texture_create({1, 1}, {1, 1})
	block_size: u32 = 4
	data_layout := wgpu.TexelCopyBufferLayout {
		offset       = 0,
		bytesPerRow  = 4,
		rowsPerImage = 1,
	}
	diffuse_data := [4]u8{255, 255, 255, 255}
	motion_data := [4]u8{127, 127, 0, 255}
	wgpu.QueueWriteTexture(
		PLATFORM.queue,
		&wgpu.TexelCopyTextureInfo{texture = texture.diffuse_texture, mipLevel = 0, origin = {0, 0, 0}, aspect = .All},
		&diffuse_data,
		4,
		&data_layout,
		&wgpu.Extent3D{width = 1, height = 1, depthOrArrayLayers = 1},
	)
	wgpu.QueueWriteTexture(
		PLATFORM.queue,
		&wgpu.TexelCopyTextureInfo{texture = texture.motion_texture, mipLevel = 0, origin = {0, 0, 0}, aspect = .All},
		&motion_data,
		4,
		&data_layout,
		&wgpu.Extent3D{width = 1, height = 1, depthOrArrayLayers = 1},
	)
	return texture
}


motion_texture_sizes_are_ok :: proc(diffuse_size: IVec2, motion_size: IVec2, needs_to_be_pow_2: bool) -> bool {

	if needs_to_be_pow_2 {
		sizes_are_pow_2 :=
			is_power_of_two(diffuse_size.x) &&
			is_power_of_two(diffuse_size.y) &&
			is_power_of_two(motion_size.x) &&
			is_power_of_two(motion_size.y)
		if !sizes_are_pow_2 {
			return false
		}
	}

	return(
		diffuse_size.x >= motion_size.x &&
		diffuse_size.y >= motion_size.y &&
		diffuse_size.x / motion_size.x == diffuse_size.y / motion_size.y &&
		diffuse_size.x % motion_size.x == 0 &&
		diffuse_size.y % motion_size.y == 0 \
	)
}


motion_texture_create :: proc(diffuse_size: IVec2, motion_size: IVec2) -> (res: MotionTexture) {
	assert(
		motion_texture_sizes_are_ok(diffuse_size, motion_size, needs_to_be_pow_2 = true),
		tprint(
			"texture sizes not ok (should be pow2 and proportional), diffuse: ",
			diffuse_size,
			"motion:",
			motion_size,
		),
	)

	DIFFUSE_FORMAT := wgpu.TextureFormat.RGBA8UnormSrgb
	MOTION_FORMAT := wgpu.TextureFormat.RGBA8Unorm // maybe use RG8SNorm later because we only need two channels but anyway...

	diffuse_size := UVec2{u32(diffuse_size.x), u32(diffuse_size.y)}
	motion_size := UVec2{u32(motion_size.x), u32(motion_size.y)}
	res.diffuse_size = diffuse_size
	res.diffuse_texture = wgpu.DeviceCreateTexture(
		PLATFORM.device,
		&wgpu.TextureDescriptor {
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = wgpu.Extent3D{width = diffuse_size.x, height = diffuse_size.y, depthOrArrayLayers = 1},
			format = DIFFUSE_FORMAT,
			mipLevelCount = 1,
			sampleCount = 1,
			viewFormatCount = 1,
			viewFormats = &DIFFUSE_FORMAT,
		},
	)
	res.diffuse_view = wgpu.TextureCreateView(
		res.diffuse_texture,
		&wgpu.TextureViewDescriptor {
			format = DIFFUSE_FORMAT,
			dimension = ._2D,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = 1,
			aspect = .All,
		},
	)
	res.motion_size = motion_size
	res.motion_texture = wgpu.DeviceCreateTexture(
		PLATFORM.device,
		&wgpu.TextureDescriptor {
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = wgpu.Extent3D{width = motion_size.x, height = motion_size.y, depthOrArrayLayers = 1},
			format = MOTION_FORMAT,
			mipLevelCount = 1,
			sampleCount = 1,
			viewFormatCount = 1,
			viewFormats = &MOTION_FORMAT,
		},
	)
	res.motion_view = wgpu.TextureCreateView(
		res.motion_texture,
		&wgpu.TextureViewDescriptor {
			format = MOTION_FORMAT,
			dimension = ._2D,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = 1,
			aspect = .All,
		},
	)

	res.sampler = wgpu.DeviceCreateSampler(
		PLATFORM.device,
		&wgpu.SamplerDescriptor {
			addressModeU = .Repeat,
			addressModeV = .Repeat,
			addressModeW = .Repeat,
			magFilter = .Linear,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			maxAnisotropy = 1,
		},
	)

	bind_group_descriptor_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, textureView = res.diffuse_view},
		wgpu.BindGroupEntry{binding = 1, textureView = res.motion_view},
		wgpu.BindGroupEntry{binding = 2, sampler = res.sampler},
	}
	res.bind_group = wgpu.DeviceCreateBindGroup(
		PLATFORM.device,
		&wgpu.BindGroupDescriptor {
			layout = motion_texture_bind_group_layout_cached(),
			entryCount = uint(len(bind_group_descriptor_entries)),
			entries = &bind_group_descriptor_entries[0],
		},
	)
	return
}

motion_texture_create_from_images :: proc(diffuse: Image, motion: Image) -> (res: MotionTexture) {

	res = motion_texture_create(diffuse.size, motion.size)
	motion_texture_write(res, diffuse, motion)
	return res
}

motion_texture_write :: proc(this: MotionTexture, diffuse: Image, motion: Image) {
	assert(UVec2{u32(diffuse.size.x), u32(diffuse.size.y)} == this.diffuse_size)
	assert(UVec2{u32(motion.size.x), u32(motion.size.y)} == this.motion_size)

	wgpu.QueueWriteTexture(
		PLATFORM.queue,
		&wgpu.TexelCopyTextureInfo{texture = this.diffuse_texture, mipLevel = 0, origin = {0, 0, 0}, aspect = .All},
		raw_data(diffuse.pixels),
		uint(len(diffuse.pixels) * 4),
		&wgpu.TexelCopyBufferLayout {
			offset = 0,
			bytesPerRow = 4 * this.diffuse_size.x,
			rowsPerImage = 4 * this.diffuse_size.y,
		},
		&wgpu.Extent3D{width = this.diffuse_size.x, height = this.diffuse_size.y, depthOrArrayLayers = 1},
	)
	wgpu.QueueWriteTexture(
		PLATFORM.queue,
		&wgpu.TexelCopyTextureInfo{texture = this.motion_texture, mipLevel = 0, origin = {0, 0, 0}, aspect = .All},
		raw_data(motion.pixels),
		uint(len(motion.pixels) * 4),
		&wgpu.TexelCopyBufferLayout {
			offset = 0,
			bytesPerRow = 4 * this.motion_size.x,
			rowsPerImage = 4 * this.motion_size.y,
		},
		&wgpu.Extent3D{width = this.motion_size.x, height = this.motion_size.y, depthOrArrayLayers = 1},
	)
}

DIFFUSE_AND_MOTION_TEXTURE_BIND_GROUP_LAYOUT: wgpu.BindGroupLayout
diffuse_and_motion_texture_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	if DIFFUSE_AND_MOTION_TEXTURE_BIND_GROUP_LAYOUT == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout{sampleType = .Float, viewDimension = ._2D, multisampled = false},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout{sampleType = .Float, viewDimension = ._2D, multisampled = false},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 2,
				visibility = {.Fragment},
				sampler = wgpu.SamplerBindingLayout{type = .Filtering},
			},
		}
		DIFFUSE_AND_MOTION_TEXTURE_BIND_GROUP_LAYOUT = wgpu.DeviceCreateBindGroupLayout(
			device,
			&wgpu.BindGroupLayoutDescriptor{entryCount = uint(len(entries)), entries = &entries[0]},
		)
	}
	return DIFFUSE_AND_MOTION_TEXTURE_BIND_GROUP_LAYOUT
}


MotionParticleInstance :: struct {
	pos:      Vec2,
	size:     Vec2,
	color:    Color,
	z:        f32,
	rotation: f32,
	lifetime: f32,
	t_offset: f32,
}

// ASSUMPTION: tiles of the diffuse image and motion image have the same UV coords (motion image can be scaled though!!)
FlipbookData :: struct {
	time:         f32,
	_:            f32,
	n_tiles:      u32, // how many tiles there are in total
	n_x_tiles:    u32, // how many tiles there are in x direction
	start_uv:     Vec2, // diffuse and motion image start uv pos of first flipbook tile in atlas
	uv_tile_size: Vec2, // size per tile!
}

MotionParticlesRenderCommand :: struct {
	texture:        MotionTextureHandle,
	first_instance: u32,
	instance_count: u32,
	flipbook:       FlipbookData,
}

// all particles share the same instance_buffer, that is rewritten every frame
motion_particles_render :: proc(
	pipeline: wgpu.RenderPipeline,
	instance_buffer: DynamicBuffer(MotionParticleInstance),
	commands: []MotionParticlesRenderCommand,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_2d_uniform: wgpu.BindGroup,
) {
	if len(commands) == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_2d_uniform)
	wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, instance_buffer.buffer, 0, instance_buffer.size)
	motion_textures := assets_get_map(MotionTexture)
	for &cmd in commands {
		motion_texture := slotmap_get(motion_textures, cmd.texture)
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, motion_texture.bind_group)
		wgpu.RenderPassEncoderSetPushConstants(
			render_pass,
			{.Vertex, .Fragment},
			0,
			size_of(FlipbookData),
			&cmd.flipbook,
		)
		wgpu.RenderPassEncoderDraw(render_pass, 4, cmd.instance_count, 0, cmd.first_instance)
	}
}

MOTION_PARTICLE_ATTRIBUTES := []VertAttibute {
	{format = .Float32x2, offset = offset_of(MotionParticleInstance, pos)}, // vec2<f32>
	{format = .Float32x2, offset = offset_of(MotionParticleInstance, size)}, // vec2<f32>
	{format = .Float32x4, offset = offset_of(MotionParticleInstance, color)}, // color: vec4<f32>
	{format = .Float32x2, offset = offset_of(MotionParticleInstance, z)}, // z: f32, rotation: f32
	{format = .Float32x2, offset = offset_of(MotionParticleInstance, lifetime)}, // lifetime: f32, t_offset: f32
}

motion_particles_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "motion_particle",
		vs_shader = "motion_particle",
		vs_entry_point = "vs_main",
		fs_shader = "motion_particle",
		fs_entry_point = "fs_main",
		topology = .TriangleStrip,
		vertex = {},
		instance = {ty_id = MotionParticleInstance, attributes = MOTION_PARTICLE_ATTRIBUTES},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera2DUniformData),
			motion_texture_bind_group_layout_cached(),
		),
		push_constant_ranges = push_const_range(FlipbookData, {.Vertex, .Fragment}),
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}

MOTION_TEXTURE_BIND_GROUP_LAYOUT: wgpu.BindGroupLayout
motion_texture_bind_group_layout_cached :: proc() -> wgpu.BindGroupLayout {
	if MOTION_TEXTURE_BIND_GROUP_LAYOUT == nil {
		entries := [3]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout{sampleType = .Float, viewDimension = ._2D, multisampled = false},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout{sampleType = .Float, viewDimension = ._2D, multisampled = false},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 2,
				visibility = {.Fragment},
				sampler = wgpu.SamplerBindingLayout{type = .Filtering},
			},
		}
		MOTION_TEXTURE_BIND_GROUP_LAYOUT = wgpu.DeviceCreateBindGroupLayout(
			PLATFORM.device,
			&wgpu.BindGroupLayoutDescriptor{entryCount = uint(len(entries)), entries = &entries[0]},
		)
	}
	return MOTION_TEXTURE_BIND_GROUP_LAYOUT
}
