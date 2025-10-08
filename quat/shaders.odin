package quat

// import "base:runtime"
// import "core:fmt"
// import "core:os"
// import "core:path/filepath"
// import "core:slice"
// import "core:strings"
// import wgpu "vendor:wgpu"


// // all allocations in NEVER_FREE_ALLOCATOR
// ShaderRegistry :: struct {
// 	shader_directories:               []string,
// 	changed_shaders_since_last_watch: [dynamic]string,
// 	device:                           wgpu.Device,
// 	shaders:                          map[string]Shader, // maps shader names, i.e foo.wgsl without the .wgsl to the shaders
// 	pipelines:                        [dynamic]RenderPipelineHandle, // owned by the shader registry!!!
// 	hot_reload_shaders:               bool,
// }

// shader_registry_add_directory :: proc(dir_path: string) {
// 	reg := &PLATFORM.shader_registry
// 	new_shader_directories := make([]string, len(reg.shader_directories) + 1)
// 	copy(new_shader_directories, reg.shader_directories)
// 	new_shader_directories[len(reg.shader_directories)] = strings.clone(dir_path, NEVER_FREE_ALLOCATOR)
// 	reg.shader_directories = new_shader_directories
// }

// Shader :: struct {
// 	src_path:            string,
// 	src_wgsl:            string,
// 	src_file_mod_time:   os.File_Time,
// 	composited_wgsl:     string,
// 	import_shader_names: [dynamic]string,
// 	shader_module:       Maybe(wgpu.ShaderModule), // nullable, only shaders with entry points create modules, not some wgsl snippets.
// }

// // shader_destroy :: proc(shader: ^Shader) {
// // 	if shader.shader_module != nil {
// // 		wgpu.ShaderModuleRelease(shader.shader_module)
// // 	}
// // 	delete(shader.src.path)
// // 	delete(shader.src.wgsl_code)
// // 	delete(shader.composited.wgsl_code.c_str)
// // 	for &e in shader.composited.imports {
// // 		delete(e)
// // 	}
// // 	delete(shader.composited.imports)
// // }

// shader_registry_destroy :: proc(reg: ^ShaderRegistry) {
// 	for pipeline in reg.pipelines {
// 		assert(pipeline.layout != nil)
// 		assert(pipeline.pipeline != nil)
// 		wgpu.PipelineLayoutRelease(pipeline.layout)
// 		wgpu.RenderPipelineRelease(pipeline.pipeline)
// 		free(pipeline)
// 	}
// 	delete(reg.pipelines)
// 	for name, shader in reg.shaders {
// 		if mod, ok := shader.shader_module.(wgpu.ShaderModule); ok {
// 			wgpu.ShaderModuleRelease(mod)
// 		}
// 	}
// 	delete(reg.shaders)
// 	// todo: likely more to delete here, but should not matter much, because only happens at end of program
// }

// shader_registry_create :: proc(
// 	device: wgpu.Device,
// 	shaders_dir_path: string,
// 	hot_reload_shaders: bool,
// ) -> ShaderRegistry {

// 	return ShaderRegistry {
// 		device = device,
// 		shader_directories = slice.clone([]string{shaders_dir_path}, NEVER_FREE_ALLOCATOR),
// 		hot_reload_shaders = hot_reload_shaders,
// 		shaders = make(map[string]Shader, context.allocator),
// 		pipelines = make([dynamic]RenderPipelineHandle, context.allocator),
// 	}
// }

// shader_registry_get_or_load_shader_module :: proc(
// 	reg: ^ShaderRegistry,
// 	shader_name: string,
// ) -> (
// 	module: wgpu.ShaderModule,
// 	err: Error,
// ) {
// 	shader := get_or_load_shader(reg, shader_name) or_return
// 	if module, ok := shader.shader_module.(wgpu.ShaderModule); ok {
// 		return module, nil
// 	} else {
// 		module, err := create_shader_module(shader_name, shader.composited_wgsl)
// 		if err, has_err := err.(WgpuError); has_err {
// 			return {}, tprint(err.message)
// 		} else {
// 			shader.shader_module = module
// 			return module, nil
// 		}
// 	}
// }

