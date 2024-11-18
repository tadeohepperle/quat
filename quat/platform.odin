package quat

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import glfw "vendor:glfw"
import wgpu "vendor:wgpu"
import wgpu_glfw "vendor:wgpu/glfwglue"

PlatformSettings :: struct {
	title:              string,
	initial_size:       UVec2,
	clear_color:        Color,
	shaders_dir_path:   string,
	default_font_path:  string,
	power_preference:   wgpu.PowerPreference,
	present_mode:       wgpu.PresentMode,
	hot_reload_shaders: bool,
	debug_fps_in_title: bool,
	tonemapping:        TonemappingMode,
}

PLATFORM_SETTINGS_DEFAULT :: PlatformSettings {
	title              = "Dplatform",
	initial_size       = {800, 600},
	clear_color        = Color_Dark_Gray,
	shaders_dir_path   = "./shaders",
	default_font_path  = "./assets/marko_one_regular",
	power_preference   = .LowPower,
	present_mode       = .Fifo,
	tonemapping        = .Disabled,
	debug_fps_in_title = true,
	hot_reload_shaders = true,
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
	settings:                     PlatformSettings,
	window:                       glfw.WindowHandle,
	// wgpu related fields:
	surface_config:               wgpu.SurfaceConfiguration,
	surface:                      wgpu.Surface,
	instance:                     wgpu.Instance,
	adapter:                      wgpu.Adapter,
	device:                       wgpu.Device,
	queue:                        wgpu.Queue,
	shader_registry:              ShaderRegistry,
	hdr_screen_texture:           Texture,
	tonemapping_pipeline:         RenderPipeline,
	asset_manager:                AssetManager,

	// input related fields:
	total_secs:                   f32,
	delta_secs:                   f32,
	screen_size:                  UVec2,
	screen_size_f32:              Vec2,
	screen_resized:               bool,
	should_close:                 bool,
	old_cursor_pos:               Vec2,
	cursor_pos:                   Vec2,
	cursor_delta:                 Vec2,
	keys:                         #sparse[Key]PressFlags,
	mouse_buttons:                [MouseButton]PressFlags,
	chars:                        [16]rune, // 16 should be enough
	chars_len:                    int,
	scroll:                       f32,
	last_left_just_released_time: time.Time,
	double_clicked:               bool,

	// globals: 
	globals_data:                 ShaderGlobals,
	globals:                      UniformBuffer(ShaderGlobals),
}

ShaderGlobals :: struct {
	camera_proj_col_1: Vec3,
	_pad_1:            f32,
	camera_proj_col_2: Vec3,
	_pad_2:            f32,
	camera_proj_col_3: Vec3,
	_pad_3:            f32,
	camera_pos:        Vec2,
	screen_size:       Vec2,
	cursor_pos:        Vec2,
	time_secs:         f32,
	_last_pad:         f32,
}
platform_create :: proc(
	platform: ^Platform,
	settings: PlatformSettings = PLATFORM_SETTINGS_DEFAULT,
) {
	platform.settings = settings
	_init_glfw_window(platform)
	_init_wgpu(platform)
	platform.hdr_screen_texture = texture_create(
		platform.device,
		platform.screen_size,
		HDR_SCREEN_TEXTURE_SETTINGS,
	)
	platform.shader_registry = shader_registry_create(platform.device, settings.shaders_dir_path)
	uniform_buffer_create(&platform.globals, platform.device)
	platform.tonemapping_pipeline.config = tonemapping_pipeline_config(platform.device)
	render_pipeline_create_panic(&platform.tonemapping_pipeline, &platform.shader_registry)
	asset_manager_create(
		&platform.asset_manager,
		settings.default_font_path,
		platform.device,
		platform.queue,
	)
}

platform_prepare :: proc(platform: ^Platform, camera: Camera) {
	screen_size := platform.screen_size_f32
	camera_raw := camera_to_raw(camera, screen_size)
	platform.globals_data = ShaderGlobals {
		camera_proj_col_1 = camera_raw.proj[0],
		camera_proj_col_2 = camera_raw.proj[1],
		camera_proj_col_3 = camera_raw.proj[2],
		camera_pos        = camera_raw.pos,
		screen_size       = screen_size,
		cursor_pos        = platform.cursor_pos,
		time_secs         = platform.total_secs,
	}
	uniform_buffer_write(platform.queue, &platform.globals, &platform.globals_data)
}

platform_destroy :: proc(platform: ^Platform) {
	uniform_buffer_destroy(&platform.globals)
	render_pipeline_destroy(&platform.tonemapping_pipeline)
	asset_manager_destroy(&platform.asset_manager)
	shader_registry_destroy(&platform.shader_registry)
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

	total_secs_before := platform.total_secs
	platform.total_secs = f32(time)
	platform.delta_secs = platform.total_secs - total_secs_before

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


	return true
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
	wgpu.QueueSubmit(platform.queue, {command_buffer})
	wgpu.SurfacePresent(platform.surface)
	// cleanup:
	wgpu.TextureRelease(surface_texture.texture)
	wgpu.TextureViewRelease(surface_view)
	wgpu.CommandBufferRelease(command_buffer)
}

