package quat

import "core:fmt"
import wgpu "vendor:wgpu"

IMAGE_FORMAT :: wgpu.TextureFormat.RGBA8Unorm
DEPTH_SPRITE_IMAGE_FORMAT :: wgpu.TextureFormat.R16Unorm

TEXTURE_SETTINGS_RGBA :: TextureSettings {
	label        = "",
	format       = IMAGE_FORMAT,
	address_mode = .Repeat,
	mag_filter   = .Linear,
	min_filter   = .Nearest,
	usage        = {.TextureBinding, .CopyDst},
}
TEXTURE_SETTINGS_DEPTH_SPRITE :: TextureSettings {
	label        = "",
	format       = DEPTH_SPRITE_IMAGE_FORMAT,
	address_mode = .ClampToEdge,
	mag_filter   = .Linear,
	min_filter   = .Nearest,
	usage        = {.TextureBinding, .CopyDst},
}


TextureSettings :: struct {
	label:        string,
	format:       wgpu.TextureFormat,
	address_mode: wgpu.AddressMode,
	mag_filter:   wgpu.FilterMode,
	min_filter:   wgpu.FilterMode,
	usage:        wgpu.TextureUsageFlags,
}

// Can also represent a texture array if info.layers > 1
Texture :: struct {
	info:       TextureInfo,
	texture:    wgpu.Texture,
	view:       wgpu.TextureView,
	sampler:    wgpu.Sampler,
	bind_group: wgpu.BindGroup,
}

DepthTexture :: struct {
	using _: Texture,
}

TextureInfo :: struct {
	size:     UVec2,
	settings: TextureSettings,
	layers:   u32, // Only > 1 for a texture_array
}

TextureTile :: struct {
	handle: TextureHandle,
	uv:     Aabb,
}

TextureTileWithDepth :: struct {
	color: TextureHandle, // RGBA8
	depth: TextureHandle, // R16 for depth
	uv:    Aabb,
}

texture_from_image_path :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	path: string,
	settings: TextureSettings = TEXTURE_SETTINGS_RGBA,
) -> (
	texture: Texture,
	error: Error,
) {
	img := image_load(path) or_return
	texture = texture_from_image(device, queue, img, settings)
	image_drop(&img)
	return
}

COPY_BYTES_PER_ROW_ALIGNMENT: u32 : 256 // Buffer-Texture copies must have [`bytes_per_row`] aligned to this number.
texture_from_image :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	img: Image,
	settings: TextureSettings = TEXTURE_SETTINGS_RGBA,
) -> (
	texture: Texture,
) {
	assert(settings.format == IMAGE_FORMAT)
	size := UVec2{u32(img.size.x), u32(img.size.y)}
	if size.x % 64 != 0 {
		panic(
			"Currently only images with at least 64px per row (256 bytes per row) are supported, bc. of https://docs.rs/wgpu/latest/wgpu/struct.ImageDataLayout.html",
		)
	}
	texture = texture_create(device, size, settings)
	texture_write_from_image(queue, texture, img)
	return texture
}
texture_write_from_image :: proc(queue: wgpu.Queue, texture: Texture, img: Image) {
	size := texture.info.size
	assert(size.x == u32(img.size.x))
	assert(size.y == u32(img.size.y))

	BLOCK_SIZE :: 4
	bytes_per_row :=
		((size.x * BLOCK_SIZE + COPY_BYTES_PER_ROW_ALIGNMENT - 1) &
			~(COPY_BYTES_PER_ROW_ALIGNMENT - 1))
	image_copy := texture_as_image_copy(texture)
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = bytes_per_row,
		rowsPerImage = size.y,
	}
	wgpu.QueueWriteTexture(
		queue,
		&image_copy,
		raw_data(img.pixels),
		uint(len(img.pixels) * 4),
		&data_layout,
		&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
	)
}

depth_texture_16bit_r_from_image_path :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	path: string,
	settings: TextureSettings = TEXTURE_SETTINGS_DEPTH_SPRITE,
) -> (
	texture: Texture,
	error: Error,
) {
	assert(settings.format == DEPTH_SPRITE_IMAGE_FORMAT)
	img := depth_image_load(path) or_return
	defer {depth_image_drop(&img)}
	size := UVec2{u32(img.size.x), u32(img.size.y)}
	texture = texture_create(device, size, settings)

	if size.x % 128 != 0 {
		panic(
			"Currently only depth images with at least 128px per row (256 bytes per row) are supported, bc. of https://docs.rs/wgpu/latest/wgpu/struct.ImageDataLayout.html",
		)
	}
	block_size: u32 = 2
	bytes_per_row := size.x * block_size
	image_copy := texture_as_image_copy(texture)
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = bytes_per_row,
		rowsPerImage = size.y,
	}
	wgpu.QueueWriteTexture(
		queue,
		&image_copy,
		raw_data(img.pixels),
		uint(len(img.pixels) * 2),
		&data_layout,
		&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
	)
	return texture, {}
}

