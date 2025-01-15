package quat

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import wgpu "vendor:wgpu"

import "core:math/rand"
None :: struct {}
Error :: union {
	string,
}
print :: fmt.println
tprint :: fmt.tprint
tmp_arr :: proc($T: typeid, cap: int = 8) -> [dynamic]T {
	return make([dynamic]T, 0, cap, context.temp_allocator)
}
tmp_slice :: proc($T: typeid, len: int) -> []T {
	return make([]T, len, context.temp_allocator)
}
triangles_to_u32s :: proc(tris: []IdxTriangle) -> []u32 {
	return slice.from_ptr(cast(^u32)raw_data(tris), len(tris) * 3)
}
tmp_cstr :: proc(str: string) -> cstring {
	return strings.clone_to_cstring(str, allocator = context.temp_allocator)
}

IdxTriangle :: [3]u32
Aabb :: struct {
	min: Vec2,
	max: Vec2,
}
aabb_extend :: proc(aabb: ^Aabb, p: Vec2) {
	aabb.max.x = max(aabb.max.x, p.x)
	aabb.max.y = max(aabb.max.y, p.y)
	aabb.min.x = min(aabb.min.x, p.x)
	aabb.min.y = min(aabb.min.y, p.y)
}
UNIT_AABB :: Aabb{Vec2{0, 0}, Vec2{1, 1}}
// ensures that both x and y of the max are >= than the min
aabb_standard_form :: proc "contextless" (aabb: Aabb) -> Aabb {
	r := aabb
	if r.max.x < r.min.x {
		r.min.x, r.max.x = r.max.x, r.min.x
	}
	if r.max.y < r.min.y {
		r.min.y, r.max.y = r.max.y, r.min.y
	}
	return r
}
aabb_contains :: proc "contextless" (aabb: Aabb, pt: Vec2) -> bool {
	return pt.x >= aabb.min.x && pt.y >= aabb.min.y && pt.x <= aabb.max.x && pt.y <= aabb.max.y
}
aabb_center :: proc "contextless" (aabb: Aabb) -> Vec2 {
	return (aabb.min + aabb.max) / 2
}
aabb_fully_contains :: proc "contextless" (big: Aabb, small: Aabb) -> bool {
	return(
		big.min.x <= small.min.x &&
		big.min.y <= small.min.y &&
		big.max.x >= small.max.x &&
		big.max.y >= small.max.y \
	)
}
aabb_intersection :: proc "contextless" (a: Aabb, b: Aabb) -> (res: Aabb, intersects: bool) {
	res = Aabb {
		min = Vec2{max(a.min.x, b.min.x), max(a.min.y, b.min.y)},
		max = Vec2{min(a.max.x, b.max.x), min(a.max.y, b.max.y)},
	}
	intersects = res.max.x > res.min.x && res.max.y > res.min.y
	return res, intersects
}

aabb_intersects :: proc "contextless" (a: Aabb, b: Aabb) -> bool {
	return(
		min(a.max.x, b.max.x) >= max(a.min.x, b.min.x) &&
		min(a.max.y, b.max.y) >= max(a.min.y, b.min.y) \
	)
}
DVec2 :: [2]f64
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat2 :: matrix[2, 2]f32
Mat3 :: matrix[3, 3]f32
Mat4 :: matrix[4, 4]f32
UVec2 :: [2]u32
UVec3 :: [3]u32
ivec2_to_vec2 :: proc "contextless" (i: IVec2) -> Vec2 {
	return Vec2{f32(i.x), f32(i.y)}
}

@(test)
transform_test :: proc(t: ^testing.T) {
	// should work with any values for P and C
	P := affine_from_vectors({0, 0}, {0, 2}, {0, 0}, {1, 2}) // parent
	C := affine_from_vectors({0, 0}, {0, 1}, {1, 1}, {1, 2}) // child
	for p in ([]Vec2{{0, 1}, {1, 0}, {-2, 3}}) {
		testing.expect_value(
			t,
			affine_apply(affine_combine(P, C), p),
			affine_apply(P, affine_apply(C, p)),
		)
	}
}
AFFINE2_UNIT :: Affine2{{1, 0, 0, 1}, {0, 0}}
// Sadly, in Odin the Mat2 has align=16, but in wgsl mat2x2<f32> only has align=8, see https://www.w3.org/TR/WGSL/#alignment-and-size
// But if we apply align(8) in Odin, we get segmentation faults when multiplying unaligned matrices. 
// 
// so we have 8 useless bytes of padding at the end, meh. 
// In the future we might optimize this using not the builtin Mat2, wgpu will be happy too.
Affine2 :: struct {
	m:      Mat2,
	offset: Vec2,
}

