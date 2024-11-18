package engine

// This shows a little engine implementation based on the dengine framework. 
// Please use this only for experimentation and develop your own engine with custom renderers
// and custom control from for each specific project. We do NOT attempt to make a one size fits all thing here.

import q "../"
import "core:math"
import "core:math/linalg"
import wgpu "vendor:wgpu"

Vec2 :: q.Vec2
Vec3 :: q.Vec3
Color :: q.Color
print :: q.print

Renderers :: struct {
	bloom_renderer:      q.BloomRenderer,
	sprite_renderer:     q.SpriteRenderer,
	gizmos_renderer:     q.GizmosRenderer,
	ui_renderer:         q.UiRenderer,
	color_mesh_renderer: q.ColorMeshRenderer,
	// terrain_renderer:    q.TerrainRenderer,
}

GIZMOS_COLOR := q.Color{1, 0, 0, 1}
DEFAULT_FONT_COLOR := q.Color_White
DEFAULT_FONT_SIZE: f32 = 16
_renderers_create :: proc(ren: ^Renderers, platform: ^q.Platform) {
	q.bloom_renderer_create(&ren.bloom_renderer, platform)
	q.sprite_renderer_create(&ren.sprite_renderer, platform)
	q.gizmos_renderer_create(&ren.gizmos_renderer, platform)
	q.ui_renderer_create(&ren.ui_renderer, platform, DEFAULT_FONT_COLOR, DEFAULT_FONT_SIZE)
	q.color_mesh_renderer_create(&ren.color_mesh_renderer, platform)
	// q.terrain_renderer_create(&ren.terrain_renderer, platform)
}
_renderers_destroy :: proc(ren: ^Renderers) {
	q.bloom_renderer_destroy(&ren.bloom_renderer)
	q.sprite_renderer_destroy(&ren.sprite_renderer)
	q.gizmos_renderer_destroy(&ren.gizmos_renderer)
	q.ui_renderer_destroy(&ren.ui_renderer)
	q.color_mesh_renderer_destroy(&ren.color_mesh_renderer)
	// q.terrain_renderer_destroy(&ren.terrain_renderer)
}

EngineSettings :: struct {
	using platform:        q.PlatformSettings,
	bloom_enabled:         bool,
	bloom_settings:        q.BloomSettings,
	debug_ui_gizmos:       bool,
	debug_collider_gizmos: bool,
}
ENGINE_SETTINGS_DEFAULT :: EngineSettings {
	platform              = q.PLATFORM_SETTINGS_DEFAULT,
	bloom_enabled         = true,
	bloom_settings        = q.BLOOM_SETTINGS_DEFAULT,
	debug_ui_gizmos       = false,
	debug_collider_gizmos = true,
}
Engine :: struct {
	settings:        EngineSettings,
	using renderers: Renderers,
	platform:        q.Platform,
	hit:             HitInfo,
	scene:           Scene,
}

Scene :: struct {
	camera:               q.Camera,
	sprites:              [dynamic]q.Sprite,
	// terrain_meshes:       [dynamic]^q.TerrainMesh,
	terrain_textures:     q.TextureArrayHandle,
	colliders:            [dynamic]q.Collider,
	last_frame_colliders: [dynamic]q.Collider,
}

HitInfo :: struct {
	hit_pos:          Vec2,
	hit_collider:     q.ColliderMetadata,
	hit_collider_idx: int,
	is_on_ui:         bool,
}

_scene_create :: proc(scene: ^Scene) {
	scene.camera = q.DEFAULT_CAMERA
}

_scene_destroy :: proc(scene: ^Scene) {
	delete(scene.sprites)
}

_scene_clear :: proc(scene: ^Scene) {
	clear(&scene.sprites)
	// clear(&scene.terrain_meshes)
	// scene.last_frame_colliders, scene.colliders = scene.colliders, scene.last_frame_colliders
	// clear(&scene.colliders)
}


ENGINE: Engine

_engine_create :: proc(engine: ^Engine, settings: EngineSettings) {
	engine.settings = settings
	q.platform_create(&engine.platform, settings.platform)
	_renderers_create(&engine.renderers, &engine.platform)
	_scene_create(&engine.scene)
}

