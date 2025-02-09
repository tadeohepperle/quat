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
	bloom_renderer:         q.BloomRenderer,
	sprite_renderer:        q.SpriteRenderer,
	gizmos_renderer:        q.GizmosRenderer,
	ui_renderer:            q.UiRenderer,
	color_mesh_renderer:    q.ColorMeshRenderer,
	textured_mesh_renderer: q.TexturedMeshRenderer,
	tritex_renderer:        q.TritexRenderer,
	skinned_renderer:       q.SkinnedRenderer,
	mesh_3d_renderer:       q.Mesh3dRenderer,
}

GIZMOS_COLOR := q.Color{1, 0, 0, 1}
_renderers_create :: proc(ren: ^Renderers, platform: ^q.Platform) {
	q.bloom_renderer_create(&ren.bloom_renderer, platform)
	q.sprite_renderer_create(&ren.sprite_renderer, platform)
	q.gizmos_renderer_create(&ren.gizmos_renderer, platform)
	q.ui_renderer_create(&ren.ui_renderer, platform)
	q.color_mesh_renderer_create(&ren.color_mesh_renderer, platform)
	q.textured_mesh_renderer_create(&ren.textured_mesh_renderer, platform)
	q.tritex_renderer_create(&ren.tritex_renderer, platform)
	q.skinned_renderer_create(&ren.skinned_renderer, platform)
	q.mesh_3d_renderer_create(&ren.mesh_3d_renderer, platform)
}
_renderers_destroy :: proc(ren: ^Renderers) {
	q.bloom_renderer_destroy(&ren.bloom_renderer)
	q.sprite_renderer_destroy(&ren.sprite_renderer)
	q.gizmos_renderer_destroy(&ren.gizmos_renderer)
	q.ui_renderer_destroy(&ren.ui_renderer)
	q.color_mesh_renderer_destroy(&ren.color_mesh_renderer)
	q.textured_mesh_renderer_destroy(&ren.textured_mesh_renderer)
	q.tritex_renderer_destroy(&ren.tritex_renderer)
	q.skinned_renderer_destroy(&ren.skinned_renderer)
}

EngineSettings :: struct {
	using platform:        q.PlatformSettings,
	bloom_enabled:         bool,
	bloom_settings:        q.BloomSettings,
	debug_ui_gizmos:       bool,
	debug_collider_gizmos: bool,
}
DEFAULT_ENGINE_SETTINGS := EngineSettings {
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
	ui_ctx:          q.UiCtx,
}

Scene :: struct {
	camera:                  q.Camera,
	top_level_ui_elements:   [dynamic]q.Ui,
	sprites:                 [dynamic]q.Sprite,
	depth_sprites:           [dynamic]q.DepthSprite,
	tritex_meshes:           [dynamic]q.TritexMesh,
	tritex_textures:         q.TextureArrayHandle,
	colliders:               [dynamic]q.Collider,
	last_frame_colliders:    [dynamic]q.Collider,
	skinned_render_commands: [dynamic]q.SkinnedRenderCommand,
	annotations:             [dynamic]Annotation,
	meshes_3d:               [dynamic]q.Mesh3d,
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
	delete(scene.depth_sprites)
	delete(scene.tritex_meshes)
	delete(scene.top_level_ui_elements)
	delete(scene.last_frame_colliders)
	delete(scene.colliders)
	delete(scene.skinned_render_commands)
	delete(scene.annotations)
	delete(scene.meshes_3d)
}

_scene_clear :: proc(scene: ^Scene) {
	clear(&scene.sprites)
	clear(&scene.depth_sprites)
	clear(&scene.tritex_meshes)
	scene.last_frame_colliders, scene.colliders = scene.colliders, scene.last_frame_colliders
	clear(&scene.colliders)
	clear(&scene.top_level_ui_elements)
	clear(&scene.skinned_render_commands)
	clear(&scene.annotations)
	clear(&scene.meshes_3d)
}

ENGINE: Engine

// after creating the engine, let it be pinned, don't move it in memory!!
_engine_create :: proc(engine: ^Engine, settings: EngineSettings) {
	engine.settings = settings
	q.platform_create(&engine.platform, settings.platform)
	engine.ui_ctx = q.ui_ctx_create(&engine.platform)
	q.set_global_ui_ctx_ptr(&engine.ui_ctx)
	_renderers_create(&engine.renderers, &engine.platform)
	_scene_create(&engine.scene)
}
_engine_destroy :: proc(engine: ^Engine) {
	q.platform_destroy(&engine.platform)
	_renderers_destroy(&engine.renderers)
	_scene_destroy(&engine.scene)
	q.set_global_ui_ctx_ptr(nil)
	q.ui_ctx_drop(&engine.ui_ctx)
}


