package quat

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:os"
import "core:strings"
import "core:time"
import glfw "vendor:glfw"
import wgpu "vendor:wgpu"
import wgpu_glfw "vendor:wgpu/glfwglue"


is_initialized :: proc() -> bool {
	return PLATFORM.is_initialized
}
platform_init :: proc(settings: PlatformSettings = PLATFORM_SETTINGS_DEFAULT) {
	_init_platform(&PLATFORM, settings)
}
platform_deinit :: proc() {
	print("MotionTexture  map before drop", assets_get_map(MotionTexture))
	assets_drop(&PLATFORM.assets)
	shader_registry_destroy(&PLATFORM.shader_registry)
	texture_destroy(&PLATFORM.hdr_screen_texture)
	texture_destroy(&PLATFORM.depth_screen_texture)

	cached_bind_group_layouts := []wgpu.BindGroupLayout {
		DIFFUSE_AND_MOTION_TEXTURE_BIND_GROUP_LAYOUT,
		SHADER_GLOBALS_BIND_GROUP_LAYOUT,
		TRITEX_TEXTURES_BIND_GROUP_LAYOUT,
		DEPTH_TEXTURE_BIND_GROUP_LAYOUT,
		RGBA_TEXTURE_ARRAY_BIND_GROUP_LAYOUT,
		BONES_STORAGE_BUFFER_BIND_GROUP_LAYOUT,
		HEX_CHUNK_DATA_BIND_GROUP_LAYOUT,
	}
	for layout in cached_bind_group_layouts {
		if layout != nil do wgpu.BindGroupLayoutRelease(layout)
	}


	if PLATFORM._surface_texture.texture != nil {
		wgpu.TextureRelease(PLATFORM._surface_texture.texture)
	}
	wgpu.SurfaceRelease(PLATFORM.surface)
	wgpu.QueueRelease(PLATFORM.queue)

	wgpu.DeviceDestroy(PLATFORM.device)
	wgpu.DeviceRelease(PLATFORM.device)

	wgpu.AdapterRelease(PLATFORM.adapter)
	wgpu.InstanceRelease(PLATFORM.instance)

	glfw.DestroyWindow(PLATFORM.window)
	glfw.Terminate()
}

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
}

PLATFORM_SETTINGS_DEFAULT :: PlatformSettings {
	title              = "Quat App",
	initial_size       = {800, 600},
	clear_color        = ColorBlack,
	shaders_dir_path   = "./shaders",
	default_font_path  = "",
	power_preference   = .LowPower,
	present_mode       = .Fifo,
	debug_fps_in_title = true,
	hot_reload_shaders = true,
}
@(private = "file")
DEFAULT_FONT_TTF := #load("../assets/Lora-Medium.ttf")

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

