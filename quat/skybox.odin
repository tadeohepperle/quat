package quat

import "core:c"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import wgpu "vendor:wgpu"

import stbi "vendor:stb/image"


// todo: follow https://learnopengl.com/PBR/IBL/Diffuse-irradiance


cube_texture_load_and_generate_mip_levels :: proc(
	reader: EquirectReader,
	mip_generator: CubeTextureMipGenerator,
	path: string,
	cube_texture_size: u32,
) -> (
	cube_texture: CubeTexture,
	err: Error,
) {
	if !is_power_of_two(int(cube_texture_size)) {
		return {}, tprint("cube texture size has to be power of 2, got ", cube_texture_size)
	}

	cube_texture = cube_texture_load(reader, path, cube_texture_size) or_return
	cube_texture_generate_mip_levels(mip_generator, cube_texture)
	return cube_texture, nil
}

cube_texture_load :: proc(
	reader: EquirectReader,
	path: string,
	cube_texture_size: u32,
) -> (
	cube_texture: CubeTexture,
	err: Error,
) {
	file_name := strings.clone_to_cstring(path, context.temp_allocator)

	x, y, channels: i32
	desired_channels: i32 = 4

	if !bool(stbi.is_hdr(file_name)) {
		return {}, "file is not HDR!"
	}

	pixels_ptr := stbi.loadf(file_name, &x, &y, &channels, desired_channels)
	pixels := slice.from_ptr(cast(^u8)pixels_ptr, int(x * y * size_of(f32) * desired_channels))

	size := UVec2{u32(x), u32(y)}
	fmt.println("Loaded hdr environment map with size", size)

	wgpu.DevicePushErrorScope(PLATFORM.device, .Validation)

	src_texture := wgpu.DeviceCreateTexture(
		PLATFORM.device,
		&wgpu.TextureDescriptor {
			usage = {.CopyDst, .TextureBinding},
			dimension = ._2D,
			size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
			format = SKY_TEXTURE_FORMAT,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	defer wgpu.TextureRelease(src_texture)

	src_texture_view := wgpu.TextureCreateView(
		src_texture,
		&wgpu.TextureViewDescriptor{dimension = ._2D, mipLevelCount = 1, arrayLayerCount = 1, aspect = .All},
	)
	defer wgpu.TextureViewRelease(src_texture_view)

	src_texture_sampler := wgpu.DeviceCreateSampler(
		PLATFORM.device,
		&wgpu.SamplerDescriptor {
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			maxAnisotropy = 1,
		},
	)
	defer wgpu.SamplerRelease(src_texture_sampler)

	// copy pixels to the texture:
	wgpu.QueueWriteTexture(
		PLATFORM.queue,
		&wgpu.TexelCopyTextureInfo{texture = src_texture, mipLevel = 0, origin = {0, 0, 0}, aspect = .All},
		raw_data(pixels),
		len(pixels),
		&wgpu.TexelCopyBufferLayout {
			offset = 0,
			bytesPerRow = size.x * size_of(f32) * u32(desired_channels),
			rowsPerImage = size.y,
		},
		&wgpu.Extent3D{size.x, size.y, 1},
	)

	cube_size := UVec2{cube_texture_size, cube_texture_size}
	cube_texture = cube_texture_create(cube_size)
	// defer if err != nil {
	// 	cube_texture_destroy(&cube_texture)
	// }

	cube_map_2d_arr_view := wgpu.TextureCreateView(
		cube_texture.texture,
		&wgpu.TextureViewDescriptor {
			label = "cube map view as texture array",
			dimension = wgpu.TextureViewDimension._2DArray,
			mipLevelCount = 1,
			arrayLayerCount = 6,
			aspect = .All,
		},
	)


	defer wgpu.TextureViewRelease(cube_map_2d_arr_view)

	bind_group_descriptor_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, textureView = src_texture_view},
		wgpu.BindGroupEntry{binding = 1, textureView = cube_map_2d_arr_view},
	}

	bind_group := wgpu.DeviceCreateBindGroup(
		PLATFORM.device,
		&wgpu.BindGroupDescriptor {
			layout = reader.bind_group_layout,
			entryCount = uint(len(bind_group_descriptor_entries)),
			entries = &bind_group_descriptor_entries[0],
		},
	)
	defer wgpu.BindGroupRelease(bind_group)

	// now ready to dispatch compute:

	encoder := wgpu.DeviceCreateCommandEncoder(PLATFORM.device)

	pass := wgpu.CommandEncoderBeginComputePass(encoder, &wgpu.ComputePassDescriptor{label = "equirect pass"})
	num_workgroups := (cube_texture_size + 15) / 16
	wgpu.ComputePassEncoderSetPipeline(pass, reader.compute_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(pass, 0, bind_group)
	wgpu.ComputePassEncoderDispatchWorkgroups(pass, num_workgroups, num_workgroups, 6)
	wgpu.ComputePassEncoderEnd(pass)
	wgpu.ComputePassEncoderRelease(pass)

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.CommandEncoderRelease(encoder)
	wgpu.QueueSubmit(PLATFORM.queue, {command_buffer})

	if err, has_err := wgpu_pop_error_scope(PLATFORM.device).(WgpuError); has_err {
		return {}, tprint("Error creating cubemap texture:", err.message)
	} else {
		return cube_texture, nil
	}

}


SKYBOX_EQUIRECTANGULAR_WGSL: string : #load("skybox_equirectangular.wgsl")
SKYBOX_MIP_LEVEL_WGSL: string : #load("skybox_mip_level.wgsl")

SKY_TEXTURE_FORMAT :: wgpu.TextureFormat.RGBA32Float

EquirectReader :: struct {
	bind_group_layout: wgpu.BindGroupLayout,
	pipeline_layout:   wgpu.PipelineLayout,
	shader_module:     wgpu.ShaderModule,
	compute_pipeline:  wgpu.ComputePipeline,
}

equirect_reader_create :: proc() -> EquirectReader {
	entries := [?]wgpu.BindGroupLayoutEntry {
		wgpu.BindGroupLayoutEntry {
			binding = 0,
			visibility = {.Compute},
			texture = wgpu.TextureBindingLayout {
				sampleType = .UnfilterableFloat,
				viewDimension = ._2D,
				multisampled = false,
			},
		},
		wgpu.BindGroupLayoutEntry {
			binding = 1,
			visibility = {.Compute},
			storageTexture = wgpu.StorageTextureBindingLayout {
				access = .WriteOnly,
				format = SKY_TEXTURE_FORMAT,
				viewDimension = ._2DArray,
			},
		},
	}
	bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		PLATFORM.device,
		&wgpu.BindGroupLayoutDescriptor{entryCount = uint(len(entries)), entries = &entries[0]},
	)

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		PLATFORM.device,
		&wgpu.PipelineLayoutDescriptor{bindGroupLayoutCount = 1, bindGroupLayouts = &bind_group_layout},
	)


	shader_module := wgpu.DeviceCreateShaderModule(
		PLATFORM.device,
		&wgpu.ShaderModuleDescriptor {
			label = "equirect_to_cubemap",
			nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = SKYBOX_EQUIRECTANGULAR_WGSL},
		},
	)

	compute_pipeline := wgpu.DeviceCreateComputePipeline(
		PLATFORM.device,
		&wgpu.ComputePipelineDescriptor {
			layout = pipeline_layout,
			label = "equirect_to_cubemap",
			compute = wgpu.ProgrammableStageDescriptor {
				module = shader_module,
				entryPoint = "compute_equirect_to_cubemap",
			},
		},
	)

	return EquirectReader{bind_group_layout, pipeline_layout, shader_module, compute_pipeline}
}

