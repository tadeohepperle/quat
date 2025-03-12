package quat

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import stbi "vendor:stb/image"

DepthImage16 :: struct {
	size:           IVec2,
	pixels:         []u16,
	backed_by_stbi: bool,
}
depth_image_load :: proc(path: string) -> (DepthImage16, Error) {
	x, y, c: i32
	DESIRED_CHANNELS :: 1
	im_ptr := stbi.load_16(tmp_cstr(path), &x, &y, &c, DESIRED_CHANNELS)
	if im_ptr == nil {
		msg := tprint(
			"stbi could not load depth image from ",
			path,
			"reason:",
			stbi.failure_reason(),
		)
		return {}, msg
	}

	img := DepthImage16 {
		size           = IVec2{int(x), int(y)},
		pixels         = slice.from_ptr(im_ptr, int(x * y)),
		backed_by_stbi = true,
	}
	return img, nil
}
depth_image_drop :: proc(this: ^DepthImage16) {
	if this.backed_by_stbi {
		stbi.image_free(raw_data(this.pixels))
	} else {
		delete(this.pixels)
	}
}

Image :: struct {
	size:           IVec2,
	pixels:         []Rgba `fmt:"-"`,
	backed_by_stbi: bool,
}
StbiAllocation :: distinct rawptr // buffer containing the pixels allocated by stbi
ArrayAllocation :: [dynamic]Rgba // buffer allocated by odin
Rgba :: [4]u8

is_image_path :: proc(path: string) -> bool {
	return strings.ends_with(path, ".png") // todo: extend further later, needs to support jpeg as well
}
image_load :: proc(path: string) -> (Image, Error) {
	x, y, c: i32
	DESIRED_CHANNELS :: 4
	im_ptr := stbi.load(tmp_cstr(path), &x, &y, &c, DESIRED_CHANNELS)
	if im_ptr == nil {
		msg := tprint("stbi could not load image from ", path, "reason:", stbi.failure_reason())
		return {}, msg
	}

	img := Image {
		size           = IVec2{int(x), int(y)},
		pixels         = slice.from_ptr(cast(^Rgba)im_ptr, int(x * y)),
		backed_by_stbi = true,
	}
	return img, nil
}
image_load_from_memory :: proc(bytes: []u8) -> (Image, Error) {
	x, y, c: i32
	DESIRED_CHANNELS :: 4
	im_ptr := stbi.load_from_memory(raw_data(bytes), i32(len(bytes)), &x, &y, &c, DESIRED_CHANNELS)
	if im_ptr == nil {
		msg := tprint("stbi could not load image from bytes reason:", stbi.failure_reason())
		return {}, msg
	}
	img := Image {
		size           = IVec2{int(x), int(y)},
		pixels         = slice.from_ptr(cast(^Rgba)im_ptr, int(x * y)),
		backed_by_stbi = true,
	}
	return img, nil

}
image_drop :: proc(this: ^Image) {
	if this.backed_by_stbi {
		stbi.image_free(raw_data(this.pixels))
	} else {
		delete(this.pixels)
	}
}
image_clear :: proc(this: ^Image) {
	mem.zero_slice(this.pixels)
}
image_create :: proc(size: IVec2) -> Image {
	buf_len := size.x * size.y
	backing := make([dynamic]Rgba, cap = buf_len, len = buf_len)
	return Image{size = size, pixels = backing[:], backed_by_stbi = false}
}
image_create_colored :: proc(size: IVec2, color: Rgba) -> Image {
	res := image_create(size)
	for &px in res.pixels {
		px = color
	}
	return res
}
image_clone :: proc(this: Image) -> Image {
	res := image_create(this.size)
	assert(len(res.pixels) == len(this.pixels))
	mem.copy_non_overlapping(raw_data(res.pixels), raw_data(this.pixels), len(this.pixels) * 4)
	return res
}

image_save_as_png :: proc(this: Image, path: string) -> Error {
	path_c_str := tmp_cstr(path)
	res := stbi.write_png(
		path_c_str,
		i32(this.size.x),
		i32(this.size.y),
		4,
		raw_data(this.pixels),
		0,
	)
	if res != 1 {
		return tprint("stbi was not able to write image to ", path)
	}
	return nil
}

