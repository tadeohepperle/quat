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
	using _:               UiBatches,
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
	ui_batches_drop(this)
	dynamic_buffer_destroy(&this.vertex_buffer)
	dynamic_buffer_destroy(&this.index_buffer)
	dynamic_buffer_destroy(&this.glyph_instance_buffer)
}

ui_render_buffers_batch_and_prepare :: proc(this: ^UiRenderBuffers, top_level_elements: []TopLevelElement) {
	ui_system_build_batches(top_level_elements, this)
	// for b in this.batches {
	// 	print(b)
	// 	if b.transform.space == .World {
	// 		print("     W: ", b.transform.data.world_transform)
	// 	}
	// }
	dynamic_buffer_write(&this.vertex_buffer, this.primitives.vertices[:])
	dynamic_buffer_write(&this.index_buffer, this.primitives.triangles[:])
	dynamic_buffer_write(&this.glyph_instance_buffer, this.primitives.glyphs_instances[:])
}

ui_render :: proc(
	buffers: UiRenderBuffers,
	rect_pipeline: wgpu.RenderPipeline,
	glyph_pipeline: wgpu.RenderPipeline,
	render_pass: wgpu.RenderPassEncoder,
	globals_bind_group: wgpu.BindGroup,
	screen_reference_size: Vec2,
	screen_size: UVec2,
) {
	screen_size_f32 := Vec2{f32(screen_size.x), f32(screen_size.y)}
	if len(buffers.batches) == 0 {
		return
	}
	last_kind := buffers.batches[0].kind
	last_transform := UiTransform{.Screen, {clipped_to = nil}} // no batch will have this, so the first batch already fulfills batch.clipped_to != last_clipped_to
	pipeline: wgpu.RenderPipeline = nil
	last_clipped_to: Maybe(Aabb) = nil


	textures := assets_get_map(Texture)
	fonts := assets_get_map(Font)

	for &batch in buffers.batches {
		set_world_transform_push_const := false
		if batch.kind != last_kind || pipeline == nil {
			last_kind = batch.kind
			switch batch.kind {
			case .Rect:
				pipeline = rect_pipeline
			case .Glyph:
				pipeline = glyph_pipeline
			}
			wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_bind_group)

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
			if batch.transform.space == .World2D {
				set_world_transform_push_const = true
			}
		}

		if batch.transform != last_transform {
			if batch.transform.space == .World2D {
				set_world_transform_push_const = true
			}

			last_transform = batch.transform
			clipped_to: Maybe(Aabb) = nil
			if batch.transform.space == .Screen {
				clipped_to = batch.transform.data.clipped_to
			}
			if clipped_to != last_clipped_to {
				last_clipped_to = clipped_to
				if clipped_to, ok := clipped_to.(Aabb); ok {
					// convert clipping rect from layout to screen space and then set it:
					min_f32 := layout_to_screen_space(clipped_to.min, screen_reference_size, screen_size_f32)
					max_f32 := layout_to_screen_space(clipped_to.max, screen_reference_size, screen_size_f32)
					min_x := min(u32(min_f32.x), screen_size.x)
					min_y := min(u32(min_f32.y), screen_size.x)
					max_x := min(u32(max_f32.x), screen_size.x)
					max_y := min(u32(max_f32.y), screen_size.x)
					wgpu.RenderPassEncoderSetScissorRect(render_pass, min_x, min_y, max_x - min_x, max_y - min_y)
				} else {
					// remove scissor
					wgpu.RenderPassEncoderSetScissorRect(render_pass, 0, 0, screen_size.x, screen_size.y)
				}
			}
		}
		if set_world_transform_push_const {
			wgpu.RenderPassEncoderSetPushConstants(
				render_pass,
				{.Vertex},
				0,
				size_of(UiTransform2d),
				&batch.transform.data.transform2d,
			)
		}

		switch batch.kind {
		case .Rect:
			texture_bind_group := slotmap_get(textures, transmute(TextureHandle)batch.handle).bind_group
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_bind_group)
			// important: take *3 here to get from triangle_idx to index_idx
			start_idx := u32(batch.start_idx) * 3
			index_count := u32(batch.end_idx - batch.start_idx) * 3
			wgpu.RenderPassEncoderDrawIndexed(render_pass, index_count, 1, start_idx, 0, 0)
		case .Glyph:
			texture_handle := slotmap_get(fonts, transmute(FontHandle)batch.handle).texture_handle
			font_texture_bind_group := slotmap_get(textures, texture_handle).bind_group
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, font_texture_bind_group)
			instance_count := u32(batch.end_idx - batch.start_idx)
			wgpu.RenderPassEncoderDraw(render_pass, 4, instance_count, 0, u32(batch.start_idx))
		}
	}
	// remove scissor again after all batches are done if last batch was in scissor:
	if last_transform.space == .World2D || last_transform.data.clipped_to == nil {
		// remove scissor
		wgpu.RenderPassEncoderSetScissorRect(render_pass, 0, 0, screen_size.x, screen_size.y)
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
		bind_group_layouts = bind_group_layouts(globals_bind_group_layout_cached(), rgba_bind_group_layout_cached()),
		push_constant_ranges = push_const_ranges(wgpu.PushConstantRange{stages = {.Vertex}, start = 0, end = size_of(UiTransform2d)}) if space == .World2D else {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}


UiPushConstants :: struct {
	scale:  f32,
	offset: Vec2,
}
ui_glyph_pipeline_config :: proc(space: UiSpace) -> RenderPipelineConfig {
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
		bind_group_layouts = bind_group_layouts(globals_bind_group_layout_cached(), rgba_bind_group_layout_cached()),
		push_constant_ranges = push_const_ranges(wgpu.PushConstantRange{stages = {.Vertex}, start = 0, end = size_of(UiTransform2d)}) if space == .World2D else {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}
