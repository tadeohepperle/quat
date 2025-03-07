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
ui_render_buffers_create :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> (
	this: UiRenderBuffers,
) {
	dynamic_buffer_init(&this.vertex_buffer, {.Vertex}, device, queue)
	dynamic_buffer_init(&this.index_buffer, {.Index}, device, queue)
	dynamic_buffer_init(&this.glyph_instance_buffer, {.Vertex}, device, queue)
	return this
}
ui_render_buffers_destroy :: proc(this: ^UiRenderBuffers) {
	ui_batches_drop(this)
	dynamic_buffer_destroy(&this.vertex_buffer)
	dynamic_buffer_destroy(&this.index_buffer)
	dynamic_buffer_destroy(&this.glyph_instance_buffer)
}

ui_render_buffers_batch_and_prepare :: proc(
	this: ^UiRenderBuffers,
	top_level_elements: []Ui,
	is_world_ui: bool,
) {
	build_ui_batches_and_attach_z_info(top_level_elements, this, is_world_ui)
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
	assets: AssetManager,
) {
	screen_size_f32 := Vec2{f32(screen_size.x), f32(screen_size.y)}
	if len(buffers.batches) == 0 {
		return
	}
	last_kind := buffers.batches[0].kind
	last_clipped_to: Maybe(Aabb) = Aabb{} // no batch will have this, so the first batch already fulfills batch.clipped_to != last_clipped_to
	pipeline: wgpu.RenderPipeline = nil
	for &batch in buffers.batches {
		if batch.clipped_to != last_clipped_to {
			if clipped_to, ok := batch.clipped_to.(Aabb); ok {
				// convert clipping rect from layout to screen space and then set it:
				min_f32 := layout_to_screen_space(
					clipped_to.min,
					screen_reference_size,
					screen_size_f32,
				)
				max_f32 := layout_to_screen_space(
					clipped_to.max,
					screen_reference_size,
					screen_size_f32,
				)
				min_x := min(u32(min_f32.x), screen_size.x)
				min_y := min(u32(min_f32.y), screen_size.x)
				max_x := min(u32(max_f32.x), screen_size.x)
				max_y := min(u32(max_f32.y), screen_size.x)
				wgpu.RenderPassEncoderSetScissorRect(
					render_pass,
					min_x,
					min_y,
					max_x - min_x,
					max_y - min_y,
				)
			} else {
				// remove scissor
				wgpu.RenderPassEncoderSetScissorRect(
					render_pass,
					0,
					0,
					screen_size.x,
					screen_size.y,
				)
			}
		}

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
		}
		switch batch.kind {
		case .Rect:
			texture_bind_group := assets_get_texture_bind_group(
				assets,
				TextureHandle(batch.handle),
			)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_bind_group)
			// important: take *3 here to get from triangle_idx to index_idx
			start_idx := u32(batch.start_idx) * 3
			index_count := u32(batch.end_idx - batch.start_idx) * 3
			wgpu.RenderPassEncoderDrawIndexed(render_pass, index_count, 1, start_idx, 0, 0)
		case .Glyph:
			font_texture_bind_group := assets_get_font_texture_bind_group(
				assets,
				FontHandle(batch.handle),
			)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, font_texture_bind_group)
			instance_count := u32(batch.end_idx - batch.start_idx)
			wgpu.RenderPassEncoderDraw(render_pass, 4, instance_count, 0, u32(batch.start_idx))
		}
	}
	// remove scissor again after all batches are done if last batch was in scissor:
	if last_clipped_to != nil {
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

ui_rect_pipeline_config :: proc(device: wgpu.Device, in_world: bool) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "ui_rect",
		vs_shader = "ui",
		vs_entry_point = "vs_rect_world" if in_world else "vs_rect",
		fs_shader = "ui",
		fs_entry_point = "fs_rect_world" if in_world else "fs_rect",
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
			globals_bind_group_layout_cached(device),
			rgba_bind_group_layout_cached(device),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}


UiPushConstants :: struct {
	scale:  f32,
	offset: Vec2,
}
ui_glyph_pipeline_config :: proc(device: wgpu.Device, in_world: bool) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "ui_glyph",
		vs_shader = "ui",
		vs_entry_point = "vs_glyph_world" if in_world else "vs_glyph",
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
			globals_bind_group_layout_cached(device),
			rgba_bind_group_layout_cached(device),
		),
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}
