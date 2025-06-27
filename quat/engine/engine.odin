package engine

// This shows a little engine implementation based on the dengine framework. 
// Please use this only for experimentation and develop your own engine with custom renderers
// and custom control from for each specific project. We do NOT attempt to make a one size fits all thing here.

import q "../"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import wgpu "vendor:wgpu"

Vec2 :: q.Vec2
Vec3 :: q.Vec3
Color :: q.Color
print :: q.print
GIZMOS_COLOR := q.Color{1, 0, 0, 1}

EngineSettings :: struct {
	using platform:           q.PlatformSettings,
	bloom_enabled:            bool,
	bloom_settings:           q.BloomSettings,
	debug_ui_gizmos:          bool,
	debug_collider_gizmos:    bool,
	use_simple_sprite_shader: bool, // does not use the depth calculations
}
DEFAULT_ENGINE_SETTINGS := EngineSettings {
	platform              = q.PLATFORM_SETTINGS_DEFAULT,
	bloom_enabled         = true,
	bloom_settings        = q.BLOOM_SETTINGS_DEFAULT,
	debug_ui_gizmos       = false,
	debug_collider_gizmos = true,
}

Pipeline :: ^q.RenderPipeline
Engine :: struct {
	settings:                         EngineSettings,
	platform:                         q.Platform,
	hit:                              HitInfo,
	scene:                            Scene,
	ui_ctx:                           q.UiCtx,
	bloom_renderer:                   q.BloomRenderer,
	gizmos_renderer:                  q.GizmosRenderer,
	color_mesh_renderer:              q.ColorMeshRenderer,
	mesh_2d_renderer:                 q.Mesh2dRenderer,
	pipelines:                        [PipelineType]^q.RenderPipeline,
	cutout_sprites:                   SpriteBuffers,
	shine_sprites:                    SpriteBuffers,
	transparent_sprites_low:          SpriteBuffers,
	transparent_sprites_high:         SpriteBuffers,
	world_ui_buffers:                 q.UiRenderBuffers,
	screen_ui_buffers:                q.UiRenderBuffers,
	motion_particles_render_commands: [dynamic]q.MotionParticlesRenderCommand,
	motion_particles_buffer:          q.DynamicBuffer(q.MotionParticleInstance),
	top_level_elements_scratch:       [dynamic]q.TopLevelElement,

	// sprite_pipeline:     Pipeline,
	// tritex_pipeline:     Pipeline,
	// skinned_pipeline:    Pipeline,
	// mesh_3d_pipeline:    Pipeline,
}

SpriteBuffers :: struct {
	batches:         [dynamic]q.SpriteBatch,
	instances:       [dynamic]q.SpriteInstance,
	instance_buffer: q.DynamicBuffer(q.SpriteInstance),
}
sprite_buffers_create :: proc(device: wgpu.Device, queue: wgpu.Queue) -> (this: SpriteBuffers) {
	q.dynamic_buffer_init(&this.instance_buffer, {.Vertex}, device, queue)
	return this
}
sprite_buffers_destroy :: proc(this: ^SpriteBuffers) {
	delete(this.batches)
	delete(this.instances)
	q.dynamic_buffer_destroy(&this.instance_buffer)
}
sprite_buffers_batch_and_prepare :: proc(this: ^SpriteBuffers, sprites: []q.Sprite) {
	q.sprites_sort_and_batch(sprites[:], &this.batches, &this.instances)
	q.dynamic_buffer_write(&this.instance_buffer, this.instances[:])
}

PipelineType :: enum {
	HexChunk,
	SpriteCutout,
	SpriteSimple,
	SpriteShine,
	SpriteTransparent,
	SkinnedCutout,
	// SkinnedTransparent,
	// SkinnedShine,
	// SkinnedShine,
	Mesh3d,
	Mesh3dHexChunkMasked,
	Tritex,
	ScreenUiGlyph,
	ScreenUiRect,
	WorldUiGlyph,
	WorldUiRect,
	MotionParticles,
}