texture_as_image_copy :: proc(texture: Texture) -> wgpu.ImageCopyTexture {
	return wgpu.ImageCopyTexture {
		texture = texture.texture,
		mipLevel = 0,
		origin = {0, 0, 0},
		aspect = .All,
	}
}

_texture_create_1px_white :: proc(device: wgpu.Device, queue: wgpu.Queue) -> Texture {
	texture := texture_create(device, {1, 1}, TEXTURE_SETTINGS_RGBA)
	block_size: u32 = 4
	image_copy := texture_as_image_copy(texture)
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = 4,
		rowsPerImage = 1,
	}
	data := [4]u8{255, 255, 255, 255}
	wgpu.QueueWriteTexture(
		queue,
		&image_copy,
		&data,
		4,
		&data_layout,
		&wgpu.Extent3D{width = 1, height = 1, depthOrArrayLayers = 1},
	)
	return texture
}

DEPTH_TEXTURE_FORMAT :: wgpu.TextureFormat.Depth32Float
depth_texture_create :: proc(device: wgpu.Device, size: UVec2) -> DepthTexture {
	texture: Texture
	settings := TextureSettings {
		label        = "depth_texture",
		format       = DEPTH_TEXTURE_FORMAT,
		address_mode = .ClampToEdge,
		mag_filter   = .Linear,
		min_filter   = .Nearest,
		usage        = {.TextureBinding, .RenderAttachment},
	}

	texture.info = TextureInfo{size, settings, 1}
	descriptor := wgpu.TextureDescriptor {
		usage = settings.usage,
		dimension = ._2D,
		size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
		format = settings.format,
		mipLevelCount = 1,
		sampleCount = 1,
		viewFormatCount = 1,
		viewFormats = &texture.info.settings.format,
	}
	texture.texture = wgpu.DeviceCreateTexture(device, &descriptor)

	texture_view_descriptor := wgpu.TextureViewDescriptor {
		format          = settings.format,
		dimension       = ._2D,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = 1,
		aspect          = .All,
	}
	texture.view = wgpu.TextureCreateView(texture.texture, &texture_view_descriptor)

	sampler_descriptor := wgpu.SamplerDescriptor {
		addressModeU  = settings.address_mode,
		addressModeV  = settings.address_mode,
		addressModeW  = settings.address_mode,
		magFilter     = settings.mag_filter,
		minFilter     = settings.min_filter,
		mipmapFilter  = .Nearest,
		maxAnisotropy = 1,
	}
	texture.sampler = wgpu.DeviceCreateSampler(device, &sampler_descriptor)

	bind_group_descriptor_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, textureView = texture.view},
		wgpu.BindGroupEntry{binding = 1, sampler = texture.sampler},
	}
	bind_group_descriptor := wgpu.BindGroupDescriptor {
		layout     = depth_texture_bind_group_layout_cached(device),
		entryCount = uint(len(bind_group_descriptor_entries)),
		entries    = &bind_group_descriptor_entries[0],
	}
	texture.bind_group = wgpu.DeviceCreateBindGroup(device, &bind_group_descriptor)
	return DepthTexture{texture}
}
depth_texture_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	@(static) LAYOUT: wgpu.BindGroupLayout
	if LAYOUT == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout {
					sampleType = .Depth,
					viewDimension = ._2D,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Fragment},
				sampler = wgpu.SamplerBindingLayout{type = .Filtering}, // maybe comparison here??
			},
		}
		LAYOUT = wgpu.DeviceCreateBindGroupLayout(
			device,
			&wgpu.BindGroupLayoutDescriptor {
				entryCount = uint(len(entries)),
				entries = &entries[0],
			},
		)
	}
	return LAYOUT
}

texture_create :: proc(
	device: wgpu.Device,
	size: UVec2,
	settings: TextureSettings = TEXTURE_SETTINGS_RGBA,
) -> (
	texture: Texture,
) {
	assert(wgpu.TextureUsage.TextureBinding in settings.usage)

	texture.info = TextureInfo{size, settings, 1}
	descriptor := wgpu.TextureDescriptor {
		usage = settings.usage,
		dimension = ._2D,
		size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
		format = settings.format,
		mipLevelCount = 1,
		sampleCount = 1,
		viewFormatCount = 1,
		viewFormats = &texture.info.settings.format,
	}
	texture.texture = wgpu.DeviceCreateTexture(device, &descriptor)

	texture_view_descriptor := wgpu.TextureViewDescriptor {
		format          = settings.format,
		dimension       = ._2D,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = 1,
		aspect          = .All,
	}
	texture.view = wgpu.TextureCreateView(texture.texture, &texture_view_descriptor)

	sampler_descriptor := wgpu.SamplerDescriptor {
		addressModeU  = settings.address_mode,
		addressModeV  = settings.address_mode,
		addressModeW  = settings.address_mode,
		magFilter     = settings.mag_filter,
		minFilter     = settings.min_filter,
		mipmapFilter  = .Nearest,
		maxAnisotropy = 1,
		// ...
	}
	texture.sampler = wgpu.DeviceCreateSampler(device, &sampler_descriptor)

	bind_group_descriptor_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, textureView = texture.view},
		wgpu.BindGroupEntry{binding = 1, sampler = texture.sampler},
	}
	bind_group_descriptor := wgpu.BindGroupDescriptor {
		layout     = rgba_bind_group_layout_cached(device),
		entryCount = uint(len(bind_group_descriptor_entries)),
		entries    = &bind_group_descriptor_entries[0],
	}
	texture.bind_group = wgpu.DeviceCreateBindGroup(device, &bind_group_descriptor)
	return
}