affine_mul :: proc(t: Affine2, w: f32) -> Affine2 {
	return Affine2{w * t.m, w * t.offset}
}

affine_sum :: proc(affines: ..Affine2) -> (res: Affine2) {
	for a in affines {
		res.m += a.m
		res.offset += a.offset
	}
	return res
}


// applied the affine transform to a point p, rotating and scaling it
// 2d affine transformation can be applied on any point p by p' = mat * p + offset,
affine_apply :: proc "contextless" (t: Affine2, p: Vec2) -> Vec2 {
	return t.m * p + t.offset
}

AffineCombineOptions :: struct {
	no_scaling_from_parent: bool,
}
// compute child affine transform given parent transform
// `apply(combine(P, C), p)   ===   apply(P, apply(C, p))`
affine_combine :: proc(parent: Affine2, child: Affine2) -> Affine2 {
	return Affine2{parent.m * child.m, parent.m * child.offset + parent.offset}
}
affine_from_vectors :: proc(a_old: Vec2, b_old: Vec2, a_new: Vec2, b_new: Vec2) -> Affine2 {
	// If the points are identical, return identity matrix with translation
	if a_old == b_old {
		return Affine2{m = Mat2{1, 0, 0, 1}, offset = a_new}
	}
	v_old := b_old - a_old
	v_new := b_new - a_new
	m := Mat2{v_new.x / v_old.x, 0, 0, v_new.y / v_old.y}
	offset := a_new - m * a_old
	return Affine2{m = m, offset = offset}
}

// todo: affine_from_rotation does not support NO_SIDE_SCALING yet
affine_from_rotation :: proc(
	rotation: f32,
	around: Vec2 = {0, 0},
	offset := Vec2{0, 0},
) -> Affine2 {
	co := math.cos(rotation)
	si := math.sin(rotation)

	res: Affine2
	res.m = Mat2{co, -si, si, co}
	res.offset = (res.m * -around) + around + offset
	return res
}

affine_around_and_offset :: proc(affine: Affine2) -> (around: Vec2, offset: Vec2) {
	I := Mat2{1, 0, 0, 1} // Identity matrix
	M := affine.m
	inv_I_minus_M := linalg.inverse(I - M) // Invert (I - res.m)

	// Assume a point (e.g., Vec2{0, 0}) is `offset` to start solving
	around = inv_I_minus_M * affine.offset
	offset = affine.offset - (I - M) * around
	return around, offset

}

next_pow2_number :: proc(n: int) -> int {
	next: int = 2
	for {
		if next >= n {
			return next
		}
		next *= 2
	}
}
lerp :: proc "contextless" (a: $T, b: T, t: f32) -> T {
	return a + (b - a) * t
}
dump :: proc(args: ..any, filename := "log.txt") {
	sb: strings.Builder
	fmt.sbprint(&sb, args)
	os.write_entire_file(filename, sb.buf[:])
}
print_line :: proc(message: string = "") {
	if message != "" {
		fmt.printfln(
			"-------------------- %s ---------------------------------------------",
			message,
		)
	} else {
		fmt.println("------------------------------------------------------------------------")
	}

}


lorem :: proc(letters := 300) -> string {
	LOREM := "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.   "
	letters := min(letters, len(LOREM))
	return LOREM[0:letters]
}


todo :: proc(loc := #caller_location) -> ! {
	panic("Todo at", loc)
}