init :: proc(settings: EngineSettings = DEFAULT_ENGINE_SETTINGS) {
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
	q.ui_ctx_start_frame(&engine.platform)
	return true
}

_engine_recalculate_hit_info :: proc(engine: ^Engine) {
	hit_pos := q.screen_to_world_pos(
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
	is_on_ui := engine.ui_ctx.cache.state.hovered != 0
	engine.hit = HitInfo{hit_pos, hit_collider, hit_collider_idx, is_on_ui}
}

_engine_end_frame :: proc(engine: ^Engine) {
	// RESIZE AND END INPUT:
	if engine.platform.screen_resized {
		q.platform_resize(&engine.platform)
		q.bloom_renderer_resize(&engine.bloom_renderer, engine.platform.screen_size)
	}
	// ADD SOME ADDITIONAL DRAW DATA:
	_engine_draw_annotations(engine)
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
	q.platform_prepare(&engine.platform, engine.scene.camera)
	q.sprite_renderer_prepare(
		&engine.sprite_renderer,
		engine.scene.depth_sprites[:],
		engine.scene.sprites[:],
		engine.scene.sprites[:], // todo! should only be the actual shine sprites, not e.g. random grass blades
	)
	q.ui_end_frame(
		engine.scene.top_level_ui_elements[:],
		engine.ui_ctx.cache.layout_extent,
		engine.platform.delta_secs,
		&engine.ui_renderer.batches,
	)
	q.ui_renderer_end_frame_and_prepare_buffers(
		&engine.ui_renderer,
		engine.platform.delta_secs,
		engine.platform.asset_manager,
	)
	q.color_mesh_renderer_prepare(&engine.color_mesh_renderer)
	q.textured_mesh_renderer_prepare(&engine.textured_mesh_renderer)
	q.gizmos_renderer_prepare(&engine.gizmos_renderer)

	// for the skinned mesh renderer, we currently let the user 
	// do updates directly with `update_skinned_mesh_bones``
}

_engine_render :: proc(engine: ^Engine) {
	// acquire surface texture:
	surface_texture, surface_view, command_encoder := q.platform_start_render(&engine.platform)

	// hdr render pass:
	hdr_pass := q.platform_start_hdr_pass(engine.platform, command_encoder)
	global_bind_group := engine.platform.globals.bind_group
	asset_manager := engine.platform.asset_manager
	q.tritex_renderer_render(
		&engine.tritex_renderer,
		hdr_pass,
		global_bind_group,
		engine.scene.tritex_meshes[:],
		engine.scene.tritex_textures,
		asset_manager,
	)
	q.mesh_3d_renderer_render(
		&engine.mesh_3d_renderer,
		hdr_pass,
		global_bind_group,
		engine.scene.meshes_3d[:],
		asset_manager,
	)
	q.sprite_renderer_render(&engine.sprite_renderer, hdr_pass, global_bind_group, asset_manager)
	// todo: this is certainly stupid, because then we render all skinned meshes on top of sprites:
	q.skinned_renderer_render(
		&engine.skinned_renderer,
		engine.scene.skinned_render_commands[:],
		hdr_pass,
		global_bind_group,
		asset_manager,
	)
	q.textured_mesh_renderer_render(
		&engine.textured_mesh_renderer,
		hdr_pass,
		global_bind_group,
		asset_manager,
	)
	q.color_mesh_renderer_render(&engine.color_mesh_renderer, hdr_pass, global_bind_group)

	// Solution 1: batch sprites and skinned meshes together, and then switching pipelines based on the current batch
	// Solution 2: use depth writes for at least one of the two and render that first.
	// 
	// also consider, that we might need a second "shine through" skinned shader for stuff behind geometry.

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
	cache := &engine.ui_ctx.cache
	state := &cache.state

	@(static) last_state: q.InteractionState(q.UiId)

	if state.hovered != last_state.hovered {
		print("  hovered:", last_state.hovered, "->", state.hovered)
	}
	if state.pressed != last_state.pressed {
		print("  pressed:", last_state.pressed, "->", state.pressed)
	}
	if state.focused != last_state.focused {
		print("  focused:", last_state.focused, "->", state.focused)
	}
	last_state = state^


	for k, v in cache.cached {
		color := q.ColorSoftSkyBlue
		if state.hovered == k {
			color = q.ColorYellow
		}
		if state.focused == k {
			color = q.ColorSoftPink
		}
		if state.pressed == k {
			color = q.ColorRed
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
		case q.Triangle2d:
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
		color := q.ColorSoftYellow if i == engine.hit.hit_collider_idx else q.ColorLightBlue
		add_collider_gizmos(&engine.renderers.gizmos_renderer, &collider.shape, color)
	}
}

get_mouse_btn :: proc(btn: q.MouseButton = .Left) -> q.PressFlags {
	return ENGINE.platform.mouse_buttons[btn]
}
// returns nil if no files dropped into window this frame, returned strings are only valid until end of frame
get_dropped_file_paths :: proc() -> []string {
	return ENGINE.platform.dropped_file_paths
}
get_scroll :: proc() -> f32 {
	return ENGINE.platform.scroll
}
// characters typed this frame
get_input_chars :: proc() -> []rune {
	return ENGINE.platform.chars[:ENGINE.platform.chars_len]
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
get_delta_secs_f64 :: proc() -> f64 {
	return ENGINE.platform.delta_secs_f64
}
get_total_secs :: proc() -> f32 {
	return ENGINE.platform.total_secs
}
get_total_secs_f64 :: proc() -> f64 {
	return ENGINE.platform.total_secs_f64
}
get_osc :: proc(speed: f32 = 1, amplitude: f32 = 1, bias: f32 = 0, phase: f32 = 0) -> f32 {
	return math.sin_f32(ENGINE.platform.total_secs * speed + phase) * amplitude + bias
}
get_screen_size_f32 :: proc() -> Vec2 {
	return ENGINE.platform.screen_size_f32
}
get_cursor_pos :: proc() -> Vec2 {
	return ENGINE.platform.cursor_pos
}
get_cursor_delta :: proc() -> Vec2 {
	return ENGINE.platform.cursor_delta
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
is_key_just_released :: #force_inline proc(key: q.Key) -> bool {
	return .JustReleased in ENGINE.platform.keys[key]
}
is_key_just_repeated :: #force_inline proc(key: q.Key) -> bool {
	return .JustRepeated in ENGINE.platform.keys[key]
}
is_key_just_pressed_or_repeated :: #force_inline proc(key: q.Key) -> bool {
	return q.PressFlags{.JustPressed, .JustRepeated} & ENGINE.platform.keys[key] != q.PressFlags{}
}
get_key :: proc(key: q.Key) -> q.PressFlags {
	return ENGINE.platform.keys[key]
}
is_shift_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.platform.keys[.LEFT_SHIFT]
}
is_ctrl_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.platform.keys[.LEFT_CONTROL]
}
is_alt_pressed :: proc() -> bool {
	return .Pressed in ENGINE.platform.keys[.LEFT_ALT]
}
set_clipboard :: proc(s: string) {
	q.platform_set_clipboard(&ENGINE.platform, s)
}
get_clipboard :: proc() -> string {
	return q.platform_get_clipboard(&ENGINE.platform)
}
maximize_window :: proc() {
	q.platform_maximize(&ENGINE.platform)
}
create_3d_mesh :: proc() -> q.Mesh3d {
	return q.mesh_3d_create(ENGINE.platform.device, ENGINE.platform.queue, 0)
}
draw_3d_mesh :: proc(mesh: q.Mesh3d) {
	append(&ENGINE.scene.meshes_3d, mesh)
}
create_skinned_mesh :: proc(
	triangles: []q.Triangle,
	vertices: []q.SkinnedVertex,
	bone_count: int,
	texture: q.TextureHandle = q.DEFAULT_TEXTURE,
) -> q.SkinnedMeshHandle {
	return q.skinned_mesh_register(
		&ENGINE.skinned_renderer,
		triangles,
		vertices,
		bone_count,
		texture,
	)
}
destroy_skinned_mesh :: proc(handle: q.SkinnedMeshHandle) {
	q.skinned_mesh_deregister(&ENGINE.skinned_renderer, handle)
}
// call this with a slice of bone transforms that has the same length as what the skinned mesh expects
set_skinned_mesh_bones :: proc(handle: q.SkinnedMeshHandle, bones: []q.Affine2) {
	q.skinned_mesh_update_bones(&ENGINE.skinned_renderer, handle, bones)
}
draw_skinned_mesh :: proc(
	handle: q.SkinnedMeshHandle,
	pos: Vec2 = Vec2{0, 0},
	color: Color = q.ColorWhite,
) {
	append(&ENGINE.scene.skinned_render_commands, q.SkinnedRenderCommand{pos, color, handle})
}
// expected to be 8bit RGBA png
load_texture :: proc(
	path: string,
	settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA,
) -> q.TextureHandle {
	return q.assets_load_texture(&ENGINE.platform.asset_manager, path, settings)
}
create_texture_from_image :: proc(img: q.Image) -> q.TextureHandle {
	texture := q.texture_from_image(
		ENGINE.platform.device,
		ENGINE.platform.queue,
		img,
		q.TEXTURE_SETTINGS_RGBA,
	)
	handle := q.assets_add_texture(&ENGINE.platform.asset_manager, texture)
	return handle
}
destroy_texture :: proc(handle: q.TextureHandle) {
	q.assets_deregister_texture(&ENGINE.platform.asset_manager, handle)
}
get_texture_info :: proc(handle: q.TextureHandle) -> q.TextureInfo {
	return q.assets_get_texture_info(ENGINE.platform.asset_manager, handle)
}
write_image_to_texture :: proc(img: q.Image, handle: q.TextureHandle) {
	texture := q.assets_get_texture(ENGINE.platform.asset_manager, handle)
	q.texture_write_from_image(ENGINE.platform.queue, texture, img)
}
// is expected to be 16bit R channel only png
load_depth_texture :: proc(path: string) -> q.TextureHandle {
	return q.assets_load_depth_texture(&ENGINE.platform.asset_manager, path)
}
load_texture_tile :: proc(
	path: string,
	settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA,
) -> q.TextureTile {
	return q.TextureTile{load_texture(path, settings), q.UNIT_AABB}
}
load_texture_as_sprite :: proc(
	path: string,
	settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA,
) -> q.Sprite {
	texture_handle := load_texture(path, settings)
	texture_tile := q.TextureTile{texture_handle, q.UNIT_AABB}
	texture_info := q.assets_get_texture_info(ENGINE.platform.asset_manager, texture_handle)
	sprite_size := Vec2{f32(texture_info.size.x), f32(texture_info.size.y)} / 100.0
	return q.Sprite {
		pos = {0, 0},
		size = sprite_size,
		color = {1, 1, 1, 1},
		texture = texture_tile,
		rotation = 0,
		z = 0,
	}
}