texture_destroy :: proc(texture: ^Texture) {
	wgpu.BindGroupRelease(texture.bind_group)
	wgpu.SamplerRelease(texture.sampler)
	wgpu.TextureViewRelease(texture.view)
	wgpu.TextureRelease(texture.texture)
}


rgba_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
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


rgba_texture_array_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	@(static) layout: wgpu.BindGroupLayout
	if layout == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2DArray,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
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

texture_array_create :: proc(
	device: wgpu.Device,
	size: UVec2,
	layers: u32,
	settings: TextureSettings = TEXTURE_SETTINGS_RGBA,
) -> (
	array: Texture,
) {
	assert(wgpu.TextureUsage.TextureBinding in settings.usage)
	array.info = TextureInfo{size, settings, layers}
	descriptor := wgpu.TextureDescriptor {
		usage = settings.usage,
		dimension = ._2D,
		size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = layers},
		format = settings.format,
		mipLevelCount = 1,
		sampleCount = 1,
		viewFormatCount = 1,
		viewFormats = &array.info.settings.format,
	}
	array.texture = wgpu.DeviceCreateTexture(device, &descriptor)
	texture_view_descriptor := wgpu.TextureViewDescriptor {
		format          = settings.format,
		dimension       = ._2DArray,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = layers,
		aspect          = .All,
	}
	array.view = wgpu.TextureCreateView(array.texture, &texture_view_descriptor)

	sampler_descriptor := wgpu.SamplerDescriptor {
		addressModeU  = settings.address_mode,
		addressModeV  = settings.address_mode,
		addressModeW  = settings.address_mode,
		magFilter     = settings.mag_filter,
		minFilter     = settings.min_filter,
		mipmapFilter  = .Nearest,
		maxAnisotropy = 1,
		// ...
	}
	array.sampler = wgpu.DeviceCreateSampler(device, &sampler_descriptor)

	bind_group_descriptor_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, textureView = array.view},
		wgpu.BindGroupEntry{binding = 1, sampler = array.sampler},
	}
	bind_group_descriptor := wgpu.BindGroupDescriptor {
		layout     = rgba_texture_array_bind_group_layout_cached(device),
		entryCount = uint(len(bind_group_descriptor_entries)),
		entries    = &bind_group_descriptor_entries[0],
	}
	array.bind_group = wgpu.DeviceCreateBindGroup(device, &bind_group_descriptor)
	return
}

texture_array_from_image_paths :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	paths: []string,
	settings: TextureSettings = TEXTURE_SETTINGS_RGBA,
) -> (
	array: Texture,
	error: Error,
) {
	images := make([dynamic]Image)

	width: int
	height: int
	for path, i in paths {
		img := image_load(path) or_return
		if i == 0 {
			width = img.size.x
			height = img.size.y
		} else {
			if img.size.x != width || img.size.y != height {
				error = fmt.aprintf(
					"Image at path %s has size %v but it should be %v",
					path,
					img.size,
					IVec2{width, height},
					allocator = context.temp_allocator,
				)
				return
			}
		}
		append(&images, img)
	}
	array = texture_array_from_images(device, queue, images[:], settings)

	for &img in images {
		image_drop(&img)
	}
	delete(images)
	return
}


texture_array_from_images :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	images: []Image,
	settings: TextureSettings = TEXTURE_SETTINGS_RGBA,
) -> (
	array: Texture,
) {
	assert(len(images) > 0)

	for e in images {
		assert(e.size == images[0].size)
	}
	size := UVec2{u32(images[0].size.x), u32(images[0].size.y)}
	layers := u32(len(images))
	array = texture_array_create(device, size, layers, settings)

	assert(settings.format == IMAGE_FORMAT)
	block_size: u32 = 4
	bytes_per_row :=
		((size.x * block_size + COPY_BYTES_PER_ROW_ALIGNMENT - 1) &
			~(COPY_BYTES_PER_ROW_ALIGNMENT - 1))
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = bytes_per_row,
		rowsPerImage = size.y,
	}
	for img, i in images {
		image_copy := wgpu.ImageCopyTexture {
			texture  = array.texture,
			mipLevel = 0,
			origin   = {0, 0, u32(i)},
			aspect   = .All,
		}
		wgpu.QueueWriteTexture(
			queue,
			&image_copy,
			raw_data(img.pixels),
			uint(len(img.pixels) * 4),
			&data_layout,
			&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
		)
	}
	return
}