UiAtWorldPos :: struct {
	ui:        q.Ui,
	world_pos: Vec2,
	transform: q.UiWorldTransform,
}

// roughly in render order
Scene :: struct {
	camera:                         q.Camera,
	// geometry:
	tritex_meshes:                  [dynamic]q.TritexMesh,
	tritex_textures:                q.TextureArrayHandle, // not owned! just set by the user.
	meshes_3d:                      [dynamic]q.Mesh3d,
	meshes_3d_hex_chunk_masked:     [dynamic]q.Mesh3dHexChunkMasked,
	// cutout discard shader depth rendering:
	cutout_sprites:                 [dynamic]q.Sprite,
	// transparency layer 1:
	transparent_sprites_low:        [dynamic]q.Sprite,
	world_ui:                       [dynamic]UiAtWorldPos, // ui elements that are rendered below transparent sprites and shine sprites
	// transparency layer 2:
	transparent_sprites_high:       [dynamic]q.Sprite,
	shine_sprites:                  [dynamic]q.Sprite, // rendered with inverse depth test to shine through walls
	screen_ui:                      [dynamic]q.Ui,
	// other stuff
	colliders:                      [dynamic]q.Collider,
	last_frame_colliders:           [dynamic]q.Collider,
	skinned_render_commands:        [dynamic]q.SkinnedRenderCommand,
	motion_particles_draw_commands: [dynamic]_MotionParticleDrawCommand,
	annotations:                    [dynamic]Annotation, // put into ui_world_layer
	hex_chunks:                     [dynamic]q.HexChunkUniform,
	display_values:                 [dynamic]DisplayValue,
}

HitInfo :: struct {
	hit_pos:          Vec2,
	hit_collider:     q.ColliderMetadata,
	hit_collider_idx: int,
	is_on_screen_ui:  bool,
	is_on_world_ui:   bool,
}

_scene_create :: proc(scene: ^Scene) {
	scene.camera = q.DEFAULT_CAMERA
}

_scene_destroy :: proc(scene: ^Scene) {
	delete(scene.tritex_meshes)
	delete(scene.meshes_3d)
	delete(scene.meshes_3d_hex_chunk_masked)

	delete(scene.cutout_sprites)
	delete(scene.transparent_sprites_low)

	delete(scene.world_ui)
	delete(scene.transparent_sprites_high)
	delete(scene.shine_sprites)
	delete(scene.screen_ui)

	delete(scene.last_frame_colliders)
	delete(scene.colliders)
	delete(scene.skinned_render_commands)
	delete(scene.motion_particles_draw_commands)
	delete(scene.annotations)
	delete(scene.hex_chunks)
	delete(scene.display_values)
}

_scene_clear :: proc(scene: ^Scene) {
	clear(&scene.tritex_meshes)
	clear(&scene.meshes_3d)
	clear(&scene.meshes_3d_hex_chunk_masked)

	clear(&scene.cutout_sprites)
	clear(&scene.transparent_sprites_low)

	clear(&scene.world_ui)
	clear(&scene.transparent_sprites_high)
	clear(&scene.shine_sprites)
	clear(&scene.screen_ui)

	// swap with last frame to still raycast against them:
	scene.last_frame_colliders, scene.colliders = scene.colliders, scene.last_frame_colliders
	clear(&scene.colliders)
	clear(&scene.skinned_render_commands)
	clear(&scene.motion_particles_draw_commands)
	clear(&scene.annotations)
	clear(&scene.hex_chunks)
	clear(&scene.display_values)
}

// global singleton
ENGINE: Engine