equirect_reader_drop :: proc(this: ^EquirectReader) {
	wgpu.BindGroupLayoutRelease(this.bind_group_layout)
	wgpu.PipelineLayoutRelease(this.pipeline_layout)
	wgpu.ComputePipelineRelease(this.compute_pipeline)
	wgpu.ShaderModuleRelease(this.shader_module)
}

CubeTexture :: struct {
	size:            UVec2,
	mip_level_count: u32,
	texture:         wgpu.Texture,
	view:            wgpu.TextureView,
	sampler:         wgpu.Sampler,
	bind_group:      wgpu.BindGroup,
}

mip_level_count_for_texture_size :: proc(size: UVec2) -> u32 {
	return u32(math.log2(f32(min(size.x, size.y)))) + 1
}


CubeTextureMipGenerator :: struct {
	bind_group_layout: wgpu.BindGroupLayout,
	pipeline_layout:   wgpu.PipelineLayout,
	shader_module:     wgpu.ShaderModule,
	compute_pipeline:  wgpu.ComputePipeline,
}

cube_texture_mip_generator_create :: proc() -> CubeTextureMipGenerator {
	entries := [?]wgpu.BindGroupLayoutEntry {
		wgpu.BindGroupLayoutEntry {
			binding = 0,
			visibility = {.Compute},
			texture = wgpu.TextureBindingLayout{sampleType = .Float, viewDimension = ._2DArray, multisampled = false},
		},
		wgpu.BindGroupLayoutEntry {
			binding = 1,
			visibility = {.Compute},
			storageTexture = wgpu.StorageTextureBindingLayout {
				access = .WriteOnly,
				format = SKY_TEXTURE_FORMAT,
				viewDimension = ._2DArray,
			},
		},
	}
	bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		PLATFORM.device,
		&wgpu.BindGroupLayoutDescriptor{entryCount = uint(len(entries)), entries = &entries[0]},
	)

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		PLATFORM.device,
		&wgpu.PipelineLayoutDescriptor{bindGroupLayoutCount = 1, bindGroupLayouts = &bind_group_layout},
	)
	shader_module := wgpu.DeviceCreateShaderModule(
		PLATFORM.device,
		&wgpu.ShaderModuleDescriptor {
			label = "skybox_mip_level",
			nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = SKYBOX_MIP_LEVEL_WGSL},
		},
	)

	compute_pipeline := wgpu.DeviceCreateComputePipeline(
		PLATFORM.device,
		&wgpu.ComputePipelineDescriptor {
			layout = pipeline_layout,
			label = "skybox_mip_level",
			compute = wgpu.ProgrammableStageDescriptor{module = shader_module, entryPoint = "compute_mip_level"},
		},
	)

	return CubeTextureMipGenerator{bind_group_layout, pipeline_layout, shader_module, compute_pipeline}
}