// make_render_pipeline :: proc(config: RenderPipelineConfig) -> RenderPipelineHandle {
// 	pipeline := new(RenderPipeline)
// 	pipeline.config = config
// 	err := _create_or_reload_render_pipeline(&PLATFORM.shader_registry, pipeline)
// 	if err, has_err := err.(string); has_err {
// 		fmt.panicf("Failed to create Render Pipeline \"{}\": {}", pipeline.config.debug_name, err)
// 	}
// 	assert(pipeline.layout != nil)
// 	assert(pipeline.pipeline != nil)
// 	append(&PLATFORM.shader_registry.pipelines, pipeline)
// 	return pipeline
// }

// wgpu_optional_bool :: proc(b: bool) -> wgpu.OptionalBool {
// 	return .True if b else .False
// }

// // SHADERS_DIRECTORY: []runtime.Load_Directory_File = #load_directory("../shaders")
// _create_or_reload_render_pipeline :: proc(reg: ^ShaderRegistry, pipeline: RenderPipelineHandle) -> (err: Error) {
// 	config := &pipeline.config

// 	vs_shader_module := shader_registry_get_or_load_shader_module(reg, config.vs_shader) or_return
// 	fs_shader_module := shader_registry_get_or_load_shader_module(reg, config.fs_shader) or_return

// 	wgpu.DevicePushErrorScope(reg.device, .Validation)
// 	if pipeline.layout == nil {
// 		push_consts := config.push_constant_ranges
// 		extras := wgpu.PipelineLayoutExtras {
// 			chain = {sType = .PipelineLayoutExtras},
// 			pushConstantRangeCount = uint(len(push_consts)),
// 			pushConstantRanges = nil if len(push_consts) == 0 else &push_consts[0],
// 		}
// 		bindGroupLayouts := nil if len(config.bind_group_layouts) == 0 else &config.bind_group_layouts[0]
// 		layout_desc := wgpu.PipelineLayoutDescriptor {
// 			nextInChain          = &extras.chain,
// 			bindGroupLayoutCount = uint(len(config.bind_group_layouts)),
// 			bindGroupLayouts     = bindGroupLayouts,
// 		}

// 		pipeline.layout = wgpu.DeviceCreatePipelineLayout(reg.device, &layout_desc)
// 	}

// 	vert_attibutes := make([dynamic]wgpu.VertexAttribute, context.temp_allocator)
// 	vert_layouts := make([dynamic]wgpu.VertexBufferLayout, context.temp_allocator)
// 	if config.vertex.ty_id != nil && len(config.vertex.attributes) != 0 {
// 		start_idx := len(vert_attibutes)
// 		for a in config.vertex.attributes {
// 			attr := wgpu.VertexAttribute {
// 				format         = a.format,
// 				offset         = u64(a.offset),
// 				shaderLocation = u32(len(vert_attibutes)),
// 			}
// 			append(&vert_attibutes, attr)
// 		}
// 		ty_info := type_info_of(config.vertex.ty_id)
// 		layout := wgpu.VertexBufferLayout {
// 			arrayStride    = u64(ty_info.size),
// 			stepMode       = .Vertex,
// 			attributeCount = uint(len(config.vertex.attributes)),
// 			attributes     = &vert_attibutes[start_idx],
// 		}
// 		append(&vert_layouts, layout)
// 	}
// 	if config.instance.ty_id != nil && len(config.instance.attributes) != 0 {
// 		start_idx := len(vert_attibutes)
// 		for a in config.instance.attributes {
// 			attr := wgpu.VertexAttribute {
// 				format         = a.format,
// 				offset         = u64(a.offset),
// 				shaderLocation = u32(len(vert_attibutes)),
// 			}
// 			append(&vert_attibutes, attr)
// 		}
// 		ty_info := type_info_of(config.instance.ty_id)
// 		layout := wgpu.VertexBufferLayout {
// 			arrayStride    = u64(ty_info.size),
// 			stepMode       = .Instance,
// 			attributeCount = uint(len(config.instance.attributes)),
// 			attributes     = &vert_attibutes[start_idx],
// 		}
// 		append(&vert_layouts, layout)
// 	}