// after creating the engine, let it be pinned, don't move it in memory!!
_engine_create :: proc(engine: ^Engine, settings: EngineSettings) {

	assert(settings.screen_ui_reference_size.x > 0)
	assert(settings.screen_ui_reference_size.y > 0)
	engine.settings = settings
	platform := &engine.platform
	q.platform_create(platform, settings.platform)
	engine.ui_ctx = q.ui_ctx_create(platform)
	q.set_global_ui_ctx_ptr(&engine.ui_ctx)
	_scene_create(&engine.scene)

	q.bloom_renderer_create(&engine.bloom_renderer, platform)
	q.gizmos_renderer_create(&engine.gizmos_renderer, platform)
	q.color_mesh_renderer_create(&engine.color_mesh_renderer, platform)
	q.mesh_2d_renderer_create(&engine.mesh_2d_renderer, platform)


	reg := &platform.shader_registry
	device := platform.device
	queue := platform.queue
	p := &engine.pipelines
	p[.HexChunk] = q.make_render_pipeline(reg, q.hex_chunk_pipeline_config(device))
	p[.SpriteSimple] = q.make_render_pipeline(reg, q.sprite_pipeline_config(device, .Simple))
	p[.SpriteCutout] = q.make_render_pipeline(reg, q.sprite_pipeline_config(device, .Cutout))
	p[.SpriteShine] = q.make_render_pipeline(reg, q.sprite_pipeline_config(device, .Shine))
	p[.SpriteTransparent] = q.make_render_pipeline(reg, q.sprite_pipeline_config(device, .Transparent))
	p[.Mesh3d] = q.make_render_pipeline(reg, q.mesh_3d_pipeline_config(device))
	p[.Mesh3dHexChunkMasked] = q.make_render_pipeline(reg, q.mesh_3d_hex_chunk_masked_pipeline_config(device))
	p[.SkinnedCutout] = q.make_render_pipeline(reg, q.skinned_pipeline_config(device))
	p[.Tritex] = q.make_render_pipeline(reg, q.tritex_mesh_pipeline_config(device))
	p[.ScreenUiGlyph] = q.make_render_pipeline(reg, q.ui_glyph_pipeline_config(device, .Screen))
	p[.ScreenUiRect] = q.make_render_pipeline(reg, q.ui_rect_pipeline_config(device, .Screen))
	p[.WorldUiGlyph] = q.make_render_pipeline(reg, q.ui_glyph_pipeline_config(device, .World))
	p[.WorldUiRect] = q.make_render_pipeline(reg, q.ui_rect_pipeline_config(device, .World))
	p[.MotionParticles] = q.make_render_pipeline(reg, q.motion_particles_pipeline_config(device))


	engine.cutout_sprites = sprite_buffers_create(device, queue)
	engine.shine_sprites = sprite_buffers_create(device, queue)
	engine.transparent_sprites_low = sprite_buffers_create(device, queue)
	engine.transparent_sprites_high = sprite_buffers_create(device, queue)

	engine.world_ui_buffers = q.ui_render_buffers_create(device, queue)
	engine.screen_ui_buffers = q.ui_render_buffers_create(device, queue)

	q.dynamic_buffer_init(&engine.motion_particles_buffer, {.Vertex}, device, queue)
}
_engine_destroy :: proc(engine: ^Engine) {
	q.platform_destroy(&engine.platform)
	q.bloom_renderer_destroy(&engine.bloom_renderer)
	q.gizmos_renderer_destroy(&engine.gizmos_renderer)
	q.color_mesh_renderer_destroy(&engine.color_mesh_renderer)
	q.mesh_2d_renderer_destroy(&engine.mesh_2d_renderer)
	_scene_destroy(&engine.scene)
	q.set_global_ui_ctx_ptr(nil)
	q.ui_ctx_drop(&engine.ui_ctx)

	sprite_buffers_destroy(&engine.cutout_sprites)
	sprite_buffers_destroy(&engine.shine_sprites)
	sprite_buffers_destroy(&engine.transparent_sprites_low)
	sprite_buffers_destroy(&engine.transparent_sprites_high)

	q.ui_render_buffers_destroy(&engine.world_ui_buffers)
	q.ui_render_buffers_destroy(&engine.screen_ui_buffers)

	q.dynamic_buffer_destroy(&engine.motion_particles_buffer)
	delete(engine.motion_particles_render_commands)
	delete(engine.top_level_elements_scratch)
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
	q.ui_ctx_start_frame(&engine.platform, engine.hit.hit_pos)
	_engine_recalculate_ui_hit_info(engine)
	return true
}

