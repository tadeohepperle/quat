package quat

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:os"

SCREEN_REFERENCE_SIZE :: [2]u32{1920, 1080}

NO_ID: UiId = 0
UiId :: u64
ui_id :: proc(str: string) -> UiId {
	return hash.crc64_xz(transmute([]byte)str)
}
ui_id_from_ptr :: proc(ptr: rawptr) -> UiId {
	return transmute(UiId)ptr
}
ui_id_next :: proc(id: UiId) -> UiId {
	bytes := transmute([8]u8)id
	return hash.crc64_xz(bytes[:])
}
ui_id_combined :: proc(a: UiId, b: UiId) -> UiId {
	bytes := transmute([16]u8)[2]UiId{a, b}
	return hash.crc64_xz(bytes[:])
}

ui_interaction :: proc(id: UiId) -> Interaction {
	return interaction(id, &UI_CTX_PTR.cache.state)
}


UiWithInteraction :: struct {
	ui:     Ui,
	action: Interaction,
}
InteractionState :: struct($ID: typeid) {
	hovered_id:        ID,
	pressed_id:        ID,
	focused_id:        ID,
	just_pressed_id:   ID,
	just_released_id:  ID,
	just_unfocused_id: ID,
}
update_interaction_state :: proc(
	using state: ^InteractionState($T),
	new_hovered_id: T,
	press: PressFlags,
) {
	// todo! just_hovered, just_unhovered...
	hovered_id = new_hovered_id
	state.just_pressed_id = {}
	state.just_released_id = {}
	state.just_unfocused_id = {}

	if pressed_id != {} && .JustReleased in press {
		if hovered_id == pressed_id {
			focused_id = pressed_id
			just_released_id = pressed_id
		}
		pressed_id = {}
	}

	if focused_id != {} && .JustPressed in press && hovered_id != focused_id {
		just_unfocused_id = focused_id
		focused_id = {}
	}

	if hovered_id != {} && .JustPressed in press {
		just_pressed_id = hovered_id
		pressed_id = hovered_id
	}
}
Interaction :: struct {
	hovered:        bool,
	pressed:        bool,
	focused:        bool,
	just_pressed:   bool,
	just_released:  bool,
	just_unfocused: bool,
}
interaction :: proc(id: $T, state: ^InteractionState(T)) -> Interaction {
	return Interaction {
		hovered = state.hovered_id == id,
		pressed = state.pressed_id == id,
		focused = state.focused_id == id,
		just_pressed = state.just_pressed_id == id,
		just_released = state.just_released_id == id,
		just_unfocused = state.just_unfocused_id == id,
	}
}

ActiveValue :: struct #raw_union {
	slider_value_start_drag:     f32,
	slider_value_start_drag_int: int,
	window_pos_start_drag:       Vec2,
}

cache_any_pressed_or_focused :: proc(cache: ^UiCache, ids: []UiId) -> bool {
	for id in ids {
		if cache.state.pressed_id == id || cache.state.focused_id == id {
			return true
		}
	}
	return false
}

// stuff that should survive the frame boundary is stored here, e.g. previous aabb for divs that had ids
UiCache :: struct {
	cached:                 map[UiId]CachedElement,
	state:                  InteractionState(UiId),
	cursor_pos_start_press: Vec2,
	active_value:           ActiveValue,
	platform:               ^Platform,
	cursor_pos:             Vec2, // (scaled to reference cursor pos)
	layout_extent:          Vec2,
}

// Z position in made up of the following components:
// - traversal_idx - added to each encountered div during a depth-first traversal of the tree
// - layer of the UI, deliberately chosen, to render stuff earlier in the tree on top of stuff that comes later.
// can be transmuted into a u64 to be compared with another ZInfo, layer in the high bits is most significant then
ZInfo :: struct {
	traversal_idx: u32, // less significant
	layer:         u32, // most significant
}
// returns true if a is greater than b
z_gte :: #force_inline proc "contextless" (a: ZInfo, b: ZInfo) -> bool {
	return transmute(u64)a >= transmute(u64)b
}

CachedElement :: struct {
	pos:                  Vec2,
	size:                 Vec2,
	z_info:               ZInfo,
	generation:           int,
	pointer_pass_through: bool,
	color:                Color,
	border_color:         Color,
}
ComputedGlyph :: struct {
	pos:  Vec2,
	size: Vec2,
	uv:   Aabb,
}

UiBatches :: struct {
	primitives: Primitives,
	batches:    [dynamic]UiBatch,
}

Primitives :: struct {
	vertices:         [dynamic]UiVertex,
	indices:          [dynamic]u32,
	glyphs_instances: [dynamic]UiGlyphInstance,
}

UiBatch :: struct {
	start_idx:  int,
	end_idx:    int,
	kind:       BatchKind,
	handle:     TextureOrFontHandle,
	clipped_to: Maybe(Aabb),
}
TextureOrFontHandle :: distinct (u32)
BatchKind :: enum {
	Rect,
	Glyph,
}

UI_VERTEX_FLAG_TEXTURED :: 1
UI_VERTEX_FLAG_RIGHT_VERTEX :: 2
UI_VERTEX_FLAG_BOTTOM_VERTEX :: 4
UiVertex :: struct {
	pos:           Vec2,
	size:          Vec2, // size of the rect this is part of
	uv:            Vec2,
	color:         Color,
	border_color:  Color,
	border_radius: BorderRadius,
	border_width:  BorderWidth,
	flags:         u32,
}
UiGlyphInstance :: struct {
	pos:    Vec2,
	size:   Vec2,
	uv:     Aabb,
	color:  Color,
	shadow: f32,
}

UiElementBase :: struct {
	pos:    Vec2, // computed: in layout (`set_position`)
	size:   Vec2, // computed: in layout (`set_size`)
	z_info: ZInfo, // computed: parent.z + 1
	id:     UiId,
}

TextElement :: struct {
	using base:       UiElementBase,
	using text:       Text,
	glyphs_start_idx: int,
	glyphs_end_idx:   int, // excluding idx, like in a i..<j range
	text_layout_ctx:  ^TextLayoutCtx, // temp allocated! Reason: (a little hacky), save the text layouts during the set_size step here, such that other custom elements can lookup a certain text_id in the set_position step and draw geometry based on the layouted lines.
}

DivElement :: struct {
	using base:   UiElementBase,
	using div:    Div,
	content_size: Vec2, // computeds
	children:     [dynamic]Ui, // in temp storage, 
	// todo: optimize children to be 3 usizes only, and store a single child inline: {backing: []Ui | Ui, len: int} because []Ui and Ui are both 2*8 bytes.    
}

