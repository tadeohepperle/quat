package quat

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import wgpu "vendor:wgpu"

Error :: union {
	string,
}

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


ElementOrNextFreeIdx :: struct($T: typeid) #raw_union where size_of(T) >= 4 {
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
// returns slice in tmp memory
slotmap_to_slice :: proc(self: SlotMap($T)) -> []T {
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
