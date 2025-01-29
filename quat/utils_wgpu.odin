package quat

import "base:runtime"
import "core:fmt"
import "core:strings"
import wgpu "vendor:wgpu"

DynamicBuffer :: struct($T: typeid) {
	buffer:   wgpu.Buffer,
	usage:    wgpu.BufferUsageFlags,
	size:     u64,
	length:   int,
	capacity: int,
}

MIN_BUFFER_CAPACITY :: 1024
dynamic_buffer_write :: proc(
	buffer: ^DynamicBuffer($T),
	elements: []T,
	device: wgpu.Device,
	queue: wgpu.Queue,
) {
	buffer.usage |= {.CopyDst}
	buffer.length = len(elements)
	if buffer.length == 0 {
		return
	}

	target_capacity := max(next_pow2_number(buffer.length), MIN_BUFFER_CAPACITY)
	element_size := size_of(T)
	// if not enough space or unallocated, allocate  new buffer:
	if buffer.capacity < target_capacity {
		// throw old buffer away if already allocated
		if buffer.capacity != 0 {
			dynamic_buffer_destroy(buffer)
		}
		buffer.capacity = target_capacity
		buffer.size = u64(buffer.capacity * element_size)
		buffer.buffer = wgpu.DeviceCreateBuffer(
			device,
			&wgpu.BufferDescriptor {
				usage = buffer.usage,
				size = buffer.size,
				mappedAtCreation = false,
			},
		)
	}
	used_size := uint(buffer.length * element_size)
	wgpu.QueueWriteBuffer(queue, buffer.buffer, 0, raw_data(elements), used_size)
}

dynamic_buffer_write_many :: proc(
	buffer: ^DynamicBuffer($T),
	element_slices: [][]T,
	device: wgpu.Device,
	queue: wgpu.Queue,
) {
	panic("todo! not implmeneted")
}

dynamic_buffer_destroy :: proc(buffer: ^DynamicBuffer($T)) {
	if buffer.buffer != nil {
		wgpu.BufferDestroy(buffer.buffer)
		buffer.buffer = nil
	}

}

UniformBuffer :: struct($T: typeid) {
	buffer:            wgpu.Buffer,
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,
	usage:             wgpu.BufferUsageFlags,
}


uniform_buffer_destroy :: proc(buffer: ^UniformBuffer($T)) {
	wgpu.BindGroupRelease(buffer.bind_group)
	wgpu.BindGroupLayoutRelease(buffer.bind_group_layout)
	wgpu.BufferRelease(buffer.buffer) // TODO: What is the difference between BufferDestroy and BufferRelease
}

uniform_buffer_create :: proc(buffer: ^UniformBuffer($T), device: wgpu.Device) {
	buffer.usage |= {.CopyDst, .Uniform}
	buffer.buffer = wgpu.DeviceCreateBuffer(
		device,
		&wgpu.BufferDescriptor{usage = buffer.usage, size = size_of(T), mappedAtCreation = false},
	)
	print(size_of(T))
	buffer.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		device,
		&wgpu.BindGroupLayoutDescriptor {
			entryCount = 1,
			entries = &wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Vertex, .Fragment},
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of(T),
				},
			},
		},
	)
	bind_group_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry {
			binding = 0,
			buffer = buffer.buffer,
			offset = 0,
			size = u64(size_of(T)),
		},
	}
	buffer.bind_group = wgpu.DeviceCreateBindGroup(
		device,
		&wgpu.BindGroupDescriptor {
			layout = buffer.bind_group_layout,
			entryCount = 1,
			entries = raw_data(bind_group_entries[:]),
		},
	)
}

uniform_buffer_write :: proc(queue: wgpu.Queue, buffer: ^UniformBuffer($T), data: ^T) {
	wgpu.QueueWriteBuffer(queue, buffer.buffer, 0, data, size_of(T))
}


// Note:
// `pipeline` and `shader_module`, `buffer_count` and `buffers` fields in wgpu.RenderPipelineDescriptor
// are filled out autimatically and can be left empty when specifying the config.
RenderPipelineConfig :: struct {
	debug_name:           string,
	vs_shader:            string,
	vs_entry_point:       cstring,
	fs_shader:            string,
	fs_entry_point:       cstring,
	topology:             wgpu.PrimitiveTopology,
	vertex:               VertLayout,
	instance:             VertLayout,
	bind_group_layouts:   []wgpu.BindGroupLayout,
	push_constant_ranges: []wgpu.PushConstantRange,
	blend:                Maybe(wgpu.BlendState), // if nil, no blending.
	format:               wgpu.TextureFormat,
	depth:                Maybe(DepthConfig),
}
DepthConfig :: struct {
	depth_write_enabled: bool,
	depth_compare:       wgpu.CompareFunction,
}
// DEPTH_IGNORE: Maybe(DepthConfig) = nil
DEPTH_IGNORE: Maybe(DepthConfig) = DepthConfig {
	depth_write_enabled = false,
	depth_compare       = wgpu.CompareFunction.Always,
}