Children :: struct {
	backing: struct #raw_union {
		single:   Ui,
		multiple: []Ui, // cap
	},
	len:     int, // if len == 1, then backing.single can be accessed, otherwise `multiple` is a backing slice of 2^x elements, with the first `len` elements meaningful
}

CustomUiMesh :: struct {
	vertices: []UiVertex,
	indices:  []u32,
	texture:  TextureHandle,
}


CustomGlyphs :: struct {
	instances: []UiGlyphInstance,
	font:      FontHandle,
}

CustomPrimitives :: union #no_nil {
	CustomUiMesh,
	CustomGlyphs,
}

CustomUiElement :: struct {
	using base:   UiElementBase,
	using custom: CustomUi,
}
CustomUiElementStorage :: [128]u8

CustomUi :: struct {
	// `data`` points at this.data when passed to the `set_size` and `add_primitives` functions
	set_size:       proc(data: rawptr, max_size: Vec2) -> (used_size: Vec2),
	// returns the primitives that should be added (preferably allocated in tmp storage)
	add_primitives: proc(
		data: rawptr,
		pos: Vec2, // passed here, instead of having another function for set_position
		size: Vec2, // the size that is also returned in set_size().
	) -> []CustomPrimitives, // in tmp
	data:           CustomUiElementStorage,
}
Div :: struct {
	width:             f32,
	height:            f32,
	padding:           Padding,
	offset:            Vec2,
	absolute_unit_pos: Vec2, // only taken into account if flag .Absolute set
	color:             Color,
	gap:               f32, // gap between children
	flags:             DivFlags,
	texture:           TextureTile,
	border_radius:     BorderRadius,
	border_width:      BorderWidth,
	border_color:      Color,
	lerp_speed:        f32, //   (lerp speed)
	z_layer:           u32, // an offset to the parents z layer. 
}
COVER_DIV :: Div {
	flags  = {.Absolute, .WidthFraction, .HeightFraction},
	width  = 1,
	height = 1,
}
RED_BOX_DIV := Div {
	flags  = {.WidthPx, .HeightPx},
	width  = 60,
	height = 40,
	color  = ColorSoftRed,
}

Padding :: struct {
	left:   f32,
	right:  f32,
	top:    f32,
	bottom: f32,
}
BorderWidth :: struct {
	top:    f32,
	left:   f32,
	bottom: f32,
	right:  f32,
}
BorderRadius :: struct {
	top_left:     f32,
	top_right:    f32,
	bottom_right: f32,
	bottom_left:  f32,
}

Text :: struct {
	str:                  string,
	font:                 FontHandle,
	color:                Color,
	font_size:            f32,
	shadow:               f32,
	offset:               Vec2,
	line_break:           LineBreak,
	align:                TextAlign,
	pointer_pass_through: bool,
}
TextAlign :: enum {
	Left,
	Center,
	Right,
}
LineBreak :: enum {
	OnWord      = 0,
	OnCharacter = 1,
	Never       = 2,
}

DivFlags :: bit_set[DivFlag]
DivFlag :: enum u32 {
	WidthPx,
	WidthFraction,
	HeightPx,
	HeightFraction,
	AxisX, // as opposed to default = AxisY 
	MainAlignCenter,
	MainAlignEnd,
	MainAlignSpaceBetween,
	MainAlignSpaceAround,
	CrossAlignCenter,
	CrossAlignEnd,
	Absolute,
	LayoutAsText,
	LerpStyle,
	LerpTransform,
	ClipContent,
	PointerPassThrough, // divs with this are not considered when determinin which div is hovered. useful for divs that need ids to do animation but are on top of other divs that we want to interact with.
	ZeroSizeButInfiniteSizeForChildren,
}

Ui :: union {
	^DivElement,
	^TextElement,
	^CustomUiElement,
}


// The ui relies on this being set before calling any div/text creating or layout functions
// 
// I know, global state sucks, but the alternative of threading a UiCtx ptr through every 
// nested function call is just less convenient.
// The other alternative would be to use the context.user_ptr of Odin, but in effect that
// is the same, harder to control and even easier to fuck up.
UI_CTX_PTR: ^UiCtx
UiCtx :: struct {
	// all buffers here are fixed size, allocated once because any reallocation could
	// fuck up the internal ptrs in the childrens arrays!
	divs:                    []DivElement,
	divs_len:                int,
	custom_uis:              []CustomUiElement,
	custom_uis_len:          int,
	texts:                   []TextElement,
	texts_len:               int,
	// todo!: possibly these could be GlyphInstances directly, such that we do not need to copy out of here again when creating the instance for UIBatches. 
	// For that, make this a dynamic array that is swapped to the ui_batches
	glyphs:                  []ComputedGlyph,
	glyphs_len:              int,
	cache:                   UiCache,
	text_ids_to_tmp_layouts: map[UiId]^TextLayoutCtx, // currently saved here such that custom elements can access it to read the positions of glyphs.
	temp_alloc:              runtime.Allocator,
}

DIVS_MAX_COUNT :: 2024
TEXTS_MAX_COUNT :: 4096
CUSTOM_UIS_MAX_COUNT :: 512
GLYPHS_MAX_COUNT :: 8192

// Idea: Global ctx could be outsourced to engine package instead of living in quat.
// but then we need all functions like `div`, `text`, etc. to pass the ctx around constantly
// and we need to provide wrappers referring to the GLOBAL_CTX in the `engine` package 
ui_ctx_create :: proc(platform: ^Platform) -> (ctx: UiCtx) {
	ctx.divs = make([]DivElement, DIVS_MAX_COUNT)
	ctx.texts = make([]TextElement, TEXTS_MAX_COUNT)
	ctx.custom_uis = make([]CustomUiElement, CUSTOM_UIS_MAX_COUNT)
	ctx.glyphs = make([]ComputedGlyph, GLYPHS_MAX_COUNT)
	ctx.temp_alloc = context.temp_allocator
	ctx.cache.platform = platform
	return ctx
}

ui_ctx_drop :: proc(ctx: ^UiCtx) {
	delete(ctx.divs)
	delete(ctx.custom_uis)
	delete(ctx.texts)
	delete(ctx.glyphs)
	delete(ctx.cache.cached)
	delete(ctx.text_ids_to_tmp_layouts)
}

ui_add_child :: proc(of: ^DivElement, child: Ui) {
	append(&of.children, child)
}

ui_div :: proc(div: Div, id: UiId = NO_ID) -> ^DivElement {
	UI_CTX_PTR.divs[UI_CTX_PTR.divs_len] = DivElement {
		base = UiElementBase{id = id},
		div = div,
		children = make([dynamic]Ui, allocator = context.temp_allocator),
	}
	#no_bounds_check {
		ptr := &UI_CTX_PTR.divs[UI_CTX_PTR.divs_len]
		UI_CTX_PTR.divs_len += 1
		return ptr
	}
}

