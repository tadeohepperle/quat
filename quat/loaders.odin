package quat

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "shared:sdffont"
import "shared:slotman"
import wgpu "vendor:wgpu"

Handle :: slotman.Handle

DEFAULT_FONT :: FontHandle{0}
DEFAULT_TEXTURE :: TextureHandle{0}
DEFAULT_MOTION_TEXTURE :: MotionTextureHandle{0}
FontHandle :: Handle(Font)
TextureHandle :: Handle(Texture)
DepthTextureHandle :: Handle(DepthTexture)
MotionTextureHandle :: Handle(MotionTexture)
TextureArrayHandle :: Handle(TextureArray) // just the same ...
SkinnedMeshHandle :: Handle(SkinnedMesh)
RenderPipelineHandle :: Handle(RenderPipeline)

CubeTextureHandle :: Handle(CubeTexture)

Slotmap :: slotman.Slotmap
slotmap_get :: slotman.slotmap_get
get_map :: slotman.get_slotmap


register_asset_types :: proc() {
	slotman.register_asset_type(RgbaImage, image_drop)
	slotman.register_path_loader(RgbaImage, image_load_from_path)

	slotman.register_asset_type(Texture, texture_destroy)
	texture_loader_1 :: proc(input: TextureSettingsAndPath) -> (tex: Texture, err: Error) {
		full_path := slotman.try_load_full_path(input.path) or_return
		return texture_load_from_image_path(full_path, input.settings)
	}
	slotman.register_loader(Texture, TextureSettingsAndPath, texture_loader_1)
	texture_loader_2 :: proc(fullpath: string) -> (Texture, Error) {
		return texture_load_from_image_path(fullpath, TEXTURE_SETTINGS_RGBA)
	}
	slotman.register_path_loader(Texture, texture_loader_2)

	slotman.register_asset_type(DepthTexture, depth_texture_destroy)
	slotman.register_path_loader(DepthTexture, depth_texture_16bit_r_from_image_path)


	texture_array_loader :: proc(paths: []string) -> (array: TextureArray, err: Error) {
		full_paths := make([]string, len(paths), context.temp_allocator)
		for path, i in paths {
			full_paths[i] = slotman.try_load_full_path(path) or_return
		}
		return texture_array_from_image_paths(full_paths)
	}
	slotman.register_asset_type(TextureArray, texture_array_destroy)
	slotman.register_loader(TextureArray, []string, texture_array_loader)

	slotman.register_asset_type(Font, font_destroy)
	font_loader :: proc(ttf_file_path: string) -> (font: Font, err: Error) {
		return font_from_path(ttf_file_path)
	}
	slotman.register_path_loader(Font, font_loader)

	// no loaders:
	slotman.register_asset_type(MotionTexture, motion_texture_destroy)
	slotman.register_asset_type(SkinnedGeometry, skinned_mesh_geometry_drop)
	slotman.register_asset_type(SkinnedMesh, skinned_mesh_drop)
	slotman.register_asset_type(CubeTexture, cube_texture_destroy)

	// shaders:
	slotman.register_asset_type(WgslSource, wgsl_source_drop)
	slotman.register_bytes_loader(WgslSource, wgsl_source_load)
	slotman.register_asset_type(RenderPipeline, render_pipeline_drop)
	slotman.register_loader(RenderPipeline, RenderPipelineConfig, render_pipeline_loader)
}

make_render_pipeline :: proc(config: RenderPipelineConfig) -> RenderPipelineHandle {
	return slotman.load(RenderPipeline, config)
}

@(private)
update_changed_font_atlas_textures :: proc(queue: wgpu.Queue) {
	i := 0
	fonts: slotman.Slotmap(Font) = slotman.get_slotmap(Font)
	textures: slotman.Slotmap(Texture) = slotman.get_slotmap(Texture)
	for slot in fonts.slots {
		if slot.ref_count == 0 do continue
		font: Font = slot.data
		if sdffont.font_has_atlas_image_changed(font.sdf_font) {
			log.info("Update font atlas texture because it has changed:", font.name)
			atlas_image := sdffont.font_get_atlas_image(font.sdf_font)
			texture := slotman.slotmap_get(textures, font.texture_handle)
			size := texture.info.size
			image_copy := wgpu.TexelCopyTextureInfo {
				texture  = texture.texture,
				mipLevel = 0,
				origin   = {0, 0, 0},
				aspect   = .All,
			}
			data_layout := wgpu.TexelCopyBufferLayout {
				offset       = 0,
				bytesPerRow  = size.x,
				rowsPerImage = size.y,
			}
			wgpu.QueueWriteTexture(
				queue,
				&image_copy,
				raw_data(atlas_image.bytes),
				uint(len(atlas_image.bytes)),
				&data_layout,
				&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
			)
		}


	}
}


