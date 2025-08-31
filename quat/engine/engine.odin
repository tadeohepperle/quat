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
Vec4 :: q.Vec4
Color :: q.Color
print :: q.print
GIZMOS_COLOR := q.Color{1, 0, 0, 1}

PLATFORM := &q.PLATFORM
EngineSettings :: struct {
	using platform:           q.PlatformSettings,
	bloom_enabled:            bool,
	bloom_settings:           q.BloomSettings,
	debug_ui_gizmos:          bool,
	debug_collider_gizmos:    bool,
	use_simple_sprite_shader: bool, // does not use the depth calculations
	screen_ui_reference_size: Vec2, // should be e.g. 1920x1080
	world_2d_ui_px_per_unit:  f32,
	tonemapping:              q.TonemappingMode,
}
DEFAULT_ENGINE_SETTINGS := EngineSettings {
	platform                 = q.PLATFORM_SETTINGS_DEFAULT,
	bloom_enabled            = true,
	bloom_settings           = q.BLOOM_SETTINGS_DEFAULT,
	debug_ui_gizmos          = false,
	debug_collider_gizmos    = true,
	screen_ui_reference_size = {1920, 1080},
	world_2d_ui_px_per_unit  = 100,
	tonemapping              = q.TonemappingMode.Disabled,
}

Pipeline :: ^q.RenderPipeline
Engine :: struct {
	settings:                         EngineSettings,
	hit:                              HitInfo,
	scene:                            Scene,
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
	screen_ui_batches:                q.UiBatches,
	screen_ui_buffers:                q.UiRenderBuffers,
	motion_particles_render_commands: [dynamic]q.MotionParticlesRenderCommand,
	motion_particles_buffer:          q.DynamicBuffer(q.MotionParticleInstance),
	top_level_elements_scratch:       [dynamic]q.TopLevelElement,
	ui_id_interaction:                q.InteractionState(q.UiId),
	ui_tag_interaction:               q.InteractionState(q.UiTag),
	screen_ui_layout_extent:          Vec2,
	camera_2d_uniform_data:           q.Camera2DUniformData,
	camera_2d_uniform:                q.UniformBuffer(q.Camera2DUniformData),
	frame_uniform_data:               q.FrameUniformData,
	frame_uniform:                    q.UniformBuffer(q.FrameUniformData),
}