ui_text :: proc(text: Text, id: UiId = NO_ID) -> ^TextElement {
	UI_CTX_PTR.texts[UI_CTX_PTR.texts_len] = TextElement {
		base = UiElementBase{id = id},
		text = text,
	}
	#no_bounds_check {
		ptr := &UI_CTX_PTR.texts[UI_CTX_PTR.texts_len]
		UI_CTX_PTR.texts_len += 1
		return ptr
	}
}

ui_custom :: proc(
	data: $T,
	set_size: proc(data: ^T, max_size: Vec2) -> (used_size: Vec2),
	add_primitives: proc(
		data: ^T,
		pos: Vec2, // passed here, instead of having another function for set_position
		size: Vec2, // the size that is also returned in set_size().
	) -> []CustomPrimitives,
	id: UiId = 0,
) -> ^CustomUiElement where size_of(T) <= size_of(CustomUiElementStorage) {
	custom_element := CustomUiElement {
		base = UiElementBase{id = id},
		custom = CustomUi {
			data = CustomUiElementStorage{},
			set_size = auto_cast set_size,
			add_primitives = auto_cast add_primitives,
		},
	}
	// write the data:
	data_dst: ^T = cast(^T)&custom_element.data
	data_dst^ = data
	UI_CTX_PTR.custom_uis[UI_CTX_PTR.custom_uis_len] = custom_element
	#no_bounds_check {
		ptr := &UI_CTX_PTR.custom_uis[UI_CTX_PTR.custom_uis_len]
		UI_CTX_PTR.custom_uis_len += 1
		return ptr
	}
}


ui_ctx_start_frame :: proc(platform: ^Platform) {
	screen_size := platform.screen_size_f32
	cache := &UI_CTX_PTR.cache
	cache.platform = platform
	cache.layout_extent = Vec2 {
		f32(SCREEN_REFERENCE_SIZE.y) * screen_size.x / screen_size.y,
		f32(SCREEN_REFERENCE_SIZE.y),
	}
	cache.cursor_pos = screen_to_layout_space(platform.cursor_pos, screen_size)

	_ui_ctx_clear(UI_CTX_PTR)
	// todo: this could probably also be done, by using the div tree as a space partitioning structure 
	// (assuming non-overlapping divs for the most part!)
	// figure out if any ui element with an id is hovered. If many, select the one with highest z value
	hovered_id: UiId = 0
	highest_z := ZInfo{}
	for id, cached in cache.cached {
		if cached.pointer_pass_through {
			continue
		}
		if z_gte(cached.z_info, highest_z) {
			cursor_in_bounds :=
				cache.cursor_pos.x >= cached.pos.x &&
				cache.cursor_pos.y >= cached.pos.y &&
				cache.cursor_pos.x <= cached.pos.x + cached.size.x &&
				cache.cursor_pos.y <= cached.pos.y + cached.size.y
			if cursor_in_bounds {
				highest_z = cached.z_info
				hovered_id = id
			}
		}
	}

	// determine the rest of ids, i.e. 
	update_interaction_state(&cache.state, hovered_id, cache.platform.mouse_buttons[.Left])

	if cache.state.just_pressed_id != 0 {
		// print("just_pressed_id", cache.state.just_pressed_id)
		cache.cursor_pos_start_press = cache.cursor_pos
	}
}
_ui_ctx_clear :: proc(ctx: ^UiCtx) {
	ctx.divs_len = 0
	ctx.texts_len = 0
	ctx.custom_uis_len = 0
	ctx.glyphs_len = 0
}

ui_end_frame :: proc(
	top_level_elements: []Ui,
	max_size: Vec2,
	delta_secs: f32,
	out_batches: ^UiBatches,
) {
	assert(
		UI_CTX_PTR.cache.platform != nil,
		"platform ptr must be set on UI_CTX_PTR.cache, because it contains the asset manager that we need for resolving fonts!",
	)
	for ui in top_level_elements {
		layout(ui, max_size) // warning! uses the global context at the moment
	}
	build_ui_batches_and_attach_z_info(top_level_elements, out_batches)
	update_ui_cache(delta_secs) // important! do this after z-info is attached to divs, done in `build_ui_batches_and_attach_z_info`
	return
}

// /////////////////////////////////////////////////////////////////////////////
// SECTION: Layout algorithm
// /////////////////////////////////////////////////////////////////////////////
layout :: proc(ui: Ui, max_size: Vec2) {
	initial_pos := Vec2{0, 0}
	_set_size(ui, max_size)
	_set_position(ui, initial_pos)
}

_set_size :: proc(ui: Ui, max_size: Vec2) -> (used_size: Vec2) {
	switch el in ui {
	case ^DivElement:
		_set_size_for_div(el, max_size)
		used_size = el.size
	case ^TextElement:
		_set_size_for_text(el, max_size)
		if el.id != 0 {
			UI_CTX_PTR.text_ids_to_tmp_layouts[el.id] = el.text_layout_ctx
		}
		used_size = el.size
	case ^CustomUiElement:
		el.size = el.set_size(&el.data, max_size)
		used_size = el.size
	}
	return used_size
}

_set_size_for_text :: proc(text: ^TextElement, max_size: Vec2) {
	// if text.str == "" {return Vec2{}}
	text.text_layout_ctx = tmp_text_layout_ctx(max_size, 0.0, text.align)
	_layout_text_in_text_ctx(text.text_layout_ctx, text)
	text.size = finalize_text_layout_ctx_and_return_size(text.text_layout_ctx)
}

_set_child_sizes_for_div :: proc(div: ^DivElement, max_size: Vec2) {
	axis_is_x := DivFlag.AxisX in div.flags

	if DivFlag.LayoutAsText in div.flags {
		// todo: the whole DivFlag.LayoutAsText story is not properly tested yet.
		// perform a text layout with all children:
		ctx := tmp_text_layout_ctx(max_size, f32(div.gap), .Left) // todo! .Left not necessarily correct here, maybe use divs CrossAlign converted to text align or something.
		for ch in div.children {
			_layout_element_in_text_ctx(ctx, ch)
		}
		div.content_size = finalize_text_layout_ctx_and_return_size(ctx)
	} else {
		// perform normal layout:
		div.content_size = Vec2{0, 0}
		for ch in div.children {
			ch_size := _set_size(ch, max_size)
			if !_has_absolute_positioning(ch) {
				if axis_is_x {
					div.content_size.x += ch_size.x
					div.content_size.y = max(div.content_size.y, ch_size.y)
				} else {
					div.content_size.x = max(div.content_size.x, ch_size.x)
					div.content_size.y += ch_size.y
				}
			}
		}
	}
}

