package quat

import "core:slice"

IVec2 :: [2]int
// guillotine atlas allocator 
Atlas :: struct {
	size:        IVec2,
	free_areas:  [dynamic]Area,
	allocations: map[IVec2]IVec2, // maps pos to size
}
Area :: struct {
	pos:  IVec2, // top left corner of the allocation
	size: IVec2,
}
atlas_init :: proc(atlas: ^Atlas, size: IVec2) {
	atlas.size = size
	clear(&atlas.free_areas)
	clear(&atlas.allocations)
	append(&atlas.free_areas, Area{pos = {0, 0}, size = size})
}
atlas_clone :: proc(atlas: Atlas) -> (res: Atlas) {
	res.size = atlas.size
	res.free_areas = slice.clone_to_dynamic(atlas.free_areas[:])
	for pos, size in atlas.allocations {
		res.allocations[pos] = size
	}
	return res
}
atlas_drop :: proc(atlas: ^Atlas) {
	delete(atlas.free_areas)
	delete(atlas.allocations)
}
atlas_allocate :: proc(atlas: ^Atlas, item_size: IVec2) -> (pos: IVec2, ok: bool) {
	assert(is_non_negative(item_size))
	idx := _atlas_select_allocation_rect(atlas^, item_size) or_return
	area := atlas.free_areas[idx]
	pos = area.pos
	unordered_remove(&atlas.free_areas, idx)
	diff := area.size - item_size
	new_area_1, new_area_2: Area = ---, ---
	if diff.x > diff.y {
		// split vertically
		new_area_1 = Area {
			pos  = {pos.x, pos.y + item_size.y},
			size = {item_size.x, area.size.y - item_size.y},
		}
		new_area_2 = Area {
			pos  = {pos.x + item_size.x, pos.y},
			size = {area.size.x - item_size.x, area.size.y},
		}
	} else {
		// split horizontally
		new_area_1 = Area {
			pos  = {pos.x + item_size.x, pos.y},
			size = {area.size.x - item_size.x, item_size.y},
		}
		new_area_2 = Area {
			pos  = {pos.x, pos.y + item_size.y},
			size = {area.size.x, area.size.y - item_size.y},
		}
	}
	// only add non-sero sized areas:
	if new_area_1.size.x > 0 && new_area_1.size.y > 0 {
		append(&atlas.free_areas, new_area_1)
	}
	if new_area_2.size.x > 0 && new_area_2.size.y > 0 {
		append(&atlas.free_areas, new_area_2)
	}
	assert(pos not_in atlas.allocations)
	atlas.allocations[pos] = item_size
	return pos, true
}
atlas_deallocate :: proc(atlas: ^Atlas, rect: Area) -> bool {
	if rect.pos not_in atlas.allocations {
		return false
	}
	assert(atlas.allocations[rect.pos] == rect.size)
	delete_key(&atlas.allocations, rect.pos)
	append(&atlas.free_areas, rect)

	// merge free areas that are next to each other:
	for i := 0; i < len(atlas.free_areas); i += 1 {
		j := i + 1
		for j < len(atlas.free_areas) {
			if _try_merge_areas(&atlas.free_areas[i], &atlas.free_areas[j]) {
				// now atlas.free_areas[i] holds the merged area
				unordered_remove(&atlas.free_areas, j)
			} else {
				j += 1
			}
		}
	}
	return true
}

// merge two areas a and b into a, if adjacent
_try_merge_areas :: proc(a: ^Area, b: ^Area) -> bool {
	if a.pos.y == b.pos.y && a.size.y == b.size.y {
		// Merge horizontally
		if a.pos.x + a.size.x == b.pos.x {
			// extend a to the right side such that it covers b
			a.size.x += b.size.x
			return true
		} else if b.pos.x + b.size.x == a.pos.x {
			// extend a to the left side such that it covers b
			a.size.x += b.size.x
			a.pos.x = b.pos.x
			return true
		}
	}
	if a.pos.x == b.pos.x && a.size.x == b.size.x && a.pos.y + a.size.y == b.pos.y {
		// Merge vertically
		if a.pos.y + a.size.y == b.pos.y {
			// extend a to to the region below it such that it covers b
			a.size.y += b.size.y
			return true
		} else if b.pos.y + b.size.y == a.pos.y {
			// extend a to to the region above it side such that it covers b
			a.size.y += b.size.y
			a.pos.y = b.pos.y
			return true
		}
	}
	return false
}

