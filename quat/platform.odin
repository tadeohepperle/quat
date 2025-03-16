package quat

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import glfw "vendor:glfw"
import wgpu "vendor:wgpu"
import wgpu_glfw "vendor:wgpu/glfwglue"

PlatformSettings :: struct {
	title:                    string,
	initial_size:             UVec2,
	clear_color:              Color,
	shaders_dir_path:         string,
	default_font_path:        string,
	power_preference:         wgpu.PowerPreference,
	present_mode:             wgpu.PresentMode,
	hot_reload_shaders:       bool,
	debug_fps_in_title:       bool,
	tonemapping:              TonemappingMode,
	screen_ui_reference_size: Vec2,
	world_ui_px_per_unit:     f32,
}

PLATFORM_SETTINGS_DEFAULT :: PlatformSettings {
	title                    = "Quat App",
	initial_size             = {800, 600},
	clear_color              = ColorBlack,
	shaders_dir_path         = "./shaders",
	default_font_path        = "",
	power_preference         = .LowPower,
	present_mode             = .Fifo,
	tonemapping              = .Disabled,
	debug_fps_in_title       = true,
	hot_reload_shaders       = true,
	screen_ui_reference_size = {1920, 1080},
	world_ui_px_per_unit     = 100,
}

SURFACE_FORMAT := wgpu.TextureFormat.BGRA8UnormSrgb
HDR_FORMAT := wgpu.TextureFormat.RGBA16Float
HDR_SCREEN_TEXTURE_SETTINGS := TextureSettings {
	label        = "hdr_screen_texture",
	format       = HDR_FORMAT,
	address_mode = .ClampToEdge,
	mag_filter   = .Linear,
	min_filter   = .Nearest,
	usage        = {.RenderAttachment, .TextureBinding},
}

Platform :: struct {
	settings:                    PlatformSettings,
	window:                      glfw.WindowHandle,
	// wgpu related fields:
	surface_config:              wgpu.SurfaceConfiguration,
	surface:                     wgpu.Surface,
	instance:                    wgpu.Instance,
	adapter:                     wgpu.Adapter,
	device:                      wgpu.Device,
	queue:                       wgpu.Queue,
	shader_registry:             ShaderRegistry,
	hdr_screen_texture:          Texture,
	depth_screen_texture:        DepthTexture,
	tonemapping_pipeline:        ^RenderPipeline, // owned by ShaderRegistry
	asset_manager:               AssetManager,

	// input related fields:
	total_secs_f64:              f64,
	total_secs:                  f32,
	delta_secs_f64:              f64,
	delta_secs:                  f32,
	screen_size:                 UVec2,
	screen_size_f32:             Vec2,
	ui_layout_extent:            Vec2, // screen size, scaled such that height is always e.g. 1080px
	screen_resized:              bool,
	should_close:                bool,
	old_cursor_pos:              Vec2,
	cursor_pos:                  Vec2,
	cursor_delta:                Vec2,
	keys:                        #sparse[Key]PressFlags,
	mouse_buttons:               [MouseButton]PressFlags,
	chars:                       [16]rune, // 16 should be enough
	chars_len:                   int,
	scroll:                      f32,
	last_left_just_pressed_time: time.Time,
	double_clicked:              bool,
	dropped_file_paths:          []string,

	// globals: 
	globals_xxx:                 Vec4,
	globals_data:                ShaderGlobals,
	globals:                     UniformBuffer(ShaderGlobals),
}


ShaderGlobals :: struct {
	camera_proj_col_1:       Vec3,
	_pad_1:                  f32,
	camera_proj_col_2:       Vec3,
	_pad_2:                  f32,
	camera_proj_col_3:       Vec3,
	_pad_3:                  f32,
	camera_pos:              Vec2,
	camera_height:           f32,
	time_secs:               f32,
	screen_size:             Vec2,
	cursor_pos:              Vec2,
	screen_ui_layout_extent: Vec2,
	world_ui_px_per_unit:    f32,
	_pad_4:                  f32,
	xxx:                     Vec4, // some floats for testing purposes
}
platform_create :: proc(platform: ^Platform, settings: PlatformSettings = PLATFORM_SETTINGS_DEFAULT) {
	platform.settings = settings
	_init_glfw_window(platform)
	_init_wgpu(platform)
	platform.hdr_screen_texture = texture_create(platform.device, platform.screen_size, HDR_SCREEN_TEXTURE_SETTINGS)
	platform.depth_screen_texture = depth_texture_create(platform.device, platform.screen_size)
	platform.shader_registry = shader_registry_create(
		platform.device,
		settings.shaders_dir_path,
		settings.hot_reload_shaders,
	)
	uniform_buffer_create_from_bind_group_layout(
		&platform.globals,
		platform.device,
		globals_bind_group_layout_cached(platform.device),
	)

	platform.tonemapping_pipeline = make_render_pipeline(
		&platform.shader_registry,
		tonemapping_pipeline_config(platform.device),
	)
	asset_manager_create(&platform.asset_manager, settings.default_font_path, platform.device, platform.queue)
}
globals_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	@(static) layout: wgpu.BindGroupLayout
	if layout == nil {
		layout = uniform_bind_group_layout(device, size_of(ShaderGlobals))
	}
	return layout
}