_has_absolute_positioning :: proc(element: Ui) -> bool {
	if div, ok := element.(^DivElement); ok && DivFlag.Absolute in div.flags {
		return true
	}
	return false
}

// writes to div.size
_set_size_for_div :: proc(div: ^DivElement, max_size: Vec2) {
	if .ZeroSizeButInfiniteSizeForChildren in div.flags {
		INFINITE_SIZE :: Vec2{max(f32), max(f32)}
		_set_child_sizes_for_div(div, INFINITE_SIZE)
		div.size = Vec2{0, 0}
		return
	}

	width_fixed := false
	if DivFlag.WidthPx in div.flags {
		width_fixed = true
		div.size.x = div.width
	} else if DivFlag.WidthFraction in div.flags {
		width_fixed = true
		div.size.x = div.width * max_size.x
	}
	height_fixed := false
	if DivFlag.HeightPx in div.flags {
		height_fixed = true
		div.size.y = div.height
	} else if DivFlag.HeightFraction in div.flags {
		height_fixed = true
		div.size.y = div.height * max_size.y
	}
	pad_x := div.padding.left + div.padding.right
	pad_y := div.padding.top + div.padding.bottom


	child_count := len(div.children)
	if child_count > 1 && div.gap != 0 {
		if DivFlag.LayoutAsText in div.flags {
			// if there is min 1 text child, then text layout mode is used.
			// there we add the div.gap onto each line instead.
			// -> do nothing here.
		} else {
			additional_gap_space := div.gap * f32(child_count - 1)
			if DivFlag.AxisX in div.flags {
				pad_x += additional_gap_space
			} else {
				pad_y += additional_gap_space
			}
		}
	}

	if width_fixed {
		if height_fixed {
			max_size := div.size - Vec2{pad_x, pad_y}
			_set_child_sizes_for_div(div, max_size)
		} else {
			max_size := Vec2{div.size.x - pad_x, max_size.y}
			_set_child_sizes_for_div(div, max_size)
			div.size.y = div.content_size.y + pad_y
		}
	} else {
		if height_fixed {
			max_size := Vec2{max_size.x, div.size.y - pad_y}
			_set_child_sizes_for_div(div, max_size)
			div.size.x = div.content_size.x + pad_x
		} else {
			_set_child_sizes_for_div(div, max_size)
			div.size = Vec2{div.content_size.x + pad_x, div.content_size.y + pad_y}
		}
	}
}

// writes to ui.base.pos
_set_position :: proc(ui: Ui, pos: Vec2) {
	switch el in ui {
	case ^DivElement:
		_set_position_for_div(el, pos)
	case ^TextElement:
		_set_position_for_text(el, pos)
	case ^CustomUiElement:
		el.pos = pos
	}
}

// writes to div.pos
_set_position_for_div :: proc(div: ^DivElement, pos: Vec2) {
	div.pos = pos + div.offset
	if len(div.children) == 0 {
		return
	}

	if DivFlag.LayoutAsText in div.flags {
		_set_child_positions_for_div_with_text_layout(div)
	} else {
		_set_child_positions_for_div(div)
	}
}

// assumes div.size and div.pos are already set
_set_child_positions_for_div_with_text_layout :: proc(div: ^DivElement) {
	/// WARNING: THIS IS STILL EXPERIMENTAL AND SHOULD PROBABLY NOT BE USED!!! MANY CASES NOT HANDLED, LAYOUT ATTRIBUTES ON PARENT DIV IGNORED.
	for ch in div.children {
		switch el in ch {
		case ^DivElement:
			_set_position_for_div(el, el.pos + div.pos)
		case ^TextElement:
			_set_position_for_text(el, el.pos + div.pos)
		case ^CustomUiElement:
			panic("Custom Ui elements in text not supported.")
		}
	}
}

// assumes div.size and div.pos are already set
_set_child_positions_for_div :: proc(div: ^DivElement) {
	pad_x := div.padding.left + div.padding.right
	pad_y := div.padding.top + div.padding.bottom

	child_count := len(div.children)
	inner_size := Vec2{div.size.x - pad_x, div.size.y - pad_y}
	inner_pos := div.pos + Vec2{div.padding.left, div.padding.top}

	main_size: f32 = ---
	cross_size: f32 = ---
	main_content_size: f32 = ---
	axis_is_x := DivFlag.AxisX in div.flags
	if axis_is_x {
		main_size = inner_size.x
		cross_size = inner_size.y
		main_content_size = div.content_size.x
	} else {
		main_size = inner_size.y
		cross_size = inner_size.x
		main_content_size = div.content_size.y
	}

	main_offset: f32 = 0.0
	main_step: f32 = div.gap
	{ 	// scoped block to keep the variables contained
		m_content_size := main_content_size
		if child_count > 1 {
			m_content_size = main_content_size + f32(child_count - 1) * div.gap
		}
		if DivFlag.MainAlignCenter in div.flags {
			main_offset = (main_size - m_content_size) * 0.5
		} else if DivFlag.MainAlignEnd in div.flags {
			main_offset = main_size - m_content_size
		} else if DivFlag.MainAlignSpaceBetween in div.flags {
			if child_count == 1 {
				main_step = 0.0
			} else {
				main_step = (main_size - main_content_size) / f32(child_count - 1)
			}
		} else if DivFlag.MainAlignSpaceAround in div.flags {
			main_step = (main_size - main_content_size) / f32(child_count)
			main_offset = main_step / 2.0
		}
	}

	for ch in div.children {
		ch_size: Vec2 = _element_base_ptr(ch).size
		ch_main_size: f32 = ---
		ch_cross_size: f32 = ---
		if axis_is_x {
			ch_main_size = ch_size.x
			ch_cross_size = ch_size.y
		} else {
			ch_main_size = ch_size.y
			ch_cross_size = ch_size.x
		}
		ch_cross_offset: f32 = 0.0
		if DivFlag.CrossAlignCenter in div.flags {
			ch_cross_offset = (cross_size - ch_cross_size) / 2.0
		} else if DivFlag.CrossAlignEnd in div.flags {
			ch_cross_offset = cross_size - ch_cross_size
		}

		ch_rel_pos: Vec2 = ---
		if _has_absolute_positioning(ch) {
			ch_rel_pos = (inner_size - ch_size) * ch.(^DivElement).absolute_unit_pos
		} else {
			if axis_is_x {
				ch_rel_pos = Vec2{main_offset, ch_cross_offset}
			} else {
				ch_rel_pos = Vec2{ch_cross_offset, main_offset}
			}
			main_offset += ch_main_size + main_step
		}
		ch_pos := ch_rel_pos + inner_pos
		_set_position(ch, ch_pos)
	}
}