ALPHA_BLENDING :: wgpu.BlendState {
	color = wgpu.BlendComponent {
		srcFactor = .SrcAlpha,
		dstFactor = .OneMinusSrcAlpha,
		operation = .Add,
	},
	alpha = BLEND_COMPONENT_OVER,
}
PREMULTIPLIED_ALPHA_BLENDING :: wgpu.BlendState {
	color = BLEND_COMPONENT_OVER,
	alpha = BLEND_COMPONENT_OVER,
}
BLEND_COMPONENT_OVER :: wgpu.BlendComponent {
	srcFactor = .One,
	dstFactor = .OneMinusSrcAlpha,
	operation = .Add,
}
BLEND_COMPONENT_REPLACE :: wgpu.BlendComponent {
	srcFactor = .One,
	dstFactor = .Zero,
	operation = .Add,
}

VertAttibute :: struct {
	format: wgpu.VertexFormat,
	offset: uintptr,
}
VertLayout :: struct {
	ty_id:      typeid,
	attributes: []VertAttibute,
}

RenderPipeline :: struct {
	config:   RenderPipelineConfig,
	layout:   wgpu.PipelineLayout,
	pipeline: wgpu.RenderPipeline,
}


SHADERS_DIRECTORY: []runtime.Load_Directory_File = #load_directory("../shaders")
render_pipeline_create_or_panic :: proc(pipeline: ^RenderPipeline, reg: ^ShaderRegistry) {
	err := render_pipeline_create(pipeline, reg)
	if err != nil {
		fmt.panicf(
			"Failed to create Render Pipeline \"%s\": %s",
			pipeline.config.debug_name,
			err.(WgpuError).message,
		)
	}
}

render_pipeline_create :: proc(pipeline: ^RenderPipeline, reg: ^ShaderRegistry) -> MaybeWgpuError {
	config := &pipeline.config
	wgpu.DevicePushErrorScope(reg.device, .Validation)
	if pipeline.layout == nil {
		push_consts := config.push_constant_ranges
		extras := wgpu.PipelineLayoutExtras {
			chain = {sType = .PipelineLayoutExtras},
			pushConstantRangeCount = uint(len(push_consts)),
			pushConstantRanges = nil if len(push_consts) == 0 else &push_consts[0],
		}
		bindGroupLayouts :=
			nil if len(config.bind_group_layouts) == 0 else &config.bind_group_layouts[0]
		layout_desc := wgpu.PipelineLayoutDescriptor {
			nextInChain          = &extras.chain,
			bindGroupLayoutCount = uint(len(config.bind_group_layouts)),
			bindGroupLayouts     = bindGroupLayouts,
		}

		pipeline.layout = wgpu.DeviceCreatePipelineLayout(reg.device, &layout_desc)
	}

	vs_shader_module := shader_registry_get(reg, config.vs_shader)
	fs_shader_module := shader_registry_get(reg, config.fs_shader)

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
		depth_stencil =
		&wgpu.DepthStencilState {
			format = DEPTH_TEXTURE_FORMAT,
			depthWriteEnabled = b32(depth_config.depth_write_enabled),
			depthCompare = depth_config.depth_compare,
			stencilFront = STENCIL_IGNORE,
			stencilBack = STENCIL_IGNORE,
		}
	}

	pipeline_descriptor := wgpu.RenderPipelineDescriptor {
		label = strings.clone_to_cstring(config.debug_name),
		layout = pipeline.layout,
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
		primitive = wgpu.PrimitiveState{topology = config.topology, cullMode = .None},
		multisample = {count = 1, mask = 0xFFFFFFFF},
	}
	pipeline_handle := wgpu.DeviceCreateRenderPipeline(reg.device, &pipeline_descriptor)
	err := wgpu_pop_error_scope(reg.device)
	if err == nil {
		old_pipeline := pipeline.pipeline
		pipeline.pipeline = pipeline_handle
		if old_pipeline != nil {
			wgpu.RenderPipelineRelease(old_pipeline)
		}
		shader_registry_register_pipeline(reg, pipeline)
	}

	return err
}

render_pipeline_destroy :: proc(pipeline: ^RenderPipeline) {
	// todo! config is not destroyed
	if pipeline.layout != nil {
		wgpu.PipelineLayoutRelease(pipeline.layout)
	}
	if pipeline.pipeline != nil {
		wgpu.RenderPipelineRelease(pipeline.pipeline)
	}
}

