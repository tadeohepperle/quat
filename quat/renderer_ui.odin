package quat

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:os"

import wgpu "vendor:wgpu"

UiRenderer :: struct {
	device:                wgpu.Device,
	queue:                 wgpu.Queue,
	rect_pipeline:         RenderPipeline,
	glyph_pipeline:        RenderPipeline,
	batches:               UiBatches,
	vertex_buffer:         DynamicBuffer(UiVertex),
	index_buffer:          DynamicBuffer(u32),
	glyph_instance_buffer: DynamicBuffer(UiGlyphInstance),
}

ui_renderer_render :: proc(
	rend: ^UiRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_bind_group: wgpu.BindGroup,
	screen_size: UVec2,
	assets: AssetManager,
) {
	screen_size_f32 := Vec2{f32(screen_size.x), f32(screen_size.y)}
	if len(rend.batches.batches) == 0 {
		return
	}
	last_kind := rend.batches.batches[0].kind
	pipeline: ^RenderPipeline = nil
	for &batch in rend.batches.batches {
		if batch.kind != last_kind || pipeline == nil {
			last_kind = batch.kind
			switch batch.kind {
			case .Rect:
				pipeline = &rend.rect_pipeline
			case .Glyph:
				pipeline = &rend.glyph_pipeline
			}


			if clipped_to, ok := batch.clipped_to.(Aabb); ok {
				// convert clipping rect from layout to screen space and then set it:
				min_f32 := layout_to_screen_space(clipped_to.min, screen_size_f32)
				max_f32 := layout_to_screen_space(clipped_to.max, screen_size_f32)
				min_x := u32(min_f32.x)
				min_y := u32(min_f32.y)
				width_x := u32(max_f32.x) - min_x
				width_y := u32(max_f32.y) - min_y
				wgpu.RenderPassEncoderSetScissorRect(render_pass, min_x, min_y, width_x, width_y)
			} else {
				wgpu.RenderPassEncoderSetScissorRect(
					render_pass,
					0,
					0,
					screen_size.x,
					screen_size.y,
				)
			}
			wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline.pipeline)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_bind_group)
			switch batch.kind {
			case .Rect:
				wgpu.RenderPassEncoderSetVertexBuffer(
					render_pass,
					0,
					rend.vertex_buffer.buffer,
					0,
					u64(rend.vertex_buffer.size),
				)

				wgpu.RenderPassEncoderSetIndexBuffer(
					render_pass,
					rend.index_buffer.buffer,
					.Uint32,
					0,
					u64(rend.index_buffer.size),
				)
			case .Glyph:
				wgpu.RenderPassEncoderSetVertexBuffer(
					render_pass,
					0,
					rend.glyph_instance_buffer.buffer,
					0,
					u64(rend.glyph_instance_buffer.size),
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
			index_count := u32(batch.end_idx - batch.start_idx)
			wgpu.RenderPassEncoderDrawIndexed(
				render_pass,
				index_count,
				1,
				u32(batch.start_idx),
				0,
				0,
			)
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
}


screen_to_layout_space :: proc(pt: Vec2, screen_size: Vec2) -> Vec2 {
	return pt * (f32(SCREEN_REFERENCE_SIZE.y) / screen_size.y)
}

layout_to_screen_space :: proc(pt: Vec2, screen_size: Vec2) -> Vec2 {
	return pt * (screen_size.y / f32(SCREEN_REFERENCE_SIZE.y))
}

ui_renderer_end_frame_and_prepare_buffers :: proc(
	rend: ^UiRenderer,
	delta_secs: f32,
	asset_manager: AssetManager,
) {
	dynamic_buffer_write(
		&rend.vertex_buffer,
		rend.batches.primitives.vertices[:],
		rend.device,
		rend.queue,
	)
	dynamic_buffer_write(
		&rend.index_buffer,
		rend.batches.primitives.indices[:],
		rend.device,
		rend.queue,
	)
	dynamic_buffer_write(
		&rend.glyph_instance_buffer,
		rend.batches.primitives.glyphs_instances[:],
		rend.device,
		rend.queue,
	)
}

ui_renderer_create :: proc(
	rend: ^UiRenderer,
	platform: ^Platform,
	default_font_color: Color,
	default_font_size: f32,
) {
	rend.device = platform.device
	rend.queue = platform.queue
	rend.rect_pipeline.config = ui_rect_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.rect_pipeline, &platform.shader_registry)
	rend.glyph_pipeline.config = ui_glyph_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.glyph_pipeline, &platform.shader_registry)

	rend.vertex_buffer.usage = {.Vertex}
	rend.index_buffer.usage = {.Index}
	rend.glyph_instance_buffer.usage = {.Vertex}

	return
}

ui_rect_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "ui_rect",
		vs_shader = "ui",
		vs_entry_point = "vs_rect",
		fs_shader = "ui",
		fs_entry_point = "fs_rect",
		topology = .TriangleList,
		vertex = {
			ty_id = UiVertex,
			attributes = {
				{format = .Float32x2, offset = offset_of(UiVertex, pos)},
				{format = .Float32x2, offset = offset_of(UiVertex, size)},
				{format = .Float32x2, offset = offset_of(UiVertex, uv)},
				{format = .Float32x4, offset = offset_of(UiVertex, color)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_color)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_radius)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_width)},
				{format = .Uint32, offset = offset_of(UiVertex, flags)},
			},
		},
		instance = {},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}

ui_glyph_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "ui_glyph",
		vs_shader = "ui",
		vs_entry_point = "vs_glyph",
		fs_shader = "ui",
		fs_entry_point = "fs_glyph",
		topology = .TriangleStrip,
		vertex = {},
		instance = {
			ty_id = UiGlyphInstance,
			attributes = {
				{format = .Float32x2, offset = offset_of(UiGlyphInstance, pos)},
				{format = .Float32x2, offset = offset_of(UiGlyphInstance, size)},
				{format = .Float32x4, offset = offset_of(UiGlyphInstance, uv)},
				{format = .Float32x4, offset = offset_of(UiGlyphInstance, color)},
				{format = .Float32, offset = offset_of(UiGlyphInstance, shadow)},
			},
		},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
		depth = DEPTH_IGNORE,
	}
}

ui_renderer_destroy :: proc(rend: ^UiRenderer) {
	ui_batches_destroy(&rend.batches)
	render_pipeline_destroy(&rend.rect_pipeline)
	render_pipeline_destroy(&rend.glyph_pipeline)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
	dynamic_buffer_destroy(&rend.glyph_instance_buffer)
}

ui_batches_destroy :: proc(batches: ^UiBatches) {
	delete(batches.primitives.vertices)
	delete(batches.primitives.indices)
	delete(batches.primitives.glyphs_instances)
	delete(batches.batches)
}
