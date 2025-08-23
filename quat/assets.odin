package quat

import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:log"
import "core:mem"
import "core:os"
import "shared:sdffont"
import wgpu "vendor:wgpu"


DEFAULT_FONT :: FontHandle{0}
DEFAULT_TEXTURE :: TextureHandle{0}
DEFAULT_MOTION_TEXTURE :: MotionTextureHandle{0}
FontHandle :: Handle(Font)
TextureHandle :: Handle(Texture)
MotionTextureHandle :: Handle(MotionTexture)
TextureArrayHandle :: Handle(Texture) // just the same ...
SkinnedMeshHandle :: Handle(SkinnedMesh)
Assets :: struct {
	textures: Slotmap(Texture),
	fonts:    Slotmap(Font),
	// type punned slot maps
	slotmaps: map[typeid]Slotmap(None),
}

assets_insert :: proc(elem: $T) -> Handle(T) {
	slotmap: ^Slotmap(T) = assets_get_map_ref(T)
	return slotmap_insert(slotmap, elem)
}
assets_get_map :: proc($T: typeid) -> Slotmap(T) {
	return assets_get_map_ref(T)^
}
assets_get_map_ref :: proc($T: typeid) -> ^Slotmap(T) {
	when T == Texture {
		return &PLATFORM.assets.textures
	} else when T == Font {
		return &PLATFORM.assets.fonts
	} else {
		_, punned_slotmap, _just_inserted, _ := map_entry(&PLATFORM.assets.slotmaps, T)
		slotmap: ^Slotmap(T) = cast(^Slotmap(T))punned_slotmap
		return slotmap
	}
}
assets_remove :: proc(handle: Handle($T)) -> (elem: T, ok: bool) #optional_ok {
	slotmap: ^Slotmap(T) = assets_get_map_ref(T)
	return slotmap_remove(slotmap, handle)
}
assets_get :: proc(handle: Handle($T)) -> (elem: T, ok: bool) #optional_ok {
	slotmap: ^Slotmap(T) = assets_get_map_ref(T)
	return slotmap_get(slotmap^, handle)
}
assets_get_ref :: proc(handle: Handle($T)) -> (elem: ^T, ok: bool) #optional_ok {
	slotmap: ^Slotmap(T) = assets_get_map_ref(T)
	return slotmap_get_ref(slotmap, handle)
}


Handle :: struct($T: typeid) {
	idx: u32,
}
Slotmap :: struct($T: typeid) {
	slots:         [dynamic]SlotmapElement(T),
	next_free_idx: u32, // there is a linked stack of next free indices starting here, that can be followed through the slots array until NO_FREE_IDX is hit
}
SlotmapElement :: struct($T: typeid) {
	element:       T,
	next_free_idx: u32, // if is NO_FREE_IDX, means that there is an element in here
}
NO_FREE_IDX :: max(u32)
slotmap_insert :: proc(this: ^Slotmap($T), element: T) -> (handle: Handle(T)) {
	if this.next_free_idx >= u32(len(this.slots)) {
		// append a new element to end of elements array:
		handle.idx = u32(len(this.slots))
		append(&this.slots, SlotmapElement(T){element, NO_FREE_IDX})
	} else {
		// there is a free slot at next_handle
		handle.idx = this.next_free_idx
		slot := &this.slots[this.next_free_idx]
		this.next_free_idx = slot.next_free_idx

		slot.element = element
		slot.next_free_idx = NO_FREE_IDX
	}
	return handle
}
slotmap_remove :: proc(this: ^Slotmap($T), handle: Handle(T)) -> (res: T, ok: bool) #optional_ok {
	if handle.idx >= u32(len(this.slots)) {
		return {}, false
	}
	slot := &this.slots[handle.idx]
	if slot.next_free_idx != NO_FREE_IDX {
		return {}, false
	}
	res = slot.element
	slot.next_free_idx = this.next_free_idx
	this.next_free_idx = handle.idx
	return res, true
}
slotmap_get :: #force_inline proc(this: Slotmap($T), handle: Handle(T)) -> (res: T, ok: bool) #optional_ok {
	if handle.idx >= u32(len(this.slots)) {
		return {}, false
	}
	assert(handle.idx < u32(len(this.slots)))
	slot := this.slots[handle.idx]
	if slot.next_free_idx != NO_FREE_IDX {
		return {}, false
	}
	return slot.element, true
}
slotmap_get_ref :: #force_inline proc(this: ^Slotmap($T), handle: Handle(T)) -> (elem: ^T, ok: bool) #optional_ok {
	if handle.idx >= u32(len(this.slots)) {
		return {}, false
	}
	assert(handle.idx < u32(len(this.slots)))
	slot := &this.slots[handle.idx]
	if slot.next_free_idx != NO_FREE_IDX {
		return {}, false
	}
	return &slot.element, true
}
// returns slice in tmp memory with only the taken slots in it, useful for calling a drop function on  all elements in the slotmap
@(private = "file")
slotmap_to_tmp_slice :: proc(this: Slotmap($T)) -> []T {
	elements := make([dynamic]T, 0, len(this.slots), allocator = context.temp_allocator)
	for el in this.slots {
		if el.next_free_idx == NO_FREE_IDX {
			append(&elements, el.element)
		}
	}
	return elements[:]
}
// set i to 0 initially
@(private = "file")
slotmap_iter :: proc "contextless" (this: ^Slotmap($T), i: ^int) -> (element: ^T, handle: Handle(T), ok: bool) {
	idx := i^
	for idx < len(this.slots) {
		el := &this.slots[idx]
		if el.next_free_idx == NO_FREE_IDX {
			i^ = idx + 1
			handle.idx = u32(idx)
			return &el.element, handle, true
		}
		idx += 1
	}
	i^ = idx
	handle.idx = NO_FREE_IDX
	return {}, handle, false
}

