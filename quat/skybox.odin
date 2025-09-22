package quat

import "core:fmt"
import "core:slice"
import "core:strings"
import wgpu "vendor:wgpu"

import stbi "vendor:stb/image"

equirect_reader_load_cube_texture :: proc(
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


EQUIRECTANGULAR_WGSL: string : #load("equirectangular.wgsl")


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
			nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = EQUIRECTANGULAR_WGSL},
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
	size:       UVec2,
	texture:    wgpu.Texture,
	view:       wgpu.TextureView,
	sampler:    wgpu.Sampler,
	bind_group: wgpu.BindGroup,
}
cube_texture_create :: proc(size: UVec2, label: string = "cube_texture") -> CubeTexture {
	format := SKY_TEXTURE_FORMAT
	texture := wgpu.DeviceCreateTexture(
		PLATFORM.device,
		&wgpu.TextureDescriptor {
			label = label,
			usage = {.TextureBinding, .StorageBinding},
			dimension = wgpu.TextureDimension._2D,
			size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 6},
			format = format,
			mipLevelCount = 1,
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
			mipLevelCount = 1,
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
			minFilter     = .Nearest,
			mipmapFilter  = .Nearest,
			maxAnisotropy = 1,
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

	return CubeTexture{size = size, texture = texture, view = view, sampler = sampler, bind_group = bind_group}
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
		vs_shader = "sky",
		vs_entry_point = "vs_main",
		fs_shader = "sky",
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
