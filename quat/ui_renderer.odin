package quat

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:os"

import wgpu "vendor:wgpu"

UiRenderBuffers :: struct {
	vertex_buffer:         DynamicBuffer(UiVertex),
	index_buffer:          DynamicBuffer(Triangle),
	glyph_instance_buffer: DynamicBuffer(UiGlyphInstance),
}
ui_render_buffers_create :: proc() -> (this: UiRenderBuffers) {
	dynamic_buffer_init(&this.vertex_buffer, {.Vertex})
	dynamic_buffer_init(&this.index_buffer, {.Index})
	dynamic_buffer_init(&this.glyph_instance_buffer, {.Vertex})
	return this
}
ui_render_buffers_destroy :: proc(this: ^UiRenderBuffers) {
	dynamic_buffer_destroy(&this.vertex_buffer)
	dynamic_buffer_destroy(&this.index_buffer)
	dynamic_buffer_destroy(&this.glyph_instance_buffer)
}

ui_render_buffers_prepare :: proc(this: ^UiRenderBuffers, batches: UiBatches) {
	dynamic_buffer_write(&this.vertex_buffer, batches.primitives.vertices[:])
	dynamic_buffer_write(&this.index_buffer, batches.primitives.triangles[:])
	dynamic_buffer_write(&this.glyph_instance_buffer, batches.primitives.glyphs_instances[:])
}

ui_screen_ui_render :: proc(
	batches: UiBatches,
	buffers: UiRenderBuffers,
	rect_pipeline: wgpu.RenderPipeline,
	glyph_pipeline: wgpu.RenderPipeline,
	render_pass: wgpu.RenderPassEncoder,
	frame_uniform: wgpu.BindGroup,
	screen_size_u: UVec2,
) {
	if len(batches.batches) == 0 {
		return
	}
	ui_batches_debug_print(batches)

	screen_size := batches.screen_size

	last_batch_kind: BatchKind = BatchKind(255) // illegal value
	last_scaling_factor := max(f32)
	last_scissor: Maybe([4]u32) = nil
	pipeline: wgpu.RenderPipeline = nil

	textures := assets_get_map(Texture)
	fonts := assets_get_map(Font)

	for &batch, i in batches.batches {

		proj := batches.projections[batch.proj_idx]
		screen_proj := proj.(UiScreenProjection) or_else panic("only UiScreenProjection expected")
		scaling_factor := ui_screen_projection_scaling_factor(screen_proj, screen_size)
		// fmt.printfln("batch {}, scaling factor: {}", i, scaling_factor)

		// set the render pipeline and buffers:
		if batch.kind != last_batch_kind || pipeline == nil {
			last_batch_kind = batch.kind
			switch batch.kind {
			case .Rect:
				pipeline = rect_pipeline
			case .Glyph:
				pipeline = glyph_pipeline
			}
			wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, frame_uniform)

			switch batch.kind {
			case .Rect:
				wgpu.RenderPassEncoderSetVertexBuffer(
					render_pass,
					0,
					buffers.vertex_buffer.buffer,
					0,
					u64(buffers.vertex_buffer.size),
				)
				wgpu.RenderPassEncoderSetIndexBuffer(
					render_pass,
					buffers.index_buffer.buffer,
					.Uint32,
					0,
					u64(buffers.index_buffer.size),
				)
			case .Glyph:
				wgpu.RenderPassEncoderSetVertexBuffer(
					render_pass,
					0,
					buffers.glyph_instance_buffer.buffer,
					0,
					u64(buffers.glyph_instance_buffer.size),
				)
			}
		}

		// set the scaling factor as push constant:
		// if last_scaling_factor != scaling_factor {
		// 	last_scaling_factor = scaling_factor

		// }

		wgpu.RenderPassEncoderSetPushConstants(render_pass, {.Vertex, .Fragment}, 0, size_of(f32), &scaling_factor)

		// set or remove clipping rect via scissor:
		if clipping_rect, ok := batch.clipping_rect.(Aabb); ok {
			min_f32 := clipping_rect.min * scaling_factor
			max_f32 := clipping_rect.max * scaling_factor
			min_x := min(u32(min_f32.x), screen_size_u.x)
			min_y := min(u32(min_f32.y), screen_size_u.x)
			max_x := min(u32(max_f32.x), screen_size_u.x)
			max_y := min(u32(max_f32.y), screen_size_u.x)
			scissor := [4]u32{min_x, min_y, max_x, max_y}
			if scissor != last_scissor {
				last_scissor = scissor
				wgpu.RenderPassEncoderSetScissorRect(render_pass, min_x, min_y, max_x - min_x, max_y - min_y)
			}
		} else if last_scissor != nil {
			// remove scissor
			last_scissor = nil
			wgpu.RenderPassEncoderSetScissorRect(render_pass, 0, 0, screen_size_u.x, screen_size_u.y)
		}


		texture_or_font := u32(batch.texture_or_font_idx)
		switch batch.kind {
		case .Rect:
			texture_bind_group := slotmap_get(textures, transmute(TextureHandle)texture_or_font).bind_group
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_bind_group)
			// important: take *3 here to get from triangle_idx to index_idx
			start_idx := u32(batch.start_idx) * 3
			index_count := u32(batch.end_idx - batch.start_idx) * 3
			wgpu.RenderPassEncoderDrawIndexed(render_pass, index_count, 1, start_idx, 0, 0)
		case .Glyph:
			texture_handle := slotmap_get(fonts, transmute(FontHandle)texture_or_font).texture_handle
			font_texture_bind_group := slotmap_get(textures, texture_handle).bind_group
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, font_texture_bind_group)
			instance_count := u32(batch.end_idx - batch.start_idx)
			wgpu.RenderPassEncoderDraw(render_pass, 4, instance_count, 0, u32(batch.start_idx))
		}
	}

	// remove last scissor if still set, to not affect following render pipelines
	if last_scissor != nil {
		wgpu.RenderPassEncoderSetScissorRect(render_pass, 0, 0, screen_size_u.x, screen_size_u.y)
	}
}

