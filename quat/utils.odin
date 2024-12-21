package quat

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import wgpu "vendor:wgpu"

import "core:math/rand"
Error :: union {
	string,
}

triangles_to_u32s :: proc(tris: []IdxTriangle) -> []u32 {
	return slice.from_ptr(cast(^u32)raw_data(tris), len(tris) * 3)
}

IdxTriangle :: [3]u32
Aabb :: struct {
	min: Vec2,
	max: Vec2,
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
IVec2 :: [2]i32


@(test)
transform_test :: proc(t: ^testing.T) {
	// should work with any values for P and C
	P := affine_create({0, 0}, {0, 2}, {0, 0}, {1, 2}) // parent
	C := affine_create({0, 0}, {0, 1}, {1, 1}, {1, 2}) // child
	for p in ([]Vec2{{0, 1}, {1, 0}, {-2, 3}}) {
		testing.expect_value(
			t,
			affine_apply(affine_combine(P, C), p),
			affine_apply(P, affine_apply(C, p)),
		)
	}
}

AFFINE2_UNIT :: Affine2 {
	m      = {1, 0, 0, 1},
	offset = {0, 0},
}
Affine2 :: struct {
	m:      Mat2,
	offset: Vec2,
}
// applied the affine transform to a point p, rotating and scaling it
affine_apply :: proc(t: Affine2, p: Vec2) -> Vec2 {
	return t.m * p + t.offset
}
// a 2d affine transform, applied to a point p by:    p' = mat * p + offset,
// `apply(combine(P, C), p)   ===   apply(P, apply(C, p))`
affine_combine :: proc(parent: Affine2, child: Affine2) -> Affine2 {
	merged_mat := parent.m * child.m
	merged_offset := parent.m * child.offset + parent.offset
	return Affine2{merged_mat, merged_offset}
}
// creates a new affine transform from two offsetted vectors, mapping the `from` to the `to` when the 
// resulting affine transform A is applied, so: 
// - `to_root === affine_apply(A, from_root)`
// - `to_head === affine_apply(A, from_head)`
affine_create :: proc(from_root: Vec2, from_head: Vec2, to_root: Vec2, to_head: Vec2) -> Affine2 {
	a := from_head - from_root
	b := to_head - to_root
	// the transformation matrix M that is needed to map from `a` to `b` needs to be found:
	// goal: find M, such that Ma = b
	// solution: M = A^-1 * B, where A and B are the ortho-bases for a and b
	A := Mat2{a.x, -a.y, a.y, a.x}
	B := Mat2{b.x, -b.y, b.y, b.x}
	A_DET := A[0, 0] * A[1, 1] - A[1, 0] * A[0, 1]
	A_INV := (f32(1.0) / A_DET) * Mat2{A[1, 1], -A[0, 1], -A[1, 0], A[0, 0]}
	M := A_INV * B
	diff := to_root - from_root
	offset := (M * (-from_root)) + to_root
	return Affine2{M, offset}
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
lerp :: proc(a: $T, b: T, s: f32) -> T {
	return a + (b - a) * s
}

Empty :: struct {}

print :: fmt.println

dump :: proc(args: ..any, filename := "log.txt") {
	sb: strings.Builder
	fmt.sbprint(&sb, args)
	os.write_entire_file(filename, sb.buf[:])
}

tmp_str :: proc(args: ..any) -> string {
	return fmt.aprint(..args, allocator = context.temp_allocator)
}
tmp_arr :: proc($T: typeid, cap: int = 8) -> [dynamic]T {
	return make([dynamic]T, 0, cap, context.temp_allocator)
}
tmp_slice :: proc($T: typeid, len: int) -> []T {
	return make([]T, len, context.temp_allocator)
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
}
NO_FREE_IDX: u32 : max(u32)
slotmap_create :: proc($T: typeid, reserve_n: int = 4) -> (slotmap: SlotMap(T)) {
	reserve(&slotmap.slots, reserve_n)
	slotmap.next_free_idx = NO_FREE_IDX
	return slotmap
}
slotmap_insert :: proc(self: ^SlotMap($T), element: T) -> (handle: u32) {
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
	empty_slot_indices := make(map[u32]Empty, allocator = context.temp_allocator)
	elements := make([dynamic]T, 0, len(self.slots), allocator = context.temp_allocator)

	// follow the linked list to collect the indices of all empty slots:
	next_free_idx := self.next_free_idx
	for next_free_idx != NO_FREE_IDX {
		empty_slot_indices[next_free_idx] = Empty{}
		next_free_idx = self.slots[next_free_idx].next_free_idx
	}

	for s, i in self.slots {
		if u32(i) not_in empty_slot_indices {
			append(&elements, s.element)
		}
	}
	return elements[:]
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