platform_prepare :: proc(platform: ^Platform, camera: Camera) {
	screen_size := platform.screen_size_f32
	camera_proj := camera_projection_matrix(camera, screen_size)
	platform.globals_data = ShaderGlobals {
		camera_proj_col_1       = camera_proj[0],
		camera_proj_col_2       = camera_proj[1],
		camera_proj_col_3       = camera_proj[2],
		camera_pos              = camera.focus_pos,
		camera_height           = camera.height,
		time_secs               = platform.total_secs,
		screen_size             = screen_size,
		cursor_pos              = platform.cursor_pos,
		screen_ui_layout_extent = platform.ui_layout_extent,
		world_ui_px_per_unit    = platform.settings.world_ui_px_per_unit,
		xxx                     = platform.globals_xxx,
	}
	uniform_buffer_write(platform.queue, &platform.globals, &platform.globals_data)
	asset_manager_update_changed_font_atlas_textures(&platform.asset_manager)
}

platform_destroy :: proc(platform: ^Platform) {
	uniform_buffer_destroy(&platform.globals)
	asset_manager_destroy(&platform.asset_manager)
	shader_registry_destroy(&platform.shader_registry)
	texture_destroy(&platform.hdr_screen_texture)
	texture_destroy(&platform.depth_screen_texture)
	wgpu.QueueRelease(platform.queue)
	wgpu.DeviceDestroy(platform.device)
	wgpu.InstanceRelease(platform.instance)
}


// returns false if should be shut down
platform_start_frame :: proc(platform: ^Platform) -> bool {
	if platform.should_close {
		return false
	}

	time := glfw.GetTime()
	glfw.PollEvents()

	total_secs_before_f64 := platform.total_secs_f64
	platform.total_secs_f64 = time
	platform.total_secs = f32(time)
	platform.delta_secs_f64 = platform.total_secs_f64 - total_secs_before_f64
	platform.delta_secs = f32(platform.delta_secs_f64)

	if glfw.WindowShouldClose(platform.window) || .JustPressed in platform.keys[.ESCAPE] {
		return false
	}

	if platform.settings.hot_reload_shaders {
		shader_registry_hot_reload(&platform.shader_registry)
	}

	if platform.settings.debug_fps_in_title {
		dt_ms := platform.delta_secs * 1000
		fps := int(1.0 / platform.delta_secs)
		title := fmt.caprintf("%d fps/ %.2f ms", fps, dt_ms, allocator = context.temp_allocator)
		glfw.SetWindowTitle(platform.window, title)
	}
	_recalculate_ui_layout_extent(platform)

	return true
}

_recalculate_ui_layout_extent :: proc "contextless" (platform: ^Platform) {
	ref_size := platform.settings.screen_ui_reference_size
	screen_aspect := (platform.screen_size_f32.x / platform.screen_size_f32.y)
	platform.ui_layout_extent = Vec2{ref_size.y * screen_aspect, ref_size.y}
}

platform_end_render :: proc(
	platform: ^Platform,
	surface_texture: wgpu.SurfaceTexture,
	surface_view: wgpu.TextureView,
	command_encoder: wgpu.CommandEncoder,
) {
	tonemap(
		command_encoder,
		platform.tonemapping_pipeline.pipeline,
		platform.hdr_screen_texture.bind_group,
		surface_view,
		platform.settings.tonemapping,
	)
	// /////////////////////////////////////////////////////////////////////////////
	// SECTION: Present
	// /////////////////////////////////////////////////////////////////////////////

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	wgpu.CommandEncoderRelease(command_encoder)
	wgpu.QueueSubmit(platform.queue, {command_buffer})
	wgpu.SurfacePresent(platform.surface)
	// cleanup:
	wgpu.TextureRelease(surface_texture.texture)
	wgpu.TextureViewRelease(surface_view)
	wgpu.CommandBufferRelease(command_buffer)
}