WgslSource :: struct {
	imports:       []slotman.Handle(WgslSource),
	composited:    string,
	shader_module: Maybe(wgpu.ShaderModule),
}
WgslSourceHandle :: slotman.Handle(WgslSource)

wgsl_source_drop :: proc(this: ^WgslSource) {
	delete(this.composited)
	for handle in this.imports {
		slotman.remove(handle)
	}
	delete(this.imports)
	if shader_module, ok := this.shader_module.(wgpu.ShaderModule); ok {
		wgpu.ShaderModuleRelease(shader_module)
	}
	this^ = {}
}

write :: strings.write_string

wgsl_source_load :: proc(bytes: []u8) -> (wgsl: WgslSource, err: Error) {
	str := string(bytes)
	imports := make([dynamic]WgslSourceHandle)
	b: strings.Builder
	defer if err != nil {
		for e in imports do slotman.remove(e)
		delete(imports)
		strings.builder_destroy(&b)
	}

	for line in strings.split_lines(str, context.temp_allocator) {
		if strings.starts_with(line, "#import") {
			line_without_import, ok := strings.substring(line, len("#import"), len(line))
			assert(ok)
			import_path := strings.trim_space(line_without_import)
			imported_handle := slotman.try_load_from_path(WgslSource, import_path) or_return
			import_source := slotman.get(imported_handle)
			write(&b, import_source.composited)
			append(&imports, imported_handle)
		} else {
			write(&b, line)
		}
		write(&b, "\n")
	}

	shrink(&imports)
	return WgslSource{imports = imports[:], composited = strings.to_string(b)}, nil
}

wgsl_source_try_make_shader_module :: proc(
	source: ^WgslSource,
	label: Maybe(string) = nil,
) -> (
	module: wgpu.ShaderModule,
	err: Error,
) {
	shader_module, wgpu_err := _create_shader_module(source.composited, label)
	if wgpu_err, ok := wgpu_err.(WgpuError); ok {
		return {}, tprint(wgpu_err.type, wgpu_err.message)
	}
	source.shader_module = shader_module
	return shader_module, nil
}

_create_shader_module :: proc(
	composited_wgsl: string,
	label: Maybe(string) = nil,
) -> (
	module: wgpu.ShaderModule,
	err: MaybeWgpuError,
) {
	wgpu.DevicePushErrorScope(PLATFORM.device, .Validation)
	module = wgpu.DeviceCreateShaderModule(
		PLATFORM.device,
		&wgpu.ShaderModuleDescriptor {
			label = label.(string) or_else "unnamed_shader_module",
			nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = composited_wgsl},
		},
	)
	if err, has_err := wgpu_pop_error_scope(PLATFORM.device).(WgpuError); has_err {
		return {}, err
	} else {
		return module, nil
	}
}

get_pipeline :: proc(handle: RenderPipelineHandle) -> wgpu.RenderPipeline {
	return slotman.get(handle).pipeline
}

