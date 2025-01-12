package quat

import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"
import wgpu "vendor:wgpu"

// We only support sdf fonts created with https://github.com/tadeohepperle/assetpacker
//
// This type should be equivalent to the SdfFont struct in the assetpacker Rust crate (https://github.com/tadeohepperle/assetpacker/blob/main/src/font.rs).
Font :: struct {
	rasterization_size: int,
	line_metrics:       LineMetrics,
	name:               string,
	glyphs:             map[rune]Glyph,
	texture:            TextureHandle,
}
LineMetrics :: struct {
	ascent:        f32,
	descent:       f32,
	line_gap:      f32,
	new_line_size: f32,
}
Glyph :: struct {
	xmin:           f32,
	ymin:           f32,
	width:          f32,
	height:         f32,
	advance:        f32,
	is_white_space: bool,
	uv_min:         Vec2,
	uv_max:         Vec2,
}
font_destroy :: proc(font: ^Font) {
	delete(font.glyphs)
	delete(font.name)
}

// this function expects to find a file at {path}.json and {path}.png, representing the fonts data and sdf glyphs
_font_load_from_path :: proc(
	path: string,
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> (
	font: Font,
	font_texture: Texture,
	error: Error,
) {
	// read json:
	FontWithStringKeys :: struct {
		rasterization_size: int,
		line_metrics:       LineMetrics,
		name:               string,
		glyphs:             map[string]Glyph,
	}
	font_with_string_keys: FontWithStringKeys
	json_path := fmt.aprintf("%s.sdf_font.json", path, allocator = context.temp_allocator)
	json_bytes, ok := os.read_entire_file(json_path)
	if !ok {
		error = "could not read file"
		return
	}
	defer {delete(json_bytes)}
	json_err := json.unmarshal(json_bytes, &font_with_string_keys)
	if json_err != nil {
		error = tprint(json_err)
		return
	}
	font.rasterization_size = font_with_string_keys.rasterization_size
	font.line_metrics = font_with_string_keys.line_metrics
	font.name = font_with_string_keys.name
	for s, v in font_with_string_keys.glyphs {
		for r, i in s {
			font.glyphs[r] = v
			if i != 0 {
				error = "Only single character strings allowed as glyph keys!"
				return
			}
		}
	}
	delete(font_with_string_keys.glyphs)

	// read image: 
	png_path := fmt.aprintf("%s.sdf_font.png", path, allocator = context.temp_allocator)
	tex_err: png.Error
	font_texture = texture_from_image_path(device, queue, path = png_path) or_return
	return font, font_texture, nil
}
