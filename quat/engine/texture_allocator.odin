package engine
import q ".."
import "core:fmt"
import "vendor:wgpu"

IVec2 :: [2]int
Image :: q.Image
Atlas :: q.Atlas
TextureTile :: q.TextureTile
TextureHandle :: q.TextureHandle
None :: q.None


AtlasId :: distinct u32
SrcImageId :: distinct u32

MotionTextureAllocator :: struct {
	atlas:       Atlas, // stores coords of diffuse_img, motion_img should be the same but scaled, so uv of diffuse and motion img are the same!
	diffuse_img: Image,
	motion_img:  Image,
	ratio:       int, // diffuse_img.size should be an integer multiple of motion_img.size
	texture:     q.MotionTextureHandle,
}
// currently only supports fixed size, no resizing
motion_texture_allocator_create :: proc(diffuse_size: IVec2, motion_size: IVec2) -> (res: MotionTextureAllocator) {
	ratio, is_ratio := _is_ratio(diffuse_size, motion_size)
	assert(is_ratio, q.tprint("non-integer ratio between diffuse size", diffuse_size, "and motion size", motion_size))
	res.ratio = ratio

	texture := q.motion_texture_create(diffuse_size, motion_size)
	q.atlas_init(&res.atlas, diffuse_size)
	res.texture = q.assets_insert(texture)
	res.diffuse_img = q.image_create(diffuse_size)
	res.motion_img = q.image_create(motion_size)
	return res
}

_is_ratio :: proc(big: IVec2, small: IVec2) -> (ratio: int, ok: bool) {
	if big == small {
		return 1, true
	}
	if big.x % small.x != 0 || big.y % small.y != 0 {
		return 0, false
	}
	if big.x < small.x || big.y < small.y {
		return 0, false
	}

	ratio_x := big.x / small.x
	ratio_y := big.y / small.y
	if ratio_x != ratio_y {
		return 0, false
	}
	return ratio_x, true
}

DiffuseAndMotionImage :: struct {
	diffuse: q.ImageView,
	motion:  q.ImageView,
}
motion_texture_allocator_allocate_flipbook :: proc(
	this: ^MotionTextureAllocator,
	diffuse_image: q.ImageView,
	motion_image: q.ImageView,
	n_x_tiles: int,
	n_y_tiles: int,
	n_tiles: int,
	sync_to_texture: bool = true,
) -> (
	flipbook: q.FlipbookData,
	err: q.Error,
) {

	d_size := diffuse_image.size
	m_size := motion_image.size

	if n_tiles > n_x_tiles * n_y_tiles || n_tiles <= 0 {
		return {}, "invalid tiling params n_x_tiles, n_y_tiles, n_tiles"
	}

	if d_size.x % n_x_tiles != 0 ||
	   d_size.y % n_y_tiles != 0 ||
	   m_size.x % n_x_tiles != 0 ||
	   m_size.y % n_y_tiles != 0 {
		return {}, "diffuse and motion image sizes need to be divisible by n_tiles_x and n_tiles_y"
	}

	ratio, is_ratio := _is_ratio(diffuse_image.size, motion_image.size)
	if !is_ratio {
		return {}, "non integer ratio between diffuse image size and motion image size!"
	}
	if ratio != this.ratio {
		return {}, "allocators ratio of diffuse/motion size should be the same as flipbook"
	}

	pos_in_atlas, success := q.atlas_allocate(&this.atlas, d_size)
	if !success {
		return {}, "no space for all motion frames in atlas!"
	}

	assert(pos_in_atlas.x % ratio == 0 && pos_in_atlas.y % ratio == 0)
	atlas_size_f := q.ivec2_to_vec2(this.atlas.size)

	start_uv := q.ivec2_to_vec2(pos_in_atlas) / atlas_size_f
	uv_tile_size := q.ivec2_to_vec2(d_size) / atlas_size_f / Vec2{f32(n_x_tiles), f32(n_y_tiles)}

	q.image_copy_into(&this.diffuse_img, diffuse_image, pos_in_atlas)
	q.image_copy_into(&this.motion_img, motion_image, pos_in_atlas / ratio)

	flipbook.start_uv = start_uv
	flipbook.uv_tile_size = uv_tile_size
	flipbook.n_tiles = u32(n_tiles)
	flipbook.n_x_tiles = u32(n_x_tiles)

	if sync_to_texture {
		_motion_texture_allocator_sync(this)
	}
	return flipbook, nil
}

_motion_texture_allocator_sync :: proc(this: ^MotionTextureAllocator) {
	texture: q.MotionTexture = q.assets_get(this.texture)
	q.motion_texture_write(texture, this.diffuse_img, this.motion_img)
}

// motion_texture_allocator_bind_group :: proc(this: MotionTextureAllocator) -> wgpu.BindGroup {
// 	return this.texture.bind_group
// }


TextureAllocatorSettings :: struct {
	max_size:         IVec2,
	max_n_atlases:    int,
	auto_grow_shrink: bool,
}