render_pipeline_loader :: proc(config: RenderPipelineConfig) -> (pipeline: RenderPipeline, err: Error) {
	fs_shader := slotman.try_load_from_path(WgslSource, config.fs_shader) or_return
	defer if err != nil do slotman.remove(fs_shader)
	vs_shader := slotman.try_load_from_path(WgslSource, config.vs_shader) or_return
	defer if err != nil do slotman.remove(vs_shader)

	fs_shader_module := wgsl_source_try_make_shader_module(slotman.get_ref(fs_shader)) or_return
	vs_shader_module := wgsl_source_try_make_shader_module(slotman.get_ref(vs_shader)) or_return

	device := PLATFORM.device
	wgpu.DevicePushErrorScope(device, .Validation)

	push_consts := config.push_constant_ranges
	extras := wgpu.PipelineLayoutExtras {
		chain = {sType = .PipelineLayoutExtras},
		pushConstantRangeCount = uint(len(push_consts)),
		pushConstantRanges = nil if len(push_consts) == 0 else &push_consts[0],
	}
	bindGroupLayouts := nil if len(config.bind_group_layouts) == 0 else &config.bind_group_layouts[0]
	layout_desc := wgpu.PipelineLayoutDescriptor {
		nextInChain          = &extras.chain,
		bindGroupLayoutCount = uint(len(config.bind_group_layouts)),
		bindGroupLayouts     = bindGroupLayouts,
	}

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(device, &layout_desc)
	defer if err != nil {wgpu.PipelineLayoutRelease(pipeline_layout)}

	vert_attibutes := make([dynamic]wgpu.VertexAttribute, context.temp_allocator)
	vert_layouts := make([dynamic]wgpu.VertexBufferLayout, context.temp_allocator)
	if config.vertex.ty_id != nil && len(config.vertex.attributes) != 0 {
		start_idx := len(vert_attibutes)
		for a in config.vertex.attributes {
			attr := wgpu.VertexAttribute {
				format         = a.format,
				offset         = u64(a.offset),
				shaderLocation = u32(len(vert_attibutes)),
			}
			append(&vert_attibutes, attr)
		}
		ty_info := type_info_of(config.vertex.ty_id)
		layout := wgpu.VertexBufferLayout {
			arrayStride    = u64(ty_info.size),
			stepMode       = .Vertex,
			attributeCount = uint(len(config.vertex.attributes)),
			attributes     = &vert_attibutes[start_idx],
		}
		append(&vert_layouts, layout)
	}
	if config.instance.ty_id != nil && len(config.instance.attributes) != 0 {
		start_idx := len(vert_attibutes)
		for a in config.instance.attributes {
			attr := wgpu.VertexAttribute {
				format         = a.format,
				offset         = u64(a.offset),
				shaderLocation = u32(len(vert_attibutes)),
			}
			append(&vert_attibutes, attr)
		}
		ty_info := type_info_of(config.instance.ty_id)
		layout := wgpu.VertexBufferLayout {
			arrayStride    = u64(ty_info.size),
			stepMode       = .Instance,
			attributeCount = uint(len(config.instance.attributes)),
			attributes     = &vert_attibutes[start_idx],
		}
		append(&vert_layouts, layout)
	}

	blend: ^wgpu.BlendState
	switch &b in config.blend {
	case wgpu.BlendState:
		blend = &b
	case:
		blend = nil
	}

	STENCIL_IGNORE :: wgpu.StencilFaceState {
		compare     = wgpu.CompareFunction.Always,
		failOp      = wgpu.StencilOperation.Keep,
		depthFailOp = wgpu.StencilOperation.Keep,
		passOp      = wgpu.StencilOperation.Keep,
	}
	depth_stencil: ^wgpu.DepthStencilState = nil
	if depth_config, ok := config.depth.(DepthConfig); ok {
		depth_stencil = &wgpu.DepthStencilState {
			format = DEPTH_TEXTURE_FORMAT,
			depthWriteEnabled = wgpu_optional_bool(depth_config.depth_write_enabled),
			depthCompare = depth_config.depth_compare,
			stencilFront = STENCIL_IGNORE,
			stencilBack = STENCIL_IGNORE,
		}
	}

	cull_mode: wgpu.CullMode = config.cull_mode
	if cull_mode == .Undefined {
		cull_mode = .None
	}

	pipeline_descriptor := wgpu.RenderPipelineDescriptor {
		label = config.debug_name,
		layout = pipeline_layout,
		vertex = wgpu.VertexState {
			module = vs_shader_module,
			entryPoint = config.vs_entry_point,
			bufferCount = uint(len(vert_layouts)),
			buffers = nil if len(vert_layouts) == 0 else &vert_layouts[0],
		},
		fragment = &wgpu.FragmentState {
			module      = fs_shader_module,
			entryPoint  = config.fs_entry_point,
			targetCount = 1,
			targets     = &wgpu.ColorTargetState {
				format    = config.format,
				writeMask = wgpu.ColorWriteMaskFlags_All,
				blend     = blend, // todo! alpha blending
			},
		},
		depthStencil = depth_stencil,
		primitive = wgpu.PrimitiveState{topology = config.topology, frontFace = .CCW, cullMode = cull_mode},
		multisample = {count = 1, mask = 0xFFFFFFFF},
	}
	wgpu_pipeline := wgpu.DeviceCreateRenderPipeline(device, &pipeline_descriptor)
	wgpu_err := wgpu_pop_error_scope(device)
	if wgpu_err, has_err := wgpu_err.(WgpuError); has_err {
		return {}, tprint(wgpu_err)
	} else {
		return RenderPipeline{config, fs_shader, vs_shader, pipeline_layout, wgpu_pipeline}, nil
	}
}

wgpu_optional_bool :: proc(b: bool) -> wgpu.OptionalBool {
	return .True if b else .False
}