ElementOrNextFreeIdx :: struct($T: typeid) #raw_union {
	element:       T,
	next_free_idx: u32,
}
SlotMap :: struct($T: typeid) {
	slots:         [dynamic]ElementOrNextFreeIdx(T),
	next_free_idx: u32, // there is a linked stack of next free indices starting here, that can be followed through the slots array until NO_FREE_IDX is hit
	initialized:   bool, // set to true only once on first insert, to set the next_free_idx to NO_FREE_IDX instead of 0
}
NO_FREE_IDX: u32 : max(u32)
slotmap_insert :: proc(self: ^SlotMap($T), element: T) -> (handle: u32) {
	if !self.initialized {
		self.next_free_idx = NO_FREE_IDX
		self.initialized = true
	}
	if self.next_free_idx == NO_FREE_IDX {
		// append a new element to end of elements array:
		append(&self.slots, ElementOrNextFreeIdx(T){element = element})
		handle = u32(len(self.slots)) - 1
	} else {
		// there is a free slot at next_handle
		handle = self.next_free_idx
		slot := &self.slots[handle]
		self.next_free_idx = slot.next_free_idx
		slot.element = element
	}
	return handle
}
slotmap_remove :: proc(self: ^SlotMap($T), handle: u32) -> T {
	slot := &self.slots[handle]
	el := slot.element
	slot.next_free_idx = self.next_free_idx
	self.next_free_idx = handle
	return el
}
slotmap_get :: #force_inline proc(self: SlotMap($T), handle: u32) -> T {
	assert(handle < u32(len(self.slots)))
	return self.slots[handle].element
}
slotmap_access :: #force_inline proc(self: ^SlotMap($T), handle: u32) -> ^T {
	assert(handle < u32(len(self.slots)))
	return &self.slots[handle].element
}
// returns slice in tmp memory with only the taken slots in it, useful for calling a drop function on  all elements in the slotmap
slotmap_to_tmp_slice :: proc(self: SlotMap($T)) -> []T {
	empty_slot_indices := make(map[u32]None, allocator = context.temp_allocator)
	elements := make([dynamic]T, 0, len(self.slots), allocator = context.temp_allocator)

	// follow the linked list to collect the indices of all empty slots:
	next_free_idx := self.next_free_idx if self.initialized else NO_FREE_IDX
	for next_free_idx != NO_FREE_IDX {
		empty_slot_indices[next_free_idx] = None{}
		next_free_idx = self.slots[next_free_idx].next_free_idx
	}

	for s, i in self.slots {
		if u32(i) not_in empty_slot_indices {
			append(&elements, s.element)
		}
	}
	return elements[:]
}


// Note: all these functions (vert_attributes, bind_group_layouts, push_const_ranges)
// just clone the args from a stack slice into the default allocator
vert_attributes :: proc(args: ..VertAttibute) -> []VertAttibute {
	return slice.clone(args)
}
bind_group_layouts :: proc(args: ..wgpu.BindGroupLayout) -> []wgpu.BindGroupLayout {
	return slice.clone(args)
}
push_const_ranges :: proc(args: ..wgpu.PushConstantRange) -> []wgpu.PushConstantRange {
	return slice.clone(args)
}


// Range :: struct {
// 	start: int,
// 	end:   int,
// }
// SubBufferPool :: struct($T: typeid) {
// 	free_list:     [dynamic]Range, // sorted by their start_idx, such that multiple can be joined later when freed.
// 	occupied_list: [dynamic]Range,
// 	data:          []T,
// 	data_len:      int,
// 	gpu_data:      DynamicBuffer(T),
// }
// sub_buffer_pool_alloc :: proc(pool: ^SubBufferPool($T), n_elements: int) -> (idx: int) {
// 	assert(n_elements != 0)
// 	if len(pool.free_list) != 0 {
// 		// search free list first:

// 	}
// 	// otherwise just append to the end:
// 	cap := len(pool.data)
// 	// if backing data buffer too small, resize:
// 	needed_len := pool.data_len + n_elements
// 	if needed_len > cap {
// 		next_cap := cap * 2
// 		if next_cap < needed_len {
// 			next_cap = next_pow2_number(needed_len)
// 		}
// 		next_cap = max(next_cap, 64)
// 		new_data = make([]T, new_cap)
// 		mem.copy_non_overlapping(
// 			raw_data(new_data),
// 			raw_data(pool.data),
// 			pool.data_len * size_of(T),
// 		)
// 		delete(pool.data)
// 		pool.data = new_data
// 	}
// }