ImageView :: struct {
	size: IVec2,
	rows: [][]Rgba,
}

// returns a slice in tmp that contains lines of the image in the specified rect.
// provide {0,0}, {0,0} or {0,0}, this.size to view the whole image
image_view :: proc(
	this: Image,
	min: IVec2 = IVec2{0, 0},
	max: IVec2 = IVec2{0, 0},
	allocator := context.temp_allocator,
) -> ImageView {
	assert(size_contains(this.size, min))
	assert(size_contains(this.size, max))
	max := max
	if min == {0, 0} && max == min {
		max = this.size
	}
	if max.x <= min.x || max.y <= min.y {
		return {}
	}
	row_len := max.x - min.x

	rows := make([][]Rgba, max.y - min.y, allocator)
	for &row, i in rows {
		start_idx := (min.y + i) * this.size.x + min.x
		end_idx := start_idx + row_len
		row = this.pixels[start_idx:end_idx]
	}
	view_size := max - min
	return {view_size, rows}
}
size_contains :: proc(size: IVec2, pt: IVec2) -> bool {
	return pt.x >= 0 && pt.y >= 0 && pt.x <= size.x && pt.y <= size.y
}

image_copy_into :: proc(target: ^Image, view: ImageView, pos_in_target: IVec2) {
	if view.size == {} {
		return
	}
	view_width := view.size.x
	view_height := view.size.y
	assert(target.size.x - pos_in_target.x >= view_width)
	assert(target.size.y - pos_in_target.y >= view_height)

	for row, i in view.rows {
		assert(len(row) == view_width)
		start_idx := (i + pos_in_target.y) * target.size.x + pos_in_target.x
		mem.copy(&target.pixels[start_idx], raw_data(row), view_width * 4)
	}
}

image_get_pixel :: proc(this: Image, pos: IVec2) -> Rgba {
	assert(pos.x < this.size.x)
	assert(pos.y < this.size.y)
	assert(pos.x >= 0)
	assert(pos.y >= 0)
	return this.pixels[pos.y * this.size.x + pos.x]
}

image_rotate_90 :: proc(this: Image) -> Image {
	res := image_create(IVec2{this.size.y, this.size.x})
	for y in 0 ..< this.size.y {
		for x in 0 ..< this.size.x {
			res_x := this.size.y - y - 1
			res_y := x
			res.pixels[res_y * res.size.x + res_x] = this.pixels[y * this.size.x + x]
		}
	}
	return res
}


image_to_grey_scale :: proc(img: Image) -> Image {
	res := image_clone(img)
	for &p in res.pixels {
		grey := u8((int(p.r) + int(p.g) + int(p.b)) / 3)
		p = {grey, grey, grey, p.a}
	}
	return res
}

// calculated the sdf via jump flooding
SdfOptions :: struct {
	pad:                   int,
	max_dist:              int,
	solid_alpha_threshold: u8,
}
DEFAULT_SDF_OPTIONS :: SdfOptions {
	pad                   = 32,
	max_dist              = 32,
	solid_alpha_threshold = 100,
}
create_signed_distance_field :: proc(img: Image, using options := DEFAULT_SDF_OPTIONS) -> Image {
	p_size := img.size + IVec2{pad * 2, pad * 2}
	p_img := image_create(p_size) // padded image

	distances, size := _distance_field(img, options)
	assert(size == p_size)
	for &p, i in p_img.pixels {
		dist := distances[i].dist
		grey := u8(clamp(dist / f32(max_dist) * 255.0, 0, 255))
		p = {grey, grey, grey, 255}
	}

	return p_img
}
// padding is applied on each side seperately.
transparent_pad :: proc(img: Image, pad: IVec2) -> Image {
	out := image_create(img.size + pad * 2)
	image_copy_into(&out, image_view(img), pad)
	return out
}


