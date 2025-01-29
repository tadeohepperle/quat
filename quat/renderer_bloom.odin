package quat

import wgpu "vendor:wgpu"

N_BLOOM_TEXTURES :: 9

BloomPipelineKind :: enum {
	FirstDownsample,
	Downsample,
	Upsample,
	FinalUpsample,
}

BloomSettings :: struct {
	blend_factor: f64,
}

BLOOM_SETTINGS_DEFAULT :: BloomSettings {
	blend_factor = 0.1,
	// TODO: add values that are currently hardcoded in bloom shader
}

BloomRenderer :: struct {
	device:                    wgpu.Device,
	queue:                     wgpu.Queue,
	first_downsample_pipeline: RenderPipeline,
	downsample_pipeline:       RenderPipeline,
	upsample_pipeline:         RenderPipeline,
	final_upsample_pipeline:   RenderPipeline,
	textures:                  [N_BLOOM_TEXTURES]Maybe(Texture), // is none, if it would be too small to matter, that means, once one is nil all textures after it also nil
}

bloom_renderer_destroy :: proc(rend: ^BloomRenderer) {
	render_pipeline_destroy(&rend.first_downsample_pipeline)
	render_pipeline_destroy(&rend.downsample_pipeline)
	render_pipeline_destroy(&rend.upsample_pipeline)
	render_pipeline_destroy(&rend.final_upsample_pipeline)
	for &e in rend.textures {
		switch &tex in e {
		case Texture:
			texture_destroy(&tex)
		case:
		}
	}
}

bloom_renderer_create :: proc(rend: ^BloomRenderer, platform: ^Platform) {
	rend.device = platform.device
	rend.queue = platform.queue

	_create_bloom_textures(rend, platform.screen_size)


	bind_group_layouts := bind_group_layouts(
		platform.globals.bind_group_layout,
		rgba_bind_group_layout_cached(platform.device),
	)
	first_downsample_config := RenderPipelineConfig {
		debug_name           = "bloom first_downsample",
		vs_shader            = "screen",
		vs_entry_point       = "vs_main",
		fs_shader            = "bloom",
		fs_entry_point       = "first_downsample",
		topology             = .TriangleStrip,
		vertex               = {},
		instance             = {},
		bind_group_layouts   = bind_group_layouts,
		push_constant_ranges = {},
		blend                = nil,
		format               = HDR_FORMAT,
	}
	downsample_config := RenderPipelineConfig {
		debug_name           = "bloom downsample",
		vs_shader            = "screen",
		vs_entry_point       = "vs_main",
		fs_shader            = "bloom",
		fs_entry_point       = "downsample",
		topology             = .TriangleStrip,
		vertex               = {},
		instance             = {},
		bind_group_layouts   = bind_group_layouts,
		push_constant_ranges = {},
		blend                = nil,
		format               = HDR_FORMAT,
	}
	upsample_config := RenderPipelineConfig {
		debug_name = "bloom upsample",
		vs_shader = "screen",
		vs_entry_point = "vs_main",
		fs_shader = "bloom",
		fs_entry_point = "upsample",
		topology = .TriangleStrip,
		vertex = {},
		instance = {},
		bind_group_layouts = bind_group_layouts,
		push_constant_ranges = {},
		blend = wgpu.BlendState {
			color = wgpu.BlendComponent{srcFactor = .One, dstFactor = .One, operation = .Add},
			alpha = BLEND_COMPONENT_OVER,
		},
		format = HDR_FORMAT,
	}
	final_upsample_config := RenderPipelineConfig {
		debug_name = "bloom final_upsample",
		vs_shader = "screen",
		vs_entry_point = "vs_main",
		fs_shader = "bloom",
		fs_entry_point = "upsample", // same entry point as normal upsample, only blend state different.
		topology = .TriangleStrip,
		vertex = {},
		instance = {},
		bind_group_layouts = bind_group_layouts,
		push_constant_ranges = {},
		blend = wgpu.BlendState {
			color = wgpu.BlendComponent{srcFactor = .Constant, dstFactor = .One, operation = .Add},
			alpha = BLEND_COMPONENT_OVER,
		},
		format = HDR_FORMAT,
	}
	rend.first_downsample_pipeline.config = first_downsample_config
	rend.downsample_pipeline.config = downsample_config
	rend.upsample_pipeline.config = upsample_config
	rend.final_upsample_pipeline.config = final_upsample_config

	render_pipeline_create_or_panic(&rend.first_downsample_pipeline, &platform.shader_registry)
	render_pipeline_create_or_panic(&rend.downsample_pipeline, &platform.shader_registry)
	render_pipeline_create_or_panic(&rend.upsample_pipeline, &platform.shader_registry)
	render_pipeline_create_or_panic(&rend.final_upsample_pipeline, &platform.shader_registry)

}

