package quat

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import wgpu "vendor:wgpu"

ShaderRegistry :: struct {
	shaders_dir_path:                 string,
	changed_shaders_since_last_watch: [dynamic]string,
	device:                           wgpu.Device,
	shaders:                          map[string]Shader,
	registered_pipelines:             [dynamic]^RenderPipeline,
}


ShaderSourceWgsl :: struct {
	path:            string,
	last_write_time: os.File_Time,
	wgsl_code:       string,
}

ShaderCompositedWgsl :: struct {
	wgsl_code: StringAndCString,
	imports:   [dynamic]string,
}

Shader :: struct {
	src:           ShaderSourceWgsl,
	composited:    ShaderCompositedWgsl,
	shader_module: wgpu.ShaderModule, // nullable, only shaders with entry points create modules, not some wgsl snippets.
}

/// Both pointing to the same backing storage
StringAndCString :: struct {
	c_str: cstring,
	str:   string,
}

// shader_destroy :: proc(shader: ^Shader) {
// 	if shader.shader_module != nil {
// 		wgpu.ShaderModuleRelease(shader.shader_module)
// 	}
// 	delete(shader.src.path)
// 	delete(shader.src.wgsl_code)
// 	delete(shader.composited.wgsl_code.c_str)
// 	for &e in shader.composited.imports {
// 		delete(e)
// 	}
// 	delete(shader.composited.imports)
// }

shader_registry_destroy :: proc(reg: ^ShaderRegistry) {
	delete(reg.registered_pipelines) // todo: likely more to delete here, but should not matter much, because only happens at end of program
}

shader_registry_create :: proc(
	device: wgpu.Device,
	shaders_dir_path: string = "./shaders",
) -> ShaderRegistry {
	return ShaderRegistry{device = device, shaders_dir_path = shaders_dir_path}
}

shader_registry_get :: proc(reg: ^ShaderRegistry, shader_name: string) -> wgpu.ShaderModule {

	shader, err := get_or_load_shader(reg, shader_name, true)
	if err != "" {
		fmt.panicf("shader_registry_get should not panic (at least not on hot-reload): %s", err)
	}
	return shader.shader_module
}

shader_registry_register_pipeline :: proc(reg: ^ShaderRegistry, pipeline: ^RenderPipeline) {
	for ptr in reg.registered_pipelines {
		if rawptr(ptr) == rawptr(pipeline) {
			return
		}
	}
	append(&reg.registered_pipelines, pipeline)
}

// Note: does not create shader module
get_or_load_shader :: proc(
	reg: ^ShaderRegistry,
	shader_name: string,
	create_module: bool,
) -> (
	shader: ^Shader,
	err: string,
) {
	if shader_name not_in reg.shaders {
		loaded_shader: Shader
		err = load_shader_wgsl(reg, shader_name, &loaded_shader)
		if err != "" {
			return
		}
		err = composite_wgsl_code(reg, &loaded_shader) // TODO or_return usable here
		if err != "" {
			return
		}
		if create_module {
			err = create_shader_module(reg.device, &loaded_shader)
			if err != "" {
				return
			}
		}
		reg.shaders[shader_name] = loaded_shader
	}
	shader = &reg.shaders[shader_name]
	return
}

// Note: does not create shader module
create_shader_module :: proc(device: wgpu.Device, shader: ^Shader) -> (err: string) {
	wgpu.DevicePushErrorScope(device, .Validation)
	shader.shader_module = wgpu.DeviceCreateShaderModule(
		device,
		&wgpu.ShaderModuleDescriptor {
			label = strings.clone_to_cstring(shader.src.path),
			nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
				sType = .ShaderModuleWGSLDescriptor,
				code = shader.composited.wgsl_code.c_str,
			},
		},
	)
	switch create_shader_err in wgpu_pop_error_scope(device) {
	case WgpuError:
		err = create_shader_err.message
	case:
	}
	return
}


composite_wgsl_code :: proc(reg: ^ShaderRegistry, shader: ^Shader) -> (err: string) {
	wgsl_code: StringAndCString
	imports: [dynamic]string
	// replace the #import statements in the code with contents of that shader.
	lines := strings.split_lines(shader.src.wgsl_code, context.temp_allocator)
	b: strings.Builder
	for line in lines {
		if strings.has_prefix(line, "#import ") {
			if !strings.has_suffix(line, ".wgsl") {
				err = strings.clone(line)
				return
			}
			import_shader_name := strings.trim_space(line[7:len(line) - 5])
			import_shader: ^Shader
			import_shader, err = get_or_load_shader(reg, import_shader_name, false)
			if err != "" {
				return
			}
			append(&imports, import_shader_name)
			// replace the import line by the wgsl code in the imported file:
			strings.write_string(&b, import_shader.composited.wgsl_code.str)
		} else {
			strings.write_string(&b, line)
			strings.write_rune(&b, '\n')
		}
	}
	wgsl_code = StringAndCString {
		c_str = strings.to_cstring(&b),
		str   = strings.to_string(b),
	}
	shader.composited = ShaderCompositedWgsl{wgsl_code, imports}
	return
}

