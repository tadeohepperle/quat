package quat

import "base:runtime"
import "core:fmt"
import "core:strings"
import wgpu "vendor:wgpu"

DynamicBuffer :: struct($T: typeid) {
	device:   wgpu.Device,
	queue:    wgpu.Queue,
	buffer:   wgpu.Buffer,
	usage:    wgpu.BufferUsageFlags,
	size:     u64, // in bytes
	length:   int,
	capacity: int,
}

MIN_BUFFER_CAPACITY :: 1024
dynamic_buffer_init :: proc(
	this: ^DynamicBuffer($T),
	usage: wgpu.BufferUsageFlags,
	device: wgpu.Device,
	queue: wgpu.Queue,
) {
	this.usage = {.CopyDst} | usage
	this.device = device
	this.queue = queue
}

dynamic_buffer_write :: proc(this: ^DynamicBuffer($T), elements: []T, loc := #caller_location) {
	assert(this.queue != nil, tprint(loc))
	this.length = len(elements)
	if this.length == 0 {
		return
	}

	target_capacity := max(next_pow2_number(this.length), MIN_BUFFER_CAPACITY)
	element_size := size_of(T)
	// if not enough space or unallocated, allocate  new buffer:
	if this.capacity < target_capacity {
		// throw old buffer away if already allocated
		if this.capacity != 0 {
			dynamic_buffer_destroy(this)
		}
		this.capacity = target_capacity
		this.size = u64(this.capacity * element_size)
		this.buffer = wgpu.DeviceCreateBuffer(
			this.device,
			&wgpu.BufferDescriptor{usage = this.usage, size = this.size, mappedAtCreation = false},
		)
	}
	used_size := uint(this.length * element_size)
	wgpu.QueueWriteBuffer(this.queue, this.buffer, 0, raw_data(elements), used_size)
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
uniform_buffer_create_from_bind_group_layout :: proc(
	buffer: ^UniformBuffer($T),
	device: wgpu.Device,
	bind_group_layout: wgpu.BindGroupLayout,
) {
	buffer.usage |= {.CopyDst, .Uniform}
	buffer.buffer = wgpu.DeviceCreateBuffer(
		device,
		&wgpu.BufferDescriptor{usage = buffer.usage, size = size_of(T), mappedAtCreation = false},
	)
	buffer.bind_group_layout = bind_group_layout
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
uniform_bind_group_layout :: proc(device: wgpu.Device, size_of_t: u64) -> wgpu.BindGroupLayout {
	return wgpu.DeviceCreateBindGroupLayout(
		device,
		&wgpu.BindGroupLayoutDescriptor {
			entryCount = 1,
			entries = &wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Vertex, .Fragment},
				buffer = wgpu.BufferBindingLayout {
					type = .Uniform,
					hasDynamicOffset = false,
					minBindingSize = size_of_t,
				},
			},
		},
	)
}
uniform_buffer_create :: proc(buffer: ^UniformBuffer($T), device: wgpu.Device) {
	layout := uniform_bind_group_layout(device, size_of(T))
	uniform_buffer_create_from_bind_group_layout(buffer, device, layout)
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
