package quat

import wgpu "vendor:wgpu"
tonemapping_pipeline_config :: proc(device: wgpu.Device) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "tonemapping",
		vs_shader = "screen",
		vs_entry_point = "vs_main",
		fs_shader = "tonemapping",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {},
		instance = {},
		bind_group_layouts = {rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {
			wgpu.PushConstantRange {
				stages = {.Fragment},
				start = 0,
				end = size_of(TonemappingMode),
			},
		},
		blend = ALPHA_BLENDING,
		format = SURFACE_FORMAT,
	}
}

TonemappingMode :: enum u32 {
	Disabled = 0,
	Aces     = 1,
}

tonemap :: proc(
	command_encoder: wgpu.CommandEncoder,
	tonemapping_pipeline: wgpu.RenderPipeline,
	hdr_texture_bind_group: wgpu.BindGroup,
	sdr_texture_view: wgpu.TextureView,
	mode: TonemappingMode,
) {
	tonemap_pass := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&wgpu.RenderPassDescriptor {
			label = "surface render pass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = sdr_texture_view,
				resolveTarget = nil,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = wgpu.Color{0.2, 0.3, 0.4, 1.0},
			},
			depthStencilAttachment = nil,
			occlusionQuerySet = nil,
			timestampWrites = nil,
		},
	)
	defer wgpu.RenderPassEncoderRelease(tonemap_pass)

	wgpu.RenderPassEncoderSetPipeline(tonemap_pass, tonemapping_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(tonemap_pass, 0, hdr_texture_bind_group)
	push_constants := mode
	wgpu.RenderPassEncoderSetPushConstants(
		tonemap_pass,
		{.Fragment},
		0,
		size_of(TonemappingMode),
		&push_constants,
	)
	wgpu.RenderPassEncoderDraw(tonemap_pass, 3, 1, 0, 0)

	wgpu.RenderPassEncoderEnd(tonemap_pass)
}
