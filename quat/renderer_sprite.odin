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
	device:                wgpu.Device,
	queue:                 wgpu.Queue,
	pipeline:              RenderPipeline,
	batches:               [dynamic]SpriteBatch,
	instances:             [dynamic]SpriteInstance,
	instance_buffer:       DynamicBuffer(SpriteInstance),
	depth_pipeline:        RenderPipeline,
	depth_batches:         [dynamic]SpriteBatch,
	depth_instances:       [dynamic]SpriteInstance,
	depth_instance_buffer: DynamicBuffer(SpriteInstance),
}

sprite_renderer_prepare :: proc(
	rend: ^SpriteRenderer,
	sprites: []Sprite,
	depth_sprites: []Sprite,
) {
	_sort_and_batch_sprites(sprites, &rend.batches, &rend.instances)
	_sort_and_batch_sprites(depth_sprites, &rend.depth_batches, &rend.depth_instances)
	dynamic_buffer_write(&rend.instance_buffer, rend.instances[:], rend.device, rend.queue)
	dynamic_buffer_write(
		&rend.depth_instance_buffer,
		rend.depth_instances[:],
		rend.device,
		rend.queue,
	)
}

sprite_renderer_render :: proc(
	rend: ^SpriteRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	assets: AssetManager,
) {
	if len(rend.depth_batches) > 0 {
		wgpu.RenderPassEncoderSetPipeline(render_pass, rend.depth_pipeline.pipeline)
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass,
			0,
			rend.depth_instance_buffer.buffer,
			0,
			rend.depth_instance_buffer.size,
		)
		for batch in rend.depth_batches {
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

	if len(rend.batches) > 0 {
		wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass,
			0,
			rend.instance_buffer.buffer,
			0,
			rend.instance_buffer.size,
		)
		for batch in rend.batches {
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

}

sprite_renderer_destroy :: proc(rend: ^SpriteRenderer) {
	delete(rend.batches)
	delete(rend.instances)
	render_pipeline_destroy(&rend.pipeline)
	render_pipeline_destroy(&rend.depth_pipeline)
	dynamic_buffer_destroy(&rend.instance_buffer)
	dynamic_buffer_destroy(&rend.depth_instance_buffer)
}

sprite_renderer_create :: proc(rend: ^SpriteRenderer, platform: ^Platform) {
	rend.device = platform.device
	rend.queue = platform.queue
	rend.instance_buffer.usage = {.Vertex}
	rend.depth_instance_buffer.usage = {.Vertex}
	rend.pipeline.config = sprite_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.pipeline, &platform.shader_registry)
	rend.depth_pipeline.config = depth_sprite_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.depth_pipeline, &platform.shader_registry)
}

sprite_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "sprite_standard",
		vs_shader = "sprite",
		vs_entry_point = "vs_main",
		fs_shader = "sprite",
		fs_entry_point = "fs_main",
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
		depth = DEPTH_IGNORE,
	}
}


depth_sprite_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "depth_sprite",
		vs_shader = "sprite",
		vs_entry_point = "vs_depth",
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