SpriteBuffers :: struct {
	batches:         [dynamic]q.SpriteBatch,
	instances:       [dynamic]q.SpriteInstance,
	instance_buffer: q.DynamicBuffer(q.SpriteInstance),
}
sprite_buffers_create :: proc() -> (this: SpriteBuffers) {
	q.dynamic_buffer_init(&this.instance_buffer, {.Vertex})
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
	Tonemapping,
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

UiInWorld2D :: struct {
	ui:        q.Ui,
	transform: q.UiWorld2DTransform,
}

// roughly in render order
Scene :: struct {
	camera:                         q.Camera2D, // 2d camera
	// geometry:
	tritex_meshes:                  [dynamic]q.TritexMesh,
	tritex_textures:                q.TextureArrayHandle, // not owned! just set by the user.
	meshes_3d:                      [dynamic]q.Mesh3d,
	meshes_3d_hex_chunk_masked:     [dynamic]q.Mesh3dHexChunkMasked,
	// cutout discard shader depth rendering:
	cutout_sprites:                 [dynamic]q.Sprite,
	// transparency layer 1:
	transparent_sprites_low:        [dynamic]q.Sprite,
	uis_in_world_2d:                [dynamic]UiInWorld2D, // ui elements that are rendered below transparent sprites and shine sprites
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
	display_values:                 [dynamic]q.DisplayValue,
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

	delete(scene.uis_in_world_2d)
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

	clear(&scene.uis_in_world_2d)
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
	assert(!q.is_initialized())

	assert(settings.screen_ui_reference_size.x > 0)
	assert(settings.screen_ui_reference_size.y > 0)
	engine.settings = settings

	q.platform_init(settings.platform)
	q.ui_system_init()

	_scene_create(&engine.scene)

	q.bloom_renderer_create(&engine.bloom_renderer)
	q.gizmos_renderer_create(&engine.gizmos_renderer)
	q.color_mesh_renderer_create(&engine.color_mesh_renderer)
	q.mesh_2d_renderer_create(&engine.mesh_2d_renderer)

	p := &engine.pipelines
	// p[.HexChunk] = q.make_render_pipeline(q.hex_chunk_pipeline_config())
	// p[.SpriteSimple] = q.make_render_pipeline(q.sprite_pipeline_config(.Simple))
	// p[.SpriteCutout] = q.make_render_pipeline(q.sprite_pipeline_config(.Cutout))
	// p[.SpriteShine] = q.make_render_pipeline(q.sprite_pipeline_config(.Shine))
	// p[.SpriteTransparent] = q.make_render_pipeline(q.sprite_pipeline_config(.Transparent))
	// p[.Mesh3d] = q.make_render_pipeline(q.mesh_3d_pipeline_config())
	// p[.Mesh3dHexChunkMasked] = q.make_render_pipeline(q.mesh_3d_hex_chunk_masked_pipeline_config())
	// p[.SkinnedCutout] = q.make_render_pipeline(q.skinned_pipeline_config())
	// p[.Tritex] = q.make_render_pipeline(q.tritex_mesh_pipeline_config())
	p[.ScreenUiGlyph] = q.make_render_pipeline(q.ui_glyph_pipeline_config(.Screen))
	p[.ScreenUiRect] = q.make_render_pipeline(q.ui_rect_pipeline_config(.Screen))
	// p[.WorldUiGlyph] = q.make_render_pipeline(q.ui_glyph_pipeline_config(.World2D))
	// p[.WorldUiRect] = q.make_render_pipeline(q.ui_rect_pipeline_config(.World2D))
	// p[.MotionParticles] = q.make_render_pipeline(q.motion_particles_pipeline_config())
	p[.Tonemapping] = q.make_render_pipeline(q.tonemapping_pipeline_config())


	engine.cutout_sprites = sprite_buffers_create()
	engine.shine_sprites = sprite_buffers_create()
	engine.transparent_sprites_low = sprite_buffers_create()
	engine.transparent_sprites_high = sprite_buffers_create()

	engine.world_ui_buffers = q.ui_render_buffers_create()
	engine.screen_ui_buffers = q.ui_render_buffers_create()

	engine.frame_uniform_data = q.FrameUniformData{}
	engine.frame_uniform = q.uniform_buffer_create(q.FrameUniformData)
	engine.camera_2d_uniform_data = q.Camera2DUniformData{}
	engine.camera_2d_uniform = q.uniform_buffer_create(q.Camera2DUniformData)

	q.dynamic_buffer_init(&engine.motion_particles_buffer, {.Vertex})
}
_engine_destroy :: proc(engine: ^Engine) {

	q.bloom_renderer_destroy(&engine.bloom_renderer)
	q.gizmos_renderer_destroy(&engine.gizmos_renderer)
	q.color_mesh_renderer_destroy(&engine.color_mesh_renderer)
	q.mesh_2d_renderer_destroy(&engine.mesh_2d_renderer)
	_scene_destroy(&engine.scene)

	sprite_buffers_destroy(&engine.cutout_sprites)
	sprite_buffers_destroy(&engine.shine_sprites)
	sprite_buffers_destroy(&engine.transparent_sprites_low)
	sprite_buffers_destroy(&engine.transparent_sprites_high)

	q.ui_render_buffers_destroy(&engine.world_ui_buffers)
	q.ui_render_buffers_destroy(&engine.screen_ui_buffers)

	q.dynamic_buffer_destroy(&engine.motion_particles_buffer)
	delete(engine.motion_particles_render_commands)
	delete(engine.top_level_elements_scratch)

	q.ui_batches_drop(&engine.screen_ui_batches)

	q.uniform_buffer_destroy(&engine.camera_2d_uniform)
	q.uniform_buffer_destroy(&engine.frame_uniform)

	q.ui_system_deinit()
	q.platform_deinit()
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
	if !q.platform_start_frame() {
		return false
	}
	_engine_recalculate_hit_info(engine)
	q.ui_system_start_frame_clearing_arenas()


	screen_size := PLATFORM.screen_size
	cursor_pos := PLATFORM.cursor_pos

	engine.screen_ui_layout_extent = q.screen_to_layout_space(
		screen_size,
		engine.settings.screen_ui_reference_size,
		screen_size,
	)

	screen_layout_cursor_pos := q.screen_to_layout_space(
		cursor_pos,
		engine.settings.screen_ui_reference_size,
		screen_size,
	)
	world_2d_cursor_pos := q.screen_to_world_pos(engine.scene.camera, cursor_pos, screen_size)


	hovered_id, hovered_tag := q.ui_system_get_hovered_id_and_tag()
	left_press := PLATFORM.mouse_buttons[.Left]
	q.update_interaction_state(&engine.ui_id_interaction, hovered_id, left_press)
	q.update_interaction_state(&engine.ui_tag_interaction, hovered_tag, left_press)
	q.ui_system_set_user_vals(
		q.UiUserProvidedValues {
			delta_secs = PLATFORM.delta_secs,
			id_state = engine.ui_id_interaction,
			tag_state = engine.ui_tag_interaction,
			cursor_pos = PLATFORM.cursor_pos,
			screen_size = PLATFORM.screen_size,
		},
	)
	engine.hit.is_on_world_ui = false
	engine.hit.is_on_screen_ui = false
	if hovered_id != 0 {
		cached_info, ok := q.ui_get_cached_no_user_data(hovered_id)
		proj := q.ui_get_cached_projection(cached_info.proj_idx)
		switch _ in proj.projection {
		case q.UiScreenProjection:
			engine.hit.is_on_screen_ui = true
		case q.UiWorld2DProjection:
			engine.hit.is_on_world_ui = true
		case q.UiWorld3DProjection:
			unimplemented()
		}
	}

	return true
}

add_window :: proc(title: string, content: []q.Ui, window_width: f32 = 0) {
	add_ui(q.window_widget(title, content, window_width))
}

_engine_recalculate_hit_info :: proc(engine: ^Engine) {
	hit_pos := q.screen_to_world_pos(engine.scene.camera, PLATFORM.cursor_pos, PLATFORM.screen_size)

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


_engine_end_frame :: proc(engine: ^Engine) {
	// RESIZE AND END INPUT:
	if PLATFORM.screen_resized {
		q.bloom_renderer_resize(&engine.bloom_renderer, PLATFORM.screen_size_u)
	}
	// ADD SOME ADDITIONAL DRAW DATA:
	_engine_draw_annotations(engine)
	if engine.settings.debug_ui_gizmos {
		_engine_debug_ui_gizmos(engine)
	}
	if engine.settings.debug_collider_gizmos {
		_engine_debug_collider_gizmos(engine)
	}

	PLATFORM.settings = engine.settings.platform
	q.platform_reset_input_at_end_of_frame()

	if len(engine.scene.display_values) > 0 {
		add_ui(q.display_values_widget(engine.scene.display_values[:]))
	}

	// PREPARE
	_engine_prepare(engine)


	// print("batches: ")
	// for b, i in engine.screen_ui_batches.batches {
	// 	print(i, ":", b.kind, b.end_idx - b.start_idx)
	// }

	// RENDER
	_engine_render(engine)

	// CLEAR
	_scene_clear(&engine.scene)
	free_all(context.temp_allocator)
}

_engine_prepare :: proc(engine: ^Engine) {
	scene := &engine.scene
	q.platform_prepare()

	// prepare the globals bindgroup:
	engine.frame_uniform_data.screen_size = PLATFORM.screen_size
	engine.frame_uniform_data.cursor_pos = PLATFORM.cursor_pos
	engine.frame_uniform_data.space_pressed = q.is_key_pressed(.SPACE)
	engine.frame_uniform_data.ctrl_pressed = q.is_ctrl_pressed()
	engine.frame_uniform_data.shift_pressed = q.is_shift_pressed()
	engine.frame_uniform_data.alt_pressed = q.is_alt_pressed()

	engine.camera_2d_uniform_data = q.camera_2d_uniform_data(engine.scene.camera, PLATFORM.screen_size)
	q.uniform_buffer_write(&engine.camera_2d_uniform, &engine.camera_2d_uniform_data)
	q.uniform_buffer_write(&engine.frame_uniform, &engine.frame_uniform_data)


	// ui layout and rendering
	clear(&engine.top_level_elements_scratch)
	screen_projection := q.UiScreenProjection {
		reference_screen_size = engine.settings.screen_ui_reference_size,
		x_scaling_factor      = 0.0,
		clipped_to            = nil,
	}
	for ui in scene.screen_ui {
		append(&engine.top_level_elements_scratch, q.TopLevelElement{ui, screen_projection})
	}
	q.ui_system_layout_elements_and_build_batches(engine.top_level_elements_scratch[:], &engine.screen_ui_batches)
	q.ui_render_buffers_prepare(&engine.screen_ui_buffers, engine.screen_ui_batches)


	// todo! put world ui back in!
	// for e in scene.world_ui {
	// 	engine.top_level_elements_scratch
	// 	q.ui_system_layout_in_world_2d_space(
	// 		e.ui,
	// 		e.world_pos,
	// 		q.UI_UNIT_TRANSFORM_2D,
	// 		engine.settings.world_2d_ui_px_per_unit,
	// 	)
	// 	projection := q.UiWorld2DProjection {
	// 		transform = q.UI_UNIT_TRANSFORM_2D,
	// 	}
	// 	append(
	// 		&engine.top_level_elements_scratch,
	// 		q.TopLevelElement{e.ui, q.UiTransform{space = .World2D, data = {transform2d = e.transform}}},
	// 	)
	// }

	// q.ui_update_ui_cache_end_of_frame_after_layout_before_batching(engine.platform.delta_secs)
	// q.ui_render_buffers_batch_and_prepare(
	// 	&engine.world_ui_buffers,
	// 	engine.top_level_elements_scratch[:len(scene.world_ui)],
	// )


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
	surface_view, command_encoder := q.platform_start_render()

	// hdr render pass:
	hdr_pass := q.start_hdr_render_pass(
		command_encoder,
		PLATFORM.hdr_screen_texture,
		PLATFORM.depth_screen_texture,
		engine.settings.clear_color,
	)

	// todo!: reenable this check!
	// for pipeline in engine.pipelines {
	// 	assert(pipeline != nil)
	// }
	frame_uniform := engine.frame_uniform.bind_group
	camera_2d_uniform := engine.camera_2d_uniform.bind_group

	// q.hex_chunks_render(
	// 	engine.pipelines[.HexChunk].pipeline,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// 	engine.scene.tritex_textures,
	// 	engine.scene.hex_chunks[:],
	// )
	// q.tritex_mesh_render(
	// 	engine.pipelines[.Tritex].pipeline,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// 	engine.scene.tritex_meshes[:],
	// 	engine.scene.tritex_textures,
	// )
	// q.mesh_3d_renderer_render(
	// 	engine.pipelines[.Mesh3d].pipeline,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// 	engine.scene.meshes_3d[:],
	// )
	// q.mesh_3d_renderer_render_hex_chunk_masked(
	// 	engine.pipelines[.Mesh3dHexChunkMasked].pipeline,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// 	engine.scene.meshes_3d_hex_chunk_masked[:],
	// )

	simple_sprite_shader := engine.settings.use_simple_sprite_shader
	// q.sprite_batches_render(
	// 	engine.pipelines[.SpriteSimple if simple_sprite_shader else .SpriteCutout].pipeline,
	// 	engine.cutout_sprites.batches[:],
	// 	engine.cutout_sprites.instance_buffer,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// )
	// // todo: this is certainly stupid, because then we render all skinned meshes on top of sprites:
	// q.skinned_mesh_render(
	// 	engine.pipelines[.SkinnedCutout].pipeline,
	// 	engine.scene.skinned_render_commands[:],
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// )
	// q.motion_particles_render(
	// 	engine.pipelines[.MotionParticles].pipeline,
	// 	engine.motion_particles_buffer,
	// 	engine.motion_particles_render_commands[:],
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// )
	// q.mesh_2d_renderer_render(&engine.mesh_2d_renderer, hdr_pass, frame_uniform, camera_2d_uniform)
	// q.color_mesh_renderer_render(&engine.color_mesh_renderer, hdr_pass, frame_uniform, camera_2d_uniform)

	// // sandwich the world ui, e.g. health bars in two layers of transparent sprites + cutout sprites on top:
	// q.sprite_batches_render(
	// 	engine.pipelines[.SpriteTransparent].pipeline,
	// 	engine.transparent_sprites_low.batches[:],
	// 	engine.transparent_sprites_low.instance_buffer,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// )
	// q.ui_render(
	// 	engine.world_ui_buffers,
	// 	engine.pipelines[.WorldUiRect].pipeline,
	// 	engine.pipelines[.WorldUiGlyph].pipeline,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// 	engine.settings.screen_ui_reference_size,
	// 	PLATFORM.screen_size,
	// )
	// q.sprite_batches_render(
	// 	engine.pipelines[.SpriteTransparent].pipeline,
	// 	engine.transparent_sprites_high.batches[:],
	// 	engine.transparent_sprites_high.instance_buffer,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// )
	// q.sprite_batches_render(
	// 	engine.pipelines[.SpriteShine].pipeline,
	// 	engine.shine_sprites.batches[:],
	// 	engine.shine_sprites.instance_buffer,
	// 	hdr_pass,
	// 	frame_uniform,
	// 	camera_2d_uniform,
	// )
	// Solution 1: batch sprites and skinned meshes together, and then switching pipelines based on the current batch
	// Solution 2: use depth writes for at least one of the two and render that first.
	//
	// also consider, that we might need a second "shine through" skinned shader for stuff behind geometry.

	q.gizmos_renderer_render(&engine.gizmos_renderer, hdr_pass, frame_uniform, camera_2d_uniform, .WORLD)
	q.ui_screen_ui_render(
		engine.screen_ui_batches,
		engine.screen_ui_buffers,
		engine.pipelines[.ScreenUiRect].pipeline,
		engine.pipelines[.ScreenUiGlyph].pipeline,
		hdr_pass,
		frame_uniform,
		PLATFORM.screen_size_u,
	)
	q.gizmos_renderer_render(&engine.gizmos_renderer, hdr_pass, frame_uniform, camera_2d_uniform, .SCREEN)
	wgpu.RenderPassEncoderEnd(hdr_pass)
	wgpu.RenderPassEncoderRelease(hdr_pass)

	// bloom:
	if engine.settings.bloom_enabled {
		q.render_bloom(
			command_encoder,
			&engine.bloom_renderer,
			PLATFORM.hdr_screen_texture,
			frame_uniform,
			engine.settings.bloom_settings,
		)
	}

	q.tonemap(
		command_encoder,
		engine.pipelines[.Tonemapping].pipeline,
		PLATFORM.hdr_screen_texture,
		surface_view,
		engine.settings.tonemapping,
	)

	q.platform_end_render(surface_view, command_encoder)
}

@(private)
_engine_debug_ui_gizmos :: proc(engine: ^Engine) {
	cache, projections := q.ui_system_view_cache_and_projections()
	state := engine.ui_id_interaction

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
	last_state = state


	for k, v in cache {
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
		proj := projections[v.proj_idx]
		switch proj in proj.projection {
		case q.UiScreenProjection:
			scaling := q.ui_screen_projection_scaling_factor(proj, PLATFORM.screen_size)
			rect := q.Aabb{v.pos * scaling, (v.pos + v.size) * scaling}
			q.gizmos_renderer_add_aabb(&engine.gizmos_renderer, rect, color, .SCREEN)
		case q.UiWorld2DProjection:
		// todo!
		// pos := Vec2{v.pos.x, -v.pos.y} / engine.settings.world_2d_ui_px_per_unit
		// size := Vec2{v.size.x, -v.size.y} / engine.settings.world_2d_ui_px_per_unit
		// a := pos
		// b := pos + Vec2{0, size.y}
		// c := pos + size
		// d := pos + Vec2{size.x, 0}
		// trans := v.transform.data.transform2d
		// if trans != q.UI_UNIT_TRANSFORM_2D {
		// 	a = q.ui_transform_2d_apply(trans, a)
		// 	b = q.ui_transform_2d_apply(trans, b)
		// 	c = q.ui_transform_2d_apply(trans, c)
		// 	d = q.ui_transform_2d_apply(trans, d)
		// }
		// q.gizmos_renderer_add_line(&engine.gizmos_renderer, a, b, color, .WORLD)
		// q.gizmos_renderer_add_line(&engine.gizmos_renderer, b, c, color, .WORLD)
		// q.gizmos_renderer_add_line(&engine.gizmos_renderer, c, d, color, .WORLD)
		// q.gizmos_renderer_add_line(&engine.gizmos_renderer, d, a, color, .WORLD)
		case q.UiWorld3DProjection:
			unimplemented()
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
	return PLATFORM.mouse_buttons[btn]
}
// returns nil if no files dropped into window this frame, returned strings are only valid until end of frame
get_dropped_file_paths :: proc() -> []string {
	return PLATFORM.dropped_file_paths
}
get_scroll :: proc() -> f32 {
	return PLATFORM.scroll
}
// characters typed this frame
get_input_chars :: proc() -> []rune {
	return PLATFORM.chars[:PLATFORM.chars_len]
}
get_hit :: #force_inline proc() -> HitInfo {
	return ENGINE.hit
}
get_hit_pos :: proc() -> Vec2 {
	return ENGINE.hit.hit_pos
}
get_osc :: proc(speed: f32 = 1, amplitude: f32 = 1, bias: f32 = 0, phase: f32 = 0) -> f32 {
	return math.sin_f32(PLATFORM.total_secs * speed + phase) * amplitude + bias
}
get_ui_layout_extent :: proc() -> Vec2 {
	return ENGINE.screen_ui_layout_extent
}
get_ui_id_hovered :: proc() -> q.UiId {
	return ENGINE.ui_id_interaction.hovered
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
	return q.hex_chunk_uniform_create(PLATFORM.device, PLATFORM.queue, chunk_pos)
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
	return q.skinned_mesh_register(triangles, vertices, bone_count, texture)
}
destroy_skinned_mesh :: proc(handle: q.SkinnedMeshHandle) {
	q.skinned_mesh_deregister(handle)
}
// call this with a slice of bone transforms that has the same length as what the skinned mesh expects
set_skinned_mesh_bones :: proc(handle: q.SkinnedMeshHandle, bones: []q.Affine2) {
	q.skinned_mesh_update_bones(handle, bones)
}
draw_skinned_mesh :: proc(handle: q.SkinnedMeshHandle, pos: Vec2 = Vec2{0, 0}, color: Color = q.ColorWhite) {
	append(&ENGINE.scene.skinned_render_commands, q.SkinnedRenderCommand{pos, color, handle})
}
// expected to be 8bit RGBA png
load_texture_from_path :: proc(
	path: string,
	settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA,
) -> q.TextureHandle {
	texture, err := q.texture_from_image_path(path, settings)
	if err, has_err := err.(string); has_err {
		panic(err)
	}
	return q.assets_insert(texture)
}
create_texture_from_image :: proc(img: q.Image) -> q.TextureHandle {
	texture := q.texture_from_image(img, q.TEXTURE_SETTINGS_RGBA)
	return q.assets_insert(texture)
}
get_texture_info :: proc(handle: q.TextureHandle) -> q.TextureInfo {
	return q.assets_get(handle).info
}
write_image_to_texture :: proc(img: q.Image, handle: q.TextureHandle) {
	texture := q.assets_get(handle)
	q.texture_write_from_image(texture, img)
}
// is expected to be 16bit R channel only png
load_depth_texture :: proc(path: string) -> q.TextureHandle {
	depth_texture, err := q.depth_texture_16bit_r_from_image_path(path)
	if err, has_err := err.(string); has_err {
		panic(err)
	}
	return q.assets_insert(depth_texture)
}
load_texture :: proc(path: string, settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA) -> q.TextureHandle {
	texture, err := q.texture_from_image_path(path, settings)
	if err, has_err := err.(string); has_err {
		panic(err)
	}
	return q.assets_insert(texture)
}
load_texture_tile :: proc(path: string, settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA) -> q.TextureTile {
	return q.TextureTile{load_texture(path, settings), q.UNIT_AABB}
}
load_texture_as_sprite :: proc(path: string, settings: q.TextureSettings = q.TEXTURE_SETTINGS_RGBA) -> q.Sprite {
	texture_handle := load_texture(path, settings)
	texture_tile := q.TextureTile{texture_handle, q.UNIT_AABB}
	texture_info := q.assets_get(texture_handle).info
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
add_world_ui :: proc(world_pos: Vec2, ui: q.Ui, scale: Vec2 = {1, 1}, rotation: f32 = 0) {
	basis_x := Vec2{1 / ENGINE.settings.world_2d_ui_px_per_unit, 0} * scale
	if rotation != 0 {
		basis_x = q.rotate_2d(basis_x, rotation)
	}
	transform := q.UiWorld2DTransform {
		pos     = world_pos,
		basis_x = basis_x,
		z       = 0.0,
	}
	append(&ENGINE.scene.uis_in_world_2d, UiInWorld2D{ui, transform})
}
add_ui_next_to_world_point :: proc(
	world_pos: Vec2,
	ui: q.Ui,
	px_offset: Vec2 = {0, 0},
	additional_flags: q.DivFlags = q.DivFlags{.MainAlignCenter},
) {
	screen_size := q.get_screen_size()
	screen_pos := q.world_to_screen_pos(get_camera(), world_pos, screen_size)
	screen_unit_pos := screen_pos / screen_size
	flags := q.DivFlags{.Absolute, .ZeroSizeButInfiniteSizeForChildren} + additional_flags
	at_ptr := q.div(q.Div{flags = flags, absolute_unit_pos = screen_unit_pos, offset = px_offset})
	add_ui(at_ptr)
	q.ui_add_child(at_ptr, ui)
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
set_camera :: proc(camera: q.Camera2D) {
	ENGINE.scene.camera = camera
	_engine_recalculate_hit_info(&ENGINE) // todo! probably not appropriate??
}
access_shader_globals_xxx :: proc() -> ^Vec4 {
	return &ENGINE.frame_uniform_data.xxx
}
set_tritex_textures :: proc(textures: q.TextureArrayHandle) {
	ENGINE.scene.tritex_textures = textures
}
get_camera :: proc() -> q.Camera2D {
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
	ENGINE.settings.tonemapping = mode
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
display_value :: proc(values: ..any, label: string = "") {
	append(&ENGINE.scene.display_values, q.DisplayValue{label = label, value = fmt.tprint(..values)})
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

	screen_size := PLATFORM.screen_size
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

		ui := q.text(
		q.Text {
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


get_default_font_line_metrics :: proc() -> q.LineMetrics {
	return q.assets_get(q.DEFAULT_FONT).line_metrics
}

set_default_font_line_metrics :: proc(line_metrics: q.LineMetrics) {
	font: ^q.Font = q.assets_get_ref(q.DEFAULT_FONT)
	font.line_metrics = line_metrics
}