// The platform is some global thing that NEEDS to be initialized for the rest of the codebase to work.
// Earlier we used dependency injection everywhere, passing e.g. the shader registry, the queue, the device, etc around.
// But it is much more useful to have just one singleton PLATFORM memory location and work with that.
PLATFORM: Platform
Platform :: struct {
	is_initialized:              bool,
	settings:                    PlatformSettings,
	window:                      glfw.WindowHandle,
	// wgpu related fields:
	surface_config:              wgpu.SurfaceConfiguration,
	surface:                     wgpu.Surface,
	instance:                    wgpu.Instance,
	adapter:                     wgpu.Adapter,
	device:                      wgpu.Device,
	queue:                       wgpu.Queue,
	assets:                      Assets,
	shader_registry:             ShaderRegistry,
	hdr_screen_texture:          Texture,
	depth_screen_texture:        DepthTexture,
	_surface_texture:            wgpu.SurfaceTexture, // a little hacky... acquired before input polling and stored here at start of frame to avoid V-Sync latency.
	// tonemapping_pipeline:        ^RenderPipeline, // owned by ShaderRegistry

	// input related fields:
	total_secs_f64:              f64,
	total_secs:                  f32,
	delta_secs_f64:              f64,
	delta_secs:                  f32,
	screen_size:                 UVec2,
	screen_size_f32:             Vec2,
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
shader_globals_set_camera_2d :: proc(globals: ^ShaderGlobals, camera: Camera2D, screen_size: Vec2) {
	camera_proj := camera_projection_matrix(camera, screen_size)
	globals.camera_proj_col_1 = camera_proj[0]
	globals.camera_proj_col_2 = camera_proj[1]
	globals.camera_proj_col_3 = camera_proj[2]
	globals.camera_pos = camera.focus_pos
	globals.camera_height = camera.height
	globals.screen_size = screen_size
}

// this is honestly a bit stupid:
_init_platform :: proc(platform: ^Platform, settings: PlatformSettings = PLATFORM_SETTINGS_DEFAULT) {
	assert(platform == &PLATFORM)
	platform^ = {}
	platform.settings = settings

	// /////////////////////////////////////////////////////////////////////////////
	// Setup window and wgpu

	_init_glfw_window(platform)
	_init_wgpu(platform)

	// /////////////////////////////////////////////////////////////////////////////
	// Setup Assets (Default 1px white Texture + Default Font)

	platform.assets = Assets{}

	assets_register_drop_fn(Texture, texture_destroy)
	assets_register_drop_fn(Font, font_destroy)
	assets_register_drop_fn(MotionTexture, motion_texture_destroy)
	assets_register_drop_fn(SkinnedGeometry, skinned_mesh_geometry_drop)
	assets_register_drop_fn(SkinnedMesh, skinned_mesh_drop)

	default_texture_handle := assets_insert(_texture_create_1px_white())
	assert(DEFAULT_TEXTURE == default_texture_handle)

	default_font: Font
	font_err: Error
	if settings.default_font_path == "" {
		default_font, font_err = font_from_bytes(DEFAULT_FONT_TTF, "LuxuriousRoman")
	} else {
		default_font, font_err = font_from_path(settings.default_font_path)
	}
	default_font_handle := assets_insert(default_font)
	assert(DEFAULT_FONT == default_font_handle)

	default_motion_texture_handle := assets_insert(_motion_texture_create_1px_white())
	assert(DEFAULT_MOTION_TEXTURE == default_motion_texture_handle)

	// /////////////////////////////////////////////////////////////////////////////
	// Setup hdr screen texture, depth texture shader registery

	platform.hdr_screen_texture = texture_create(platform.screen_size, HDR_SCREEN_TEXTURE_SETTINGS)
	platform.depth_screen_texture = depth_texture_create(platform.screen_size)
	platform.shader_registry = shader_registry_create(
		platform.device,
		settings.shaders_dir_path,
		settings.hot_reload_shaders,
	)
	platform.is_initialized = true
}


SHADER_GLOBALS_BIND_GROUP_LAYOUT: wgpu.BindGroupLayout
shader_globals_bind_group_layout_cached :: proc() -> wgpu.BindGroupLayout {
	if SHADER_GLOBALS_BIND_GROUP_LAYOUT == nil {
		SHADER_GLOBALS_BIND_GROUP_LAYOUT = uniform_bind_group_layout(size_of(ShaderGlobals))
	}
	return SHADER_GLOBALS_BIND_GROUP_LAYOUT
}
platform_prepare :: proc() {
	// screen_size := PLATFORM.screen_size_f32
	// camera_proj := camera_projection_matrix(camera, screen_size)
	// PLATFORM.globals_data = ShaderGlobals {
	// 	camera_proj_col_1 = camera_proj[0],
	// 	camera_proj_col_2 = camera_proj[1],
	// 	camera_proj_col_3 = camera_proj[2],
	// 	camera_pos        = camera.focus_pos,
	// 	camera_height     = camera.height,
	// 	time_secs         = PLATFORM.total_secs,
	// 	screen_size       = screen_size,
	// 	cursor_pos        = PLATFORM.cursor_pos,
	// 	xxx               = PLATFORM.globals_xxx,
	// }
	// uniform_buffer_write(PLATFORM.queue, &PLATFORM.globals, &PLATFORM.globals_data)
	update_changed_font_atlas_textures(PLATFORM.queue)
	if PLATFORM.screen_resized {
		_platform_resize_frame_buffer()
	}
}


// returns false if should be shut down
platform_start_frame :: proc() -> (should_keep_running: bool) {
	platform := &PLATFORM
	if platform.should_close {
		return false
	}

	// IMPORTANT! do this before polling events! Otherwise big vsync delay on all input
	_acquire_surface_texture(platform)

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

	return true
}

platform_end_render :: proc(surface_view: wgpu.TextureView, command_encoder: wgpu.CommandEncoder) {
	// tonemap(
	// 	command_encoder,
	// 	PLATFORM.tonemapping_pipeline.pipeline,
	// 	PLATFORM.hdr_screen_texture.bind_group,
	// 	surface_view,
	// 	PLATFORM.settings.tonemapping,
	// )
	// /////////////////////////////////////////////////////////////////////////////
	// SECTION: Present
	// /////////////////////////////////////////////////////////////////////////////

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	wgpu.CommandEncoderRelease(command_encoder)
	wgpu.QueueSubmit(PLATFORM.queue, {command_buffer})
	wgpu.SurfacePresent(PLATFORM.surface)
	// cleanup:
	wgpu.TextureViewRelease(surface_view)
	wgpu.CommandBufferRelease(command_buffer)

	PLATFORM.screen_resized = false
}

start_hdr_render_pass :: proc(
	command_encoder: wgpu.CommandEncoder,
	hdr_screen_texture: Texture,
	depth_screen_texture: Texture,
	clear_color: Color,
) -> wgpu.RenderPassEncoder {
	hdr_pass := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&wgpu.RenderPassDescriptor {
			label = "surface render pass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = hdr_screen_texture.view,
				resolveTarget = nil,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = color_to_wgpu(clear_color),
			},
			occlusionQuerySet = nil,
			depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment {
				view = depth_screen_texture.view,
				depthLoadOp = .Clear,
				depthStoreOp = .Store,
				depthClearValue = 0.0,
			},
			timestampWrites = nil,
		},
	)
	return hdr_pass
}