// all variants of Ui have first field `base: UiElementBase`, so we can convert a Ui ptr union to the base ptr.
_element_base_ptr :: #force_inline proc(ui: Ui) -> ^UiElementBase {
	// the first 8 bytes of Ui are always a ^UiElementBase, the second 8 Bytes are a tag.
	UiFatPtr :: struct {
		ptr:       ^UiElementBase, // because all variants have UiElementBase as first field
		tag_bytes: [8]u8,
	}
	return (transmute(UiFatPtr)(ui)).ptr
}

_set_position_for_text :: proc(text: ^TextElement, pos: Vec2) {
	text.pos = pos + text.offset
	for &g in UI_CTX_PTR.glyphs[text.glyphs_start_idx:text.glyphs_end_idx] {
		g.pos.x += f32(text.pos.x)
		g.pos.y += f32(text.pos.y)
	}
	return
}


// /////////////////////////////////////////////////////////////////////////////
// SECTION: Text Layout
// /////////////////////////////////////////////////////////////////////////////

TextLayoutCtx :: struct {
	max_size:                     Vec2,
	max_width:                    f32,
	glyphs_start_idx:             int,
	glyphs_end_idx:               int,
	lines:                        [dynamic]LineRun,
	current_line:                 LineRun,
	additional_line_gap:          f32,
	// save for the last few glyphs that are connected without whitespace in-between their adavances in x direction.
	last_non_whitespace_advances: [dynamic]XOffsetAndAdvance,
	divs_and_their_line_idxs:     [dynamic]DivAndLineIdx,
	align:                        TextAlign,
	byte_advances:                [dynamic]f32,
	last_whitespace_byte_idx:     int,
	last_byte_idx:                int,
}
LineRun :: struct {
	baseline_y:       f32,
	x_offset:         f32, // starting x pos of line (while advance is ending x pos)
	// current advance where to place the next glyph if still space
	advance:          f32,
	// TODO! add width and use instead of advance. width:            f32, // almost the same as advance, but could be slightly different: the last glyph is 
	glyphs_start_idx: int, // index into GLOBAL_CTX.glyphs
	glyphs_end_idx:   int, // index into GLOBAL_CTX.glyphs
	metrics:          LineMetrics,
	byte_end_idx:     int, // inclusive!
}
XOffsetAndAdvance :: struct {
	offset:  f32,
	advance: f32,
}
DivAndLineIdx :: struct {
	div:      ^DivElement,
	line_idx: int,
}

tmp_text_layout_ctx :: proc(
	max_size: Vec2,
	additional_line_gap: f32,
	align: TextAlign,
) -> ^TextLayoutCtx {
	ctx := new(TextLayoutCtx, allocator = context.temp_allocator)
	start_idx := UI_CTX_PTR.glyphs_len
	ctx^ = TextLayoutCtx {
		max_size = max_size,
		max_width = f32(max_size.x),
		additional_line_gap = additional_line_gap,
		glyphs_start_idx = start_idx,
		glyphs_end_idx = start_idx,
		lines = make([dynamic]LineRun, allocator = context.temp_allocator),
		current_line = {glyphs_start_idx = start_idx},
		last_non_whitespace_advances = make(
			[dynamic]XOffsetAndAdvance,
			4,
			allocator = context.temp_allocator,
		),
		divs_and_their_line_idxs = make(
			[dynamic]DivAndLineIdx,
			allocator = context.temp_allocator,
		),
		align = align,
		byte_advances = make([dynamic]f32, allocator = context.temp_allocator),
	}
	return ctx
}


_layout_element_in_text_ctx :: proc(ctx: ^TextLayoutCtx, ui_element: Ui) -> (skipped: int) {
	switch el in ui_element {
	case ^DivElement:
		_layout_div_in_text_ctx(ctx, el)
	case ^TextElement:
		_layout_text_in_text_ctx(ctx, el)
		skipped = 1
	case ^CustomUiElement:
		panic("Custom Ui elements in text not allowed yet.")
	}
	return
}


_layout_div_in_text_ctx :: proc(ctx: ^TextLayoutCtx, div: ^DivElement) {
	_set_size_for_div(div, ctx.max_size)
	line_break_needed := ctx.current_line.advance + div.size.x > ctx.max_width
	if line_break_needed {
		break_line(ctx)
	}
	// assign the x part of the element relative position already, the relative y is assined later, when we know the fine heights of each line.
	div.size.x = ctx.current_line.advance
	ctx.current_line.advance += div.size.x
	line_idx := len(ctx.lines)
	append(&ctx.divs_and_their_line_idxs, DivAndLineIdx{div = div, line_idx = line_idx})
	// todo! maybe adjust the line height for the line this div is in 
	// ctx.current_line.metrics.ascent = max(ctx.current_line.metrics.ascent, f32(element_size.y))
	return
}

_ui_get_font :: proc(handle: FontHandle) -> Font {
	assets := UI_CTX_PTR.cache.platform.asset_manager
	return assets_get_font(assets, handle)
}