_engine_recalculate_hit_info :: proc(engine: ^Engine) {
	hit_pos := q.screen_to_world_pos(engine.scene.camera, engine.platform.cursor_pos, engine.platform.screen_size_f32)

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
	engine.hit.hit_pos = hit_pos
	engine.hit.hit_collider = hit_collider
	engine.hit.hit_collider_idx = hit_collider_idx
}
_engine_recalculate_ui_hit_info :: proc(engine: ^Engine) {
	hovered_id := engine.ui_ctx.cache.state.hovered
	engine.hit.is_on_world_ui = false
	engine.hit.is_on_screen_ui = false
	if hovered_id != 0 {
		cached_element := engine.ui_ctx.cache.cached[hovered_id]
		switch cached_element.transform.space {
		case .Screen:
			engine.hit.is_on_screen_ui = true
		case .World:
			engine.hit.is_on_world_ui = true
		}
	}
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
	_display_values(engine.scene.display_values[:])

	// PREPARE
	_engine_prepare(engine)

	// RENDER
	_engine_render(engine)
	// CLEAR
	_scene_clear(&engine.scene)
	free_all(context.temp_allocator)
}

_engine_prepare :: proc(engine: ^Engine) {
	scene := &engine.scene
	q.platform_prepare(&engine.platform, scene.camera)
	q.assert_ui_ctx_ptr_is_set()
	clear(&engine.top_level_elements_scratch)
	for e in scene.world_ui {
		q.layout_in_world_space(
			e.ui,
			e.world_pos,
			q.WORLD_UI_UNIT_TRANSFORM,
			engine.platform.settings.world_ui_px_per_unit,
		)
		append(
			&engine.top_level_elements_scratch,
			q.TopLevelElement{e.ui, q.UiTransform{space = .World, data = {world_transform = e.transform}}},
		)
	}
	for ui in scene.screen_ui {
		q.layout_in_screen_space(ui, engine.platform.ui_layout_extent)
		append(
			&engine.top_level_elements_scratch,
			q.TopLevelElement{ui, q.UiTransform{space = .Screen, data = {clipped_to = nil}}},
		)
	}
	// q.ui_update_ui_cache_end_of_frame_after_layout_before_batching(engine.platform.delta_secs)
	q.ui_render_buffers_batch_and_prepare(
		&engine.world_ui_buffers,
		engine.top_level_elements_scratch[:len(scene.world_ui)],
	)
	q.ui_render_buffers_batch_and_prepare(
		&engine.screen_ui_buffers,
		engine.top_level_elements_scratch[len(scene.world_ui):],
	)

	q.color_mesh_renderer_prepare(&engine.color_mesh_renderer)
	q.mesh_2d_renderer_prepare(&engine.mesh_2d_renderer)
	q.gizmos_renderer_prepare(&engine.gizmos_renderer)

	sprite_buffers_batch_and_prepare(&engine.cutout_sprites, scene.cutout_sprites[:])
	sprite_buffers_batch_and_prepare(&engine.shine_sprites, scene.shine_sprites[:])
	sprite_buffers_batch_and_prepare(&engine.transparent_sprites_low, scene.transparent_sprites_low[:])
	sprite_buffers_batch_and_prepare(&engine.transparent_sprites_high, scene.transparent_sprites_high[:])
	// for the skinned mesh renderer, we currently let the user 
	// do updates directly with `update_skinned_mesh_bones``


	// schedule buffer writes for all submitted slices of particles to be written to a single instance buffer
	clear(&engine.motion_particles_render_commands)
	n_particles := 0
	for cmd in scene.motion_particles_draw_commands {
		n_particles += len(cmd.particles)
	}
	q.dynamic_buffer_clear(&engine.motion_particles_buffer)
	q.dynamic_buffer_reserve(&engine.motion_particles_buffer, n_particles)
	first_instance: u32 = 0
	for cmd in scene.motion_particles_draw_commands {
		instance_count := u32(len(cmd.particles))
		append(
			&engine.motion_particles_render_commands,
			q.MotionParticlesRenderCommand {
				texture = cmd.texture,
				first_instance = first_instance,
				instance_count = instance_count,
				flipbook = cmd.flipbook,
			},
		)
		first_instance += instance_count
		q.dynamic_buffer_append_no_resize(&engine.motion_particles_buffer, cmd.particles)
	}
}

