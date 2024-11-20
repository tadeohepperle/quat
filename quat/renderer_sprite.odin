package quat

import "core:slice"
import wgpu "vendor:wgpu"


Sprite :: struct {
	pos:      Vec2,
	size:     Vec2,
	color:    Color,
	texture:  TextureTile,
	rotation: f32,
	z:        f32,
}

SpriteInstance :: struct {
	pos:      Vec2,
	size:     Vec2,
	color:    Color,
	uv:       Aabb,
	rotation: f32,
	z:        f32,
}

// is a depth sprite, the alpha channel value of 0 means transparency, while every other depth value betweeen 1 and 255
// is mapped to a depth range between -1 and 1 in the game world. This allows for depth sprites that use
// DepthSprite :: distinct Sprite

SpriteBatch :: struct {
	texture:   TextureHandle,
	start_idx: int,
	end_idx:   int,
	key:       u32,
}

@(private)
_sort_and_batch_sprites :: proc(
	sprites: []Sprite,
	batches: ^[dynamic]SpriteBatch,
	instances: ^[dynamic]SpriteInstance,
) {
	clear(batches)
	clear(instances)
	if len(sprites) == 0 {
		return
	}


	sprite_sort_fn := proc(a, b: Sprite) -> bool {
		if a.z < b.z {
			return false
		} else if a.z == b.z {
			return a.pos.y > b.pos.y
		} else {
			return true
		}
	}
	slice.sort_by(sprites, sprite_sort_fn)

	append(
		batches,
		SpriteBatch {
			start_idx = 0,
			end_idx = 0,
			texture = sprites[0].texture.handle,
			key = _sprite_batch_key(&sprites[0]),
		},
	)
	for &sprite in sprites {
		last_batch := &batches[len(batches) - 1]
		sprite_key := _sprite_batch_key(&sprite)
		if last_batch.key != sprite_key {
			last_batch.end_idx = len(instances)
			append(
				batches,
				SpriteBatch {
					start_idx = len(instances),
					end_idx = 0,
					texture = sprite.texture.handle,
					key = sprite_key,
				},
			)
		}
		append(
			instances,
			SpriteInstance {
				pos = sprite.pos,
				size = sprite.size,
				color = sprite.color,
				uv = sprite.texture.uv,
				rotation = sprite.rotation,
				z = sprite.z,
			},
		)
	}
	batches[len(batches) - 1].end_idx = len(instances)
}

@(private)
_sprite_batch_key :: #force_inline proc(sprite: ^Sprite) -> u32 {
	return u32(sprite.texture.handle)
}

SpriteRenderer :: struct {
	device:  wgpu.Device,
	queue:   wgpu.Queue,
	// renders depth sprites like walls and other parts of the environment.
	depth:   SpriteSubRenderer,
	// renders normal sprites, with single depth value per sprite, respecting the env depth, not writing depth themselves
	default: SpriteSubRenderer,
	// renders sprites only where depth is so high that default sprites would be hidden.
	shine:   SpriteSubRenderer,
}

// for depth_sprites, normal sprites and shine_on_top_sprites
SpriteSubRenderer :: struct {
	pipeline:        RenderPipeline,
	batches:         [dynamic]SpriteBatch,
	instances:       [dynamic]SpriteInstance,
	instance_buffer: DynamicBuffer(SpriteInstance),
}

_sub_renderer_prepare :: proc(
	sub: ^SpriteSubRenderer,
	sprites: []Sprite,
	device: wgpu.Device,
	queue: wgpu.Queue,
) {
	_sort_and_batch_sprites(sprites, &sub.batches, &sub.instances)
	dynamic_buffer_write(&sub.instance_buffer, sub.instances[:], device, queue)
}

sprite_renderer_prepare :: proc(
	rend: ^SpriteRenderer,
	depth_sprites: []Sprite,
	default_sprites: []Sprite,
	shine_sprites: []Sprite,
) {
	_sub_renderer_prepare(&rend.depth, depth_sprites, rend.device, rend.queue)
	_sub_renderer_prepare(&rend.default, default_sprites, rend.device, rend.queue)
	_sub_renderer_prepare(&rend.shine, shine_sprites, rend.device, rend.queue)
}

_sub_renderer_render :: proc(
	sub: ^SpriteSubRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	assets: AssetManager,
) {
	if len(sub.batches) == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, sub.pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		sub.instance_buffer.buffer,
		0,
		sub.instance_buffer.size,
	)
	for batch in sub.batches {
		texture_bind_group := assets_get_texture_bind_group(assets, batch.texture)
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_bind_group)
		wgpu.RenderPassEncoderDraw(
			render_pass,
			4,
			u32(batch.end_idx - batch.start_idx),
			0,
			u32(batch.start_idx),
		)
	}

}