platform_start_hdr_pass :: proc(platform: Platform, command_encoder: wgpu.CommandEncoder) -> wgpu.RenderPassEncoder {
	hdr_pass := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&wgpu.RenderPassDescriptor {
			label = "surface render pass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = platform.hdr_screen_texture.view,
				resolveTarget = nil,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = color_to_wgpu(platform.settings.clear_color),
			},
			occlusionQuerySet = nil,
			depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment {
				view = platform.depth_screen_texture.view,
				depthLoadOp = .Clear,
				depthStoreOp = .Store,
				depthClearValue = 0.0,
			},
			timestampWrites = nil,
		},
	)
	return hdr_pass
}

platform_start_render :: proc(
	platform: ^Platform,
) -> (
	surface_texture: wgpu.SurfaceTexture,
	surface_view: wgpu.TextureView,
	command_encoder: wgpu.CommandEncoder,
) {
	surface_texture = wgpu.SurfaceGetCurrentTexture(platform.surface)

	switch surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	// All good, could check for `surface_texture.suboptimal` here.
	case .Timeout, .Outdated, .Lost:
		// Skip this frame, and re-configure surface.
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}
		platform_resize(platform)
		surface_texture = wgpu.SurfaceGetCurrentTexture(platform.surface)
		assert(surface_texture.status == .SuccessOptimal || surface_texture.status == .SuccessSuboptimal)
	case .OutOfMemory, .DeviceLost, .Error:
		// Fatal error
		fmt.panicf("Fatal error in wgpu.SurfaceGetCurrentTexture, status=", surface_texture.status)
	}
	surface_view = wgpu.TextureCreateView(
		surface_texture.texture,
		&wgpu.TextureViewDescriptor {
			label = "surface view",
			format = SURFACE_FORMAT,
			dimension = ._2D,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = 1,
			aspect = wgpu.TextureAspect.All,
		},
	)
	command_encoder = wgpu.DeviceCreateCommandEncoder(platform.device, nil)
	return surface_texture, surface_view, command_encoder
}

// platform
platform_reset_input_at_end_of_frame :: proc(platform: ^Platform) {
	platform.scroll = 0
	platform.chars_len = 0
	platform.cursor_delta = 0
	platform.double_clicked = false
	for key in Key {
		state := &platform.keys[key]
		if .Pressed in state {
			state^ = {.Pressed}
		} else {
			state^ = {}
		}
	}
	for &btn in platform.mouse_buttons {
		if .Pressed in btn {
			btn = {.Pressed}
		} else {
			btn = {}
		}
	}
	_clear_file_paths(&platform.dropped_file_paths)
}
_clear_file_paths :: proc(paths: ^[]string) {
	if len(paths) > 0 {
		for path in paths {
			delete(path)
		}
		delete(paths^)
	}
	paths^ = nil
}

platform_resize :: proc(platform: ^Platform) {
	platform.screen_resized = false
	platform.surface_config.width = platform.screen_size.x
	platform.surface_config.height = platform.screen_size.y
	wgpu.SurfaceConfigure(platform.surface, &platform.surface_config)
	texture_destroy(&platform.hdr_screen_texture)
	texture_destroy(&platform.depth_screen_texture)
	platform.hdr_screen_texture = texture_create(platform.device, platform.screen_size, HDR_SCREEN_TEXTURE_SETTINGS)
	platform.depth_screen_texture = depth_texture_create(platform.device, platform.screen_size)
}

_platform_receive_glfw_char_event :: proc(platform: ^Platform, char: rune) {
	if platform.chars_len < len(platform.chars) {
		platform.chars[platform.chars_len] = char
		platform.chars_len += 1
	} else {
		print("Warning: a character has been dropped:", char)
	}
}


_platform_receive_glfw_key_event :: proc "contextless" (platform: ^Platform, glfw_key, action: i32) {
	switch key in glfw_int_to_key(glfw_key) {
	case Key:
		switch action {
		case glfw.PRESS:
			platform.keys[key] = {.JustPressed, .Pressed}
		case glfw.REPEAT:
			platform.keys[key] = {.JustRepeated, .Pressed}
		case glfw.RELEASE:
			platform.keys[key] = {.JustReleased}
		}
	}
}