_engine_render :: proc(engine: ^Engine) {
	// get surface texture view:
	surface_view, command_encoder := q.platform_start_render(&engine.platform)

	// hdr render pass:
	hdr_pass := q.platform_start_hdr_pass(engine.platform, command_encoder)
	global_bind_group := engine.platform.globals.bind_group
	asset_manager := engine.platform.asset_manager

	for pipeline in engine.pipelines {
		assert(pipeline != nil)
	}

	q.hex_chunks_render(
		engine.pipelines[.HexChunk].pipeline,
		hdr_pass,
		global_bind_group,
		engine.scene.tritex_textures,
		engine.scene.hex_chunks[:],
		asset_manager,
	)
	q.tritex_mesh_render(
		engine.pipelines[.Tritex].pipeline,
		hdr_pass,
		global_bind_group,
		engine.scene.tritex_meshes[:],
		engine.scene.tritex_textures,
		asset_manager,
	)
	q.mesh_3d_renderer_render(
		engine.pipelines[.Mesh3d].pipeline,
		hdr_pass,
		global_bind_group,
		engine.scene.meshes_3d[:],
		asset_manager,
	)
	q.mesh_3d_renderer_render_hex_chunk_masked(
		engine.pipelines[.Mesh3dHexChunkMasked].pipeline,
		hdr_pass,
		global_bind_group,
		engine.scene.meshes_3d_hex_chunk_masked[:],
		asset_manager,
	)

	simple_sprite_shader := engine.settings.use_simple_sprite_shader
	q.sprite_batches_render(
		engine.pipelines[.SpriteSimple if simple_sprite_shader else .SpriteCutout].pipeline,
		engine.cutout_sprites.batches[:],
		engine.cutout_sprites.instance_buffer,
		hdr_pass,
		global_bind_group,
		asset_manager,
	)
	// todo: this is certainly stupid, because then we render all skinned meshes on top of sprites:
	q.skinned_mesh_render(
		engine.pipelines[.SkinnedCutout].pipeline,
		engine.scene.skinned_render_commands[:],
		hdr_pass,
		global_bind_group,
		asset_manager,
	)
	q.motion_particles_render(
		engine.pipelines[.MotionParticles].pipeline,
		engine.motion_particles_buffer,
		engine.motion_particles_render_commands[:],
		hdr_pass,
		global_bind_group,
		asset_manager,
	)
	q.mesh_2d_renderer_render(&engine.mesh_2d_renderer, hdr_pass, global_bind_group, asset_manager)
	q.color_mesh_renderer_render(&engine.color_mesh_renderer, hdr_pass, global_bind_group)

	// sandwich the world ui, e.g. health bars in two layers of transparent sprites + cutout sprites on top:
	q.sprite_batches_render(
		engine.pipelines[.SpriteTransparent].pipeline,
		engine.transparent_sprites_low.batches[:],
		engine.transparent_sprites_low.instance_buffer,
		hdr_pass,
		global_bind_group,
		asset_manager,
	)
	q.ui_render(
		engine.world_ui_buffers,
		engine.pipelines[.WorldUiRect].pipeline,
		engine.pipelines[.WorldUiGlyph].pipeline,
		hdr_pass,
		global_bind_group,
		engine.platform.settings.screen_ui_reference_size,
		engine.platform.screen_size,
		asset_manager,
	)
	q.sprite_batches_render(
		engine.pipelines[.SpriteTransparent].pipeline,
		engine.transparent_sprites_high.batches[:],
		engine.transparent_sprites_high.instance_buffer,
		hdr_pass,
		global_bind_group,
		asset_manager,
	)
	q.sprite_batches_render(
		engine.pipelines[.SpriteShine].pipeline,
		engine.shine_sprites.batches[:],
		engine.shine_sprites.instance_buffer,
		hdr_pass,
		global_bind_group,
		asset_manager,
	)
	// Solution 1: batch sprites and skinned meshes together, and then switching pipelines based on the current batch
	// Solution 2: use depth writes for at least one of the two and render that first.
	// 
	// also consider, that we might need a second "shine through" skinned shader for stuff behind geometry.

	q.gizmos_renderer_render(&engine.gizmos_renderer, hdr_pass, global_bind_group, .WORLD)
	q.ui_render(
		engine.screen_ui_buffers,
		engine.pipelines[.ScreenUiRect].pipeline,
		engine.pipelines[.ScreenUiGlyph].pipeline,
		hdr_pass,
		global_bind_group,
		engine.platform.settings.screen_ui_reference_size,
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

	q.platform_end_render(&engine.platform, surface_view, command_encoder)
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
		switch v.space {
		case .Screen:
			q.gizmos_renderer_add_aabb(&engine.gizmos_renderer, {v.pos, v.pos + v.size}, color, .UI)
		case .World:
			pos := Vec2{v.pos.x, -v.pos.y} / engine.settings.world_ui_px_per_unit
			size := Vec2{v.size.x, -v.size.y} / engine.settings.world_ui_px_per_unit
			a := pos
			b := pos + Vec2{0, size.y}
			c := pos + size
			d := pos + Vec2{size.x, 0}
			trans := v.transform.data.world_transform
			if trans != q.WORLD_UI_UNIT_TRANSFORM {
				a = q.ui_world_transform_apply(trans, a)
				b = q.ui_world_transform_apply(trans, b)
				c = q.ui_world_transform_apply(trans, c)
				d = q.ui_world_transform_apply(trans, d)
			}
			q.gizmos_renderer_add_line(&engine.gizmos_renderer, a, b, color, .WORLD)
			q.gizmos_renderer_add_line(&engine.gizmos_renderer, b, c, color, .WORLD)
			q.gizmos_renderer_add_line(&engine.gizmos_renderer, c, d, color, .WORLD)
			q.gizmos_renderer_add_line(&engine.gizmos_renderer, d, a, color, .WORLD)
		}
	}
}