/// Note: Does not create the actual shader module!
load_shader_wgsl :: proc(
	reg: ^ShaderRegistry,
	shader_name: string,
	shader: ^Shader,
) -> (
	err: string,
) {
	print("LOAD", shader_name, shader)
	shader.src.path = fmt.aprintf("%s/%s.wgsl", reg.shaders_dir_path, shader_name)
	src_time, src_err := os.last_write_time_by_name(shader.src.path)
	if src_err != 0 {
		err = fmt.aprint("file does not exist:", shader.src.path)
		return
	}
	content, _ := os.read_entire_file(shader.src.path)
	if len(content) == 0 {
		err = fmt.aprintf(
			"Empty shader file: %s",
			shader.src.path,
			allocator = context.temp_allocator,
		)
		return
	}
	shader.src.wgsl_code = string(content)
	shader.src.last_write_time = src_time
	return
}


// Note: currently stops after first changed file detected.
// Sould not be a porblem in reality, because we change only 0 to 1 shader files in each frame.
// In case a lot of files are rewritten in a single frame, this reload needs to run multiple frames, before all are reloaded.
//
// Warning: There are a couple of memory leaks regarding strings, import dynamic arrays, etc. in here: I don't care at the moment
// Hot reloading is only meant for development anyway, so fuck it - Tadeo Hepperle, 2024-07-13
shader_registry_hot_reload :: proc(reg: ^ShaderRegistry) {
	if len(reg.registered_pipelines) == 0 {
		return
	}
	// try to find a shader file that has changed:
	changed_shader_name: string
	changed_shader: ^Shader
	for shader_name, &shader in reg.shaders {
		last_write_time, err := os.last_write_time_by_name(shader.src.path)
		if err != 0 {
			fmt.panicf("Shader file at %s got deleted", shader.src.path)
		}
		if shader.src.last_write_time >= last_write_time {
			continue
		}
		changed_shader_name = shader_name
		changed_shader = &shader
		break
	}
	if changed_shader == nil {
		return
	}

	print("Detected file change in ", changed_shader.src.path)
	// reload the wgsl from the file for that shader:
	old_src := changed_shader.src
	load_err := load_shader_wgsl(reg, changed_shader_name, changed_shader)
	if load_err != "" {
		fmt.eprintfln("Error loading shader at %s: %s", changed_shader.src.path, load_err)
		return
	}
	// print_line("read content:")
	// print(changed_shader.src.wgsl_code)
	// set a chain reaction in motion updating this shader and all its dependants:
	shaders_with_changed_modules := make(map[string]Empty, allocator = context.temp_allocator)
	queue := make([dynamic]string, allocator = context.temp_allocator)
	append(&queue, changed_shader_name)
	for len(queue) > 0 {
		shader_name := pop_front(&queue)
		shader := &reg.shaders[shader_name]
		old_composited := shader.composited
		composite_err := composite_wgsl_code(reg, shader)

		// print_line("old:")
		// print(old_composited.wgsl_code.str)
		// print_line("new:")
		// print(shader.composited.wgsl_code.str)
		// print_line()
		if composite_err != "" {
			fmt.eprintfln("Error compositing wgsl for %s: %s", shader.src.path, composite_err)
			return
		}
		if shader.shader_module != nil &&
		   old_composited.wgsl_code.str != shader.composited.wgsl_code.str {
			old_shader_module := shader.shader_module
			create_err := create_shader_module(reg.device, shader)
			if create_err != "" {
				fmt.printfln("Error creating shader module %s:\n%s", shader.src.path, create_err)
				return
			}
			wgpu.ShaderModuleRelease(old_shader_module)
			shaders_with_changed_modules[shader_name] = Empty{}
		}
		for name, shader in reg.shaders {
			if name == shader_name {
				continue
			}
			if slice.contains(shader.composited.imports[:], shader_name) {
				append(&queue, name)
			}
		}
	}
	// if we get until here, no error has occurred, we can recreate pipelines using any o
	for &pipeline in reg.registered_pipelines {
		should_recreate_pipeline :=
			pipeline.config.vs_shader in shaders_with_changed_modules ||
			pipeline.config.fs_shader in shaders_with_changed_modules
		if should_recreate_pipeline {
			err := render_pipeline_create(pipeline, reg)
			switch e in err {
			case WgpuError:
				fmt.eprintfln("Error creating pipeline %s: %s", pipeline.config.debug_name, err)
				continue
			case:
				print("Hot reloaded pipeline:", pipeline.config.debug_name)
			}
		}
	}
}