_platform_receive_glfw_mouse_btn_event :: proc "contextless" (platform: ^Platform, glfw_button, action: i32) {
	switch button in glfw_int_to_mouse_button(glfw_button) {
	case MouseButton:
		switch action {
		case glfw.PRESS:
			platform.mouse_buttons[button] = {.JustPressed, .Pressed}
			if button == .Left {
				now := time.now()
				if time.diff(platform.last_left_just_pressed_time, now) <
				   DOUBLE_CLICK_MAX_INTERVAL_MS * time.Millisecond {
					platform.double_clicked = true
				}
				platform.last_left_just_pressed_time = now
			}
		case glfw.REPEAT:
			platform.mouse_buttons[button] = {.JustRepeated, .Pressed}
		case glfw.RELEASE:
			platform.mouse_buttons[button] = {.JustReleased}
		}
	}
}

_init_glfw_window :: proc(platform: ^Platform) {
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 1)
	platform.window = glfw.CreateWindow(
		i32(platform.settings.initial_size.x),
		i32(platform.settings.initial_size.y),
		strings.clone_to_cstring(platform.settings.title),
		nil,
		nil,
	)
	platform.window = platform.window
	w, h := glfw.GetFramebufferSize(platform.window)
	platform.screen_size = {u32(w), u32(h)}
	platform.screen_size_f32 = {f32(w), f32(h)}
	glfw.SetWindowUserPointer(platform.window, platform)

	framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, w, h: i32) {
		platform: ^Platform = auto_cast glfw.GetWindowUserPointer(window)
		platform.screen_resized = true
		platform.screen_size = {u32(w), u32(h)}
		platform.screen_size_f32 = {f32(w), f32(h)}
		_recalculate_ui_layout_extent(platform)
	}
	glfw.SetFramebufferSizeCallback(platform.window, framebuffer_size_callback)

	key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, _mods: i32) {
		platform: ^Platform = auto_cast glfw.GetWindowUserPointer(window)
		_platform_receive_glfw_key_event(platform, key, action)
	}
	glfw.SetKeyCallback(platform.window, key_callback)

	char_callback :: proc "c" (window: glfw.WindowHandle, char: rune) {
		context = runtime.default_context()
		platform: ^Platform = auto_cast glfw.GetWindowUserPointer(window)
		_platform_receive_glfw_char_event(platform, char)
	}
	glfw.SetCharCallback(platform.window, char_callback)

	cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, x_pos, y_pos: f64) {
		platform: ^Platform = auto_cast glfw.GetWindowUserPointer(window)

		new_cursor_pos := Vec2{f32(x_pos), f32(y_pos)}
		platform.cursor_delta += new_cursor_pos - platform.cursor_pos
		platform.cursor_pos = new_cursor_pos
	}
	glfw.SetCursorPosCallback(platform.window, cursor_pos_callback)

	scroll_callback :: proc "c" (window: glfw.WindowHandle, x_offset, y_offset: f64) {
		platform: ^Platform = auto_cast glfw.GetWindowUserPointer(window)
		platform.scroll = f32(y_offset)
	}
	glfw.SetScrollCallback(platform.window, scroll_callback)

	mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, _mods: i32) {
		platform: ^Platform = auto_cast glfw.GetWindowUserPointer(window)
		_platform_receive_glfw_mouse_btn_event(platform, button, action)
	}
	glfw.SetMouseButtonCallback(platform.window, mouse_button_callback)

	drop_callback :: proc "c" (window: glfw.WindowHandle, count: i32, paths: [^]cstring) {
		context = runtime.default_context()
		platform: ^Platform = auto_cast glfw.GetWindowUserPointer(window)
		_clear_file_paths(&platform.dropped_file_paths)
		platform.dropped_file_paths = make([]string, int(count))
		for i in 0 ..< count {
			platform.dropped_file_paths[i] = strings.clone_from_cstring(paths[i])
		}
	}
	glfw.SetDropCallback(platform.window, drop_callback)
}