platform_start_hdr_pass :: proc(
	platform: Platform,
	command_encoder: wgpu.CommandEncoder,
) -> wgpu.RenderPassEncoder {
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
			depthStencilAttachment = nil,
			occlusionQuerySet = nil,
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
	case .Success:
	// All good, could check for `surface_texture.suboptimal` here.
	case .Timeout, .Outdated, .Lost:
		// Skip this frame, and re-configure surface.
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}
		platform_resize(platform)
		surface_texture = wgpu.SurfaceGetCurrentTexture(platform.surface)
		assert(surface_texture.status == .Success)
	case .OutOfMemory, .DeviceLost:
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
}

platform_resize :: proc(platform: ^Platform) {
	platform.screen_resized = false
	platform.surface_config.width = platform.screen_size.x
	platform.surface_config.height = platform.screen_size.y
	wgpu.SurfaceConfigure(platform.surface, &platform.surface_config)
	texture_destroy(&platform.hdr_screen_texture)
	platform.hdr_screen_texture = texture_create(
		platform.device,
		platform.screen_size,
		HDR_SCREEN_TEXTURE_SETTINGS,
	)
}

_platform_receive_glfw_char_event :: proc(platform: ^Platform, char: rune) {
	if platform.chars_len < len(platform.chars) {
		platform.chars[platform.chars_len] = char
		platform.chars_len += 1
	} else {
		print("Warning: a character has been dropped:", char)
	}
}


_platform_receive_glfw_key_event :: proc "contextless" (
	platform: ^Platform,
	glfw_key, action: i32,
) {
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

_platform_receive_glfw_mouse_btn_event :: proc "contextless" (
	platform: ^Platform,
	glfw_button, action: i32,
) {
	switch button in glfw_int_to_mouse_button(glfw_button) {
	case MouseButton:
		switch action {
		case glfw.PRESS:
			platform.mouse_buttons[button] = {.JustPressed, .Pressed}
		case glfw.REPEAT:
			platform.mouse_buttons[button] = {.JustRepeated, .Pressed}
		case glfw.RELEASE:
			platform.mouse_buttons[button] = {.JustReleased}
			if button == .Left {
				now := time.now()
				if time.diff(platform.last_left_just_released_time, now) <
				   DOUBLE_CLICK_MAX_INTERVAL_MS * time.Millisecond {
					platform.double_clicked = true
				}
				platform.last_left_just_released_time = now
			}
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
}

_init_wgpu :: proc(platform: ^Platform) {
	instance_extras := wgpu.InstanceExtras {
		chain = {next = nil, sType = wgpu.SType.InstanceExtras},
		backends = wgpu.InstanceBackendFlags_All,
	}
	platform.instance = wgpu.CreateInstance(
		&wgpu.InstanceDescriptor{nextInChain = &instance_extras.chain},
	)
	platform.surface = wgpu_glfw.GetSurface(platform.instance, platform.window)

	AwaitStatus :: enum {
		Awaiting,
		Success,
		Error,
	}

	AdapterResponse :: struct {
		adapter: wgpu.Adapter,
		status:  wgpu.RequestAdapterStatus,
		message: cstring,
	}
	adapter_res: AdapterResponse
	wgpu.InstanceRequestAdapter(
		platform.instance,
		&wgpu.RequestAdapterOptions {
			powerPreference = platform.settings.power_preference,
			compatibleSurface = platform.surface,
		},
		proc "c" (
			status: wgpu.RequestAdapterStatus,
			adapter: wgpu.Adapter,
			message: cstring,
			userdata: rawptr,
		) {
			adapter_res: ^AdapterResponse = auto_cast userdata
			adapter_res.status = status
			adapter_res.adapter = adapter
			adapter_res.message = message
		},
		&adapter_res,
	)
	if adapter_res.status != .Success {
		panic(tmp_str("Failed to get wgpu adapter: %s", adapter_res.message))
	}
	assert(adapter_res.adapter != nil)
	platform.adapter = adapter_res.adapter

	print("Created adapter successfully")


	DeviceRes :: struct {
		status:  wgpu.RequestDeviceStatus,
		device:  wgpu.Device,
		message: cstring,
	}
	device_res: DeviceRes


	required_features := [?]wgpu.FeatureName{.PushConstants, .TimestampQuery}
	required_limits_extras := wgpu.RequiredLimitsExtras {
		chain = {sType = .RequiredLimitsExtras},
		limits = wgpu.NativeLimits{maxPushConstantSize = 128, maxNonSamplerBindings = 1_000_000},
	}
	required_limits := wgpu.RequiredLimits {
		nextInChain = &required_limits_extras.chain,
		limits      = WGPU_DEFAULT_LIMITS,
	}
	wgpu.AdapterRequestDevice(
		platform.adapter,
		&wgpu.DeviceDescriptor {
			requiredFeatureCount = uint(len(required_features)),
			requiredFeatures = &required_features[0],
			requiredLimits = &required_limits,
		},
		proc "c" (
			status: wgpu.RequestDeviceStatus,
			device: wgpu.Device,
			message: cstring,
			userdata: rawptr,
		) {
			context = runtime.default_context()
			print("Err: ", message)
			device_res: ^DeviceRes = auto_cast userdata
			device_res.status = status
			device_res.device = device
			device_res.message = message
		},
		&device_res,
	)
	if device_res.status != .Success {
		fmt.panicf("Failed to get wgpu device: %s", device_res.message)
	}
	assert(device_res.device != nil)
	platform.device = device_res.device
	print("Created device successfully")

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
	glfw.SetClipboardString(platform.window, strings.to_cstring(&builder))
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