WgpuError :: struct {
	type:    wgpu.ErrorType,
	message: string,
}
MaybeWgpuError :: union {
	WgpuError,
}
wgpu_pop_error_scope :: proc(device: wgpu.Device) -> MaybeWgpuError {
	ErrorRes :: struct {
		state: enum {
			Pending,
			Success,
			Error,
		},
		error: WgpuError,
	}
	error_res := ErrorRes {
		state = .Pending,
	}
	error_callback :: proc "c" (type: wgpu.ErrorType, message: cstring, userdata: rawptr) {
		context = runtime.default_context()
		error_res: ^ErrorRes = auto_cast userdata
		if type == .NoError {
			error_res.state = .Success
		} else {
			error_res.state = .Error
			error_res.error = WgpuError{type, strings.clone_from_cstring(message)}
		}
	}
	wgpu.DevicePopErrorScope(device, error_callback, &error_res)
	for error_res.state == .Pending {}
	if error_res.state == .Error {
		return error_res.error
	}
	return nil
}


// This is the set of limits that is guaranteed to work on all modern backends and is
// guaranteed to be supported by WebGPU. Applications needing more modern features can
// use this as a reasonable set of limits if they are targeting only desktop and modern
// mobile devices.
WGPU_DEFAULT_LIMITS :: wgpu.Limits {
	maxTextureDimension1D                     = 8192,
	maxTextureDimension2D                     = 8192,
	maxTextureDimension3D                     = 2048,
	maxTextureArrayLayers                     = 256,
	maxBindGroups                             = 4,
	maxBindGroupsPlusVertexBuffers            = 24,
	maxBindingsPerBindGroup                   = 1000,
	maxDynamicUniformBuffersPerPipelineLayout = 8,
	maxDynamicStorageBuffersPerPipelineLayout = 4,
	maxSampledTexturesPerShaderStage          = 16,
	maxSamplersPerShaderStage                 = 16,
	maxStorageBuffersPerShaderStage           = 8,
	maxStorageTexturesPerShaderStage          = 4,
	maxUniformBuffersPerShaderStage           = 12,
	maxUniformBufferBindingSize               = 64 << 10, // (64 KiB)
	maxStorageBufferBindingSize               = 128 << 20, // (128 MiB)
	minUniformBufferOffsetAlignment           = 256,
	minStorageBufferOffsetAlignment           = 256,
	maxVertexBuffers                          = 8,
	maxBufferSize                             = 256 << 20, // (256 MiB)
	maxVertexAttributes                       = 16,
	maxVertexBufferArrayStride                = 2048,
	maxInterStageShaderComponents             = 60,
	maxInterStageShaderVariables              = 16,
	maxColorAttachments                       = 8,
	maxColorAttachmentBytesPerSample          = 32,
	maxComputeWorkgroupStorageSize            = 16384,
	maxComputeInvocationsPerWorkgroup         = 256,
	maxComputeWorkgroupSizeX                  = 256,
	maxComputeWorkgroupSizeY                  = 256,
	maxComputeWorkgroupSizeZ                  = 64,
	maxComputeWorkgroupsPerDimension          = 65535,
}


// This is a set of limits that is guaranteed to work on almost all backends, including
// “downlevel” backends such as OpenGL and D3D11, other than WebGL. For most applications
// we recommend using these limits, assuming they are high enough for your application,
// and you do not intent to support WebGL.
WGPU_DOWNLEVEL_LIMITS :: wgpu.Limits {
	maxTextureDimension1D                     = 2048,
	maxTextureDimension2D                     = 2048,
	maxTextureDimension3D                     = 256,
	maxTextureArrayLayers                     = 256,
	maxBindGroups                             = 4,
	maxBindGroupsPlusVertexBuffers            = 24,
	maxBindingsPerBindGroup                   = 1000,
	maxDynamicUniformBuffersPerPipelineLayout = 8,
	maxDynamicStorageBuffersPerPipelineLayout = 4,
	maxSampledTexturesPerShaderStage          = 16,
	maxSamplersPerShaderStage                 = 16,
	maxStorageBuffersPerShaderStage           = 4,
	maxStorageTexturesPerShaderStage          = 4,
	maxUniformBuffersPerShaderStage           = 12,
	maxUniformBufferBindingSize               = 16 << 10, // (16 KiB)
	maxStorageBufferBindingSize               = 128 << 20, // (128 MiB)
	minUniformBufferOffsetAlignment           = 256,
	minStorageBufferOffsetAlignment           = 256,
	maxVertexBuffers                          = 8,
	maxBufferSize                             = 256 << 20, // (256 MiB)
	maxVertexAttributes                       = 16,
	maxVertexBufferArrayStride                = 2048,
	maxInterStageShaderComponents             = 60,
	maxInterStageShaderVariables              = 16,
	maxColorAttachments                       = 8,
	maxColorAttachmentBytesPerSample          = 32,
	maxComputeWorkgroupStorageSize            = 16352,
	maxComputeInvocationsPerWorkgroup         = 256,
	maxComputeWorkgroupSizeX                  = 256,
	maxComputeWorkgroupSizeY                  = 256,
	maxComputeWorkgroupSizeZ                  = 64,
	maxComputeWorkgroupsPerDimension          = 65535,
}