cube_texture_mip_generator_drop :: proc(this: ^CubeTextureMipGenerator) {
	wgpu.BindGroupLayoutRelease(this.bind_group_layout)
	wgpu.PipelineLayoutRelease(this.pipeline_layout)
	wgpu.ComputePipelineRelease(this.compute_pipeline)
	wgpu.ShaderModuleRelease(this.shader_module)
}

cube_texture_generate_mip_levels :: proc(mip_generator: CubeTextureMipGenerator, cube_texture: CubeTexture) {
	assert(cube_texture.size.x == cube_texture.size.y)

	n_mip_levels := cube_texture
	mip_level_texture_views := make([]wgpu.TextureView, cube_texture.mip_level_count)
	defer {
		for view in mip_level_texture_views do wgpu.TextureViewRelease(view)
		delete(mip_level_texture_views)
	}

	for &view, i in mip_level_texture_views {
		view = wgpu.TextureCreateView(
			cube_texture.texture,
			&wgpu.TextureViewDescriptor {
				label = tprint("cube texture mip level", i),
				dimension = wgpu.TextureViewDimension._2DArray,
				baseMipLevel = u32(i),
				mipLevelCount = 1,
				baseArrayLayer = 0,
				arrayLayerCount = 6,
				aspect = .All,
			},
		)
	}

	encoder := wgpu.DeviceCreateCommandEncoder(PLATFORM.device)
	defer wgpu.CommandEncoderRelease(encoder)

	dst_view_size := cube_texture.size
	for dst_mip_level in 1 ..< cube_texture.mip_level_count {
		dst_view_size /= 2
		src_view := mip_level_texture_views[dst_mip_level - 1]
		dst_view := mip_level_texture_views[dst_mip_level]

		bind_group_entries := [?]wgpu.BindGroupEntry {
			wgpu.BindGroupEntry{binding = 0, textureView = src_view},
			wgpu.BindGroupEntry{binding = 1, textureView = dst_view},
		}
		bind_group := wgpu.DeviceCreateBindGroup(
			PLATFORM.device,
			&wgpu.BindGroupDescriptor {
				layout = mip_generator.bind_group_layout,
				entryCount = uint(len(bind_group_entries)),
				entries = &bind_group_entries[0],
			},
		)
		defer wgpu.BindGroupRelease(bind_group)

		// dispatch compute:
		pass := wgpu.CommandEncoderBeginComputePass(encoder, &wgpu.ComputePassDescriptor{label = "mip level pass"})

		wgpu.ComputePassEncoderSetPipeline(pass, mip_generator.compute_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, bind_group)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, dst_view_size.x, dst_view_size.y, 6)
		wgpu.ComputePassEncoderEnd(pass)
		wgpu.ComputePassEncoderRelease(pass)
	}

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	wgpu.QueueSubmit(PLATFORM.queue, {command_buffer})
}

