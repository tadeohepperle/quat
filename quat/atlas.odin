package quat

IVec2 :: [2]int
// guillotine atlas allocator 
Atlas :: struct {
	size:       IVec2,
	free_areas: [dynamic]Area,
	used_areas: map[Area]None,
}
Area :: struct {
	pos:  IVec2, // top left corner of the allocation
	size: IVec2,
}
atlas_init :: proc(atlas: ^Atlas, size: IVec2) {
	atlas.size = size
	clear(&atlas.free_areas)
	clear(&atlas.used_areas)
	append(&atlas.free_areas, Area{pos = {0, 0}, size = size})
}
atlas_drop :: proc(atlas: ^Atlas) {
	delete(atlas.free_areas)
	delete(atlas.used_areas)
}
atlas_allocate :: proc(atlas: ^Atlas, item_size: IVec2) -> (pos: IVec2, ok: bool) {
	assert(is_non_negative(item_size))
	idx := _select_allocation_rect(atlas^, item_size) or_return
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
	append(&atlas.free_areas, new_area_1)
	append(&atlas.free_areas, new_area_2)
	assert(Area{pos, item_size} not_in atlas.used_areas)
	atlas.used_areas[Area{pos, item_size}] = None{}
	return pos, true
}
atlas_deallocate :: proc(atlas: ^Atlas, rect: Area) -> bool {
	if rect not_in atlas.used_areas {
		return false
	}
	delete_key(&atlas.used_areas, rect)
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
_select_allocation_rect :: proc(atlas: Atlas, item_size: IVec2) -> (idx: int, ok: bool) {
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