slotmap_drop :: proc(slotmap: ^Slotmap($T)) {
	delete(slotmap.slots)
}

@(private)
destroy_assets :: proc() {
	textures := assets_get_map_ref(Texture)
	i := 0
	for texture, _ in slotmap_iter(textures, &i) {
		texture_destroy(texture^)
	}

	fonts := assets_get_map_ref(Font)
	i = 0
	for font, _ in slotmap_iter(&PLATFORM.assets.fonts, &i) {
		font_destroy(font)
	}

	skinned_geometries := assets_get_map_ref(SkinnedGeometry)
	i = 0
	for geom, _ in slotmap_iter(skinned_geometries, &i) {
		_geometry_drop(geom)
	}

	skinned_meshes := assets_get_map_ref(SkinnedMesh)
	i = 0
	for mesh, _ in slotmap_iter(skinned_meshes, &i) {
		_skinned_mesh_drop(mesh)
	}

	slotmap_drop(&PLATFORM.assets.fonts)
	slotmap_drop(&PLATFORM.assets.textures)
	for _, &slotmap in PLATFORM.assets.slotmaps {
		slotmap_drop(&slotmap)
	}
	delete(PLATFORM.assets.slotmaps)
}

@(private)
update_changed_font_atlas_textures :: proc(queue: wgpu.Queue) {
	i := 0
	fonts := assets_get_map_ref(Font)
	textures := assets_get_map(Texture)
	for font, _ in slotmap_iter(fonts, &i) {
		if sdffont.font_has_atlas_image_changed(font.sdf_font) {
			log.info("Update font atlas texture because it has changed:", font.name)
			atlas_image := sdffont.font_get_atlas_image(font.sdf_font)
			texture := slotmap_get(textures, font.texture_handle)
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

// /////////////////////////////////////////////////////////////////////////////
// SECTION: Some utilities for texture loading:
// /////////////////////////////////////////////////////////////////////////////


load_depth_texture :: proc(path: string) -> TextureHandle {
	texture, err := depth_texture_16bit_r_from_image_path(path)
	if err, has_err := err.(string); has_err {
		fmt.panicf("Panic loading depth 16bit R texture from path {}: {}", path, err)
	}
	return assets_insert(texture)
}
load_texture :: proc(path: string, settings: TextureSettings = TEXTURE_SETTINGS_RGBA) -> TextureHandle {
	texture, err := texture_from_image_path(path, settings)
	if err, has_err := err.(string); has_err {
		fmt.panicf("Panic loading texture from path {}: {}", path, err)
	}
	return assets_insert(texture)
}

load_texture_array :: proc(paths: []string, settings: TextureSettings = TEXTURE_SETTINGS_RGBA) -> TextureArrayHandle {
	texture, err := texture_array_from_image_paths(paths, settings)
	if err, has_err := err.(string); has_err {
		fmt.panicf("Panic loading texture array from paths {}:  {}", paths, err)
	}
	return assets_insert(texture)
}
load_font :: proc(ttf_path: string) -> FontHandle {
	font, err := font_from_path(ttf_path)
	if err, has_err := err.(string); has_err {
		fmt.panicf("Panic loading font from ttf path {}:  {}", ttf_path, err)
	}
	return assets_insert(font)
}
