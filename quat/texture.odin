package quat

import "core:fmt"
import "core:image"
import "core:image/png"
import wgpu "vendor:wgpu"

IMAGE_FORMAT :: wgpu.TextureFormat.RGBA8Unorm

TEXTURE_SETTINGS_DEFAULT :: TextureSettings {
	label        = "",
	format       = IMAGE_FORMAT,
	address_mode = .Repeat,
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

texture_from_image_path :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	path: string,
	settings: TextureSettings = TEXTURE_SETTINGS_DEFAULT,
) -> (
	texture: Texture,
	error: image.Error,
) {
	img, img_error := image.load_from_file(path, options = image.Options{.alpha_add_if_missing})
	if img_error != nil {
		error = img_error
		return
	}
	defer {image.destroy(img)}
	texture = texture_from_image(device, queue, img, settings)
	return
}

COPY_BYTES_PER_ROW_ALIGNMENT: u32 : 256 // Buffer-Texture copies must have [`bytes_per_row`] aligned to this number.
texture_from_image :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	img: ^image.Image,
	settings: TextureSettings = TEXTURE_SETTINGS_DEFAULT,
) -> (
	texture: Texture,
) {
	size := UVec2{u32(img.width), u32(img.height)}
	texture = texture_create(device, size, settings)

	if size.x % 64 != 0 {
		panic(
			"Currently only images with at least 64px per row (256 bytes per row) are supported, bc. of https://docs.rs/wgpu/latest/wgpu/struct.ImageDataLayout.html",
		)
	}
	assert(settings.format == IMAGE_FORMAT)
	block_size: u32 = 4
	bytes_per_row :=
		((size.x * block_size + COPY_BYTES_PER_ROW_ALIGNMENT - 1) &
			~(COPY_BYTES_PER_ROW_ALIGNMENT - 1))
	image_copy := texture_as_image_copy(&texture)
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = bytes_per_row,
		rowsPerImage = size.y,
	}
	wgpu.QueueWriteTexture(
		queue,
		&image_copy,
		raw_data(img.pixels.buf),
		uint(len(img.pixels.buf)),
		&data_layout,
		&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
	)
	return
}


texture_as_image_copy :: proc(texture: ^Texture) -> wgpu.ImageCopyTexture {
	return wgpu.ImageCopyTexture {
		texture = texture.texture,
		mipLevel = 0,
		origin = {0, 0, 0},
		aspect = .All,
	}
}

_texture_create_1px_white :: proc(device: wgpu.Device, queue: wgpu.Queue) -> Texture {
	texture := texture_create(device, {1, 1}, TEXTURE_SETTINGS_DEFAULT)
	block_size: u32 = 4
	image_copy := texture_as_image_copy(&texture)
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
	settings: TextureSettings = TEXTURE_SETTINGS_DEFAULT,
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
	settings: TextureSettings = TEXTURE_SETTINGS_DEFAULT,
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
	settings: TextureSettings = TEXTURE_SETTINGS_DEFAULT,
) -> (
	array: Texture,
	error: Error,
) {
	images := make([dynamic]^image.Image)
	defer {delete(images)}
	defer {for img in images {
			image.destroy(img)
		}}
	width: int
	height: int
	for path, i in paths {
		img, img_error := image.load_from_file(
			path,
			options = image.Options{.alpha_add_if_missing},
		)
		if img_error != nil {
			error = tmp_str(img_error)
			return
		}
		if i == 0 {
			width = img.width
			height = img.height
		} else {
			if img.width != width || img.height != height {
				error = fmt.aprintf(
					"Image at path %s has size %d,%d but it should be %d,%d",
					path,
					img.width,
					img.height,
					width,
					height,
					allocator = context.temp_allocator,
				)
				return
			}
		}
		append(&images, img)
	}
	array = texture_array_from_images(device, queue, images[:], settings)
	return
}


texture_array_from_images :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	images: []^image.Image,
	settings: TextureSettings = TEXTURE_SETTINGS_DEFAULT,
) -> (
	array: Texture,
) {
	assert(len(images) > 0)

	width := images[0].width
	height := images[0].height
	for e in images {
		assert(e.width == width)
		assert(e.height == height)
	}
	size := UVec2{u32(width), u32(height)}
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
			raw_data(img.pixels.buf),
			uint(len(img.pixels.buf)),
			&data_layout,
			&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
		)
	}
	return
}