_engine_destroy :: proc(engine: ^Engine) {
	q.platform_destroy(&engine.platform)
	_renderers_destroy(&engine.renderers)
	_scene_destroy(&engine.scene)
}


init :: proc(settings: EngineSettings = ENGINE_SETTINGS_DEFAULT) {
	_engine_create(&ENGINE, settings)
}

deinit :: proc() {
	_engine_destroy(&ENGINE)
}

next_frame :: proc() -> bool {
	@(static) LOOP_INITIALIZED := false

	if LOOP_INITIALIZED {
		_engine_end_frame(&ENGINE)
	} else {
		LOOP_INITIALIZED = true
	}
	return _engine_start_frame(&ENGINE)
}

_engine_start_frame :: proc(engine: ^Engine) -> bool {
	if !q.platform_start_frame(&engine.platform) {
		return false
	}
	_engine_recalculate_hit_info(engine)
	q.ui_renderer_start_frame(
		&engine.ui_renderer,
		engine.platform.screen_size_f32,
		&engine.platform,
	)
	return true
}

_engine_recalculate_hit_info :: proc(engine: ^Engine) {
	camera_raw := q.camera_to_raw(engine.scene.camera, engine.platform.screen_size_f32)
	hit_pos := q.camera_cursor_hit_pos(
		engine.scene.camera,
		engine.platform.cursor_pos,
		engine.platform.screen_size_f32,
	)

	highest_z_collider_hit: int = min(int)
	hit_collider_idx := -1
	hit_collider := q.NO_COLLIDER
	for &e, i in engine.scene.last_frame_colliders {
		if e.z > highest_z_collider_hit {
			if q.collider_overlaps_point(&e.shape, hit_pos) {
				highest_z_collider_hit = e.z
				hit_collider = e.metadata
				hit_collider_idx = i
			}
		}
	}
	is_on_ui := engine.ui_renderer.cache.state.hovered_id != 0
	engine.hit = HitInfo{hit_pos, hit_collider, hit_collider_idx, is_on_ui}
}

_engine_end_frame :: proc(engine: ^Engine) {

	// RESIZE AND END INPUT:
	if engine.platform.screen_resized {
		q.platform_resize(&engine.platform)
		q.bloom_renderer_resize(&engine.bloom_renderer, engine.platform.screen_size)
	}

	if engine.settings.debug_ui_gizmos {
		_engine_debug_ui_gizmos(engine)
	}
	if engine.settings.debug_collider_gizmos {
		_engine_debug_collider_gizmos(engine)
	}

	engine.platform.settings = engine.settings.platform
	q.platform_reset_input_at_end_of_frame(&engine.platform)
	// PREPARE

	_engine_prepare(engine)
	// RENDER
	_engine_render(engine)
	// CLEAR
	_scene_clear(&engine.scene)
	free_all(context.temp_allocator)
}

_engine_prepare :: proc(engine: ^Engine) {
	engine.platform.camera = engine.scene.camera
	q.platform_prepare(&engine.platform)
	q.sprite_renderer_prepare(&engine.sprite_renderer, engine.scene.sprites[:])
	q.color_mesh_renderer_prepare(&engine.color_mesh_renderer)
	q.gizmos_renderer_prepare(&engine.gizmos_renderer)
	q.ui_renderer_end_frame_and_prepare_buffers(
		&engine.ui_renderer,
		engine.platform.delta_secs,
		engine.platform.asset_manager,
	)
}