load_depth_sprite :: proc(
	depth_texture_path: string, // color_texture_path: string,
	color_texture_path: Maybe(string) = nil,
) -> q.DepthSprite {
	depth_texture_handle := load_depth_texture(depth_texture_path)
	tile := q.TextureTileWithDepth {
		color = {}, // 0 handle is okay, just shows white texture.
		depth = depth_texture_handle,
		uv    = q.UNIT_AABB,
	}
	if color_texture_path, ok := color_texture_path.(string); ok {
		tile.color = load_texture(color_texture_path)
	}
	texture_info := q.assets_get_texture_info(ENGINE.platform.asset_manager, depth_texture_handle)
	sprite_size := Vec2{f32(texture_info.size.x), f32(texture_info.size.y)} / 100.0
	return q.DepthSprite {
		pos = {0, 0},
		size = sprite_size,
		color = {1, 1, 1, 1},
		texture = tile,
		z = 0,
	}
}
load_texture_array :: proc(
	paths: []string,
	settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA,
) -> q.TextureArrayHandle {
	return q.assets_load_texture_array(&ENGINE.platform.asset_manager, paths, settings)
}
load_font :: proc(path: string) -> q.FontHandle {
	handle, err := q.assets_load_font(&ENGINE.platform.asset_manager, path)
	if err, has_err := err.(string); has_err {
		panic(err)
	}
	return handle
}
draw_sprite :: #force_inline proc(sprite: q.Sprite) {
	append(&ENGINE.scene.sprites, sprite)
}
draw_depth_sprite :: #force_inline proc(sprite: q.DepthSprite) {
	append(&ENGINE.scene.depth_sprites, sprite)
}
draw_tritex_mesh :: proc(mesh: q.TritexMesh) {
	append(&ENGINE.scene.tritex_meshes, mesh)
}
draw_gizmos_rect :: proc(center: Vec2, size: Vec2, color := GIZMOS_COLOR) {
	q.gizmos_renderer_add_rect(&ENGINE.gizmos_renderer, center, size, color, .WORLD)
}
draw_gizmos_aabb :: proc(aabb: q.Aabb, color := GIZMOS_COLOR, mode: q.GizmosMode = .WORLD) {
	q.gizmos_renderer_add_aabb(&ENGINE.gizmos_renderer, aabb, color, mode)
}
draw_gizmos_line :: proc(from: Vec2, to: Vec2, color := GIZMOS_COLOR) {
	q.gizmos_renderer_add_line(&ENGINE.gizmos_renderer, from, to, color)
}
draw_gizmos_triangle :: proc(a, b, c: Vec2, color := GIZMOS_COLOR) {
	q.gizmos_renderer_add_triangle(&ENGINE.gizmos_renderer, a, b, c, color)
}
draw_gizmos_coords :: proc() {
	q.gizmos_renderer_add_coordinates(&ENGINE.gizmos_renderer)
}
draw_gizmos_circle :: proc(
	center: Vec2,
	radius: f32,
	color: Color = q.ColorRed,
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
access_color_mesh_write_buffers :: #force_inline proc(
) -> (
	vertices: ^[dynamic]q.ColorMeshVertex,
	triangles: ^[dynamic]q.Triangle,
	start: u32,
) {
	vertices = &ENGINE.color_mesh_renderer.vertices
	triangles = &ENGINE.color_mesh_renderer.triangles
	start = u32(len(vertices))
	return
}
// Can write directly into these, instead of using one of the `draw_color_mesh` procs.
access_textured_mesh_write_buffers :: #force_inline proc(
) -> (
	vertices: ^[dynamic]q.TexturedVertex,
	triangles: ^[dynamic]q.Triangle,
	start: u32,
) {
	vertices = &ENGINE.textured_mesh_renderer.vertices
	triangles = &ENGINE.textured_mesh_renderer.triangles
	start = u32(len(vertices))
	return
}
set_textured_mesh_texture :: proc(texture: q.TextureHandle) {
	q.textured_mesh_renderer_set_texture(&ENGINE.textured_mesh_renderer, texture)
}

