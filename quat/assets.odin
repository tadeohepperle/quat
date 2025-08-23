package quat

import "base:runtime"
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
	slotmaps: map[typeid]AnySlotMap,
}

assets_register_drop_fn :: proc($T: typeid, drop_fn: proc(el: ^T)) {
	assets_get_map_ref(T).drop_fn = drop_fn
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
		slotmap_maybe_init(&PLATFORM.assets.textures)
		return &PLATFORM.assets.textures
	} else when T == Font {
		slotmap_maybe_init(&PLATFORM.assets.fonts)
		return &PLATFORM.assets.fonts
	} else {
		_, punned_slotmap, _just_inserted, _ := map_entry(&PLATFORM.assets.slotmaps, T)
		slotmap: ^Slotmap(T) = cast(^Slotmap(T))punned_slotmap
		slotmap_maybe_init(slotmap)
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
	slots:                      [dynamic]SlotmapElement(T),
	next_free_idx:              u32, // there is a linked stack of next free indices starting here, that can be followed through the slots array until NO_FREE_IDX is hit
	drop_fn:                    Maybe(proc(el: ^T)),
	ty:                         typeid,
	slot_size:                  uintptr,
	next_free_idx_field_offset: uintptr,
}
AnySlotMap :: struct {
	slots:                      runtime.Raw_Dynamic_Array,
	next_free_idx:              u32,
	drop_fn:                    Maybe(proc(el: rawptr)),
	ty:                         typeid,
	slot_size:                  uintptr,
	next_free_idx_field_offset: uintptr,
}

slotmap_maybe_init :: proc(this: ^Slotmap($T)) {
	if this.ty != T {
		this.next_free_idx = NO_FREE_IDX
		this.next_free_idx_field_offset = offset_of(SlotmapElement(T), next_free_idx)
		this.slot_size = size_of(SlotmapElement(T))
		this.ty = T
		this.slots = make([dynamic]SlotmapElement(T), 0, 16, allocator = context.allocator)
	}
}

SlotmapElement :: struct($T: typeid) {
	element:       T,
	next_free_idx: u32, // if is NO_FREE_IDX, means that there is an element in here
}
NO_FREE_IDX :: max(u32)
slotmap_insert :: proc(this: ^Slotmap($T), element: T) -> (handle: Handle(T)) {
	if this.next_free_idx == NO_FREE_IDX {
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
// // set i to 0 initially
// @(private = "file")
// slotmap_iter :: proc "contextless" (this: ^Slotmap($T), i: ^int) -> (element: ^T, handle: Handle(T), ok: bool) {
// 	idx := i^
// 	for idx < len(this.slots) {
// 		el := &this.slots[idx]
// 		if el.next_free_idx == NO_FREE_IDX {
// 			i^ = idx + 1
// 			handle.idx = u32(idx)
// 			return &el.element, handle, true
// 		}
// 		idx += 1
// 	}
// 	i^ = idx
// 	handle.idx = NO_FREE_IDX
// 	return {}, handle, false
// }

slotmap_drop_any :: proc(slotmap: ^AnySlotMap) -> (n_dropped: int) {
	if slotmap.drop_fn != nil {
		drop_fn := transmute(proc(el: rawptr))slotmap.drop_fn
		for i: int = 0; i < slotmap.slots.len; i += 1 {
			slot_ptr := uintptr(slotmap.slots.data) + slotmap.slot_size * uintptr(i)
			slot_next_free_idx := (cast(^u32)(slot_ptr + slotmap.next_free_idx_field_offset))^
			if slot_next_free_idx == NO_FREE_IDX {
				// slot has element
				drop_fn(rawptr(slot_ptr))
				n_dropped += 1
			}

		}
	}
	bytes_len := slotmap.slots.len * int(slotmap.slot_size)
	runtime.mem_free_with_size(slotmap.slots.data, bytes_len, slotmap.slots.allocator)
	return n_dropped
}

@(private)
assets_drop :: proc(assets: ^Assets) {
	print("THERE ARE {} textures", assets.textures)
	fmt.printfln("dropped {} elements of type Texture", slotmap_drop_any(cast(^AnySlotMap)&assets.textures))
	fmt.printfln("dropped {} elements of type Font", slotmap_drop_any(cast(^AnySlotMap)&assets.fonts))
	for _, &slotmap in assets.slotmaps {
		n_dropped := slotmap_drop_any(&slotmap)
		fmt.printfln("dropped {} elements of type {}", n_dropped, slotmap.ty)
	}
	delete(assets.slotmaps)
}

@(private)
update_changed_font_atlas_textures :: proc(queue: wgpu.Queue) {
	i := 0
	fonts := assets_get_map_ref(Font)
	textures := assets_get_map(Texture)

	for font_slot in fonts.slots {
		if font_slot.next_free_idx != NO_FREE_IDX do continue
		font := font_slot.element
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