TextureAllocator :: struct {
	settings:           TextureAllocatorSettings,
	atlases:            [dynamic]_TextureAtlas,
	src_images:         [dynamic]Maybe(SrcImage),
	free_src_image_ids: [dynamic]SrcImageId,
	grow_sizes:         []IVec2,
}

_TextureAtlas :: struct {
	id:            AtlasId,
	atlas:         Atlas,
	image:         Image,
	texture:       TextureHandle,
	src_image_ids: [dynamic]SrcImageId,
}
SrcImage :: struct {
	id:           SrcImageId,
	atlas_id:     AtlasId,
	src_path:     string,
	image:        Image,
	pos_in_atlas: IVec2, // top-left corner of rectangle in atlas that is image.size + padding * 2 pixels big
	padding:      int, // the actual image starts at alloc_pos_in_atlas + padding
	texture_tile: TextureTile,
}

texture_allocator_create :: proc(settings: TextureAllocatorSettings) -> (this: TextureAllocator) {
	this.settings = settings
	max_size_idx := -1
	for size, idx in ATLAS_SIZES {
		if size == settings.max_size {
			max_size_idx = idx
			return
		}
	}
	if max_size_idx == -1 {
		panic(fmt.tprint("settings.max_size is", settings.max_size, "but it should be one of these:", ATLAS_SIZES))
	}
	this.grow_sizes = ATLAS_SIZES[:max_size_idx + 1]

	return this
}
texture_allocator_drop :: proc(this: ^TextureAllocator) {
	for slot in this.src_images {
		src_img := slot.? or_continue
		if src_img.src_path != "" {
			delete(src_img.src_path)
			q.image_drop(&src_img.image)
		}
	}
	delete(this.src_images)
	delete(this.free_src_image_ids)
	for &atlas in this.atlases {
		q.atlas_drop(&atlas.atlas)
		q.image_drop(&atlas.image)
		delete(atlas.src_image_ids)
		if atlas.texture != {} {
			texture := q.assets_remove(atlas.texture)
			q.texture_destroy(&texture)
			atlas.texture = {}
		}
	}
	delete(this.atlases)
	// no need to deallocate this.grow_sizes, it is just a slice into ATLAS_SIZES
}

@(private)
_next_src_img_id :: proc(this: ^TextureAllocator) -> SrcImageId {
	if len(this.free_src_image_ids) > 0 {
		return pop(&this.free_src_image_ids)
	} else {
		return SrcImageId(len(this.src_images))
	}
}

@(private)
_insert_new_src_img :: proc(this: ^TextureAllocator, img: Image, src_path: string) -> ^SrcImage {
	next_id: SrcImageId
	if len(this.free_src_image_ids) > 0 {
		next_id = pop(&this.free_src_image_ids)
	} else {
		next_id = SrcImageId(len(this.src_images))
	}
	append(&this.src_images, SrcImage{id = next_id, src_path = src_path, image = img})
	return &this.src_images[next_id].(SrcImage)
}

AddImgResult :: struct {
	tile: TextureTile,
	id:   SrcImageId,
	grew: bool,
	ok:   bool,
}
texture_allocator_get_info :: proc(this: TextureAllocator, id: SrcImageId) -> SrcImage {
	return this.src_images[id].(SrcImage)
}
texture_allocator_add_img :: proc(this: ^TextureAllocator, img: Image, padding: int = 0) -> AddImgResult {
	id := _next_src_img_id(this)
	new_src_img := SrcImage {
		id       = id,
		src_path = "",
		image    = img,
		padding  = padding,
	}
	grew, ok: bool
	for &atlas in this.atlases {
		grew, ok = _try_add_img(&atlas, &new_src_img, this.settings.auto_grow_shrink, &this.src_images)
		if ok {
			break
		}
		assert(grew == false)
	}
	if !ok && len(this.atlases) < this.settings.max_n_atlases {
		new_atlas_id := AtlasId(len(this.atlases))
		new_atlas_size := this.grow_sizes[0] if this.settings.auto_grow_shrink else this.settings.max_size
		new_atlas := _atlas_create(new_atlas_id, new_atlas_size)
		grew, ok = _try_add_img(&new_atlas, &new_src_img, this.settings.auto_grow_shrink, &this.src_images)
		append(&this.atlases, new_atlas)
	}
	if !ok {
		assert(!grew)
		return AddImgResult{ok = false}
	}
	append(&this.src_images, new_src_img)
	return AddImgResult{tile = new_src_img.texture_tile, id = new_src_img.id, grew = grew, ok = true}
}

texture_allocator_remove_img :: proc(this: ^TextureAllocator, id: SrcImageId) -> (ok: bool) {
	src_img, slot_has_src := this.src_images[id].(SrcImage)
	if !slot_has_src {return false}
	atlas := &this.atlases[src_img.atlas_id]
	found_id_in_atlas := false
	for other_id, idx in atlas.src_image_ids {
		if other_id == id {
			unordered_remove(&atlas.src_image_ids, idx)
			found_id_in_atlas = true
			break
		}
	}
	assert(found_id_in_atlas)
	assert(q.atlas_deallocate(&atlas.atlas, q.Area{src_img.pos_in_atlas, src_img.image.size}))
	append(&this.free_src_image_ids, id)
	if src_img.src_path != "" {
		delete(src_img.src_path)
		q.image_drop(&src_img.image)
	}
	this.src_images[id] = nil
	return true
}