// returns x_n * y_n tiles of the same size (if img size allows for clean even tiling)
image_slice_into_tiles :: proc(
	img: Image,
	x_n: int,
	y_n: int,
	allocator := context.temp_allocator,
) -> (
	res: []ImageView,
) {
	tile_width := img.size.x / x_n
	tile_height := img.size.y / y_n

	res = make([]ImageView, x_n * y_n)
	for y_i in 0 ..< y_n {
		for x_i in 0 ..< x_n {
			min := IVec2{x_i * tile_width, y_i * tile_height}
			max := min + IVec2{tile_width, tile_height}
			res[x_i + y_i * x_n] = image_view(img, min, max, allocator)
		}
	}
	return res
}


RgbaHdr :: [4]f32
HdrImage :: struct {
	size:   IVec2,
	pixels: []RgbaHdr,
}

drop_hdr :: proc(this: ^HdrImage) {
	delete(this.pixels)
}
_rgba_to_hdr :: proc(pix: Rgba) -> RgbaHdr {
	return {f32(pix.r) / 255.0, f32(pix.g) / 255.0, f32(pix.b) / 255.0, f32(pix.a) / 255.0}
}
_rgba_from_hdr :: proc(pix: RgbaHdr) -> Rgba {
	return {u8(pix.r * 255.0), u8(pix.g * 255.0), u8(pix.b * 255.0), u8(pix.a * 255.0)}
}

to_hdr :: proc(img: Image) -> (out: HdrImage) {
	out.size = img.size
	out.pixels = make([]RgbaHdr, len(img.pixels))
	for pix, i in img.pixels {
		out.pixels[i] = _rgba_to_hdr(pix)
	}
	return out
}

from_hdr :: proc(img: HdrImage) -> (out: Image) {
	out.size = img.size
	out.pixels = make([]Rgba, len(img.pixels))
	for pix, i in img.pixels {
		out.pixels[i] = _rgba_from_hdr(pix)
	}
	return out
}

_get_pixel_clamped :: #force_inline proc(img: Image, pos: IVec2) -> Rgba {
	pos := IVec2{clamp(pos.x, 0, img.size.x - 1), clamp(pos.y, 0, img.size.y - 1)}
	return img.pixels[pos.y * img.size.x + pos.x]
}

gaussian_blur :: proc(img: Image) -> (out: Image) {
	blurred_h := image_create(img.size)
	defer {image_drop(&blurred_h)}

	_rgba_to_u32 :: #force_inline proc(p: Rgba) -> [4]u32 {
		return {u32(p.r), u32(p.g), u32(p.b), u32(p.a)}
	}
	_rgba_from_u32 :: #force_inline proc(p: [4]u32) -> Rgba {
		return {u8(p.r), u8(p.g), u8(p.b), u8(p.a)}
	}

	// Kernel :: [5]f32{7, 26, 41, 26, 7} 
	for y in 0 ..< img.size.y {
		for x in 0 ..< img.size.x {
			acc: [4]u32
			acc += _rgba_to_u32(_get_pixel_clamped(img, IVec2{x - 2, y}))
			acc += _rgba_to_u32(_get_pixel_clamped(img, IVec2{x - 1, y})) * 4
			acc += _rgba_to_u32(_get_pixel_clamped(img, IVec2{x, y})) * 6
			acc += _rgba_to_u32(_get_pixel_clamped(img, IVec2{x + 1, y})) * 4
			acc += _rgba_to_u32(_get_pixel_clamped(img, IVec2{x + 2, y}))
			acc /= 16
			blurred_h.pixels[y * img.size.x + x] = _rgba_from_u32(acc)
		}
	}

	out = image_create(img.size)
	for y in 0 ..< img.size.y {
		for x in 0 ..< img.size.x {
			acc: [4]u32
			acc += _rgba_to_u32(_get_pixel_clamped(blurred_h, IVec2{x, y - 2}))
			acc += _rgba_to_u32(_get_pixel_clamped(blurred_h, IVec2{x, y - 1})) * 4
			acc += _rgba_to_u32(_get_pixel_clamped(blurred_h, IVec2{x, y})) * 6
			acc += _rgba_to_u32(_get_pixel_clamped(blurred_h, IVec2{x, y + 1})) * 4
			acc += _rgba_to_u32(_get_pixel_clamped(blurred_h, IVec2{x, y + 2}))
			acc /= 16
			out.pixels[y * img.size.x + x] = _rgba_from_u32(acc)
		}
	}

	return out
}