// pick the free area, such that the remaining shorter side is minimized,
// so for a rect R = (rx, ry) and an area F = (fx,fy) we want to minimize min(fx-rx,fy-ry)
// so, diff is F - R, and we minimize the minimum of diff.x and diff.y
// then split the remaining area, such that bigger squarelike areas are maintained.
// that means: split horizontal, if diff.y > diff.x, split vertically, if diff.x > diff
//     ____________
//    |     |      |
//    |  R  |      |
//    |_____|______| split here
//    |            |
//    |            |
//    |            |
//    |            |
//    |____________|
//
_atlas_select_allocation_rect :: proc(atlas: Atlas, item_size: IVec2) -> (idx: int, ok: bool) {
	best_idx: int = -1
	best_min_dim := max(int)
	for area, i in atlas.free_areas {
		diff := area.size - item_size
		if is_non_negative(diff) {
			min_dim := min(diff.x, diff.y)
			if min_dim < best_min_dim {
				best_idx = i
				best_min_dim = min_dim
			}
		}
	}
	return best_idx, best_idx != -1
}

is_non_negative :: proc "contextless" (size: IVec2) -> bool {
	return size.x >= 0 && size.y >= 0
}


// if atlas was grown, positions of allocations can get remapped, so they are != nil if grown (old_pos -> new_pos)
// note: atlas_sizes must be in ascending order
// remap_allocs is returned in tmp memory
atlas_allocate_growing_if_necessary :: proc(
	atlas: ^Atlas,
	item_size: IVec2,
	atlas_sizes: []IVec2,
) -> (
	pos: IVec2,
	remap_allocs: map[IVec2]IVec2,
	ok: bool,
) {
	pos, ok = atlas_allocate(atlas, item_size)
	if ok {
		return pos, nil, true
	}
	// allocation did not work, needs to grow atlas

	next_size_idx: int = -1
	// find the first element that is greater than the current atlas size:
	assert(_sizes_are_ascending(atlas_sizes))
	for size, idx in atlas_sizes {
		if ivec2_greater(size, atlas.size) {
			next_size_idx = idx
			break
		}
	}
	if next_size_idx == -1 {
		// there is no size in the provided sizes greater than the current atlas size
		return {}, nil, false
	}

	// try the new sizes one by one, until we reach one that fits:
	original_atlas := atlas_clone(atlas^)
	for {
		next_size := atlas_sizes[next_size_idx]
		current_remap := atlas_grow_to_size(atlas, next_size)
		if remap_allocs == nil {
			remap_allocs = current_remap // the first generation of growth
		} else {
			// the remaps need to survive over possibly many generations of growth attempts
			for old_pos, &new_pos in remap_allocs {
				new_new_pos, has_it := current_remap[new_pos]
				assert(has_it)
				new_pos = new_new_pos
			}
		}
		pos, ok = atlas_allocate(atlas, item_size)
		if ok {
			atlas_drop(&original_atlas)
			return pos, remap_allocs, true
		}
		next_size_idx += 1
		if next_size_idx >= len(atlas_sizes) {
			// no more sizes to try, restore the atlas like it was before this function call
			atlas_drop(atlas)
			atlas^ = original_atlas
			return {}, nil, false
		}
	}
}

_sizes_are_ascending :: proc(sizes: []IVec2) -> bool {
	if len(sizes) == 0 {
		return true
	}
	last := sizes[0]
	for size in sizes[1:] {
		if !ivec2_greater(size, last) {
			return false
		}
		last = size
	}
	return true
}

ivec2_greater :: proc(a: IVec2, b: IVec2) -> bool {
	return a.y >= b.y && a.x >= b.x && a != b
}

// remapped_allocations
atlas_grow_to_size :: proc(
	atlas: ^Atlas,
	new_size: IVec2,
) -> (
	remap_allocs: map[IVec2]IVec2, // pos to pos
) {
	remap_allocs = make(map[IVec2]IVec2, allocator = context.temp_allocator)
	assert(ivec2_greater(new_size, atlas.size))
	// store the old positions andasizes in here to avoid another allocation
	for pos, size in atlas.allocations {
		remap_allocs[pos] = size
	}
	atlas_init(atlas, new_size)
	for _old_pos, &size in remap_allocs {
		new_pos, ok := atlas_allocate(atlas, size)
		assert(ok, "allocating the same rects in a bigger atlas should always be possible")
		size = new_pos // to return to the user
	}
	return remap_allocs
}