// 	blend: ^wgpu.BlendState
// 	switch &b in config.blend {
// 	case wgpu.BlendState:
// 		blend = &b
// 	case:
// 		blend = nil
// 	}

// 	STENCIL_IGNORE :: wgpu.StencilFaceState {
// 		compare     = wgpu.CompareFunction.Always,
// 		failOp      = wgpu.StencilOperation.Keep,
// 		depthFailOp = wgpu.StencilOperation.Keep,
// 		passOp      = wgpu.StencilOperation.Keep,
// 	}
// 	depth_stencil: ^wgpu.DepthStencilState = nil
// 	if depth_config, ok := config.depth.(DepthConfig); ok {
// 		depth_stencil = &wgpu.DepthStencilState {
// 			format = DEPTH_TEXTURE_FORMAT,
// 			depthWriteEnabled = wgpu_optional_bool(depth_config.depth_write_enabled),
// 			depthCompare = depth_config.depth_compare,
// 			stencilFront = STENCIL_IGNORE,
// 			stencilBack = STENCIL_IGNORE,
// 		}
// 	}

// 	cull_mode: wgpu.CullMode = config.cull_mode
// 	if cull_mode == .Undefined {
// 		cull_mode = .None
// 	}

// 	pipeline_descriptor := wgpu.RenderPipelineDescriptor {
// 		label = config.debug_name,
// 		layout = pipeline.layout,
// 		vertex = wgpu.VertexState {
// 			module = vs_shader_module,
// 			entryPoint = config.vs_entry_point,
// 			bufferCount = uint(len(vert_layouts)),
// 			buffers = nil if len(vert_layouts) == 0 else &vert_layouts[0],
// 		},
// 		fragment = &wgpu.FragmentState {
// 			module      = fs_shader_module,
// 			entryPoint  = config.fs_entry_point,
// 			targetCount = 1,
// 			targets     = &wgpu.ColorTargetState {
// 				format    = config.format,
// 				writeMask = wgpu.ColorWriteMaskFlags_All,
// 				blend     = blend, // todo! alpha blending
// 			},
// 		},
// 		depthStencil = depth_stencil,
// 		primitive = wgpu.PrimitiveState{topology = config.topology, frontFace = .CCW, cullMode = cull_mode},
// 		multisample = {count = 1, mask = 0xFFFFFFFF},
// 	}
// 	wgpu_pipeline := wgpu.DeviceCreateRenderPipeline(reg.device, &pipeline_descriptor)
// 	wgpu_err := wgpu_pop_error_scope(reg.device)
// 	if wgpu_err, has_err := wgpu_err.(WgpuError); has_err {
// 		return tprint(wgpu_err)
// 	} else {
// 		// swap out old pipeline for new pipeline
// 		old_pipeline := pipeline.pipeline
// 		pipeline.pipeline = wgpu_pipeline
// 		if old_pipeline != nil {
// 			wgpu.RenderPipelineRelease(old_pipeline)
// 		}
// 		return nil
// 	}
// }

// // Note: does not create shader module
// get_or_load_shader :: proc(reg: ^ShaderRegistry, shader_name: string) -> (shader: ^Shader, err: Error) {
// 	if shader_name not_in reg.shaders {
// 		shader: Shader
// 		src_path := shader_src_path(reg, shader_name) or_return
// 		src_wgsl, src_file_mod_time := load_shader_wgsl(reg, src_path) or_return
// 		composited_wgsl, import_shader_names := composite_wgsl_code(reg, src_wgsl) or_return
// 		reg.shaders[shader_name] = Shader {
// 			src_path            = src_path,
// 			src_wgsl            = src_wgsl,
// 			src_file_mod_time   = src_file_mod_time,
// 			composited_wgsl     = composited_wgsl,
// 			shader_module       = nil,
// 			import_shader_names = import_shader_names,
// 		}
// 	}
// 	return &reg.shaders[shader_name], nil
// }

