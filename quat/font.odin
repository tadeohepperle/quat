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
font_load_from_path :: proc(
	path: string,
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> (
	font: Font,
	font_texture: Texture,
	err: Error,
) {
	json_path := fmt.aprintf("{}.sdf_font.json", path, allocator = context.temp_allocator)
	json_bytes, ok := os.read_entire_file(json_path)
	if !ok {
		err = tprint("could not read file", json_path)
		return
	}
	// read image: 
	png_path := fmt.aprintf("{}.sdf_font.png", path, allocator = context.temp_allocator)
	sdf_png_img_bytes, img_read_ok := os.read_entire_file(png_path)
	if !img_read_ok {
		err = tprint("could not read file", png_path)
		return
	}
	defer {delete(json_bytes);delete(sdf_png_img_bytes)}
	return font_load_from_img_and_json_bytes(sdf_png_img_bytes, json_bytes, device, queue)
}

font_load_from_img_and_json_bytes :: proc(
	sdf_png_img_bytes: []u8,
	json_bytes: []u8,
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> (
	font: Font,
	font_texture: Texture,
	err: Error,
) {
	// read json:
	FontWithStringKeys :: struct {
		rasterization_size: int,
		line_metrics:       LineMetrics,
		name:               string,
		glyphs:             map[string]Glyph,
	}
	font_with_string_keys: FontWithStringKeys
	json_err := json.unmarshal(json_bytes, &font_with_string_keys)
	if json_err != nil {
		err = tprint(json_err)
		return
	}
	font.rasterization_size = font_with_string_keys.rasterization_size
	font.line_metrics = font_with_string_keys.line_metrics
	font.name = font_with_string_keys.name
	for s, v in font_with_string_keys.glyphs {
		for r, i in s {
			font.glyphs[r] = v
			if i != 0 {
				err = "Only single character strings allowed as glyph keys!"
				return
			}
		}
	}
	delete(font_with_string_keys.glyphs)
	TEXTURE_SETTINGS_SDF_FONT :: TextureSettings {
		label        = "sdf font",
		format       = wgpu.TextureFormat.RGBA8Unorm,
		address_mode = .Repeat,
		mag_filter   = .Linear,
		min_filter   = .Nearest,
		usage        = {.TextureBinding, .CopyDst},
	}
	img, img_load_err := image_load_from_memory(sdf_png_img_bytes)
	if img_load_err != nil {
		return {}, {}, img_load_err
	}
	font_texture = texture_from_image(device, queue, img, TEXTURE_SETTINGS_SDF_FONT)
	return font, font_texture, nil
}