distance_field_in_alpha_channel_image :: proc(
	img: Image,
	using options := DEFAULT_SDF_OPTIONS,
) -> Image {
	assert(
		options.pad == 0,
		"distance_field_in_alpha_channel_image works only with 0 padding at the moment!",
	)
	p_size := img.size + IVec2{pad * 2, pad * 2}
	p_img := image_create(p_size) // padded image
	distances, size := _distance_field(img, options)
	assert(size == p_size)
	for y in 0 ..< img.size.y {
		for x in 0 ..< img.size.x {
			p_idx := (y + pad) * p_size.x + x + pad
			dist := distances[p_idx].dist
			pix := img.pixels[y * img.size.x + x]
			pix.a = 255 - u8(clamp(dist / f32(max_dist) * 255.0, 0, 255))
			p_img.pixels[p_idx] = pix
		}
	}
	return p_img
}
DistancePixel :: struct {
	px:   IVec2, // solid pixel that is closest to this pixel
	dist: f32, // distance to that pixel
}
// determine the ks (step sizes N/2, N/4, ..., 1) for jump flooding:
_jfa_ks :: proc(size: IVec2, add_ones: int = 0) -> []int {
	ks: [dynamic]int = make([dynamic]int, allocator = context.temp_allocator)
	k := 1
	for k < max(size.x, size.y) / 2 {k *= 2}
	for k >= 1 {
		append(&ks, k)
		k /= 2
	}
	for _ in 0 ..< add_ones {
		append(&ks, 1)
	}
	fmt.println(ks)
	return ks[:]
}
_jfa_neighbor_offsets :: proc(k: int) -> [8]IVec2 {
	return [8]IVec2 {
		IVec2{-k, -k},
		IVec2{0, -k},
		IVec2{k, -k},
		IVec2{-k, 0},
		IVec2{k, 0},
		IVec2{-k, k},
		IVec2{0, k},
		IVec2{k, k},
	}
}
UNDEFINED_DIST: f32 : max(f32)
_dist :: proc(a: IVec2, b: IVec2) -> f32 {
	diff := a - b
	x, y := f32(diff.x), f32(diff.y)
	return math.sqrt(x * x + y * y)
}
_distance_field :: proc(
	img: Image,
	using options := DEFAULT_SDF_OPTIONS,
) -> (
	distances: []DistancePixel,
	p_size: IVec2,
) {
	p_size = img.size + IVec2{pad * 2, pad * 2}
	distances = make([]DistancePixel, p_size.x * p_size.y, allocator = context.temp_allocator)
	for &d in distances do d.dist = UNDEFINED_DIST

	// init mask to "solid" pixels in origin image where alpha > threshold
	for y in 0 ..< img.size.y {
		for x in 0 ..< img.size.x {
			img_idx := y * img.size.x + x
			p_img_idx := (y + pad) * p_size.x + x + pad
			is_solid := img.pixels[img_idx].a > solid_alpha_threshold
			if is_solid {
				distances[p_img_idx] = DistancePixel{IVec2{x + pad, y + pad}, 0}
			}
		}
	}

	// determine the ks (step sizes N/2, N/4, ..., 1) for jump flooding:
	ks := _jfa_ks(p_size)
	// jump flood with one iteration per k, see https://en.wikipedia.org/wiki/Jump_flooding_algorithm
	for k in ks {
		neighbor_offsets := _jfa_neighbor_offsets(k)
		for y in 0 ..< p_size.y {
			for x in 0 ..< p_size.x {
				pos := IVec2{x, y}
				pix := &distances[y * p_size.x + x]
				pix_undefined := pix.dist == UNDEFINED_DIST
				for nei_off in neighbor_offsets {
					nei_pos := pos + nei_off
					is_in_bounds :=
						nei_pos.x >= 0 &&
						nei_pos.y >= 0 &&
						nei_pos.x < p_size.x &&
						nei_pos.y < p_size.y
					if is_in_bounds {
						nei_pix := &distances[nei_pos.y * p_size.x + nei_pos.x]
						if nei_pix.dist != UNDEFINED_DIST {
							if pix_undefined || nei_pix.dist < pix.dist {
								pix.px = nei_pix.px
								pix.dist = _dist(pos, nei_pix.px)
							}
						}
					}
				}

			}
		}
	}

	return distances, p_size
}
// really stupid and slow, there is probably a smarter way to do this:
_wrapping_dist :: #force_inline proc(a: IVec2, b: IVec2, size: IVec2) -> f32 {
	return min(
		_dist(a, b + IVec2{-size.x, 0}),
		_dist(a, b),
		_dist(a, b + IVec2{size.x, 0}),
		_dist(a, b + IVec2{-size.x, size.y}),
		_dist(a, b + IVec2{0, size.y}),
		_dist(a, b + IVec2{size.x, size.y}),
		_dist(a, b + IVec2{-size.x, -size.y}),
		_dist(a, b + IVec2{0, -size.y}),
		_dist(a, b + IVec2{size.x, -size.y}),
	)
}
VoronoiMode :: enum {
	Distances,
	Indices,
	RandomColors,
}
create_voronoi_texture :: proc(
	size: IVec2,
	n: int,
	mode: VoronoiMode = .RandomColors,
) -> (
	out: Image,
	pts: []IVec2,
) {
	pts = make([]IVec2, n)
	i := 0
	outer: for i < n {
		pts[i] = IVec2{rand.int_max(size.x), rand.int_max(size.y)}
		i += 1
	}
	fmt.println("generated pts")

	// pixels: []u8
	Pix :: struct {
		id:   int, // index into start positions
		dist: f32,
	}
	distances: []Pix = make([]Pix, size.x * size.y)
	for &pix in distances {
		pix = Pix{-1, UNDEFINED_DIST}
	}
	for pos, i in pts {
		distances[pos.y * size.x + pos.x] = Pix{i, 0}
	}

	ks := _jfa_ks(size, 3)
	for k in ks {
		neighbor_offsets := _jfa_neighbor_offsets(k)
		for y in 0 ..< size.y {
			for x in 0 ..< size.x {
				pos := IVec2{x, y}
				pix := &distances[y * size.x + x]
				pix_undefined := pix.dist == UNDEFINED_DIST
				for nei_off in neighbor_offsets {
					// wrapping position:
					nei_pos := IVec2{(pos.x + nei_off.x) %% size.x, (pos.y + nei_off.y) %% size.y}
					nei_pix := &distances[nei_pos.y * size.x + nei_pos.x]
					if nei_pix.dist != UNDEFINED_DIST {
						if pix_undefined || nei_pix.dist < pix.dist {
							pix.id = nei_pix.id
							pix.dist = _wrapping_dist(pos, pts[pix.id], size)
						}
					}
				}
			}
		}
	}

	out = image_create(size)

	switch mode {
	case .Distances:
		for pix, i in distances {
			grey := u8(clamp(pix.dist, 0, 255))
			out.pixels[i] = {grey, grey, grey, 255}
		}
	case .Indices:
		for pix, i in distances {
			grey := u8(pix.id % 255)
			out.pixels[i] = {grey, grey, grey, 255}
		}
	case .RandomColors:
		colors: []Rgba = make([]Rgba, n, allocator = context.temp_allocator)
		for i in 0 ..< n {
			colors[i] = Rgba {
				u8(rand.uint32() % 255),
				u8(rand.uint32() % 255),
				u8(rand.uint32() % 255),
				255,
			}
		}
		for pix, i in distances {
			out.pixels[i] = colors[pix.id]
		}
	}


	// for pos in pts {
	// 	out.pixels[pos.y * size.x + pos.x] = {255, 0, 0, 255}
	// }

	return out, pts
}

tile :: proc(img: Image, times: IVec2) -> Image {
	out := image_create(img.size * times)
	img_view := image_view(img)
	for y in 0 ..< times.y {
		for x in 0 ..< times.x {
			offset := img.size * IVec2{x, y}
			image_copy_into(&out, img_view, offset)
		}
	}
	return out
}
