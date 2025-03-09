package quat

import "core:fmt"
import wgpu "vendor:wgpu"

DiffuseAndMotionTexture :: struct {
	size:            UVec2,
	diffuse_texture: wgpu.Texture,
	diffuse_view:    wgpu.TextureView,
	motion_texture:  wgpu.Texture,
	motion_view:     wgpu.TextureView,
	sampler:         wgpu.Sampler,
	bind_group:      wgpu.BindGroup,
}


diffuse_and_motion_texture_create :: proc(
	size: IVec2,
	device: wgpu.Device,
) -> (
	res: DiffuseAndMotionTexture,
) {
	DIFFUSE_FORMAT := wgpu.TextureFormat.RGBA8UnormSrgb
	MOTION_FORMAT := wgpu.TextureFormat.RGBA8UnormSrgb // maybe use RG8SNorm later because we only need two channels but anyway...

	size := UVec2{u32(size.x), u32(size.y)}
	res.size = size
	res.diffuse_texture = wgpu.DeviceCreateTexture(
		device,
		&wgpu.TextureDescriptor {
			usage = {.TextureBinding},
			dimension = ._2D,
			size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
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
	res.motion_texture = wgpu.DeviceCreateTexture(
		device,
		&wgpu.TextureDescriptor {
			usage = {.TextureBinding},
			dimension = ._2D,
			size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
			format = MOTION_FORMAT,
			mipLevelCount = 1,
			sampleCount = 1,
			viewFormatCount = 1,
			viewFormats = &MOTION_FORMAT,
		},
	)
	res.motion_view = wgpu.TextureCreateView(
		res.diffuse_texture,
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
		device,
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
		device,
		&wgpu.BindGroupDescriptor {
			layout = rgba_bind_group_layout_cached(device),
			entryCount = uint(len(bind_group_descriptor_entries)),
			entries = &bind_group_descriptor_entries[0],
		},
	)
	return
}

diffuse_and_motion_texture_create_from_images :: proc(
	diffuse: Image,
	motion: Image,
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> (
	res: DiffuseAndMotionTexture,
) {
	assert(diffuse.size == motion.size)
	res = diffuse_and_motion_texture_create(diffuse.size, device)
	diffuse_and_motion_texture_write(&res, diffuse, motion, queue)
	return res
}

diffuse_and_motion_texture_write :: proc(
	this: ^DiffuseAndMotionTexture,
	diffuse: Image,
	motion: Image,
	queue: wgpu.Queue,
) {
	assert(diffuse.size == motion.size)
	assert(UVec2{u32(diffuse.size.x), u32(diffuse.size.y)} == this.size)
	size := this.size

	BLOCK_SIZE :: 4
	bytes_per_row :=
		((size.x * BLOCK_SIZE + COPY_BYTES_PER_ROW_ALIGNMENT - 1) &
			~(COPY_BYTES_PER_ROW_ALIGNMENT - 1))
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = bytes_per_row,
		rowsPerImage = size.y,
	}
	extent := wgpu.Extent3D {
		width              = size.x,
		height             = size.y,
		depthOrArrayLayers = 1,
	}
	wgpu.QueueWriteTexture(
		queue,
		&wgpu.ImageCopyTexture {
			texture = this.diffuse_texture,
			mipLevel = 0,
			origin = {0, 0, 0},
			aspect = .All,
		},
		raw_data(diffuse.pixels),
		uint(len(diffuse.pixels) * 4),
		&data_layout,
		&extent,
	)
	wgpu.QueueWriteTexture(
		queue,
		&wgpu.ImageCopyTexture {
			texture = this.motion_texture,
			mipLevel = 0,
			origin = {0, 0, 0},
			aspect = .All,
		},
		raw_data(motion.pixels),
		uint(len(motion.pixels) * 4),
		&data_layout,
		&extent,
	)
}

diffuse_and_motion_texture_bind_group_layout_cached :: proc(
	device: wgpu.Device,
) -> wgpu.BindGroupLayout {
	@(static) layout: wgpu.BindGroupLayout
	if layout == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2D,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2D,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 2,
				visibility = {.Fragment},
				sampler = wgpu.SamplerBindingLayout{type = .Filtering},
			},
		}
		layout = wgpu.DeviceCreateBindGroupLayout(
			device,
			&wgpu.BindGroupLayoutDescriptor {
				entryCount = uint(len(entries)),
				entries = &entries[0],
			},
		)
	}
	return layout
}