_init_wgpu :: proc(platform: ^Platform) {
	instance_extras := wgpu.InstanceExtras {
		chain = {next = nil, sType = wgpu.SType.InstanceExtras},
		backends = wgpu.InstanceBackendFlags_All,
	}
	platform.instance = wgpu.CreateInstance(&wgpu.InstanceDescriptor{nextInChain = &instance_extras.chain})
	platform.surface = wgpu_glfw.GetSurface(platform.instance, platform.window)

	AwaitStatus :: enum {
		Awaiting,
		Success,
		Error,
	}

	AdapterResponse :: struct {
		adapter: wgpu.Adapter,
		status:  wgpu.RequestAdapterStatus,
		message: string,
	}
	adapter_res: AdapterResponse
	adapter_future := wgpu.InstanceRequestAdapter(
		platform.instance,
		&wgpu.RequestAdapterOptions {
			powerPreference = platform.settings.power_preference,
			compatibleSurface = platform.surface,
		},
		wgpu.RequestAdapterCallbackInfo{callback = on_adapter, userdata1 = &adapter_res},
	)
	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		adapter_res := cast(^AdapterResponse)userdata1
		adapter_res.status = status
		adapter_res.adapter = adapter
		adapter_res.message = message
	}

	if adapter_res.status != .Success {
		panic(tprint("Failed to get wgpu adapter: %s", adapter_res.message))
	}
	assert(adapter_res.adapter != nil)
	platform.adapter = adapter_res.adapter
	DeviceRes :: struct {
		status:  wgpu.RequestDeviceStatus,
		device:  wgpu.Device,
		message: string,
	}
	device_res: DeviceRes

	required_features := [?]wgpu.FeatureName{.PushConstants, .TimestampQuery, .TextureFormat16bitNorm}
	required_limits_extras := wgpu.NativeLimits {
		chain = {sType = .NativeLimits},
		maxPushConstantSize = 128,
		maxNonSamplerBindings = 1_000_000,
	}
	required_limits := WGPU_DEFAULT_LIMITS
	required_limits.nextInChain = &required_limits_extras
	wgpu.AdapterRequestDevice(
		platform.adapter,
		&wgpu.DeviceDescriptor {
			requiredFeatureCount = uint(len(required_features)),
			requiredFeatures = &required_features[0],
			requiredLimits = &required_limits,
		},
		wgpu.RequestDeviceCallbackInfo{callback = on_device, userdata1 = &device_res},
	)

	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		context = runtime.default_context()
		if status != .Success {
			print("AdapterRequestDevice Error: ", message)
		}
		device_res := cast(^DeviceRes)userdata1
		device_res.status = status
		device_res.device = device
		device_res.message = message
	}
	if device_res.status != .Success {
		fmt.panicf("Failed to get wgpu device: %s", device_res.message)
	}
	assert(device_res.device != nil)
	platform.device = device_res.device

	platform.queue = wgpu.DeviceGetQueue(platform.device)
	assert(platform.queue != nil)

	platform.surface_config = wgpu.SurfaceConfiguration {
		device          = platform.device,
		format          = SURFACE_FORMAT,
		usage           = {.RenderAttachment},
		viewFormatCount = 1,
		viewFormats     = &SURFACE_FORMAT,
		alphaMode       = .Opaque,
		width           = platform.screen_size.x,
		height          = platform.screen_size.y,
		presentMode     = platform.settings.present_mode,
	}

	// wgpu_error_callback :: proc "c" (type: wgpu.ErrorType, message: cstring, userdata: rawptr) {
	// 	context = runtime.default_context()
	// 	print("-----------------------------")
	// 	print("ERROR CAUGHT: ", type, message)
	// 	print("-----------------------------")
	// }
	// wgpu.DeviceSetUncapturedErrorCallback(platform.device, wgpu_error_callback, nil)

	wgpu.SurfaceConfigure(platform.surface, &platform.surface_config)
}


platform_set_clipboard :: proc(platform: ^Platform, str: string) {
	builder := strings.builder_make(allocator = context.temp_allocator)
	strings.write_string(&builder, str)
	c_str, err := strings.to_cstring(&builder)
	assert(err == .None)
	glfw.SetClipboardString(platform.window, c_str)
}
platform_get_clipboard :: proc(platform: ^Platform) -> string {
	return glfw.GetClipboardString(platform.window)
}
platform_just_pressed_or_repeated :: proc(platform: ^Platform, key: Key) -> bool {
	return PressFlags{.JustPressed, .JustRepeated} & platform.keys[key] != PressFlags{}
}
platform_just_pressed :: proc(platform: ^Platform, key: Key) -> bool {
	return .JustPressed in platform.keys[key]
}
platform_is_pressed :: proc(platform: ^Platform, key: Key) -> bool {
	return .Pressed in platform.keys[key]
}
platform_maximize :: proc(platform: ^Platform) {
	glfw.MaximizeWindow(platform.window)
}
