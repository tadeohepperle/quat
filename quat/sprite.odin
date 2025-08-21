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

// SpriteGroup :: struct {
// 	texture:         Texture,
// 	y_for_sorting:   f32, // compared to pos.y of other sprites
// 	instances:       [dynamic]SpriteInstance,
// 	instance_buffer: DynamicBuffer(SpriteInstance),
// }

SpriteInstance :: struct {
	pos:      Vec2,
	size:     Vec2,
	color:    Color,
	uv:       Aabb,
	rotation: f32,
	z:        f32,
}

SpriteBatch :: struct {
	texture:   TextureHandle,
	start_idx: int,
	end_idx:   int,
	key:       u32,
}

sprites_sort_and_batch :: proc(
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
			return false
		} else if a.z == b.z {
			return a.pos.y > b.pos.y
		} else {
			return true
		}
	})

	append(
		batches,
		SpriteBatch {
			start_idx = 0,
			end_idx = 0,
			texture = sprites[0].texture.handle,
			key = _sprite_batch_key(sprites[0]),
		},
	)
	for &sprite in sprites {
		last_batch := &batches[len(batches) - 1]
		sprite_key := _sprite_batch_key(sprite)
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
_sprite_batch_key :: #force_inline proc(sprite: Sprite) -> u32 {
	return sprite.texture.handle.idx
}

sprite_batches_render :: proc(
	pipeline: wgpu.RenderPipeline,
	batches: []SpriteBatch,
	instance_buffer: DynamicBuffer(SpriteInstance),
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
) {
	if len(batches) == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, instance_buffer.buffer, 0, instance_buffer.size)
	textures := assets_get_map(Texture)
	for batch in batches {
		texture_bind_group := slotmap_get(textures, batch.texture).bind_group
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_bind_group)
		wgpu.RenderPassEncoderDraw(render_pass, 4, u32(batch.end_idx - batch.start_idx), 0, u32(batch.start_idx))
	}

}

SpriteKind :: enum {
	Cutout,
	Transparent,
	Shine,
	Simple,
}
@(rodata)
SPRITE_KIND_DEPTH := [SpriteKind]DepthConfig {
	.Cutout = {depth_write_enabled = true, depth_compare = .GreaterEqual},
	.Transparent = {depth_write_enabled = false, depth_compare = .GreaterEqual},
	.Shine = {depth_write_enabled = false, depth_compare = .Less},
	.Simple = DepthConfig{depth_write_enabled = false, depth_compare = .Always},
}
@(rodata)
SPRITE_KIND_FS_NAMES := [SpriteKind]string {
	.Cutout      = "fs_cutout",
	.Transparent = "fs_transparent",
	.Shine       = "fs_shine",
	.Simple      = "fs_simple",
}
@(rodata)
SPRITE_KIND_VS_NAMES := [SpriteKind]string {
	.Cutout      = "vs_depth",
	.Transparent = "vs_depth",
	.Shine       = "vs_depth",
	.Simple      = "vs_simple",
}
SPRITE_VERTEX_ATTRIBUTES := []VertAttibute {
	{format = .Float32x2, offset = offset_of(SpriteInstance, pos)},
	{format = .Float32x2, offset = offset_of(SpriteInstance, size)},
	{format = .Float32x4, offset = offset_of(SpriteInstance, color)},
	{format = .Float32x4, offset = offset_of(SpriteInstance, uv)},
	{format = .Float32, offset = offset_of(SpriteInstance, rotation)},
	{format = .Float32, offset = offset_of(SpriteInstance, z)},
}
sprite_pipeline_config :: proc(kind: SpriteKind) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "sprite",
		vs_shader = "sprite",
		vs_entry_point = SPRITE_KIND_VS_NAMES[kind],
		fs_shader = "sprite",
		fs_entry_point = SPRITE_KIND_FS_NAMES[kind],
		topology = .TriangleStrip,
		vertex = {},
		instance = {ty_id = SpriteInstance, attributes = SPRITE_VERTEX_ATTRIBUTES},
		bind_group_layouts = bind_group_layouts(globals_bind_group_layout_cached(), rgba_bind_group_layout_cached()),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = SPRITE_KIND_DEPTH[kind],
	}
}