screen_to_layout_space :: proc(pt: Vec2, screen_reference_size: Vec2, screen_size: Vec2) -> Vec2 {
	return pt * (f32(screen_reference_size.y) / screen_size.y)
}

layout_to_screen_space :: proc(pt: Vec2, screen_reference_size: Vec2, screen_size: Vec2) -> Vec2 {
	return pt * (screen_size.y / f32(screen_reference_size.y))
}

ui_rect_pipeline_config :: proc(space: UiSpace) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "ui_rect",
		vs_shader = "ui",
		vs_entry_point = "vs_rect_world" if space == .World2D else "vs_rect",
		fs_shader = "ui",
		fs_entry_point = "fs_rect_world" if space == .World2D else "fs_rect",
		topology = .TriangleList,
		vertex = {
			ty_id = UiVertex,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(UiVertex, pos)},
				{format = .Float32x2, offset = offset_of(UiVertex, size)},
				{format = .Float32x2, offset = offset_of(UiVertex, uv)},
				{format = .Float32x4, offset = offset_of(UiVertex, color)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_color)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_radius)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_width)},
				{format = .Uint32, offset = offset_of(UiVertex, flags)},
			),
		},
		instance = {},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			// uniform_bind_group_layout_cached(Camera2DUniformData),
			rgba_bind_group_layout_cached(),
		),
		push_constant_ranges = push_const_range(f32, {.Vertex, .Fragment}),
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}

// ScreenUiPushConst :: struct {
// 	a: Vec4,
// 	b: Vec4,
// 	c: Vec4,
// 	d: Vec4,
// }

ui_glyph_pipeline_config :: proc(space: UiSpace) -> RenderPipelineConfig {
	// todo! support 3d!

	// todo! add linear scaling for px per height by depth!!!
	return RenderPipelineConfig {
		debug_name = "ui_glyph",
		vs_shader = "ui",
		vs_entry_point = "vs_glyph_world" if space == .World2D else "vs_glyph",
		fs_shader = "ui",
		fs_entry_point = "fs_glyph",
		topology = .TriangleStrip,
		vertex = {},
		instance = {
			ty_id = UiGlyphInstance,
			attributes = vert_attributes(
				{format = .Float32x2, offset = offset_of(UiGlyphInstance, pos)},
				{format = .Float32x2, offset = offset_of(UiGlyphInstance, size)},
				{format = .Float32x4, offset = offset_of(UiGlyphInstance, uv)},
				{format = .Float32x4, offset = offset_of(UiGlyphInstance, color)},
				{format = .Float32x2, offset = offset_of(UiGlyphInstance, shadow_and_bias)},
			),
		},
		bind_group_layouts = bind_group_layouts(
			uniform_bind_group_layout_cached(FrameUniformData),
			// uniform_bind_group_layout_cached(Camera2DUniformData),
			rgba_bind_group_layout_cached(),
		),
		// scaling factor or matrix
		push_constant_ranges = push_const_range(f32, {.Vertex, .Fragment}),
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}