draw_color_mesh :: proc {
	draw_color_mesh_vertices,
	draw_color_mesh_indexed_single_color,
	draw_color_mesh_indexed,
}
draw_color_mesh_vertices :: proc(vertices: []q.ColorMeshVertex) {
	q.color_mesh_add_vertices(&ENGINE.color_mesh_renderer, vertices)
}
draw_color_mesh_indexed :: proc(vertices: []q.ColorMeshVertex, triangles: []q.Triangle) {
	q.color_mesh_add_indexed(&ENGINE.color_mesh_renderer, vertices, triangles)
}
draw_color_mesh_indexed_single_color :: proc(
	positions: []Vec2,
	triangles: []q.Triangle,
	color := Color{1, 0, 0, 1},
) {
	q.color_mesh_add_indexed_single_color(&ENGINE.color_mesh_renderer, positions, triangles, color)
}
add_ui :: proc(ui: q.Ui) {
	append(&ENGINE.scene.top_level_ui_elements, ui)
}
add_circle_collider :: proc(center: Vec2, radius: f32, metadata: q.ColliderMetadata, z: int) {
	append(
		&ENGINE.scene.colliders,
		q.Collider{shape = q.Circle{center, radius}, metadata = metadata, z = z},
	)
}
add_rect_collider :: proc(quad: q.RotatedRect, metadata: q.ColliderMetadata, z: int) {
	append(&ENGINE.scene.colliders, q.Collider{shape = quad, metadata = metadata, z = z})
}
add_triangle_collider :: proc(triangle: q.Triangle2d, metadata: q.ColliderMetadata, z: int) {
	append(&ENGINE.scene.colliders, q.Collider{shape = triangle, metadata = metadata, z = z})
}
set_camera :: proc(camera: q.Camera) {
	ENGINE.scene.camera = camera
	_engine_recalculate_hit_info(&ENGINE) // todo! probably not appropriate??
}
set_tritex_textures :: proc(textures: q.TextureArrayHandle) {
	ENGINE.scene.tritex_textures = textures
}
get_camera :: proc() -> q.Camera {
	return ENGINE.scene.camera
}
set_clear_color :: proc(color: q.Color) {
	ENGINE.settings.platform.clear_color = color
}
set_bloom_enabled :: proc(enabled: bool) {
	ENGINE.settings.bloom_enabled = enabled
}
set_bloom_blend_factor :: proc(factor: f64) {
	ENGINE.settings.bloom_settings.blend_factor = factor
}
set_tonemapping_mode :: proc(mode: q.TonemappingMode) {
	ENGINE.settings.platform.tonemapping = mode
}
create_tritex_mesh :: proc(vertices: []q.TritexVertex) -> q.TritexMesh {
	return q.tritex_mesh_create(vertices, ENGINE.platform.device, ENGINE.platform.queue)
}
KeyVecPair :: struct {
	key: q.Key,
	dir: Vec2,
}

