package quat

import "core:slice"
import wgpu "vendor:wgpu"


Sprite :: struct {
	z:        i32,
	texture:  TextureTile,
	pos:      Vec2,
	size:     Vec2,
	rotation: f32,
	color:    Color,
}

SpriteInstance :: struct {
	pos:      Vec2,
	size:     Vec2,
	color:    Color,
	uv:       Aabb,
	rotation: f32,
}

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

	slice.sort_by(sprites, proc(a, b: Sprite) -> bool {
		if a.z < b.z {
			return true
		} else if a.z == b.z {
			return a.pos.y > b.pos.y
		} else {
			return false
		}
	})

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
	device:          wgpu.Device,
	queue:           wgpu.Queue,
	pipeline:        RenderPipeline,
	batches:         [dynamic]SpriteBatch,
	instances:       [dynamic]SpriteInstance,
	instance_buffer: DynamicBuffer(SpriteInstance),
}

sprite_renderer_prepare :: proc(rend: ^SpriteRenderer, sprites: []Sprite) {
	_sort_and_batch_sprites(sprites, &rend.batches, &rend.instances)
	dynamic_buffer_write(&rend.instance_buffer, rend.instances[:], rend.device, rend.queue)
}

sprite_renderer_render :: proc(
	rend: ^SpriteRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	assets: AssetManager,
) {

	if len(rend.batches) == 0 {
		return
	}
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

sprite_renderer_destroy :: proc(rend: ^SpriteRenderer) {
	delete(rend.batches)
	delete(rend.instances)
	render_pipeline_destroy(&rend.pipeline)
	dynamic_buffer_destroy(&rend.instance_buffer)
}

sprite_renderer_create :: proc(rend: ^SpriteRenderer, platform: ^Platform) {
	rend.device = platform.device
	rend.queue = platform.queue
	rend.instance_buffer.usage = {.Vertex}
	rend.pipeline.config = sprite_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.pipeline, &platform.shader_registry)
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
			},
		},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
	}
}