// // Note: does not create shader module
// create_shader_module :: proc(
// 	label: string,
// 	composited_wgsl: string,
// ) -> (
// 	module: wgpu.ShaderModule,
// 	err: MaybeWgpuError,
// ) {
// 	wgpu.DevicePushErrorScope(PLATFORM.device, .Validation)
// 	module = wgpu.DeviceCreateShaderModule(
// 		PLATFORM.device,
// 		&wgpu.ShaderModuleDescriptor {
// 			label = label,
// 			nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = composited_wgsl},
// 		},
// 	)
// 	if err, has_err := wgpu_pop_error_scope(PLATFORM.device).(WgpuError); has_err {
// 		return {}, err
// 	} else {
// 		return module, nil
// 	}
// }

// composite_wgsl_code :: proc(
// 	reg: ^ShaderRegistry,
// 	src_wgsl: string,
// ) -> (
// 	composited_wgsl: string,
// 	import_shader_names: [dynamic]string,
// 	err: Error,
// ) {
// 	// replace the #import statements in the code with contents of that shader.
// 	lines := strings.split_lines(src_wgsl, context.temp_allocator)
// 	b: strings.Builder
// 	strings.builder_init(&b, NEVER_FREE_ALLOCATOR)
// 	import_shader_names = make([dynamic]string, NEVER_FREE_ALLOCATOR)

// 	for line in lines {
// 		if strings.has_prefix(line, "#import ") {
// 			if !strings.has_suffix(line, ".wgsl") {
// 				return {}, {}, fmt.tprintf("#import file needs to have .wgsl ending, instead, got: {}", line)
// 			}
// 			import_shader_name := strings.trim_space(line[7:len(line) - 5])
// 			import_shader: ^Shader
// 			import_shader = get_or_load_shader(reg, import_shader_name) or_return
// 			append(&import_shader_names, import_shader_name)
// 			// replace the import line by the wgsl code in the imported file:
// 			strings.write_string(&b, import_shader.composited_wgsl)
// 		} else {
// 			strings.write_string(&b, line)
// 			strings.write_rune(&b, '\n')
// 		}
// 	}
// 	return strings.to_string(b), import_shader_names, nil
// }

// shader_src_path :: proc(reg: ^ShaderRegistry, shader_name: string) -> (path: string, err: Error) {
// 	for dir_path in reg.shader_directories {
// 		path_candidate := fmt.tprintf("{}{}{}.wgsl", dir_path, filepath.SEPARATOR, shader_name)
// 		if _, err := os.stat(path_candidate, context.temp_allocator); err == nil {
// 			fmt.printfln("selected path {} for {}", path_candidate, shader_name)
// 			return strings.clone(path_candidate, NEVER_FREE_ALLOCATOR), nil
// 		}
// 	}
// 	return {}, tprint("shader with name", shader_name, "not found in any of the directories:", reg.shader_directories)
// }

// /// Note: Does not create the actual shader module!
// load_shader_wgsl :: proc(
// 	reg: ^ShaderRegistry,
// 	src_path: string,
// ) -> (
// 	src_wgsl: string,
// 	src_file_mod_time: os.File_Time,
// 	err: Error,
// ) {
// 	src_file_modification_time, src_err := os.last_write_time_by_name(src_path)
// 	if src_err != nil {
// 		return {}, {}, fmt.tprintf("Error loading file {}: {}", src_path, src_err)
// 	}
// 	content, success := os.read_entire_file_from_filename(src_path, NEVER_FREE_ALLOCATOR)
// 	if len(content) == 0 || !success {
// 		err = fmt.tprintf("Empty shader file: {}", src_path)
// 		return {}, {}, err
// 	}
// 	src_wgsl = string(content)
// 	return src_wgsl, src_file_modification_time, nil
// }


// // Note: currently stops after first changed file detected.
// // Sould not be a porblem in reality, because we change only 0 to 1 shader files in each frame.
// // In case a lot of files are rewritten in a single frame, this reload needs to run multiple frames, before all are reloaded.
// //
// // Warning: There are a couple of memory leaks regarding strings, import dynamic arrays, etc. in here: I don't care at the moment
// // Hot reloading is only meant for development anyway, so fuck it - Tadeo Hepperle, 2024-07-13
// shader_registry_hot_reload :: proc(reg: ^ShaderRegistry) {
// 	if len(reg.pipelines) == 0 {
// 		return
// 	}
// 	// try to find a shader file that has changed (finding one per frame is enough! if multiple changed the total hot reload is just spread across frames)
// 	changed_shader_name: string
// 	changed_shader: ^Shader
// 	// note: should probably randomize iteration order!
// 	for name, &shader in reg.shaders {
// 		last_write_time, err := os.last_write_time_by_name(shader.src_path)
// 		if err != nil {
// 			continue
// 		}
// 		if shader.src_file_mod_time >= last_write_time {
// 			continue
// 		}
// 		changed_shader_name = name
// 		changed_shader = &shader
// 		break
// 	}
// 	if changed_shader == nil {
// 		return
// 	}