// WARNING: MAY BLOCK ON V_SYNC!!!!
_acquire_surface_texture :: proc(platform: ^Platform) {
	if platform._surface_texture.texture != nil {
		wgpu.TextureRelease(platform._surface_texture.texture)
	}
	platform._surface_texture = wgpu.SurfaceGetCurrentTexture(platform.surface)
	switch platform._surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	// All good, could check for `surface_texture.suboptimal` here.
	case .Timeout, .Outdated, .Lost:
		// Skip this frame, and re-configure surface.
		_platform_resize_frame_buffer()
		platform._surface_texture = wgpu.SurfaceGetCurrentTexture(platform.surface)
		assert(
			platform._surface_texture.status == .SuccessOptimal ||
			platform._surface_texture.status == .SuccessSuboptimal,
		)
	case .OutOfMemory, .DeviceLost, .Error:
		// Fatal error
		fmt.panicf("Fatal error in wgpu.SurfaceGetCurrentTexture, status=", platform._surface_texture.status)
	}
}

platform_start_render :: proc() -> (surface_view: wgpu.TextureView, command_encoder: wgpu.CommandEncoder) {
	surface_view = wgpu.TextureCreateView(
		PLATFORM._surface_texture.texture,
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
	command_encoder = wgpu.DeviceCreateCommandEncoder(PLATFORM.device, nil)
	return surface_view, command_encoder
}

// platform
platform_reset_input_at_end_of_frame :: proc() {
	platform := &PLATFORM

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

@(private)
_platform_resize_frame_buffer :: proc() {
	platform := &PLATFORM
	platform.surface_config.width = platform.screen_size.x
	platform.surface_config.height = platform.screen_size.y
	if platform._surface_texture.texture != nil {
		wgpu.TextureRelease(platform._surface_texture.texture)
	}
	wgpu.SurfaceConfigure(platform.surface, &platform.surface_config)
	texture_destroy(&platform.hdr_screen_texture)
	texture_destroy(&platform.depth_screen_texture)
	platform.hdr_screen_texture = texture_create(platform.screen_size, HDR_SCREEN_TEXTURE_SETTINGS)
	platform.depth_screen_texture = depth_texture_create(platform.screen_size)
	_acquire_surface_texture(platform)
}

@(private = "file")
_platform_receive_glfw_char_event :: proc(platform: ^Platform, char: rune) {
	if platform.chars_len < len(platform.chars) {
		platform.chars[platform.chars_len] = char
		platform.chars_len += 1
	} else {
		print("Warning: a character has been dropped:", char)
	}
}

@(private = "file")
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

@(private = "file")
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

@(private = "file")
_init_glfw_window :: proc(platform: ^Platform) {
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 1)

	platform.window = glfw.CreateWindow(
		i32(platform.settings.initial_size.x),
		i32(platform.settings.initial_size.y),
		tmp_cstr(platform.settings.title),
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


@(private = "file")
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


set_clipboard :: proc(str: string) {
	glfw.SetClipboardString(PLATFORM.window, tmp_cstr(str))
}
get_clipboard :: proc() -> string {
	return glfw.GetClipboardString(PLATFORM.window)
}
get_input_chars :: proc() -> []rune {
	return PLATFORM.chars[:PLATFORM.chars_len]
}
is_ctrl_pressed :: proc() -> bool {
	return .Pressed in PLATFORM.keys[.LEFT_CONTROL] || .Pressed in PLATFORM.keys[.RIGHT_CONTROL]
}
is_shift_pressed :: proc() -> bool {
	return .Pressed in PLATFORM.keys[.LEFT_SHIFT] || .Pressed in PLATFORM.keys[.RIGHT_SHIFT]
}
is_alt_pressed :: proc() -> bool {
	return .Pressed in PLATFORM.keys[.LEFT_ALT] || .Pressed in PLATFORM.keys[.RIGHT_ALT]
}
is_just_pressed_or_repeated :: proc(key: Key) -> bool {
	return PressFlags{.JustPressed, .JustRepeated} & PLATFORM.keys[key] != PressFlags{}
}
is_just_pressed :: proc(key: Key) -> bool {
	return .JustPressed in PLATFORM.keys[key]
}
is_pressed :: proc(key: Key) -> bool {
	return .Pressed in PLATFORM.keys[key]
}
maximize_window :: proc() {
	glfw.MaximizeWindow(PLATFORM.window)
}


KeyVecPair :: struct {
	key: Key,
	dir: Vec2,
}
// rf keys, r = +1, f =-1
get_rf :: proc() -> f32 {
	res: f32
	if .Pressed in PLATFORM.keys[.R] {
		res += 1
	} else if .Pressed in PLATFORM.keys[.F] {
		res -= 1
	}
	return res
}
// axis of arrow keys or wasd for moving e.g. camera
get_wasd :: proc() -> Vec2 {
	mapping := [?]KeyVecPair{{.W, {0, 1}}, {.A, {-1, 0}}, {.S, {0, -1}}, {.D, {1, 0}}}
	dir: Vec2
	for m in mapping {
		if .Pressed in PLATFORM.keys[m.key] {
			dir += m.dir
		}
	}
	if dir != {0, 0} {
		return linalg.normalize(dir)
	}
	return {0, 0}
}
get_arrows :: proc() -> (res: Vec2) {
	keys := ARROW_KEYS
	dirs := [4]Vec2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	for key, idx in keys {
		if .Pressed in PLATFORM.keys[key] {
			res += dirs[idx]
		}
	}
	return res
}

ARROW_KEYS :: [4]Key{.LEFT, .RIGHT, .DOWN, .UP}
WASD_KEYS :: [4]Key{.A, .D, .S, .W}

get_arrows_just_pressed_or_repeated :: proc(keys := ARROW_KEYS) -> (res: IVec2) {
	dirs := [4]IVec2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	for key, idx in keys {
		flags := PLATFORM.keys[key]
		if .JustPressed in flags || .JustRepeated in flags {
			res += dirs[idx]
		}
	}
	return res
}
get_aspect_ratio :: proc() -> f32 {
	return PLATFORM.screen_size_f32.x / PLATFORM.screen_size_f32.y
}
get_delta_secs :: proc() -> f32 {
	return PLATFORM.delta_secs
}
get_delta_secs_f64 :: proc() -> f64 {
	return PLATFORM.delta_secs_f64
}
get_total_secs :: proc() -> f32 {
	return PLATFORM.total_secs
}
get_total_secs_f64 :: proc() -> f64 {
	return PLATFORM.total_secs_f64
}
get_screen_size :: proc() -> Vec2 {
	return PLATFORM.screen_size_f32
}
get_cursor_pos :: proc() -> Vec2 {
	return PLATFORM.cursor_pos
}
get_cursor_delta :: proc() -> Vec2 {
	return PLATFORM.cursor_delta
}
is_double_clicked :: proc() -> bool {
	return PLATFORM.double_clicked
}
is_left_just_pressed :: proc() -> bool {
	return .JustPressed in PLATFORM.mouse_buttons[.Left]
}
is_left_pressed :: proc() -> bool {
	return .Pressed in PLATFORM.mouse_buttons[.Left]
}
is_left_just_released :: proc() -> bool {
	return .JustReleased in PLATFORM.mouse_buttons[.Left]
}
is_right_just_pressed :: proc() -> bool {
	return .JustPressed in PLATFORM.mouse_buttons[.Right]
}
is_right_pressed :: proc() -> bool {
	return .Pressed in PLATFORM.mouse_buttons[.Right]
}
is_right_just_released :: proc() -> bool {
	return .JustReleased in PLATFORM.mouse_buttons[.Right]
}
is_key_pressed :: #force_inline proc(key: Key) -> bool {
	return .Pressed in PLATFORM.keys[key]
}
is_key_just_pressed :: #force_inline proc(key: Key) -> bool {
	return .JustPressed in PLATFORM.keys[key]
}
is_key_just_released :: #force_inline proc(key: Key) -> bool {
	return .JustReleased in PLATFORM.keys[key]
}
is_key_just_repeated :: #force_inline proc(key: Key) -> bool {
	return .JustRepeated in PLATFORM.keys[key]
}
is_key_just_pressed_or_repeated :: #force_inline proc(key: Key) -> bool {
	return PressFlags{.JustPressed, .JustRepeated} & PLATFORM.keys[key] != PressFlags{}
}
get_key :: proc(key: Key) -> PressFlags {
	return PLATFORM.keys[key]
}