_layout_text_in_text_ctx :: proc(ctx: ^TextLayoutCtx, text: ^TextElement) {
	font := _ui_get_font(text.font)
	font_size := text.font_size
	scale := font_size / f32(font.rasterization_size)
	ctx.current_line.metrics = merge_line_metrics_to_max(
		ctx.current_line.metrics,
		scale_line_metrics(font.line_metrics, scale),
	)
	text.glyphs_start_idx = UI_CTX_PTR.glyphs_len
	resize(&ctx.byte_advances, len(ctx.byte_advances) + len(text.str))
	for ch, ch_byte_idx in text.str {
		ctx.last_byte_idx = ch_byte_idx
		g, ok := font.glyphs[ch]
		if !ok {
			fmt.panicf("Character %s not rastierized yet!", ch)
		}
		g.advance *= scale
		g.xmin *= scale
		g.ymin *= scale
		g.width *= scale
		g.height *= scale
		if ch == '\n' {
			ctx.byte_advances[ch_byte_idx] = ctx.current_line.advance
			break_line(ctx)
			continue
		}
		needs_line_break :=
			text.line_break != .Never && ctx.current_line.advance + g.advance > ctx.max_width
		if needs_line_break {
			break_line(ctx)
			if g.is_white_space {
				// just break, note: the whitespace here is omitted and does not add extra space.
				// (we do not want to have extra white space at the end of a line or at the start of a line unintentionally.)
				clear(&ctx.last_non_whitespace_advances)
				ctx.last_whitespace_byte_idx = ch_byte_idx
				continue
			}

			if text.line_break == .OnWord {
				// now move all letters that have been part of this word before onto the next line:
				move_n_to_next_line := len(ctx.last_non_whitespace_advances)
				last_line: ^LineRun = &ctx.lines[len(ctx.lines) - 1]
				last_line.glyphs_end_idx -= move_n_to_next_line
				last_line.byte_end_idx = ctx.last_whitespace_byte_idx + 1 // assuming all whitespace is one byte ?
				ctx.current_line.glyphs_start_idx -= move_n_to_next_line
				for j in 0 ..< move_n_to_next_line {
					oa := ctx.last_non_whitespace_advances[j]
					glyph_idx := ctx.current_line.glyphs_start_idx + j
					UI_CTX_PTR.glyphs[glyph_idx].pos.x = ctx.current_line.advance + oa.offset
					ctx.current_line.advance += oa.advance
					last_line.advance -= oa.advance
				}
			}
		}

		// now add the glyph to the current line:
		if g.is_white_space {
			clear(&ctx.last_non_whitespace_advances)
		} else {
			x_offset := g.xmin
			y_offset := -g.ymin
			height := g.height
			UI_CTX_PTR.glyphs[UI_CTX_PTR.glyphs_len] = ComputedGlyph {
				pos  = Vec2{ctx.current_line.advance + x_offset, -height + y_offset},
				size = Vec2{g.width, g.height},
				uv   = Aabb{g.uv_min, g.uv_max},
			}
			UI_CTX_PTR.glyphs_len += 1
			ctx.current_line.glyphs_end_idx = UI_CTX_PTR.glyphs_len // ??? idk if we should do this all the time...
			append(
				&ctx.last_non_whitespace_advances,
				XOffsetAndAdvance{offset = x_offset, advance = g.advance},
			)
		}
		ctx.current_line.advance += g.advance
		ctx.byte_advances[ch_byte_idx] = ctx.current_line.advance
	}
	text.glyphs_end_idx = UI_CTX_PTR.glyphs_len
}

break_line :: proc(ctx: ^TextLayoutCtx) {
	break_idx := UI_CTX_PTR.glyphs_len
	ctx.current_line.glyphs_end_idx = break_idx
	ctx.current_line.byte_end_idx = ctx.last_byte_idx
	append(&ctx.lines, ctx.current_line)
	// note: we keep the metrics of the line before, just reset advance to 0 and the start idx to the last lines end idx
	ctx.current_line.advance = 0
	ctx.current_line.glyphs_start_idx = break_idx
}

finalize_text_layout_ctx_and_return_size :: proc(ctx: ^TextLayoutCtx) -> (used_size: Vec2) {
	ctx.current_line.byte_end_idx = ctx.last_byte_idx
	ctx.current_line.glyphs_end_idx = UI_CTX_PTR.glyphs_len
	append(&ctx.lines, ctx.current_line)
	// calculate the y of the character baseline for each line and add it to the y position of each glyphs coordinates
	base_y: f32 = 0
	max_line_width: f32 = 0
	n_lines := len(ctx.lines)
	for &line, i in ctx.lines {
		base_y += line.metrics.ascent
		line.baseline_y = base_y
		max_line_width = max(max_line_width, line.advance) // TODO! technically line.advance is not the correct end of the line, instead the last glyphs width should be the cutoff value. The advance could be wider of less wide than the width.
		// todo! there is a bug here, if the width of the container is too small to hold a single word, the application crashes.
		// todo! crashes when line.glyphs_end_idx is 0 for whatever reason
		for &g in UI_CTX_PTR.glyphs[line.glyphs_start_idx:line.glyphs_end_idx] {
			g.pos.y += base_y
		}
		base_y += -line.metrics.descent + line.metrics.line_gap
		if i < n_lines - 1 {
			base_y += ctx.additional_line_gap // can be configured by setting div.gap property.
		}
	}

	// go over all non-text child elements and set their position to the baseline - descent (so the total bottom of a line).
	for e in ctx.divs_and_their_line_idxs {
		line := &ctx.lines[e.line_idx]
		bottom_y := line.baseline_y - line.metrics.descent
		e.div.pos = bottom_y - e.div.size.y
	} // Todo: Test this, I think I just ported this over from the Rust trading card game but not sure if divs in text layout are supported yet.


	// if right or center align, shift all the glyphs in all lines to the right
	max_size := ctx.max_size
	if ctx.align == .Left {
		used_size = Vec2{min(max_size.x, max_line_width), min(max_size.y, base_y)}
	} else {
		used_size = Vec2{max_size.x, min(max_size.y, base_y)}
		byte_start_idx: int = 0
		for &line in ctx.lines {
			offset: f32 = ---
			line_width := line.advance
			switch ctx.align {
			case .Left:
				unreachable() // handled above already, for left align, we do NOT need to glyphs in any line
			case .Center:
				offset = (max_size.x - line_width) / 2
			case .Right:
				offset = max_size.x - line_width
			}
			if offset == 0 {
				continue
			}
			for &g in UI_CTX_PTR.glyphs[line.glyphs_start_idx:line.glyphs_end_idx] {
				g.pos.x += offset
			}
			line.advance += offset
			line.x_offset = offset
			byte_start_idx = line.byte_end_idx
		}
	}
	return
}

scale_line_metrics :: proc(line_metrics: LineMetrics, scale: f32) -> LineMetrics {
	return LineMetrics {
		ascent = line_metrics.ascent * scale,
		descent = line_metrics.descent * scale,
		line_gap = line_metrics.line_gap * scale,
		new_line_size = line_metrics.new_line_size * scale,
	}
}

merge_line_metrics_to_max :: proc(a: LineMetrics, b: LineMetrics) -> (res: LineMetrics) {
	res.ascent = max(a.ascent, b.ascent)
	res.descent = min(a.descent, b.descent)
	res.line_gap = max(a.line_gap, b.line_gap)
	res.new_line_size = res.ascent - res.descent + res.line_gap
	return
}

// /////////////////////////////////////////////////////////////////////////////
// SECTION: Batching and other stuff
// /////////////////////////////////////////////////////////////////////////////

