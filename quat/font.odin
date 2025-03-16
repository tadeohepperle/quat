package quat

import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"
import "core:strings"
import "shared:sdffont"
import wgpu "vendor:wgpu"

LineMetrics :: sdffont.LineMetrics

get_or_add_glyph :: sdffont.font_get_or_add_glyph

// We only support sdf fonts created with https://github.com/tadeohepperle/assetpacker
//
// This type should be equivalent to the SdfFont struct in the assetpacker Rust crate (https://github.com/tadeohepperle/assetpacker/blob/main/src/font.rs).
Font :: struct {
	settings:       sdffont.SdfFontSettings,
	name:           string,
	sdf_font:       sdffont.SdfFont,
	texture_handle: TextureHandle,
	line_metrics:   LineMetrics,
}
font_destroy :: proc(font: ^Font) {
	sdffont.font_free(font.sdf_font)
	delete(font.name)
}
font_from_bytes :: proc(
	ttf_file_bytes: []u8,
	assets: ^AssetManager,
	name: string, // static str
	settings := sdffont.SDF_FONT_SETTINGS_DEFAULT,
) -> (
	font: Font,
	err: Error,
) {
	err_str: string
	sdf_font := sdffont.font_create(ttf_file_bytes, settings, &err_str)
	if sdf_font == nil {
		if err_str == "" {
			err_str = "Something went wrong loading ttf font from bytes"
		}
		return {}, err_str
	}
	TEXTURE_SETTINGS_SDF_FONT :: TextureSettings {
		label        = "sdf font",
		format       = wgpu.TextureFormat.R8Unorm,
		address_mode = .ClampToEdge,
		mag_filter   = .Linear,
		min_filter   = .Nearest,
		usage        = {.TextureBinding, .CopyDst},
	}
	texture := texture_create(assets.device, settings.atlas_size, TEXTURE_SETTINGS_SDF_FONT)

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
	atlas_image := sdffont.font_get_atlas_image(sdf_font)
	wgpu.QueueWriteTexture(
		assets.queue,
		&image_copy,
		raw_data(atlas_image.bytes),
		uint(len(atlas_image.bytes)),
		&data_layout,
		&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
	)

	texture_handle := assets_add_texture(assets, texture)
	font = Font {
		settings       = settings,
		name           = strings.clone(name),
		sdf_font       = sdf_font,
		texture_handle = texture_handle,
		line_metrics   = sdffont.font_get_line_metrics(sdf_font),
	}
	return font, nil


}

font_from_path :: proc(
	ttf_file_path: string,
	assets: ^AssetManager,
	settings := sdffont.SDF_FONT_SETTINGS_DEFAULT,
) -> (
	font: Font,
	err: Error,
) {
	ttf_bytes, success := os.read_entire_file(ttf_file_path)
	if !success {
		err = tprint("could not read font tile", ttf_file_path)
		return
	}
	return font_from_bytes(ttf_bytes, assets, ttf_file_path, settings)
}