// rf keys, r = +1, f =-1
get_rf :: proc() -> f32 {
	res: f32
	if .Pressed in ENGINE.platform.keys[.R] {
		res += 1
	} else if .Pressed in ENGINE.platform.keys[.F] {
		res -= 1
	}
	return res
}
// axis of arrow keys or wasd for moving e.g. camera
get_wasd :: proc() -> Vec2 {
	mapping := [?]KeyVecPair{{.W, {0, 1}}, {.A, {-1, 0}}, {.S, {0, -1}}, {.D, {1, 0}}}
	dir: Vec2
	for m in mapping {
		if .Pressed in ENGINE.platform.keys[m.key] {
			dir += m.dir
		}
	}
	if dir != {0, 0} {
		return linalg.normalize(dir)
	}
	return {0, 0}
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
// call before initializing engine!
enable_max_fps :: proc() {
	DEFAULT_ENGINE_SETTINGS.power_preference = .HighPerformance
	DEFAULT_ENGINE_SETTINGS.present_mode = .Immediate
}
// call before initializing engine!
enable_v_sync :: proc() {
	DEFAULT_ENGINE_SETTINGS.power_preference = .LowPower
	DEFAULT_ENGINE_SETTINGS.present_mode = .Fifo
}
access_last_frame_colliders :: proc() -> []q.Collider {
	return ENGINE.scene.last_frame_colliders[:]
}
get_aspect_ratio :: proc() -> f32 {
	return ENGINE.platform.screen_size_f32.x / ENGINE.platform.screen_size_f32.y
}
Annotation :: struct {
	pos:       Vec2,
	str:       string,
	font_size: f32, // 10 = 0.1 units in world space
	color:     Color,
}
draw_annotation :: proc(pos: Vec2, str: string, font_size: f32 = 12.0, color := q.ColorWhite) {
	append(&ENGINE.scene.annotations, Annotation{pos, str, font_size, color})
}
_engine_draw_annotations :: proc(engine: ^Engine) {
	if len(engine.scene.annotations) == 0 {
		return
	}
	cover := div(q.COVER_DIV)
	add_ui(cover)

	screen_size := engine.platform.screen_size_f32
	camera := engine.scene.camera
	half_cam_world_size := Vec2{camera.height * screen_size.x / screen_size.y, camera.height}
	culling_aabb := q.Aabb {
		min = camera.focus_pos - half_cam_world_size - Vec2{1, 1},
		max = camera.focus_pos + half_cam_world_size + Vec2{1, 1},
	}
	for ann in engine.scene.annotations {
		// cull points that are likely offscreen anyway
		if !q.aabb_contains(culling_aabb, ann.pos) {
			continue
		}

		screen_pos := q.world_to_screen_pos(camera, ann.pos, screen_size)
		screen_unit_pos := screen_pos / screen_size
		div_at_pt := child_div(
			cover,
			Div {
				flags = q.DivFlags {
					.Absolute,
					.MainAlignCenter,
					.ZeroSizeButInfiniteSizeForChildren,
					.CrossAlignCenter,
				},
				absolute_unit_pos = screen_unit_pos,
			},
		)
		// red_box := child_div(div_at_pt, q.RED_BOX_DIV)
		child_text(
			div_at_pt,
			Text {
				color     = ann.color,
				shadow    = 0.5,
				font_size = 10.80 / camera.height * ann.font_size, // because UI layout assumes screen is 1080 px in height
				str       = ann.str,
			},
		)
	}
}