/// Note: also modifies the Ui-Elements in the UI_Memory to achieve lerping from the last frame.
update_ui_cache :: proc(delta_secs: f32) {
	@(thread_local)
	generation: int
	@(thread_local)
	remove_queue: [dynamic]UiId

	DIV_DEFAULT_LERP_SPEED :: 5.0

	clear(&remove_queue)
	generation += 1

	cache := &UI_CTX_PTR.cache
	for &div in UI_CTX_PTR.divs[:UI_CTX_PTR.divs_len] {
		if div.id == NO_ID {
			continue
		}
		old_cached, has_old_cached := cache.cached[div.id]
		new_cached: CachedElement = CachedElement {
			pos        = div.pos,
			size       = div.size,
			z_info     = div.z_info,
			generation = generation,
		}
		new_cached.pointer_pass_through = .PointerPassThrough in div.flags
		if has_old_cached {
			lerp_style := .LerpStyle in div.flags
			lerp_transform := .LerpTransform in div.flags
			s: f32 = --- // lerp factor
			if lerp_style || lerp_transform {
				lerp_speed := div.lerp_speed
				if lerp_speed == 0 {
					lerp_speed = DIV_DEFAULT_LERP_SPEED
				}
				s = lerp_speed * delta_secs
			}
			if lerp_style {
				new_cached.color = lerp(old_cached.color, div.color, s)
				div.color = new_cached.color
				new_cached.border_color = lerp(old_cached.border_color, div.border_color, s)
				div.border_color = new_cached.border_color
			} else {
				new_cached.color = div.color
				new_cached.border_color = div.border_color
			}
			// todo: should be in relation to parent
			if lerp_transform {
				new_cached.pos = lerp(old_cached.pos, div.pos, s)
				div.pos = new_cached.pos
				new_cached.size = lerp(old_cached.size, div.size, s)
				div.size = new_cached.size
			}
		}
		cache.cached[div.id] = new_cached
	}

	for &text in UI_CTX_PTR.texts[:UI_CTX_PTR.texts_len] {
		if text.id == NO_ID {
			continue
		}
		cache.cached[text.id] = CachedElement {
			pos                  = text.pos,
			size                 = text.size,
			z_info               = text.z_info,
			generation           = generation,
			pointer_pass_through = text.pointer_pass_through,
		}
	}

	for &custom in UI_CTX_PTR.custom_uis[:UI_CTX_PTR.custom_uis_len] {
		if custom.id == NO_ID {
			continue
		}
		cache.cached[custom.id] = CachedElement {
			pos        = custom.pos,
			size       = custom.size,
			z_info     = custom.z_info,
			generation = generation,
		}
	}

	// delete old elements from the cache
	for k, &v in cache.cached {
		if v.generation != generation {
			append(&remove_queue, k)
		}
	}
	for k in remove_queue {
		delete_key(&cache.cached, k)
	}
}


PreBatch :: struct {
	end_idx: int,
	kind:    BatchKind,
	handle:  TextureOrFontHandle,
}
// writes to `z_info` of every encountered element in the ui hierarchy, setting its traversal_idx and layer.
build_ui_batches_and_attach_z_info :: proc(top_level_elements: []Ui, out_batches: ^UiBatches) {
	// different regions can make up a single batch in the end, the regions are only for controlling the 
	// order (ascending z) in which the ui elements are added to the batches.
	ZRegion :: struct {
		ui:         Ui,
		z_layer:    u32,
		clipped_to: Maybe(Aabb),
	}
	CurrentBatch :: struct {
		start_idx: int, // index into glyph instances or (vertex) indices array
		kind:      BatchKind,
		handle:    TextureOrFontHandle,
	}
	// a new z region is added for each top level element and for each child div with a non-zero z-layer (offset)
	Batcher :: struct {
		current_z_layer:    u32,
		traversal_idx:      u32,
		z_regions:          [dynamic]ZRegion, // kept sorted by region.z_info.layer
		batches:            ^UiBatches,
		current:            CurrentBatch,
		current_clipped_to: Maybe(Aabb), // todo! clipping not implemented yet!
	}
	_insert_z_region :: proc(z_regions: ^[dynamic]ZRegion, region: ZRegion) {
		// search from the back to the front, adding when larger or equal to the highest layer up to now:
		insert_idx := len(z_regions)
		for ; insert_idx > 0; insert_idx -= 1 {
			highest_z_layer := z_regions[insert_idx - 1].z_layer
			if region.z_layer >= highest_z_layer {
				break
			}
		}
		inject_at(z_regions, insert_idx, region)
	}
	_batcher_create :: proc(top_level_elements: []Ui, out_batches: ^UiBatches) -> Batcher {
		elements_count := len(top_level_elements)
		z_regions := make([dynamic]ZRegion, allocator = context.temp_allocator)
		_clear_batches(out_batches)
		for ui, i in top_level_elements {
			base := _element_base_ptr(ui)
			z_layer: u32 = 0
			if div, ok := ui.(^DivElement); ok {
				z_layer = div.z_layer
			}

			_insert_z_region(&z_regions, ZRegion{ui, z_layer, nil})
		}
		return Batcher{batches = out_batches, z_regions = z_regions}
	}

	// print("++++++++++++++++++++++++++++++++++++++++++++++++")

	// Note: currently no sorting by z here
	b: Batcher = _batcher_create(top_level_elements, out_batches)
	idx := 0
	for ; idx < len(b.z_regions); idx += 1 {
		reg: ZRegion = b.z_regions[idx]
		b.current_z_layer = reg.z_layer
		b.current_clipped_to = reg.clipped_to // note: Aabb{{0,0}, {0,0}} means no clipping
		_add(&b, reg.ui)
	}
	_flush(&b)
	// Idea: we should actually abuse the fact that most text is on the very top and it happens 
	// super rarely that there are any rects over text
	_clear_batches :: proc(batches: ^UiBatches) {
		clear(&batches.primitives.vertices)
		clear(&batches.primitives.indices)
		clear(&batches.primitives.glyphs_instances)
		clear(&batches.batches)
	}


	// Note: currently no sorting or z-index, just add children recursively in order.
	_add :: proc(b: ^Batcher, ui: Ui) {
		base := _element_base_ptr(ui)
		base.z_info = ZInfo{b.traversal_idx, b.current_z_layer}
		b.traversal_idx += 1
		write := &b.batches.primitives
		switch e in ui {
		case ^DivElement:
			_flush_if_mismatch(b, .Rect, TextureOrFontHandle(e.texture.handle))
			_add_div_rect(e, &write.vertices, &write.indices)


			prev_clip: Maybe(Aabb) = ---
			all_children_are_clipped := 0
			clips_content: bool = .ClipContent in e.flags
			if clips_content {
				prev_clip = b.current_clipped_to // save to restore later, when done with children
				div_aabb := Aabb{base.pos, base.pos + base.size}
				if current_clip, ok := b.current_clipped_to.(Aabb); !ok {
					// no clipping currently applied, set the clipping to the area covered by this div
					b.current_clipped_to = div_aabb
				} else {
					intersection_clip, has_overlap := aabb_intersection(div_aabb, current_clip)
					if !has_overlap {
						// There is a 0-sized clipping rect, meaning all children would be completely clipped, 
						// so return and skip this part of the UI tree completely
						return
					} else if intersection_clip == current_clip {
						// the div and all of its content are already clipped to a smaller area than the div would clip,
						// so it is like the div would not clip anything at all.
						clips_content = false
					} else {
						b.current_clipped_to = intersection_clip
					}
				}
			}

			// add primitives for all children, pushing children with a higher z layer back in the queue of handled ZRegions.
			for ch, i in e.children {
				if div, ok := ch.(^DivElement); ok && div.z_layer != 0 {
					// handle this child later (on top of the other ui elements with lower z)
					child_z_layer := div.z_layer + b.current_z_layer
					_insert_z_region(
						&b.z_regions,
						ZRegion{ch, child_z_layer, b.current_clipped_to},
					)
				} else {
					// add the batches for this child and all of its children recursively
					_add(b, ch)
				}
			}

			// restore the clipping rect that was present before:
			if clips_content {
				b.current_clipped_to = prev_clip
			}
		case ^TextElement:
			_flush_if_mismatch(b, .Glyph, TextureOrFontHandle(e.font))
			// todo: maybe copying them over is stupid, maybe we can create the computed glyphs
			// directly in the primitives buffer from the get go
			for g in UI_CTX_PTR.glyphs[e.glyphs_start_idx:e.glyphs_end_idx] {
				append(
					&write.glyphs_instances,
					UiGlyphInstance {
						pos = g.pos,
						size = g.size,
						uv = g.uv,
						color = e.color,
						shadow = e.shadow,
					},
				)
			}
		case ^CustomUiElement:
			custom_primitive_runs: []CustomPrimitives = e.add_primitives(&e.data, e.pos, e.size)
			for custom_primitives in custom_primitive_runs {
				switch kind in custom_primitives {
				case CustomUiMesh:
					_flush_if_mismatch(b, .Rect, TextureOrFontHandle(kind.texture))
					start_idx := u32(len(write.vertices))
					// todo: memcpy might be faster for vertices!
					for v in kind.vertices {
						append(&write.vertices, v)
					}
					for i in kind.indices {
						append(&write.indices, i + start_idx)
					}
				case CustomGlyphs:
					_flush_if_mismatch(b, .Glyph, TextureOrFontHandle(kind.font))
					// todo: memcpy might be faster for glyph instances!
					for g in kind.instances {
						append(&write.glyphs_instances, g)
					}
				}
			}

		}
	}

	_flush_if_mismatch :: proc(b: ^Batcher, kind: BatchKind, handle: TextureOrFontHandle) {
		if b.current.kind != kind || b.current.handle != handle {
			_flush(b)
			b.current.kind = kind
			b.current.handle = handle
			b.current.start_idx = _idx_for_batch_kind(&b.batches.primitives, kind)
		}
	}
	_flush :: proc(b: ^Batcher) {
		end_idx: int = _idx_for_batch_kind(&b.batches.primitives, b.current.kind)
		if end_idx > b.current.start_idx {
			append(
				&b.batches.batches,
				UiBatch {
					start_idx = b.current.start_idx,
					end_idx = end_idx,
					kind = b.current.kind,
					handle = b.current.handle,
					clipped_to = b.current_clipped_to,
				},
			)
		}
	}

	_idx_for_batch_kind :: proc(primitives: ^Primitives, kind: BatchKind) -> int {
		switch kind {
		case .Rect:
			return len(primitives.indices)
		case .Glyph:
			return len(primitives.glyphs_instances)
		}
		unreachable()
	}
}