cube_texture_create :: proc(size: UVec2, label: string = "cube_texture") -> CubeTexture {
	format := SKY_TEXTURE_FORMAT

	assert(size.x == size.y)
	assert(next_power_of_two(int(size.x)) == int(size.x))

	mip_level_count := mip_level_count_for_texture_size(size)
	print("size:", size, "mip level count", mip_level_count)
	texture := wgpu.DeviceCreateTexture(
		PLATFORM.device,
		&wgpu.TextureDescriptor {
			label = label,
			usage = {.TextureBinding, .StorageBinding},
			dimension = wgpu.TextureDimension._2D,
			size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 6},
			format = format,
			mipLevelCount = mip_level_count,
			sampleCount = 1,
			viewFormatCount = 0,
			viewFormats = nil,
		},
	)

	view := wgpu.TextureCreateView(
		texture,
		&wgpu.TextureViewDescriptor {
			label = label,
			dimension = wgpu.TextureViewDimension.Cube,
			format = format,
			baseMipLevel = 0,
			mipLevelCount = mip_level_count,
			arrayLayerCount = 6,
			aspect = .All,
		},
	)

	sampler := wgpu.DeviceCreateSampler(
		PLATFORM.device,
		&wgpu.SamplerDescriptor {
			addressModeU  = .ClampToEdge,
			addressModeV  = .ClampToEdge,
			addressModeW  = .ClampToEdge,
			magFilter     = .Linear, // or .Nearest?
			minFilter     = .Linear,
			mipmapFilter  = .Linear,
			maxAnisotropy = 1,
			lodMinClamp   = 0.0,
			lodMaxClamp   = f32(mip_level_count),
		},
	)


	bind_group_descriptor_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, textureView = view},
		wgpu.BindGroupEntry{binding = 1, sampler = sampler},
	}
	bind_group_descriptor := wgpu.BindGroupDescriptor {
		layout     = sky_box_bind_group_layout_cached(),
		entryCount = uint(len(bind_group_descriptor_entries)),
		entries    = &bind_group_descriptor_entries[0],
	}
	bind_group := wgpu.DeviceCreateBindGroup(PLATFORM.device, &bind_group_descriptor)

	return CubeTexture {
		size = size,
		mip_level_count = mip_level_count,
		texture = texture,
		view = view,
		sampler = sampler,
		bind_group = bind_group,
	}
}

cube_texture_destroy :: proc(texture: ^CubeTexture) {
	wgpu.BindGroupRelease(texture.bind_group)
	wgpu.SamplerRelease(texture.sampler)
	wgpu.TextureViewRelease(texture.view)
	wgpu.TextureRelease(texture.texture)
}

SKY_BOX_BIND_GROUP_LAYOUT: wgpu.BindGroupLayout

sky_box_bind_group_layout_cached :: proc() -> wgpu.BindGroupLayout {
	if SKY_BOX_BIND_GROUP_LAYOUT == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout{sampleType = .Float, viewDimension = .Cube, multisampled = false},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Fragment},
				sampler = wgpu.SamplerBindingLayout{type = .Filtering},
			},
		}
		SKY_BOX_BIND_GROUP_LAYOUT = wgpu.DeviceCreateBindGroupLayout(
			PLATFORM.device,
			&wgpu.BindGroupLayoutDescriptor{entryCount = uint(len(entries)), entries = &entries[0]},
		)
	}
	return SKY_BOX_BIND_GROUP_LAYOUT
}

sky_box_render :: proc(
	pipeline: wgpu.RenderPipeline,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	camera_3d_uniform: wgpu.BindGroup,
	cube_texture: wgpu.BindGroup,
) {
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, camera_3d_uniform)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, cube_texture)
	wgpu.RenderPassEncoderDraw(render_pass, 3, 1, 0, 0)
}

sky_box_pipeline_config :: proc() -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "sky",
		vs_shader = "sky.wgsl",
		vs_entry_point = "vs_main",
		fs_shader = "sky.wgsl",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			uniform_bind_group_layout_cached(Camera3DUniformData),
			sky_box_bind_group_layout_cached(),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DepthConfig{depth_write_enabled = false, depth_compare = .LessEqual},
	}
}