@(private)
_remove_img :: proc(this: ^_TextureAtlas, src: SrcImage) {
	found_id_in_atlas := false
	for other_id, idx in this.src_image_ids {
		if other_id == src.id {
			unordered_remove(&this.src_image_ids, idx)
			found_id_in_atlas = true
			break
		}
	}
	assert(found_id_in_atlas)
	assert(q.atlas_deallocate(&this.atlas, q.Area{src.pos_in_atlas, src.image.size}))
	// todo: make the decallocated region transparent in the atlas image and write to the texture?
	// or is unnecessary?
}

@(private)
_try_add_img :: proc(
	this: ^_TextureAtlas,
	src: ^SrcImage,
	grow_allowed: bool,
	src_images: ^[dynamic]Maybe(SrcImage),
) -> (
	grew: bool,
	ok: bool,
) {
	img_size_with_padding := src.image.size + src.padding * 2
	pos_in_atlas: IVec2
	if grow_allowed {
		remap_allocs: map[IVec2]IVec2
		old_atlas_size := this.atlas.size
		pos_in_atlas, remap_allocs = q.atlas_allocate_growing_if_necessary(
			&this.atlas,
			img_size_with_padding,
			ATLAS_SIZES,
		) or_return
		grew = old_atlas_size != this.atlas.size
		if grew {
			q.image_drop(&this.image)
			if this.texture != {} {
				texture := q.assets_remove(this.texture)
				q.texture_destroy(&texture)
				this.texture = {}
			}
			this.image = q.image_create(this.atlas.size)
			assert(len(remap_allocs) == len(this.src_image_ids))
			for id in this.src_image_ids {
				src_img := &src_images[id].(SrcImage) or_else panic("slot not filled")
				new_pos_in_atlas, has_new_pos := remap_allocs[src_img.pos_in_atlas]
				assert(
					has_new_pos,
					"if atlas grew, the remap_allocs map should contain entry for all prev allocations",
				)
				src_img.pos_in_atlas = new_pos_in_atlas
				q.image_copy_into(&this.image, q.image_view(src_img.image), new_pos_in_atlas + src_img.padding)
			}
		}
	} else {
		pos_in_atlas = q.atlas_allocate(&this.atlas, img_size_with_padding) or_return
	}
	src.atlas_id = this.id
	src.pos_in_atlas = pos_in_atlas
	q.image_copy_into(&this.image, q.image_view(src.image), pos_in_atlas + src.padding)
	_sync_atlas_texture_to_atlas_image(this, src_images)
	append(&this.src_image_ids, src.id)
	src_tile_uv := atlas_uv_aabb(this.atlas.size, pos_in_atlas + src.padding, src.image.size)
	src.texture_tile = q.TextureTile{this.texture, src_tile_uv}
	return grew, true
}

_sync_atlas_texture_to_atlas_image :: proc(this: ^_TextureAtlas, src_images: ^[dynamic]Maybe(SrcImage)) {
	if this.texture == {} {
		if this.atlas.size != 0 {
			this.texture = create_texture_from_image(this.image)
		} else {
			return
		}
	} else {
		size_u := get_texture_info(this.texture).size
		size_i := IVec2{int(size_u.x), int(size_u.y)}
		if size_i == this.atlas.size {
			write_image_to_texture(this.image, this.texture)
			return
		} else {
			texture := q.assets_remove(this.texture)
			q.texture_destroy(&texture)
			this.texture = create_texture_from_image(this.image)
		}
	}
	// reset the texture tile for all the textures:
	size_f32 := q.ivec2_to_vec2(this.image.size)
	for id in this.src_image_ids {
		src_img := &src_images[id].(SrcImage) or_else panic("slot not filled")
		assert(src_img.atlas_id == this.id)
		uv := atlas_uv_aabb(this.image.size, src_img.pos_in_atlas, src_img.image.size)
		src_img.texture_tile = TextureTile{this.texture, uv}
	}
}

atlas_uv_aabb :: proc(atlas_size: IVec2, pos_in_atlas: IVec2, size_of_region: IVec2) -> q.Aabb {
	size_f32 := q.ivec2_to_vec2(atlas_size)
	uv_min := q.ivec2_to_vec2(pos_in_atlas) / size_f32
	uv_max := q.ivec2_to_vec2(pos_in_atlas + size_of_region) / size_f32
	return q.Aabb{uv_min, uv_max}
}
_atlas_create :: proc(id: AtlasId, size: IVec2) -> (this: _TextureAtlas) {
	assert(size != {0, 0})
	this.id = id
	q.atlas_init(&this.atlas, size)
	this.image = q.image_create(size)
	return this
}

ATLAS_SIZES := []IVec2 {
	{128, 128},
	{256, 256},
	{512, 256},
	{512, 512},
	{1024, 512},
	{1024, 1024},
	{2048, 1024},
	{2048, 2048}, // maximum texture size
}