_engine_render :: proc(engine: ^Engine) {


	// acquire surface texture:
	surface_texture, surface_view, command_encoder := q.platform_start_render(&engine.platform)

	// hdr render pass:

	hdr_pass := q.platform_start_hdr_pass(engine.platform, command_encoder)
	global_bind_group := engine.platform.globals.bind_group
	asset_manager := engine.platform.asset_manager
	// q.terrain_renderer_render(
	// 	&engine.terrain_renderer,
	// 	hdr_pass,
	// 	global_bind_group,
	// 	engine.scene.terrain_meshes[:],
	// 	engine.scene.terrain_textures,
	// 	asset_manager,
	// )
	q.sprite_renderer_render(&engine.sprite_renderer, hdr_pass, global_bind_group, asset_manager)
	q.color_mesh_renderer_render(&engine.color_mesh_renderer, hdr_pass, global_bind_group)
	q.gizmos_renderer_render(&engine.gizmos_renderer, hdr_pass, global_bind_group, .WORLD)
	q.ui_renderer_render(
		&engine.ui_renderer,
		hdr_pass,
		global_bind_group,
		engine.platform.screen_size,
		asset_manager,
	)
	q.gizmos_renderer_render(&engine.gizmos_renderer, hdr_pass, global_bind_group, .UI)
	wgpu.RenderPassEncoderEnd(hdr_pass)
	wgpu.RenderPassEncoderRelease(hdr_pass)

	// bloom:
	if engine.settings.bloom_enabled {
		q.render_bloom(
			command_encoder,
			&engine.bloom_renderer,
			&engine.platform.hdr_screen_texture,
			global_bind_group,
			engine.settings.bloom_settings,
		)
	}

	q.platform_end_render(&engine.platform, surface_texture, surface_view, command_encoder)
}


@(private)
_engine_debug_ui_gizmos :: proc(engine: ^Engine) {
	cache := &engine.ui_renderer.cache
	state := &cache.state

	@(static) last_state: q.InteractionState(q.UiId)

	if state.hovered_id != last_state.hovered_id {
		print("  hovered_id:", last_state.hovered_id, "->", state.hovered_id)
	}
	if state.pressed_id != last_state.pressed_id {
		print("  pressed_id:", last_state.pressed_id, "->", state.pressed_id)
	}
	if state.focused_id != last_state.focused_id {
		print("  focused_id:", last_state.focused_id, "->", state.focused_id)
	}
	last_state = state^


	for k, v in cache.cached {
		color := q.Color_Light_Blue
		if state.hovered_id == k {
			color = q.Color_Yellow
		}
		if state.focused_id == k {
			color = q.Color_Violet
		}
		if state.pressed_id == k {
			color = q.Color_Red
		}
		q.gizmos_renderer_add_aabb(&engine.gizmos_renderer, {v.pos, v.pos + v.size}, color, .UI)
	}

	// for &e in UI_MEMORY_elements() {
	// 	color: Color = ---
	// 	switch &var in &e.variant {
	// 	case DivWithComputed:
	// 		color = Color_Red
	// 	case TextWithComputed:
	// 		color = Color_Yellow
	// 	case CustomUiElement:
	// 		color = Color_Green
	// 	}
	// 	
	// }
}


@(private)
_engine_debug_collider_gizmos :: proc(engine: ^Engine) {
	add_collider_gizmos :: #force_inline proc(
		rend: ^q.GizmosRenderer,
		shape: ^q.ColliderShape,
		color: Color,
	) {
		switch c in shape {
		case q.Circle:
			q.gizmos_renderer_add_circle(rend, c.pos, c.radius, color)
		case q.Aabb:
			q.gizmos_renderer_add_aabb(rend, c, color, .WORLD)
		case q.Triangle:
			q.gizmos_renderer_add_line(rend, c.a, c.b, color, .WORLD)
			q.gizmos_renderer_add_line(rend, c.b, c.c, color, .WORLD)
			q.gizmos_renderer_add_line(rend, c.c, c.a, color, .WORLD)
		case q.RotatedRect:
			q.gizmos_renderer_add_line(rend, c.a, c.b, color, .WORLD)
			q.gizmos_renderer_add_line(rend, c.b, c.c, color, .WORLD)
			q.gizmos_renderer_add_line(rend, c.c, c.d, color, .WORLD)
			q.gizmos_renderer_add_line(rend, c.d, c.a, color, .WORLD)
		}
	}


	for &collider, i in engine.scene.last_frame_colliders {
		color := q.Color_Yellow if i == engine.hit.hit_collider_idx else q.Color_Light_Blue
		add_collider_gizmos(&engine.renderers.gizmos_renderer, &collider.shape, color)
	}
}