sprite_renderer_render :: proc(
	rend: ^SpriteRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	assets: AssetManager,
) {
	_sub_renderer_render(&rend.depth, render_pass, globals_uniform_bind_group, assets)
	_sub_renderer_render(&rend.default, render_pass, globals_uniform_bind_group, assets)
	_sub_renderer_render(&rend.shine, render_pass, globals_uniform_bind_group, assets)

}

_sub_renderer_destroy :: proc(sub: ^SpriteSubRenderer) {
	delete(sub.batches)
	delete(sub.instances)
	render_pipeline_destroy(&sub.pipeline)
	dynamic_buffer_destroy(&sub.instance_buffer)
}

sprite_renderer_destroy :: proc(rend: ^SpriteRenderer) {
	_sub_renderer_destroy(&rend.depth)
	_sub_renderer_destroy(&rend.default)
	_sub_renderer_destroy(&rend.shine)
}

_sub_renderer_create :: proc(
	sub: ^SpriteSubRenderer,
	shader_registry: ^ShaderRegistry,
	config: RenderPipelineConfig,
) {
	sub.instance_buffer.usage = {.Vertex}
	sub.pipeline.config = config
	render_pipeline_create_panic(&sub.pipeline, shader_registry)
}

sprite_renderer_create :: proc(rend: ^SpriteRenderer, platform: ^Platform) {
	device := platform.device
	globals := platform.globals.bind_group_layout
	rend.device = platform.device
	rend.queue = platform.queue

	_sub_renderer_create(
		&rend.depth,
		&platform.shader_registry,
		sprite_depth_pipeline_config(device, globals),
	)
	_sub_renderer_create(
		&rend.default,
		&platform.shader_registry,
		sprite_default_pipeline_config(device, globals),
	)
	_sub_renderer_create(
		&rend.shine,
		&platform.shader_registry,
		sprite_shine_pipeline_config(device, globals),
	)
}

sprite_default_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "sprite_default",
		vs_shader = "sprite",
		vs_entry_point = "vs_all",
		fs_shader = "sprite",
		fs_entry_point = "fs_default",
		topology = .TriangleStrip,
		vertex = {},
		instance = {
			ty_id = SpriteInstance,
			attributes = {
				{format = .Float32x2, offset = offset_of(SpriteInstance, pos)},
				{format = .Float32x2, offset = offset_of(SpriteInstance, size)},
				{format = .Float32x4, offset = offset_of(SpriteInstance, color)},
				{format = .Float32x4, offset = offset_of(SpriteInstance, uv)},
				{format = .Float32, offset = offset_of(SpriteInstance, rotation)},
				{format = .Float32, offset = offset_of(SpriteInstance, z)},
			},
		},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DepthConfig{depth_write_enabled = false, depth_compare = .GreaterEqual},
	}
}

sprite_depth_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "sprite_depth",
		vs_shader = "sprite",
		vs_entry_point = "vs_all",
		fs_shader = "sprite",
		fs_entry_point = "fs_depth",
		topology = .TriangleStrip,
		vertex = {},
		instance = {
			ty_id = SpriteInstance,
			attributes = {
				{format = .Float32x2, offset = offset_of(SpriteInstance, pos)},
				{format = .Float32x2, offset = offset_of(SpriteInstance, size)},
				{format = .Float32x4, offset = offset_of(SpriteInstance, color)},
				{format = .Float32x4, offset = offset_of(SpriteInstance, uv)},
				{format = .Float32, offset = offset_of(SpriteInstance, rotation)},
				{format = .Float32, offset = offset_of(SpriteInstance, z)},
			},
		},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DepthConfig{depth_compare = .GreaterEqual, depth_write_enabled = true},
	}
}

sprite_shine_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "sprite_shine",
		vs_shader = "sprite",
		vs_entry_point = "vs_all",
		fs_shader = "sprite",
		fs_entry_point = "fs_shine",
		topology = .TriangleStrip,
		vertex = {},
		instance = {
			ty_id = SpriteInstance,
			attributes = {
				{format = .Float32x2, offset = offset_of(SpriteInstance, pos)},
				{format = .Float32x2, offset = offset_of(SpriteInstance, size)},
				{format = .Float32x4, offset = offset_of(SpriteInstance, color)},
				{format = .Float32x4, offset = offset_of(SpriteInstance, uv)},
				{format = .Float32, offset = offset_of(SpriteInstance, rotation)},
				{format = .Float32, offset = offset_of(SpriteInstance, z)},
			},
		},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DepthConfig{depth_write_enabled = false, depth_compare = .Less},
	}
}