render_bloom :: proc(
	command_encoder: wgpu.CommandEncoder,
	rend: ^BloomRenderer,
	hdr_texture: ^Texture,
	globals_bind_group: wgpu.BindGroup,
	settings: BloomSettings,
) {
	ladder := make([dynamic]^Texture, allocator = context.temp_allocator)
	append(&ladder, hdr_texture)
	for &e in rend.textures {
		switch &tex in e {
		case Texture:
			append(&ladder, &tex)
		case:
			break
		}
	}

	// downsample:
	for i := 0; i < len(ladder) - 1; i += 1 {
		from_tex := ladder[i]
		target_tex := ladder[i + 1]
		is_first_downsample := i == 0
		pipeline: wgpu.RenderPipeline
		if is_first_downsample do pipeline = rend.first_downsample_pipeline.pipeline
		else do pipeline = rend.downsample_pipeline.pipeline

		bloom_pass := wgpu.CommandEncoderBeginRenderPass(
			command_encoder,
			&wgpu.RenderPassDescriptor {
				colorAttachmentCount = 1,
				colorAttachments = &wgpu.RenderPassColorAttachment {
					view = target_tex.view,
					loadOp = .Load,
					storeOp = .Store,
				},
			},
		)
		defer wgpu.RenderPassEncoderRelease(bloom_pass)
		wgpu.RenderPassEncoderSetPipeline(bloom_pass, pipeline)
		wgpu.RenderPassEncoderSetBindGroup(bloom_pass, 0, globals_bind_group)
		wgpu.RenderPassEncoderSetBindGroup(bloom_pass, 1, from_tex.bind_group)
		wgpu.RenderPassEncoderDraw(bloom_pass, 3, 1, 0, 0)
		wgpu.RenderPassEncoderEnd(bloom_pass)
	}

	// upsample:
	for i := len(ladder) - 1; i > 0; i -= 1 {
		from_tex := ladder[i]
		target_tex := ladder[i - 1]
		is_final_upsample := i == 1
		pipeline: wgpu.RenderPipeline
		if is_final_upsample do pipeline = rend.final_upsample_pipeline.pipeline
		else do pipeline = rend.upsample_pipeline.pipeline

		bloom_pass := wgpu.CommandEncoderBeginRenderPass(
			command_encoder,
			&wgpu.RenderPassDescriptor {
				colorAttachmentCount = 1,
				colorAttachments = &wgpu.RenderPassColorAttachment {
					view = target_tex.view,
					loadOp = .Load,
					storeOp = .Store,
				},
			},
		)
		defer wgpu.RenderPassEncoderRelease(bloom_pass)
		wgpu.RenderPassEncoderSetPipeline(bloom_pass, pipeline)
		if is_final_upsample {
			b := settings.blend_factor
			blend_color := wgpu.Color{b, b, b, b}
			wgpu.RenderPassEncoderSetBlendConstant(bloom_pass, &blend_color)
		}
		wgpu.RenderPassEncoderSetBindGroup(bloom_pass, 0, globals_bind_group)
		wgpu.RenderPassEncoderSetBindGroup(bloom_pass, 1, from_tex.bind_group)
		wgpu.RenderPassEncoderDraw(bloom_pass, 3, 1, 0, 0)
		wgpu.RenderPassEncoderEnd(bloom_pass)
	}
}

bloom_renderer_resize :: proc(rend: ^BloomRenderer, size: UVec2) {
	// Note: takes care of old texture destuction too.
	_create_bloom_textures(rend, size)
}

@(private)
_create_bloom_textures :: proc(rend: ^BloomRenderer, size: UVec2) {
	BLOOM_TEXTURE_SETTINGS := TextureSettings {
		label        = "bloom texture",
		format       = HDR_FORMAT,
		address_mode = .ClampToEdge,
		mag_filter   = .Linear,
		min_filter   = .Nearest,
		usage        = {.TextureBinding, .RenderAttachment},
	}

	factor: u32 = 1
	for &e in rend.textures {
		factor *= 2
		tex_size := size / factor

		// destroy texture if already set:
		switch &texture in e {
		case Texture:
			texture_destroy(&texture)
			e = nil
		case:
		}

		texture_big_enough := max(tex_size.x, tex_size.y) > 12 && min(tex_size.x, tex_size.y) > 1
		if texture_big_enough {
			e = texture_create(rend.device, tex_size, BLOOM_TEXTURE_SETTINGS)
		}
	}
}