_add_div_rect :: #force_inline proc(
	e: ^DivElement,
	vertices: ^[dynamic]UiVertex,
	indices: ^[dynamic]u32,
) {
	if e.color == {0, 0, 0, 0} || e.size.x == 0 || e.size.y == 0 {
		return
	}
	start_v := u32(len(vertices))

	max_border_radius := min(e.size.x, e.size.y) / 2.0
	if e.border_radius.top_left > max_border_radius {
		e.border_radius.top_left = max_border_radius
	}
	if e.border_radius.top_right > max_border_radius {
		e.border_radius.top_right = max_border_radius
	}
	if e.border_radius.bottom_right > max_border_radius {
		e.border_radius.bottom_right = max_border_radius
	}
	if e.border_radius.bottom_left > max_border_radius {
		e.border_radius.bottom_left = max_border_radius
	}

	add_rect(
		vertices,
		indices,
		e.pos,
		e.size,
		e.color,
		e.border_color,
		e.border_width,
		e.border_radius,
		e.texture,
	)
}

add_rect :: #force_inline proc(
	vertices: ^[dynamic]UiVertex,
	indices: ^[dynamic]u32,
	pos: Vec2,
	size: Vec2,
	color: Color,
	border_color: Color,
	border_width: BorderWidth,
	border_radius: BorderRadius,
	texture: TextureTile,
) {
	start_v := u32(len(vertices))

	flags_all: u32 = 0
	if texture.handle != 0 {
		flags_all |= UI_VERTEX_FLAG_TEXTURED
	}

	vertex := UiVertex {
		pos           = pos,
		size          = size,
		uv            = texture.uv.min,
		color         = color,
		border_color  = border_color,
		border_radius = border_radius,
		border_width  = border_width,
		flags         = flags_all,
	}
	append(vertices, vertex)
	vertex.pos = {pos.x, pos.y + size.y}
	vertex.flags = flags_all | UI_VERTEX_FLAG_BOTTOM_VERTEX
	vertex.uv = {texture.uv.min.x, texture.uv.max.y}
	append(vertices, vertex)
	vertex.pos = pos + size
	vertex.flags = flags_all | UI_VERTEX_FLAG_BOTTOM_VERTEX | UI_VERTEX_FLAG_RIGHT_VERTEX
	vertex.uv = {texture.uv.max.x, texture.uv.max.y}
	append(vertices, vertex)
	vertex.pos = {pos.x + size.x, pos.y}
	vertex.flags = flags_all | UI_VERTEX_FLAG_RIGHT_VERTEX
	vertex.uv = {texture.uv.max.x, texture.uv.min.y}
	append(vertices, vertex)

	append(indices, start_v)
	append(indices, start_v + 1)
	append(indices, start_v + 2)
	append(indices, start_v)
	append(indices, start_v + 2)
	append(indices, start_v + 3)
}

// /////////////////////////////////////////////////////////////////////////////
// SECTION: Renderer
// /////////////////////////////////////////////////////////////////////////////
