package quat

import "base:runtime"
import "core:fmt"
import "core:strings"
import wgpu "vendor:wgpu"

DynamicBuffer :: struct($T: typeid) {
	buffer: wgpu.Buffer,
	usage:  wgpu.BufferUsageFlags,
	size:   u64, // capacity * size_of(T) in bytes, the number of bytes that is actually allocated for the buffer on the GPU
	length: int, // number of elements currently in the buffer
}

MIN_BUFFER_SIZE :: 1024
dynamic_buffer_init :: proc(this: ^DynamicBuffer($T), usage: wgpu.BufferUsageFlags) {
	this.usage = {.CopyDst} | usage
}

_target_buffer_size :: #force_inline proc "contextless" (n_elements: int, size_of_t: int) -> u64 {
	return u64(max(next_power_of_two(n_elements * size_of_t), MIN_BUFFER_SIZE))
}


dynamic_buffer_reserve :: proc(this: ^DynamicBuffer($T), for_n_total_elements: int, loc := #caller_location) {
	target_size := _target_buffer_size(for_n_total_elements, size_of(T))
	if target_size > this.size {
		if this.size != 0 {
			dynamic_buffer_destroy(this)
		}
		this.size = target_size
		assert(PLATFORM.device != nil, tprint(loc))
		this.buffer = wgpu.DeviceCreateBuffer(
			PLATFORM.device,
			&wgpu.BufferDescriptor{usage = this.usage, size = target_size, mappedAtCreation = false},
		)
	}
}

dynamic_buffer_clear :: proc "contextless" (this: ^DynamicBuffer($T)) {
	this.length = 0
}

// overwrites all data in the buffer, resizing it if necessary
dynamic_buffer_write :: proc(this: ^DynamicBuffer($T), elements: []T, loc := #caller_location) {
	assert(PLATFORM.queue != nil, tprint(loc))
	this.length = len(elements)
	if this.length == 0 {
		return
	}
	dynamic_buffer_reserve(this, this.length)
	used_size := uint(this.length * size_of(T))
	wgpu.QueueWriteBuffer(PLATFORM.queue, this.buffer, 0, raw_data(elements), used_size)
}

// appends to the end of the buffer, but requires that the buffer has enough size allocated, for this to succeed.
// use in combination with `dynamic_buffer_reserve`
dynamic_buffer_append_no_resize :: proc(this: ^DynamicBuffer($T), elements: []T, loc := #caller_location) {
	used_size := u64(this.length * size_of(T))
	additional_size := u64(len(elements) * size_of(T))
	assert(this.size >= used_size + additional_size)
	this.length += len(elements)
	wgpu.QueueWriteBuffer(PLATFORM.queue, this.buffer, used_size, raw_data(elements), uint(additional_size))
}

dynamic_buffer_write_many :: proc(
	buffer: ^DynamicBuffer($T),
	element_slices: [][]T,
	device: wgpu.Device,
	queue: wgpu.Queue,
) {
	unimplemented()
}

dynamic_buffer_destroy :: proc(buffer: ^DynamicBuffer($T)) {
	if buffer.buffer != nil {
		wgpu.BufferRelease(buffer.buffer)
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
	wgpu.BufferRelease(buffer.buffer) // TODO: What is the difference between BufferRelease and BufferRelease
}
uniform_buffer_create :: proc($T: typeid) -> (buffer: UniformBuffer(T)) {
	buffer.usage |= {.CopyDst, .Uniform}
	buffer.buffer = wgpu.DeviceCreateBuffer(
		PLATFORM.device,
		&wgpu.BufferDescriptor{usage = buffer.usage, size = size_of(T), mappedAtCreation = false},
	)
	buffer.bind_group_layout = uniform_bind_group_layout_cached(T)
	bind_group_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, buffer = buffer.buffer, offset = 0, size = u64(size_of(T))},
	}
	buffer.bind_group = wgpu.DeviceCreateBindGroup(
		PLATFORM.device,
		&wgpu.BindGroupDescriptor {
			layout = buffer.bind_group_layout,
			entryCount = 1,
			entries = raw_data(bind_group_entries[:]),
		},
	)
	return buffer
}

// maps size to a bindgroup layout for uniforms
CACHED_UNIFORM_BIND_GROUP_LAYOUTS: map[u64]wgpu.BindGroupLayout
uniform_bind_group_layout_cached :: proc($T: typeid) -> wgpu.BindGroupLayout {
	size := u64(size_of(T))
	_, layout, just_inserted, _ := map_entry(&CACHED_UNIFORM_BIND_GROUP_LAYOUTS, size)
	if just_inserted {
		layout^ = wgpu.DeviceCreateBindGroupLayout(
			PLATFORM.device,
			&wgpu.BindGroupLayoutDescriptor {
				entryCount = 1,
				entries = &wgpu.BindGroupLayoutEntry {
					binding = 0,
					visibility = {.Vertex, .Fragment},
					buffer = wgpu.BufferBindingLayout {
						type = .Uniform,
						hasDynamicOffset = false,
						minBindingSize = size,
					},
				},
			},
		)
	}
	return layout^
}

uniform_buffer_write :: proc(buffer: ^UniformBuffer($T), data: ^T) {
	wgpu.QueueWriteBuffer(PLATFORM.queue, buffer.buffer, 0, data, size_of(T))
}


// Note:
// `pipeline` and `shader_module`, `buffer_count` and `buffers` fields in wgpu.RenderPipelineDescriptor
// are filled out autimatically and can be left empty when specifying the config.
RenderPipelineConfig :: struct {
	debug_name:           string,
	vs_shader:            string,
	vs_entry_point:       string,
	fs_shader:            string,
	fs_entry_point:       string,
	topology:             wgpu.PrimitiveTopology,
	cull_mode:            wgpu.CullMode,
	vertex:               VertLayout,
	instance:             VertLayout,
	bind_group_layouts:   []wgpu.BindGroupLayout,
	push_constant_ranges: []wgpu.PushConstantRange,
	blend:                Maybe(wgpu.BlendState), // if nil, no blending.
	format:               wgpu.TextureFormat,
	depth:                Maybe(DepthConfig),
	// // just a single string flag that can be set to conditionally include some lines of wgsl, only if this is set,
	// // e.g. say `flag = "WORLDSPACE"` and then in the wgsl: `#WORLDSPACE   out.pos = vec2f(1.0,2.0);`
	// flag:                 string,
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
	color = wgpu.BlendComponent{srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha, operation = .Add},
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
	on_error :: proc "c" (
		status: wgpu.PopErrorScopeStatus,
		type: wgpu.ErrorType,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		context = runtime.default_context()
		error_res := cast(^ErrorRes)userdata1
		if type == .NoError {
			error_res.state = .Success
		} else {
			error_res.state = .Error
			error_res.error = WgpuError{type, message}
		}
	}
	wgpu.DevicePopErrorScope(device, wgpu.PopErrorScopeCallbackInfo{callback = on_error, userdata1 = &error_res})
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