@(private)
_engine_debug_collider_gizmos :: proc(engine: ^Engine) {
	add_collider_gizmos :: #force_inline proc(rend: ^q.GizmosRenderer, shape: ^q.ColliderShape, color: Color) {
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
		add_collider_gizmos(&engine.gizmos_renderer, &collider.shape, color)
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
get_ui_layout_extent :: proc() -> Vec2 {
	return ENGINE.platform.ui_layout_extent
}
get_ui_cursor_pos :: proc() -> Vec2 {
	p, _ := q.ui_cursor_pos()
	return p
}
get_ui_id_hovered :: proc() -> q.UiId {
	return ENGINE.ui_ctx.cache.state.hovered
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
draw_mesh_3d :: proc(mesh: q.Mesh3d) {
	append(&ENGINE.scene.meshes_3d, mesh)
}
draw_mesh_3d_hex_chunk_masked :: proc(mesh: q.Mesh3d, hex_chunk_bind_group: wgpu.BindGroup) {
	append(&ENGINE.scene.meshes_3d_hex_chunk_masked, q.Mesh3dHexChunkMasked{mesh, hex_chunk_bind_group})
}
draw_hex_chunk :: proc(chunk: q.HexChunkUniform) {
	append(&ENGINE.scene.hex_chunks, chunk)
}
create_hex_chunk :: proc(chunk_pos: [2]i32) -> q.HexChunkUniform {
	return q.hex_chunk_uniform_create(ENGINE.platform.device, ENGINE.platform.queue, chunk_pos)
}
destroy_hex_chunk :: proc(hex_chunk: ^q.HexChunkUniform) {
	q.hex_chunk_uniform_destroy(hex_chunk)
}
create_skinned_mesh :: proc(
	triangles: []q.Triangle,
	vertices: []q.SkinnedVertex,
	bone_count: int,
	texture: q.TextureHandle = q.DEFAULT_TEXTURE,
) -> q.SkinnedMeshHandle {
	return q.skinned_mesh_register(&ENGINE.platform.asset_manager, triangles, vertices, bone_count, texture)
}
destroy_skinned_mesh :: proc(handle: q.SkinnedMeshHandle) {
	q.skinned_mesh_deregister(&ENGINE.platform.asset_manager, handle)
}
// call this with a slice of bone transforms that has the same length as what the skinned mesh expects
set_skinned_mesh_bones :: proc(handle: q.SkinnedMeshHandle, bones: []q.Affine2) {
	q.skinned_mesh_update_bones(&ENGINE.platform.asset_manager, handle, bones)
}
draw_skinned_mesh :: proc(handle: q.SkinnedMeshHandle, pos: Vec2 = Vec2{0, 0}, color: Color = q.ColorWhite) {
	append(&ENGINE.scene.skinned_render_commands, q.SkinnedRenderCommand{pos, color, handle})
}
// expected to be 8bit RGBA png
load_texture :: proc(path: string, settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA) -> q.TextureHandle {
	return q.assets_load_texture(&ENGINE.platform.asset_manager, path, settings)
}
create_texture_from_image :: proc(img: q.Image) -> q.TextureHandle {
	texture := q.texture_from_image(ENGINE.platform.device, ENGINE.platform.queue, img, q.TEXTURE_SETTINGS_RGBA)
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
load_texture_tile :: proc(path: string, settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA) -> q.TextureTile {
	return q.TextureTile{load_texture(path, settings), q.UNIT_AABB}
}
load_texture_as_sprite :: proc(path: string, settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA) -> q.Sprite {
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
	append(&ENGINE.scene.cutout_sprites, sprite)
}
draw_shine_sprite :: #force_inline proc(sprite: q.Sprite) {
	append(&ENGINE.scene.shine_sprites, sprite)
}
// if high, above world ui layer (e.g. health bars), else below
draw_transparent_sprite :: #force_inline proc(sprite: q.Sprite, above_world_ui: bool = false) {
	buffer := &ENGINE.scene.transparent_sprites_high if above_world_ui else &ENGINE.scene.transparent_sprites_low
	append(buffer, sprite)
}
// above world ui layer (e.g. health bars)


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
	q.gizmos_renderer_add_circle(&ENGINE.gizmos_renderer, center, radius, color, segments, draw_inner_lines, .WORLD)
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
access_mesh_2d_write_buffers :: #force_inline proc(
) -> (
	vertices: ^[dynamic]q.Mesh2dVertex,
	triangles: ^[dynamic]q.Triangle,
	start: u32,
) {
	vertices = &ENGINE.mesh_2d_renderer.vertices
	triangles = &ENGINE.mesh_2d_renderer.triangles
	start = u32(len(vertices))
	return
}
set_current_mesh_2d_texture :: proc(texture: q.TextureHandle) {
	q.mesh_2d_renderer_set_texture(&ENGINE.mesh_2d_renderer, texture)
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
draw_color_mesh_indexed_single_color :: proc(positions: []Vec2, triangles: []q.Triangle, color := Color{1, 0, 0, 1}) {
	q.color_mesh_add_indexed_single_color(&ENGINE.color_mesh_renderer, positions, triangles, color)
}
add_ui :: proc(ui: q.Ui) {
	append(&ENGINE.scene.screen_ui, ui)
}
add_world_ui :: proc(world_pos: Vec2, ui: q.Ui) {
	append(&ENGINE.scene.world_ui, UiAtWorldPos{ui, world_pos, q.WORLD_UI_UNIT_TRANSFORM})
}
add_world_ui_at_transform :: proc(transform: q.UiWorldTransform, ui: q.Ui) {
	append(&ENGINE.scene.world_ui, UiAtWorldPos{ui, Vec2{0, 0}, transform})
}
add_ui_next_to_world_point :: proc(
	world_pos: Vec2,
	ui: Ui,
	px_offset: Vec2 = {0, 0},
	additional_flags: q.DivFlags = q.DivFlags{.MainAlignCenter},
) {
	screen_size := get_screen_size_f32()
	screen_pos := q.world_to_screen_pos(get_camera(), world_pos, screen_size)
	screen_unit_pos := screen_pos / screen_size
	flags := q.DivFlags{.Absolute, .ZeroSizeButInfiniteSizeForChildren} + additional_flags
	at_ptr := div(Div{flags = flags, absolute_unit_pos = screen_unit_pos, offset = px_offset})
	add_ui(at_ptr)
	child(at_ptr, ui)
}

add_circle_collider :: proc(center: Vec2, radius: f32, metadata: q.ColliderMetadata, z: int) {
	append(&ENGINE.scene.colliders, q.Collider{shape = q.Circle{center, radius}, metadata = metadata, z = z})
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
access_shader_globals_xxx :: proc() -> ^[4]f32 {
	return &ENGINE.platform.globals_xxx
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
get_arrows :: proc() -> (res: Vec2) {
	keys := ARROW_KEYS
	dirs := [4]Vec2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	for key, idx in keys {
		if .Pressed in ENGINE.platform.keys[key] {
			res += dirs[idx]
		}
	}
	return res
}

ARROW_KEYS :: [4]q.Key{.LEFT, .RIGHT, .DOWN, .UP}
WASD_KEYS :: [4]q.Key{.A, .D, .S, .W}

get_arrows_just_pressed_or_repeated :: proc(keys := ARROW_KEYS) -> (res: IVec2) {
	dirs := [4]IVec2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	for key, idx in keys {
		flags := ENGINE.platform.keys[key]
		if .JustPressed in flags || .JustRepeated in flags {
			res += dirs[idx]
		}
	}
	return res
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
display_value :: proc(values: ..any, label: string = "") {
	append(&ENGINE.scene.display_values, DisplayValue{label = label, value = fmt.tprint(..values)})
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

	screen_size := engine.platform.screen_size_f32
	camera := engine.scene.camera
	half_cam_world_size := Vec2{camera.height * screen_size.x / screen_size.y, camera.height} / 2
	margin := Vec2{1, 1}
	// todo: maybe use this culling technique also elsewhere, e.g. for skinned meshes????
	culling_aabb := q.Aabb {
		min = camera.focus_pos - half_cam_world_size - margin,
		max = camera.focus_pos + half_cam_world_size + margin,
	}
	for ann in engine.scene.annotations {
		// cull points that are likely offscreen anyway
		if !q.aabb_contains(culling_aabb, ann.pos) {
			continue
		}
		// red_box := child_div(div_at_pt, q.RED_BOX_DIV)

		ui := text(
		Text {
			color     = ann.color,
			shadow    = 0.5,
			font_size = ann.font_size, // because UI layout assumes screen is 1080 px in height
			str       = ann.str,
		},
		)
		add_world_ui(ann.pos, ui)
	}
}

_MotionParticleDrawCommand :: struct {
	particles: []q.MotionParticleInstance,
	flipbook:  q.FlipbookData,
	texture:   q.MotionTextureHandle,
}
draw_motion_particles :: proc(
	particles: []q.MotionParticleInstance,
	flipbook: q.FlipbookData,
	texture: q.MotionTextureHandle,
) {
	append(&ENGINE.scene.motion_particles_draw_commands, _MotionParticleDrawCommand{particles, flipbook, texture})
}