get_mouse_btn :: proc(btn: q.MouseButton = .Left) -> q.PressFlags {
	return ENGINE.platform.mouse_buttons[btn]
}
get_scroll :: proc() -> f32 {
	return ENGINE.platform.scroll
}
get_hit :: #force_inline proc() -> HitInfo {
	return ENGINE.hit
}
get_hit_pos :: proc() -> Vec2 {
	return ENGINE.hit.hit_pos
}
get_delta_secs :: proc() -> f32 {
	return ENGINE.platform.delta_secs
}
get_total_secs :: proc() -> f32 {
	return ENGINE.platform.total_secs
}
get_osc :: proc(speed: f32 = 1, amplitude: f32 = 1, bias: f32 = 0, phase: f32 = 0) -> f32 {
	return math.sin_f32(ENGINE.platform.total_secs * speed + phase) * amplitude + bias
}
is_double_clicked :: proc() -> bool {
	return ENGINE.platform.double_clicked
}
is_left_just_pressed :: proc() -> bool {
	return .JustPressed in ENGINE.platform.mouse_buttons[.Left]
}
is_left_pressed :: proc() -> bool {
	return .Pressed in ENGINE.platform.mouse_buttons[.Left]
}
is_left_just_released :: proc() -> bool {
	return .JustReleased in ENGINE.platform.mouse_buttons[.Left]
}
is_right_just_pressed :: proc() -> bool {
	return .JustPressed in ENGINE.platform.mouse_buttons[.Right]
}
is_right_pressed :: proc() -> bool {
	return .Pressed in ENGINE.platform.mouse_buttons[.Right]
}
is_right_just_released :: proc() -> bool {
	return .JustReleased in ENGINE.platform.mouse_buttons[.Right]
}
is_key_pressed :: #force_inline proc(key: q.Key) -> bool {
	return .Pressed in ENGINE.platform.keys[key]
}
is_key_just_pressed :: #force_inline proc(key: q.Key) -> bool {
	return .JustPressed in ENGINE.platform.keys[key]
}
is_shift_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.platform.keys[.LEFT_SHIFT]
}
is_ctrl_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.platform.keys[.LEFT_CONTROL]
}
load_texture :: proc(
	path: string,
	settings: q.TextureSettings = q.TEXTURE_SETTINGS_DEFAULT,
) -> q.TextureHandle {
	return q.assets_load_texture(&ENGINE.platform.asset_manager, path, settings)
}
load_texture_tile :: proc(
	path: string,
	settings: q.TextureSettings = q.TEXTURE_SETTINGS_DEFAULT,
) -> q.TextureTile {
	return q.TextureTile{load_texture(path, settings), q.UNIT_AABB}
}
load_texture_array :: proc(
	paths: []string,
	settings: q.TextureSettings = q.TEXTURE_SETTINGS_DEFAULT,
) -> q.TextureArrayHandle {
	return q.assets_load_texture_array(&ENGINE.platform.asset_manager, paths, settings)
}
load_font :: proc(path: string) -> q.FontHandle {
	return q.assets_load_font(&ENGINE.platform.asset_manager, path)
}
draw_sprite :: #force_inline proc(sprite: q.Sprite) {
	append(&ENGINE.scene.sprites, sprite)
}
// draw_terrain_mesh :: #force_inline proc(mesh: ^q.TerrainMesh) {
// 	append(&ENGINE.scene.terrain_meshes, mesh)
// }
draw_gizmos_rect :: proc(center: Vec2, size: Vec2, color := GIZMOS_COLOR) {
	q.gizmos_renderer_add_rect(&ENGINE.gizmos_renderer, center, size, color, .WORLD)
}
draw_gizmos_line :: proc(from: Vec2, to: Vec2, color := GIZMOS_COLOR) {
	q.gizmos_renderer_add_line(&ENGINE.gizmos_renderer, from, to, color)
}
draw_gizmos_coords :: proc() {
	q.gizmos_renderer_add_coordinates(&ENGINE.gizmos_renderer)
}
draw_gizmos_circle :: proc(
	center: Vec2,
	radius: f32,
	color: Color = q.Color_Red,
	segments: int = 12,
	draw_inner_lines: bool = false,
) {
	q.gizmos_renderer_add_circle(
		&ENGINE.gizmos_renderer,
		center,
		radius,
		color,
		segments,
		draw_inner_lines,
		.WORLD,
	)
}
draw_gizmos_circle_xz :: proc(
	center: Vec2,
	radius: f32,
	color: Color = q.Color_Red,
	segments: int = 12,
	draw_inner_lines: bool = false,
) {
	q.gizmos_renderer_add_circle(
		&ENGINE.gizmos_renderer,
		center,
		radius,
		color,
		segments,
		draw_inner_lines,
		.WORLD,
	)
}
// Can write directly into these, instead of using one of the `draw_color_mesh` procs.
access_color_mesh_write_buffers :: proc(
) -> (
	vertices: ^[dynamic]q.ColorMeshVertex,
	indices: ^[dynamic]u32,
) {
	indices = &ENGINE.color_mesh_renderer.indices
	vertices = &ENGINE.color_mesh_renderer.vertices
	return
}
draw_color_mesh :: proc {
	draw_color_mesh_vertices_single_color,
	draw_color_mesh_vertices,
	draw_color_mesh_indexed_single_color,
	draw_color_mesh_indexed,
}
draw_color_mesh_vertices_single_color :: proc(positions: []Vec2, color := Color{1, 0, 0, 1}) {
	q.color_mesh_add_vertices_single_color(&ENGINE.color_mesh_renderer, positions, color)
}
draw_color_mesh_vertices :: proc(vertices: []q.ColorMeshVertex) {
	q.color_mesh_add_vertices(&ENGINE.color_mesh_renderer, vertices)
}
draw_color_mesh_indexed :: proc(vertices: []q.ColorMeshVertex, indices: []u32) {
	q.color_mesh_add_indexed(&ENGINE.color_mesh_renderer, vertices, indices)
}
draw_color_mesh_indexed_single_color :: proc(
	positions: []Vec2,
	indices: []u32,
	color := Color{1, 0, 0, 1},
) {
	q.color_mesh_add_indexed_single_color(&ENGINE.color_mesh_renderer, positions, indices, color)
}
add_circle_collider :: proc(center: Vec2, radius: f32, metadata: q.ColliderMetadata) {
	append(
		&ENGINE.scene.colliders,
		q.Collider{shape = q.Circle{center, radius}, metadata = metadata},
	)
}
add_rect_collider :: proc(quad: q.RotatedRect, metadata: q.ColliderMetadata) {
	append(&ENGINE.scene.colliders, q.Collider{shape = quad, metadata = metadata})
}
add_triangle_collider :: proc(triangle: q.Triangle, metadata: q.ColliderMetadata) {
	append(&ENGINE.scene.colliders, q.Collider{shape = triangle, metadata = metadata})
}
set_camera :: proc(camera: q.Camera) {
	ENGINE.scene.camera = camera
}
set_clear_color :: proc(color: q.Color) {
	ENGINE.settings.platform.clear_color = color
}
KeyVecPair :: struct {
	key: q.Key,
	dir: Vec2,
}

// axis of arrow keys or wasd for moving e.g. camera
get_wasd :: proc() -> Vec2 {
	mapping := [?]KeyVecPair {
		{.UP, {0, 1}},
		{.LEFT, {-1, 0}},
		{.DOWN, {0, -1}},
		{.RIGHT, {1, 0}},
		{.W, {0, 1}},
		{.A, {-1, 0}},
		{.S, {0, -1}},
		{.D, {1, 0}},
	}
	dir: Vec2
	for m in mapping {
		if .Pressed in ENGINE.platform.keys[m.key] {
			dir += m.dir
		}
	}
	if dir != {0, 0} {
		dir = linalg.normalize(dir)
	}
	return dir
}
get_arrows :: proc() -> Vec2 {
	mapping := [?]KeyVecPair{{.UP, {0, 1}}, {.LEFT, {-1, 0}}, {.DOWN, {0, -1}}, {.RIGHT, {1, 0}}}
	dir: Vec2
	for m in mapping {
		if .Pressed in ENGINE.platform.keys[m.key] {
			dir += m.dir
		}
	}
	if dir != {0, 0} {
		dir = linalg.normalize(dir)
	}
	return dir
}
