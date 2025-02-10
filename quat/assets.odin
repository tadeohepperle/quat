package quat

import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"
import wgpu "vendor:wgpu"

TextureHandle :: distinct u32
TextureArrayHandle :: distinct u32
FontHandle :: distinct u32

DEFAULT_FONT :: FontHandle(0)
DEFAULT_TEXTURE :: TextureHandle(0)

TextureSlot :: struct #raw_union {
	texture:       Texture,
	next_free_idx: int,
}
#assert(size_of(Texture) == size_of(TextureSlot))

AssetManager :: struct {
	textures:           SlotMap(Texture), // also contains texture arrays!
	fonts:              SlotMap(Font),
	skinned_geometries: SlotMap(SkinnedGeometry),
	skinned_meshes:     SlotMap(SkinnedMesh),
	device:             wgpu.Device,
	queue:              wgpu.Queue,
}

DEFAULT_FONT_TTF := #load("../assets/Lora-Medium.ttf")
// DEFAULT_FONT_TTF := #load("../assets/LuxuriousRoman-Regular.ttf")
// DEFAULT_FONT_TTF := #load("../assets/MarkoOne-Regular.ttf")


asset_manager_create :: proc(
	assets: ^AssetManager,
	default_font_path: string,
	device: wgpu.Device,
	queue: wgpu.Queue,
) {
	assets.device = device
	assets.queue = queue

	default_texture := _texture_create_1px_white(device, queue)
	default_texture_handle := slotmap_insert(&assets.textures, default_texture)
	assert(default_texture_handle == 0) // is the first one

	default_font: Font
	font_err: Error
	if default_font_path == "" {
		default_font, font_err = font_from_bytes(DEFAULT_FONT_TTF, assets, "LuxuriousRoman")

	} else {
		default_font, font_err = font_from_path(default_font_path, assets)
	}
	if font_err, has_err := font_err.(string); has_err {
		panic(font_err)
	}
	font_handle := FontHandle(slotmap_insert(&assets.fonts, default_font))
	assert(font_handle == 0)
}
asset_manager_destroy :: proc(assets: ^AssetManager) {
	textures := slotmap_to_tmp_slice(assets.textures)
	for &texture in textures {
		texture_destroy(&texture)
	}
	fonts := slotmap_to_tmp_slice(assets.fonts)
	for &font in fonts {
		font_destroy(&font)
	}

	geometries := slotmap_to_tmp_slice(assets.skinned_geometries)
	for &geom in geometries {
		_geometry_drop(&geom)
	}
	meshes := slotmap_to_tmp_slice(assets.skinned_meshes)
	for &mesh in meshes {
		_skinned_mesh_drop(&mesh)
	}
}
assets_get_texture_array_bind_group :: proc(
	assets: AssetManager,
	handle: TextureArrayHandle,
) -> wgpu.BindGroup {
	texture := slotmap_get(assets.textures, u32(handle))
	return texture.bind_group
}
assets_get_texture_bind_group :: proc(
	assets: AssetManager,
	handle: TextureHandle,
) -> wgpu.BindGroup {
	texture := slotmap_get(assets.textures, u32(handle))
	return texture.bind_group
}

assets_get_font_texture_bind_group :: proc(
	assets: AssetManager,
	handle: FontHandle,
) -> wgpu.BindGroup {
	font := slotmap_get(assets.fonts, u32(handle))
	texture := slotmap_get(assets.textures, u32(font.texture_handle))
	return texture.bind_group
}

assets_get_texture_info :: proc(assets: AssetManager, handle: TextureHandle) -> TextureInfo {
	texture := slotmap_get(assets.textures, u32(handle))
	return texture.info
}
assets_get_texture :: proc(assets: AssetManager, handle: TextureHandle) -> Texture {
	texture := slotmap_get(assets.textures, u32(handle))
	return texture
}

assets_get_font :: proc(assets: AssetManager, handle: FontHandle) -> Font {
	return slotmap_get(assets.fonts, u32(handle))
}

assets_load_depth_texture :: proc(assets: ^AssetManager, path: string) -> TextureHandle {
	texture, err := depth_texture_16bit_r_from_image_path(assets.device, assets.queue, path)
	if err != nil {
		print(path, "error:", err)
		panic("Panic loading depth 16bit R texture")
	}
	texture_handle := TextureHandle(slotmap_insert(&assets.textures, texture))
	return texture_handle
}
assets_add_texture :: proc(assets: ^AssetManager, texture: Texture) -> TextureHandle {
	texture_handle := TextureHandle(slotmap_insert(&assets.textures, texture))
	return texture_handle
}
assets_load_texture :: proc(
	assets: ^AssetManager,
	path: string,
	settings: TextureSettings = TEXTURE_SETTINGS_RGBA,
) -> TextureHandle {
	texture, err := texture_from_image_path(assets.device, assets.queue, path, settings)
	if err != nil {
		print("error:", err)
		panic("Panic loading texture.")
	}
	return assets_add_texture(assets, texture)
}

assets_load_texture_array :: proc(
	assets: ^AssetManager,
	paths: []string,
	settings: TextureSettings = TEXTURE_SETTINGS_RGBA,
) -> TextureArrayHandle {
	texture, err := texture_array_from_image_paths(assets.device, assets.queue, paths, settings)
	if err != nil {
		print("error:", err)
		panic("Panic loading texture.")
	}
	texture_handle := TextureArrayHandle(slotmap_insert(&assets.textures, texture))
	return texture_handle
}

assets_load_font :: proc(
	assets: ^AssetManager,
	ttf_path: string,
) -> (
	handle: FontHandle,
	err: Error,
) {
	font := font_from_path(ttf_path, assets) or_return
	font_handle := FontHandle(slotmap_insert(&assets.fonts, font))
	return font_handle, nil
}

assets_deregister_texture :: proc(assets: ^AssetManager, handle: TextureHandle) {
	texture := slotmap_remove(&assets.textures, u32(handle))
	texture_destroy(&texture)
}

assets_deregister_font :: proc(assets: ^AssetManager, handle: FontHandle) {
	font := slotmap_remove(&assets.fonts, u32(handle))
	font_destroy(&font)
	assets_deregister_texture(assets, font.texture_handle)
}

/*

Todo: add a white texture with 1px that can always be used as a fallback for TextureHandle 0

*/


// font.texture = TextureHandle(slotmap_insert(&assets.textures, font_texture))
// 	font_handle = FontHandle(slotmap_insert(&assets.fonts, font))