// 	fmt.println("Detected file change in ", changed_shader.src_path)
// 	// reload the wgsl from the file for that shader:


// 	new_src_wgsl, new_src_file_mod_time, load_err := load_shader_wgsl(reg, changed_shader.src_path)
// 	if load_err, has_load_err := load_err.(string); has_load_err {
// 		fmt.eprintfln("Error loading shader at %s: %s", changed_shader.src_path, load_err)
// 		return
// 	}
// 	changed_shader.src_wgsl = new_src_wgsl
// 	changed_shader.src_file_mod_time = new_src_file_mod_time

// 	// print_line("read content:")
// 	// print(changed_shader.src.wgsl_code)
// 	// set a chain reaction in motion updating this shader and all its dependants:
// 	shaders_with_changed_modules := make(map[string]None, allocator = context.temp_allocator)
// 	queue := make([dynamic]string, allocator = context.temp_allocator)
// 	append(&queue, changed_shader_name)
// 	for len(queue) > 0 {
// 		shader_name := pop_front(&queue)
// 		shader := &reg.shaders[shader_name]

// 		fmt.printfln("took {} from queue", shader_name)

// 		new_composited_wgsl, new_import_shader_names, composite_err := composite_wgsl_code(reg, shader.src_wgsl)
// 		if composite_err, has_err := composite_err.(string); has_err {
// 			fmt.eprintfln("Error compositing wgsl for %s: %s", shader.src_path, composite_err)
// 			continue
// 		}
// 		if new_composited_wgsl == shader.composited_wgsl {
// 			fmt.printfln("new_composited_wgsl == shader.composited_wgsl for {}", shader_name)
// 			continue
// 		}

// 		if old_shader_module, ok := shader.shader_module.(wgpu.ShaderModule); ok {
// 			new_shader_module, create_err := create_shader_module(shader_name, new_composited_wgsl)

// 			if create_err, has_err := create_err.(WgpuError); has_err {
// 				fmt.printfln("Error creating shader module %s:\n%s", shader.src_path, create_err)
// 				continue
// 			} else {
// 				fmt.printfln("Created new shader module for shader {} at {}", shader_name, shader.src_path)
// 			}

// 			// swap out shader module:
// 			wgpu.ShaderModuleRelease(old_shader_module)

// 			shader.shader_module = new_shader_module
// 			shaders_with_changed_modules[shader_name] = None{}
// 		}
// 		shader.composited_wgsl = new_composited_wgsl
// 		shader.import_shader_names = new_import_shader_names

// 		// inefficient but good enough for <50 shaders I guess
// 		for other, shader in reg.shaders {
// 			if other != shader_name {
// 				if slice.contains(shader.import_shader_names[:], shader_name) {
// 					append(&queue, other)
// 				}
// 			}
// 		}
// 	}

// 	print(shaders_with_changed_modules)

// 	// if we get until here, no error has occurred, we can recreate pipelines:
// 	for pipeline in reg.pipelines {
// 		should_recreate_pipeline :=
// 			pipeline.config.vs_shader in shaders_with_changed_modules ||
// 			pipeline.config.fs_shader in shaders_with_changed_modules
// 		if should_recreate_pipeline {
// 			err := _create_or_reload_render_pipeline(reg, pipeline)
// 			if err, has_err := err.(string); has_err {
// 				fmt.eprintfln("Error creating pipeline %s: %s", pipeline.config.debug_name, err)
// 			} else {
// 				fmt.printfln("Hot reloaded pipeline: {}", pipeline.config.debug_name)
// 			}
// 		}
// 	}
// }
