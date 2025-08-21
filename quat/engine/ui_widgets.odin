package engine

import q "../"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"
import edit "core:text/edit"
import wgpu "vendor:wgpu"


color_from_hex :: q.color_from_hex
UiId :: q.UiId
Ui :: q.Ui
UiDiv :: ^q.DivElement
UiText :: ^q.TextElement
Interaction :: q.Interaction
Div :: q.Div
Text :: q.Text
UiWithInteraction :: q.UiWithInteraction

UiTheme :: struct {
	font_size_sm:      f32,
	font_size:         f32,
	font_size_lg:      f32,
	text_shadow:       f32,
	disabled_opacity:  f32,
	border_width:      Vec4,
	border_radius:     Vec4,
	border_radius_sm:  Vec4,
	control_width_lg:  f32,
	control_width_sm:  f32,
	control_height:    f32,
	control_height_sm: f32,
	control_height_lg: f32,
	text:              Color,
	text_secondary:    Color,
	background:        Color,
	success:           Color,
	highlight:         Color,
	surface:           Color,
	surface_border:    Color,
	surface_deep:      Color,
}

// not a constant, so can be switched out.
THEME: UiTheme = UiTheme {
	font_size_sm      = 14,
	font_size         = 18,
	font_size_lg      = 24,
	text_shadow       = 0.8,
	disabled_opacity  = 0.4,
	border_width      = 2.0,
	border_radius     = 8.0,
	border_radius_sm  = 4.0,
	control_width_lg  = 196,
	control_width_sm  = 48,
	control_height    = 24,
	control_height_sm = 18,
	control_height_lg = 30,
	text              = color_from_hex("#EFF4F7"),
	text_secondary    = color_from_hex("#777F8B"),
	background        = color_from_hex("#252833"),
	success           = color_from_hex("#68B767"),
	highlight         = color_from_hex("#F7EFB2"),
	surface           = color_from_hex("#577383"),
	surface_border    = color_from_hex("#8CA6BE"),
	surface_deep      = color_from_hex("#16181D"),
}

child :: #force_inline proc(parent: UiDiv, ch: Ui) {
	q.ui_add_child(parent, ch)
}
child_res :: #force_inline proc(parent: UiDiv, ch: q.UiWithInteraction) -> Interaction {
	q.ui_add_child(parent, ch.ui)
	return ch.res
}

with_children :: #force_inline proc(parent: UiDiv, children: []Ui) -> UiDiv {
	for ch in children {
		q.ui_add_child(parent, ch)
	}
	return parent
}

child_div :: #force_inline proc(parent: UiDiv, div: Div, id: UiId = 0) -> UiDiv {
	child := q.div(div, id)
	q.ui_add_child(parent, child)
	return child
}

child_text :: #force_inline proc(parent: UiDiv, text: Text, id: UiId = 0) -> UiText {
	child := q.text(text, id)
	q.ui_add_child(parent, child)
	return child
}

// child_div :: #force_inline proc(of: UiDiv, ch: UiDiv) -> UiDiv {
// 	q.ui_child(of, Ui(ch))
// 	return ch
// }

div :: q.div

text :: proc {
	q.text,
	text_from_string,
	text_from_any,
}

text_from_string :: proc(s: string, id: UiId = 0) -> UiText {
	return q.text(
		q.Text {
			str = s,
			font = q.DEFAULT_FONT,
			color = THEME.text,
			font_size = THEME.font_size,
			shadow = THEME.text_shadow,
		},
	)
}

row :: proc(children: []Ui, gap: f32 = 0) -> Ui {
	row := div(Div{gap = gap, flags = {.AxisX, .CrossAlignCenter}})
	for ch in children {
		q.ui_add_child(row, ch)
	}
	return row
}

text_from_any :: proc(text: any, id: UiId = 0) -> UiText {
	return text_from_string(fmt.aprint(text, allocator = context.temp_allocator), id)
}

add_window :: proc(title: string, content: []Ui, window_width: f32 = 0) {
	id := q.ui_id(title)
	cached_pos, cached_size, _is_world_ui, window_pos_start_drag, ok := q.ui_get_cached(id, Vec2)
	cursor_pos, cursor_pos_start_press := q.ui_cursor_pos()
	layout_extent := get_ui_layout_extent()

	res := q.ui_interaction(id)
	if res.just_pressed {
		window_pos_start_drag^ = cached_pos
	}


	window_pos: Vec2 = ---
	if ok {
		if res.pressed {
			window_pos = window_pos_start_drag^ + cursor_pos - cursor_pos_start_press
		} else {
			window_pos = cached_pos
		}
	} else {
		window_pos = Vec2{0, 0}
	}
	max_pos := layout_extent - cached_size
	window_pos.x = clamp(window_pos.x, 0, max_pos.x)
	window_pos.y = clamp(window_pos.y, 0, max_pos.y)

	window := div(
		Div {
			offset = window_pos,
			border_radius = THEME.border_radius,
			color = THEME.background,
			flags = {.Absolute},
			padding = {16, 16, 8, 16},
			gap = 12,
		},
		id,
	)
	if window_width != 0 {
		window.width = window_width
		window.flags += {.WidthPx}
	}

	child_text(
		window,
		Text {
			color = q.ColorLightGrey if res.hovered else q.ColorMiddleGrey,
			font_size = 18.0,
			str = title,
			shadow = 0.5,
		},
	)
	for ch in content {
		if ch != nil {
			q.ui_add_child(window, ch)
		}
	}
	add_ui(window)
}

button :: proc(title: string, id: string = "") -> UiWithInteraction {
	id := q.ui_id(id) if id != "" else q.ui_id(title)
	action := q.ui_interaction(id)

	color: Color = ---
	border_color: Color = ---
	if action.pressed {
		color = THEME.surface_deep
		border_color = THEME.text
	} else if action.hovered {
		color = THEME.surface_border
		border_color = THEME.text
	} else {
		color = THEME.surface
		border_color = THEME.surface_border
	}

	ui := div(
		Div {
			lerp_speed = 16,
			flags = {.CrossAlignCenter, .HeightPx, .AxisX, .LerpStyle},
			padding = {12, 12, 0, 0},
			height = THEME.control_height_lg,
			color = color,
			border_color = border_color,
			border_radius = THEME.border_radius,
			border_width = THEME.border_width,
		},
		id,
	)
	child_text(ui, Text{str = title, font_size = THEME.font_size, color = THEME.text, shadow = THEME.text_shadow})

	return {ui, action}
}

toggle :: proc(value: ^bool, title: string) -> Ui {
	id := u64(uintptr(value))
	res := q.ui_interaction(id)
	active := value^
	if res.just_pressed {
		active = !active
		value^ = active
	}

	pill_height := THEME.control_height
	pill_width := THEME.control_width_sm
	ui := div(Div{height = pill_height, flags = {.AxisX, .CrossAlignCenter, .HeightPx}, gap = 8})

	circle_color: Color = ---
	pill_color: Color = ---
	text_color: Color = ---

	if active {
		circle_color = THEME.text
		text_color = THEME.text
		pill_color = THEME.success
	} else {
		circle_color = THEME.text
		text_color = THEME.text_secondary
		pill_color = THEME.text_secondary
	}
	if res.hovered {
		pill_color = q.highlight(pill_color)
	}
	pill_flags: q.DivFlags = {.AxisX, .WidthPx, .HeightPx}
	if active {
		pill_flags |= {.MainAlignEnd}
	}

	pad := pill_height / 8
	rad := pill_height / 2
	pill := div(
		Div {
			color = pill_color,
			width = pill_width,
			height = pill_height,
			padding = {pad, pad, pad, pad},
			flags = pill_flags,
			border_radius = rad,
		},
		id = id,
	)
	flags := q.DivFlags{.WidthPx, .HeightPx, .LerpStyle, .LerpTransform, .PointerPassThrough}
	child_div(
		pill,
		Div {
			color = circle_color,
			width = 0.75 * pill_height,
			height = 0.75 * pill_height,
			lerp_speed = 10,
			flags = flags,
			border_radius = 12,
		},
		id = q.ui_id_next(id),
	)
	child(ui, pill)
	child_text(ui, Text{str = title, color = text_color, font_size = THEME.font_size, shadow = THEME.text_shadow})
	return ui
}


slider :: proc {
	slider_f32,
	slider_f64,
	slider_int,
}


slider_int :: proc(
	value: ^int,
	min: int = 0,
	max: int = 1,
	id: UiId = 0,
	slider_width: f32 = 0,
	custom_text: Maybe(string) = nil,
) -> Ui {
	slider_width := slider_width
	if slider_width == 0 {
		slider_width = THEME.control_width_lg
	}
	knob_width: f32 = THEME.font_size
	id := id if id != 0 else u64(uintptr(value))
	val: int = value^

	cached_pos, cached_size, is_world_ui, start_drag_slider_value, ok := q.ui_get_cached(id, int)
	cursor_pos, cursor_pos_start_press := q.ui_cursor_pos(is_world_ui)

	f := (f32(val) - f32(min)) / (f32(max) - f32(min))
	res := q.ui_interaction(id)


	scroll := get_scroll()
	if res.just_pressed {
		f = (cursor_pos.x - knob_width / 2 - cached_pos.CachedElementInfo) / (cached_size.x - knob_width)
		val = int(math.round(f32(min) + f * f32(max - min)))
		start_drag_slider_value^ = val
	} else if res.pressed || (scroll != 0 && res.hovered) {

		if res.pressed {
			cursor_x := cursor_pos.x
			cursor_x_start_active := cursor_pos_start_press.x
			f_shift := (cursor_x - cursor_x_start_active) / (slider_width - knob_width)
			start_f := f32(start_drag_slider_value^ - min) / f32(max - min)
			f = start_f + f_shift
		} else {
			f -= scroll * 0.05
		}

		if f < 0 {
			f = 0
		}
		if f > 1 {
			f = 1
		}
		val = int(math.round_f32(f32(min) + f * f32(max - min)))
		value^ = val
	}


	container := div(
		Div {
			width = slider_width,
			height = THEME.control_height,
			flags = {.WidthPx, .HeightPx, .AxisX, .CrossAlignCenter, .MainAlignCenter},
		},
	)
	child_div(
		container,
		Div {
			width = 1,
			height = THEME.control_height - 2,
			color = THEME.text_secondary,
			border_radius = THEME.border_radius_sm,
			flags = {.WidthFraction, .HeightPx, .Absolute},
			absolute_unit_pos = {0.5, 0.5},
		},
		id = id,
	)
	knob_border_color: Color = THEME.surface if !res.hovered else THEME.surface_border
	f_rounded := math.round(f * f32(max - min)) / f32(max - min)
	child_div(
		container,
		Div {
			width = knob_width,
			height = THEME.control_height,
			color = THEME.surface_deep,
			border_width = THEME.border_width,
			border_color = knob_border_color,
			flags = {.WidthPx, .HeightPx, .Absolute, .LerpStyle, .PointerPassThrough},
			border_radius = THEME.border_radius_sm,
			absolute_unit_pos = {f_rounded, 0.5},
			lerp_speed = 20.0,
		},
		id = q.ui_id_next(id),
	)
	child_text(
		container,
		Text {
			str = custom_text.(string) or_else fmt.tprint(val),
			color = THEME.text,
			font_size = THEME.font_size,
			shadow = THEME.text_shadow,
		},
	)
	return container
}

// todo! maybe the slider_f32 should be the wrapper instead.
slider_f64 :: proc(value: ^f64, min: f64 = 0, max: f64 = 1, id: UiId = 0) -> Ui {
	value_f32 := f32(value^)
	id := id if id != 0 else u64(uintptr(value))
	ui := slider_f32(&value_f32, f32(min), f32(max), id = id)
	value^ = f64(value_f32)
	return ui
}


slider_f32 :: proc(value: ^f32, min: f32 = 0, max: f32 = 1, id: UiId = 0, slider_width: f32 = 0) -> Ui {
	slider_width := slider_width
	if slider_width == 0 {
		slider_width = THEME.control_width_lg
	}
	knob_width: f32 = THEME.font_size
	id := id if id != 0 else u64(uintptr(value))
	val: f32 = value^

	cached_pos, cached_size, is_world_ui, start_drag_slider_value, ok := q.ui_get_cached(id, f32)
	cursor_pos, cursor_pos_start_press := q.ui_cursor_pos(is_world_ui)


	f := (val - min) / (max - min)
	res := q.ui_interaction(id)

	scroll := get_scroll()
	if res.just_pressed {
		f = (cursor_pos.x - knob_width / 2 - cached_pos.CachedElementInfo) / (cached_size.x - knob_width)
		val = min + f * (max - min)
		start_drag_slider_value^ = val
	} else if res.pressed || (scroll != 0 && res.hovered) {

		if res.pressed {
			cursor_x := cursor_pos.x
			cursor_x_start_active := cursor_pos_start_press.x
			f_shift := (cursor_x - cursor_x_start_active) / (slider_width - knob_width)
			start_f := (start_drag_slider_value^ - min) / (max - min)
			f = start_f + f_shift
		} else {
			f -= scroll * 0.05
		}

		if f < 0 {
			f = 0
		}
		if f > 1 {
			f = 1
		}
		val = min + f * (max - min)
		value^ = val
	}


	container := div(
		Div {
			width = slider_width,
			height = THEME.control_height,
			flags = {.WidthPx, .HeightPx, .AxisX, .CrossAlignCenter, .MainAlignCenter},
		},
	)
	child_div(
		container,
		Div {
			width = 1,
			height = THEME.control_height - 4,
			color = THEME.text_secondary,
			border_radius = THEME.border_radius_sm,
			flags = {.WidthFraction, .HeightPx, .Absolute},
			absolute_unit_pos = {0.5, 0.5},
		},
		id = id,
	)
	knob_border_color: Color = THEME.surface if !res.hovered else THEME.surface_border
	child_div(
		container,
		Div {
			width = knob_width,
			height = THEME.control_height,
			color = THEME.surface_deep,
			border_width = THEME.border_width,
			border_color = knob_border_color,
			flags = {.WidthPx, .HeightPx, .Absolute, .LerpStyle, .PointerPassThrough},
			border_radius = THEME.border_radius_sm,
			absolute_unit_pos = {f, 0.5},
			lerp_speed = 20.0,
		},
		id = q.ui_id_next(id),
	)
	text_str := fmt.aprintf("%f", val, allocator = context.temp_allocator)
	child_text(
		container,
		Text{str = text_str, color = THEME.text, font_size = THEME.font_size, shadow = THEME.text_shadow},
	)

	return container
}


check_box :: proc(value: ^bool, title: string, id: UiId = 0) -> Ui {
	id := id if id != 0 else u64(uintptr(value))
	val := value^
	ineraction := _check_box_inner(val, title, id)
	if ineraction.res.just_pressed {
		value^ = !val
	}
	return ineraction.ui
}

enum_dropdown :: proc(value: ^$T, id: UiId = 0) -> Ui where intrinsics.type_is_enum(T) {
	ti := runtime.type_info_base(type_info_of(T))
	ti_enum := ti.variant.(runtime.Type_Info_Enum)
	variant_names := ti_enum.names
	current_idx := 0
	for var, idx in T {
		if var == value^ {
			current_idx = idx
		}
	}

	id := id if id != 0 else u64(uintptr(value))
	ui := dropdown(variant_names, &current_idx, id)

	for var, idx in T {
		if current_idx == idx {
			value^ = var
		}
	}

	return ui
}

dropdown :: proc(values: []string, current_idx: ^int, id: UiId = 0) -> Ui {
	action := q.ui_interaction(id)
	cur_idx := clamp(current_idx^, 0, len(values))

	assert(len(values) > 0)
	id := id if id != 0 else u64(uintptr(current_idx))

	container := div(Div{width = THEME.control_width_lg, height = THEME.control_height, flags = {.WidthPx, .HeightPx}})

	first_id := q.ui_id_combined(q.ui_id_combined(id, q.ui_id(values[cur_idx])), q.ui_id("first"))
	first_el, first_el_res := _field(values[cur_idx], first_id, false)
	child(container, first_el)
	if first_el_res.focused || first_el_res.just_unfocused {
		for v, idx in values {
			field_id := q.ui_id_combined(id, q.ui_id(v))
			field, field_res := _field(v, field_id, true)
			child(container, field)
			if field_res.just_pressed {
				current_idx^ = idx
			}
		}
	}

	return container

	_field :: proc(str: string, field_id: UiId, on_top: bool) -> (^q.DivElement, q.Interaction) {
		action := q.ui_interaction(field_id)
		color: Color = THEME.surface
		border_color: Color = THEME.surface_border
		if action.pressed || action.focused {
			color = THEME.surface_deep
			if action.pressed {
				border_color = THEME.text
			}
		} else if action.hovered {
			color = THEME.surface_border
			border_color = THEME.text
		}
		field := div(
			Div {
				z_layer = 3 if on_top else 0,
				width = THEME.control_width_lg,
				height = THEME.control_height,
				color = color,
				border_color = border_color,
				border_radius = THEME.border_radius,
				border_width = THEME.border_width,
				flags = {.WidthPx, .HeightPx, .CrossAlignCenter, .LerpStyle, .MainAlignCenter},
			},
			field_id,
		)
		child_text(field, Text{str = str, font_size = THEME.font_size, color = THEME.text, shadow = 0.5})

		return field, action
	}
}


@(private)
_check_box_inner :: #force_inline proc(checked: bool, label: string, id: UiId) -> UiWithInteraction {
	action := q.ui_interaction(id)
	text_color: Color = ---
	knob_inner_color: Color = ---
	if checked || action.pressed {
		text_color = THEME.text
		knob_inner_color = THEME.surface_deep
	} else if action.hovered {
		text_color = THEME.highlight
		knob_inner_color = THEME.text_secondary
	} else {
		text_color = THEME.text_secondary
		knob_inner_color = THEME.text_secondary
	}
	ui := div(Div{height = THEME.control_height, gap = 8, flags = {.AxisX, .CrossAlignCenter, .HeightPx}}, id = id)
	child_div(
		ui,
		Div {
			width = THEME.control_height_sm,
			height = THEME.control_height_sm,
			color = knob_inner_color,
			border_color = text_color,
			flags = {.WidthPx, .HeightPx, .MainAlignCenter, .CrossAlignCenter},
			border_radius = THEME.border_radius_sm,
			border_width = {3, 3, 3, 3},
		},
	)
	child_text(ui, Text{str = label, color = text_color, font_size = THEME.font_size, shadow = THEME.text_shadow})
	return {ui, action}
}

enum_radio :: proc(value: ^$T, title: string = "", horizontal := false) -> Ui where intrinsics.type_is_enum(T) {

	ui := div(Div{})
	if horizontal {
		ui.flags = q.DivFlags{.AxisX}
		ui.gap = 16
	} else {
		ui.gap = 2
	}


	if title != "" {
		child_text(
			ui,
			Text{str = title, color = THEME.text, font_size = THEME.font_size_lg, shadow = THEME.text_shadow},
		)
	}
	if !horizontal {
		child_div(ui, Div{height = 2, flags = {.HeightPx}})
	}

	for variant in T {
		str := fmt.aprint(variant, allocator = context.temp_allocator)
		id := q.ui_id(str) ~ u64(uintptr(value))
		label := fmt.aprint(variant, allocator = context.temp_allocator)
		interaction := _check_box_inner(value^ == variant, label, id)
		if interaction.res.just_pressed {
			value^ = variant
		}
		child(ui, interaction.ui)
	}
	return ui
}

// DisplayValuePos :: enum {
// 	TopLeft,
// 	BottomLeft,
// 	TopRight,
// 	BottomRight,
// 	Top,
// 	Left,
// 	Bottom,
// 	Right,
// 	Center,
// }
// UNIT_POS_TABLE: [DisplayValuePos]Vec2 = {
// 	.TopLeft     = Vec2{0, 0},
// 	.BottomLeft  = Vec2{0, 1},
// 	.TopRight    = Vec2{1, 0},
// 	.BottomRight = Vec2{1, 1},
// 	.Top         = Vec2{0.5, 0},
// 	.Left        = Vec2{0, 0.5},
// 	.Bottom      = Vec2{0.5, 1},
// 	.Right       = Vec2{1, 0.5},
// 	.Center      = Vec2{0.5, 0.5},
// }


DisplayValue :: struct {
	label: string,
	value: string,
}

// just shows a value in some part of the screen
_display_values :: proc(values: []DisplayValue) {
	if len(values) == 0 {
		return
	}
	cover := div(q.COVER_DIV)
	upos_div := child_div(
		cover,
		Div {
			flags = {.Absolute, .PointerPassThrough},
			absolute_unit_pos = Vec2{0.5, 1},
			color = {0, 0, 0, 0.6},
			padding = {8, 8, 8, 8},
			border_radius = 8,
		},
	)
	for val in values {
		parent := upos_div
		if val.label != "" {
			parent = child_div(upos_div, Div{flags = {.AxisX, .CrossAlignCenter}, gap = 8})
			child_text(parent, Text{str = val.label, font_size = 20.0, color = q.ColorLightBlue, shadow = 0.4})
		}
		child_text(parent, Text{str = val.value, font_size = 16.0, color = {1, 1, 1, 1}, shadow = 0.4})
	}
	add_ui(cover)
}


// TODO: color picker last_hue caching is not working, if sat or val hit 0, the hue is also set to 0 right now.
color_picker :: proc(value: ^Color, title: string = "", id: UiId = 0) -> Ui {
	// use some local variables to remember the last valid values, because:
	// - in HSV if value = 0 then saturation and hue not reconstructable
	// - if saturation = 0 then hue not reconstructable
	@(thread_local)
	g_id: UiId
	@(thread_local)
	g_hsv: q.Hsv

	id: UiId = u64(uintptr(value)) if id == 0 else id
	dialog_id := q.ui_id_next(id)
	square_id := q.ui_id_next(dialog_id)
	hue_slider_id := q.ui_id_next(square_id)
	text_edit_id := q.ui_id_next(hue_slider_id)

	color_picker_ids := [?]UiId{id, dialog_id, square_id, hue_slider_id, text_edit_id}
	show_dialog := q.ui_any_pressed_or_focused(color_picker_ids[:])
	res_knob := q.ui_interaction(id)


	if show_dialog {
		res_dialog := q.ui_interaction(dialog_id)
		res_square := q.ui_interaction(square_id)
		res_hue_slider := q.ui_interaction(hue_slider_id)
		if id != g_id {
			g_id = id
			color_rgb := q.color_to_rgb(value^)
			g_hsv = q.rbg_to_hsv(color_rgb)
		}

		cursor_pos, _ := q.ui_cursor_pos()
		cached_square_pos, cached_square_size, ok := q.ui_get_cached_no_user_data(square_id)
		if ok {
			if res_square.pressed {
				unit_pos_in_square: Vec2 = (cursor_pos - cached_square_pos) / cached_square_size
				unit_pos_in_square.x = clamp(unit_pos_in_square.x, 0, 1)
				unit_pos_in_square.y = clamp(unit_pos_in_square.y, 0, 1)
				g_hsv.s = f64(unit_pos_in_square.x)
				g_hsv.v = f64(1.0 - unit_pos_in_square.y)
			}
		}

		cached_hue_slider_pos, cached_hue_slider_size, h_ok := q.ui_get_cached_no_user_data(hue_slider_id)
		if h_ok {
			if res_hue_slider.pressed {
				fract_in_slider: f32 = (cursor_pos.x - cached_square_pos.CachedElementInfo) / cached_square_size.x
				fract_in_slider = clamp(fract_in_slider, 0, 1)
				g_hsv.h = f64(fract_in_slider) * 359.8 // so that we dont loop around
			}
		}
		value^ = q.color_from_hsv(g_hsv) // write the transformed color pack to ptr

		color_picker_str := q.color_to_hex(value^)

	}
	color := value^


	ui := div(Div{height = THEME.control_height, gap = 8, flags = {.AxisX, .CrossAlignCenter, .HeightPx}}, id)
	knob := child_div(
		ui,
		Div {
			color = color,
			border_radius = THEME.border_radius,
			border_width = THEME.border_width,
			width = THEME.control_width_sm,
			height = THEME.control_height,
			flags = {.WidthPx, .HeightPx},
		},
		id = id,
	)
	if res_knob.hovered {
		knob.border_color = THEME.text
	} else {
		knob.border_color = THEME.surface_border
	}

	if title != "" {
		child_text(
			ui,
			Text{str = title, color = THEME.text_secondary, font_size = THEME.font_size, shadow = THEME.text_shadow},
		)
	}

	if show_dialog {
		dialog := child_div(
			ui,
			Div {
				padding           = 16,
				color             = THEME.surface_deep,
				border_width      = THEME.border_width,
				border_radius     = THEME.border_radius,
				border_color      = THEME.surface_border,
				absolute_unit_pos = Vec2{0, 0},
				z_layer           = 1,
				flags             = {.Absolute},
				offset            = {54, -100}, // {54, 4}
				gap               = 8,
			},
			dialog_id,
		)
		colors_n_x := 10
		colors_n_y := 10
		colors := make([]Color, colors_n_x * colors_n_y, allocator = context.temp_allocator)
		cross_hair_pos := Vec2{f32(g_hsv.s), 1.0 - f32(g_hsv.v)}
		for y in 0 ..< colors_n_y {
			for x in 0 ..< colors_n_x {
				va_fact := 1.0 - f64(y) / f64(colors_n_y - 1)
				sat_fact := f64(x) / f64(colors_n_x - 1)
				col := q.color_from_hsv(q.Hsv{g_hsv.h, sat_fact, va_fact})
				colors[y * colors_n_x + x] = col
			}
		}
		square := child_div(dialog, Div{}, square_id)
		gradient := color_gradient_rect(
			ColorGradientRect {
				width_px = 168,
				height_px = 168,
				colors_n_x = colors_n_x,
				colors_n_y = colors_n_y,
				colors = colors,
			},
		)
		child(square, gradient)
		child(square, crosshair_at_unit_pos(cross_hair_pos))

		hue_colors_n := 20
		hue_colors := make([]Color, hue_colors_n * 2, allocator = context.temp_allocator)
		for x in 0 ..< hue_colors_n {
			hue_fact := f64(x) / f64(hue_colors_n - 1) * 360.0
			col := q.color_from_hsv(q.Hsv{hue_fact, 1, 1})
			hue_colors[x] = col
			hue_colors[x + hue_colors_n] = col
		}
		hue_slider_cross_hair_pos := Vec2{f32(g_hsv.h) / 360.0, 0.5}
		hue_slider := child_div(dialog, Div{}, hue_slider_id)
		hue_gradient := color_gradient_rect(
			ColorGradientRect {
				width_px = 168,
				height_px = 16,
				colors_n_x = hue_colors_n,
				colors_n_y = 2,
				colors = hue_colors,
			},
		)
		child(hue_slider, hue_gradient)
		child(hue_slider, crosshair_at_unit_pos(hue_slider_cross_hair_pos))

	}


	return ui
}


crosshair_at_unit_pos :: proc(unit_pos: Vec2) -> Ui {

	ui := div(Div{flags = {.Absolute, .WidthPx, .HeightPx}, absolute_unit_pos = unit_pos})
	child_div(
		ui,
		Div {
			width = 16,
			height = 16,
			color = {1.0, 1.0, 1.0, 0.0},
			border_radius = 8,
			border_width = 2,
			border_color = THEME.text,
			flags = {.WidthPx, .HeightPx, .Absolute},
			absolute_unit_pos = Vec2{0.5, 0.5},
		},
	)
	return ui
}

ColorGradientRect :: struct {
	width_px:   f32,
	height_px:  f32,
	colors_n_x: int, // number of columns of colors
	colors_n_y: int, // number of rows of colors
	colors:     []Color, // the colors should be in here row-wise, e.g. first row [a,b,c] then second row [d,e,f], ...
}

color_gradient_rect :: proc(rect: ColorGradientRect, id: UiId = 0) -> Ui {

	// Big problem right now: the verts are always thinking they are sitting on the edge and thus getting
	// sdfs of 0.0 whihc amount to 0.5 when smoothed. Makes color grey instead of white.
	//
	// Solution: set negative border_width

	assert(rect.colors_n_x >= 2)
	assert(rect.colors_n_y >= 2)
	assert(len(rect.colors) == rect.colors_n_x * rect.colors_n_y)
	set_size :: proc(data: ^ColorGradientRect, max_size: Vec2) -> (used_size: Vec2) {
		return Vec2{data.width_px, data.height_px}
	}
	add_primitives :: proc(data: ^ColorGradientRect, pos: Vec2, size: Vec2) -> []q.CustomPrimitives {
		n_x := data.colors_n_x
		n_y := data.colors_n_y

		verts := make([dynamic]q.UiVertex, allocator = context.temp_allocator)
		tris := make([dynamic]q.Triangle, allocator = context.temp_allocator)
		// add vertices:
		for y in 0 ..< n_y {
			for x in 0 ..< n_x {
				i := y * n_x + x
				color := data.colors[i]
				unit_pos := Vec2{f32(x) / f32(n_x - 1), f32(y) / f32(n_y - 1)}
				vertex_pos := pos + size * unit_pos
				append(
					&verts,
					q.UiVertex {
						pos = vertex_pos,
						color = color,
						border_radius = 0,
						size = size,
						flags = 0,
						border_width = q.BORDER_WIDTH_WHEN_NO_CORNER_FLAGS_SUPPLIED,
						border_color = {},
					},
				)
			}
		}
		// add indices: 
		for y in 0 ..< n_y - 1 {
			for x in 0 ..< n_x - 1 {
				idx_0 := u32(y * n_x + x)
				idx_1 := idx_0 + u32(n_x)
				idx_2 := idx_0 + u32(n_x) + 1
				idx_3 := idx_0 + 1
				append(&tris, q.Triangle{idx_0, idx_1, idx_2})
				append(&tris, q.Triangle{idx_0, idx_2, idx_3})
			}
		}
		tmp_slice := make([]q.CustomPrimitives, 1, allocator = context.temp_allocator)
		tmp_slice[0] = q.CustomUiMesh {
			vertices  = verts[:],
			triangles = tris[:],
			texture   = 0,
		}
		return tmp_slice
	}


	return q.ui_custom(rect, set_size, add_primitives)
}


// just serves as a simple example of how you can integrate custom meshes into the ui
colored_triangle :: proc() -> Ui {
	SIZE :: Vec2{200, 150}

	v :: proc(pos: Vec2, color: q.Color) -> q.UiVertex {
		return q.UiVertex {
			pos           = pos,
			color         = color,
			border_radius = {0, 0, 0, 0},
			size          = SIZE,
			flags         = 0,
			// border_width = q.BorderWidth{-10.0, -10.0, -10.0, -10.0},
			border_color  = {},
		}
	}
	set_size :: proc(e: ^Empty, max_size: Vec2) -> Vec2 {
		return SIZE
	}
	add_primitives :: proc(e: ^Empty, pos: Vec2, size: Vec2) -> []q.CustomPrimitives {
		verts := make([]q.UiVertex, 3, allocator = context.temp_allocator)
		verts[0] = v({0, 0}, q.ColorSoftBlue)
		verts[1] = v({100, 150}, q.ColorSoftGreen)
		verts[2] = v({200, 0}, q.ColorSoftPink)
		tris := make([]q.Triangle, 1, context.temp_allocator)
		tris[0] = {0, 1, 2}
		res := make([]q.CustomPrimitives, 1, context.temp_allocator)
		res[0] = q.CustomUiMesh{verts, tris, 0}
		return res
	}
	Empty :: struct {}
	return q.ui_custom(Empty{}, set_size, add_primitives)
}


StringOrBuilderPtr :: union #no_nil {
	^string, // should be nil or allocated in context.allocator
	^strings.Builder,
}

TextEditUiWithInteraction :: struct {
	ui:          Ui,
	res:         q.Interaction,
	just_edited: bool,
}


// todo: still some bug when typing exactly 1 character more than fit in line and then hitting ctrl+A -> selection wrong, only covers first letter of first line instead of both lines
text_edit :: proc(
	value: StringOrBuilderPtr,
	id: UiId = 0,
	width_px: f32 = THEME.control_width_lg,
	max_characters: int = 10000,
	font_size: f32 = THEME.font_size,
	align: q.TextAlign = .Left,
	placeholder: string = "Type something...",
	line_break: q.LineBreak = .OnCharacter,
) -> TextEditUiWithInteraction {
	@(thread_local)
	g_id: UiId = 0
	@(thread_local)
	g_state_initialized: bool
	@(thread_local)
	g_state: edit.State = {}
	@(thread_local)
	string_builder_if_val_is_string: strings.Builder = {}

	id := id


	if id == 0 {
		switch value in value {
		case ^strings.Builder:
			id = u64(uintptr(value))
		case ^string:
			assert(value != nil, "text edit should not get a nil ptr as ^strings.Builder")
			id = u64(uintptr(value))
		}
	}

	font_size := font_size if font_size != 0 else THEME.font_size
	text_id := q.ui_id_next(id)
	res := q.ui_interaction(id)
	just_edited := false

	display_str: string = "INVALID!"
	if res.focused {

		builder: ^strings.Builder
		switch value in value {
		case ^strings.Builder:
			assert(value != nil, "text edit should not get a nil ptr as ^strings.Builder")
			builder = value
		case ^string:
			assert(value != nil, "text edit should not get a nil ptr as ^strings.Builder")
			builder = &string_builder_if_val_is_string
			strings.builder_reset(builder)
			strings.write_string(builder, value^)
		}

		if id != g_id {
			g_id = id
			if !g_state_initialized {
				g_state_initialized = true
				edit.init(&g_state, context.allocator, context.allocator)
			}
			edit.begin(&g_state, id, builder)
		}
		for c in get_input_chars() {
			if strings.rune_count(strings.to_string(builder^)) < max_characters {
				edit.input_rune(&g_state, c)
				just_edited = true
			}
		}

		is_ctrl_pressed := is_ctrl_pressed()
		is_shift_pressed := is_shift_pressed()

		if is_key_just_pressed_or_repeated(.BACKSPACE) {
			edit.delete_to(&g_state, .Left)
			just_edited = true
		}
		if is_key_just_pressed_or_repeated(.DELETE) {
			edit.delete_to(&g_state, .Right)
			just_edited = true
		}
		if is_key_just_pressed_or_repeated(.ENTER) {
			edit.perform_command(&g_state, .New_Line)
		}
		if is_ctrl_pressed {
			if is_key_just_pressed(.A) {
				edit.perform_command(&g_state, .Select_All)
			}
			// if input_just_pressed(input, .Z) { // nor working at the moment, I don't understand the undo API of text edit.
			// 	edit.perform_command(&g_state, .Undo)
			// }
			// if input_just_pressed(input, .Y) {
			// 	edit.perform_command(&g_state, .Redo)
			// }
			if is_key_just_pressed(.C) {
				set_clipboard(edit.current_selected_text(&g_state))
			}
			if is_key_just_pressed(.X) {
				set_clipboard(edit.current_selected_text(&g_state))
				edit.selection_delete(&g_state)
				just_edited = true
			}
			if is_key_just_pressed(.V) {
				edit.input_text(&g_state, get_clipboard())
				just_edited = true
			}
		}
		if is_key_just_pressed_or_repeated(.LEFT) {
			if is_shift_pressed {
				if is_ctrl_pressed {
					edit.select_to(&g_state, .Word_Left)
				} else {
					edit.select_to(&g_state, .Left)
				}
			} else {
				if is_ctrl_pressed {
					edit.move_to(&g_state, .Word_Left)
				} else {
					edit.move_to(&g_state, .Left)
				}
			}
		}

		if is_key_just_pressed_or_repeated(.RIGHT) {
			if is_shift_pressed {
				if is_ctrl_pressed {
					edit.select_to(&g_state, .Word_Right)
				} else {
					edit.select_to(&g_state, .Right)
				}
			} else {
				if is_ctrl_pressed {
					edit.move_to(&g_state, .Word_Right)
				} else {
					edit.move_to(&g_state, .Right)
				}
			}
		}
		display_str = strings.to_string(builder^)
		if just_edited {
			if str_ptr, ok := value.(^string); ok {
				delete(str_ptr^)
				str_ptr^ = strings.clone(display_str, context.allocator)
			}
		}
	} else {
		if g_id == id {
			g_id = 0
		}
		switch value in value {
		case ^strings.Builder:
			display_str = strings.to_string(value^)
		case ^string:
			display_str = value^
		}
	}


	border_color: Color = THEME.surface_border if res.focused else THEME.surface
	bg_color: Color = THEME.surface_deep

	caret_opacity: f32 = 1.0 if math.sin(ENGINE.platform.total_secs * 8.0) > 0.0 else 0.0
	markers_data: MarkersData = {
		text_id         = text_id,
		just_pressed    = res.just_pressed,
		just_released   = res.just_released,
		pressed         = res.pressed,
		caret_width     = 3,
		caret_color     = {THEME.text.r, THEME.text.g, THEME.text.b, caret_opacity},
		selection_color = THEME.surface,
		shift_pressed   = is_shift_pressed(),
	}

	ui := div(
		Div {
			width = width_px,
			color = bg_color,
			border_color = border_color,
			border_width = THEME.border_width,
			border_radius = THEME.border_radius,
			padding = q.padding_symmetric(8, 4),
			flags = {.AxisX, .WidthPx},
		},
		id,
	)
	if res.focused {
		child(ui, q.ui_custom(markers_data, set_markers_size, add_markers_elements))
	}
	if !res.focused && len(display_str) == 0 {
		child_text(
			ui,
			Text {
				str = placeholder,
				font_size = font_size,
				color = THEME.text_secondary,
				shadow = THEME.text_shadow,
				line_break = line_break,
				pointer_pass_through = true,
				align = align,
			},
			text_id,
		)
	} else {
		child_text(
			ui,
			Text {
				str = display_str,
				font_size = font_size,
				color = THEME.text,
				shadow = THEME.text_shadow,
				line_break = line_break,
				pointer_pass_through = true,
				align = align,
			},
			text_id,
		)
	}
	return TextEditUiWithInteraction{ui, res, just_edited}

	// the job of this markers element is to read the TextEditCached from local 
	// markers = caret and selection rectangles
	MarkersData :: struct {
		text_id:         UiId,
		pressed:         bool,
		just_pressed:    bool,
		just_released:   bool,
		shift_pressed:   bool,
		caret_width:     f32,
		caret_color:     Color,
		selection_color: Color,
	}
	set_markers_size :: proc(data: ^MarkersData, max_size: Vec2) -> (used_size: Vec2) {
		return Vec2{0, 0}
	}

	add_markers_elements :: proc(data: ^MarkersData, pos: Vec2, size: Vec2) -> []q.CustomPrimitives {
		vertices: [dynamic]q.UiVertex = make([dynamic]q.UiVertex, context.temp_allocator)
		tris: [dynamic]q.Triangle = make([dynamic]q.Triangle, context.temp_allocator)


		// really hacky:
		text_ctx, ok := ENGINE.ui_ctx.text_ids_to_tmp_layouts[data.text_id] // nil if text is empty string!
		assert(ok)
		assert(text_ctx != nil)
		byte_count := len(text_ctx.byte_advances)

		// get the glyph we are currently on:
		cursor_pos := ENGINE.ui_ctx.cache.cursor_pos
		rel_cursor_pos := cursor_pos - pos
		current_byte_idx := byte_count
		byte_start_idx := 0
		for line, i in text_ctx.lines {
			line_min_y := line.baseline_y - line.metrics.ascent
			line_max_y := line.baseline_y - line.metrics.descent
			if line_min_y > rel_cursor_pos.y || line_max_y < rel_cursor_pos.y {
				byte_start_idx = line.byte_end_idx
				continue
			}
			last_advance: f32 = line.x_offset
			outer: for j in byte_start_idx ..< line.byte_end_idx {
				byte_advance := text_ctx.byte_advances[j] + line.x_offset
				if byte_advance > rel_cursor_pos.x { 	// likely wrong
					current_byte_idx = j
					if byte_advance - rel_cursor_pos.x < rel_cursor_pos.x - last_advance {
						// click is more towards end of a letter
						// search forward to the next different advance (most likely just 1 byte, but could be more bc of UTF8)
						for {
							current_byte_idx += 1
							if current_byte_idx < byte_count {
								byte_advance_next := text_ctx.byte_advances[current_byte_idx]
								if byte_advance_next == 0 {
									continue
								}
							} else {
								current_byte_idx = byte_count // end of bytes
							}
							break outer
						}
					}
					break
				}
				last_advance = byte_advance
			}
			break
		}
		if data.just_pressed {
			if data.shift_pressed {
				g_state.selection[0] = current_byte_idx
			} else {
				g_state.selection = {current_byte_idx, current_byte_idx}
			}
		}
		if data.pressed {
			g_state.selection[0] = current_byte_idx
		}

		// if there is a selection draw the selection:
		left_idx, right_idx := edit.sorted_selection(&g_state)
		if left_idx != right_idx {
			assert(left_idx < right_idx)
			// for each line that is part of the selection draw a rect:
			byte_start_idx: int = 0
			is_first := true
			for line in text_ctx.lines {
				if line.byte_end_idx < left_idx {
					continue
				}
				defer {is_first = false}
				is_last := byte_idx_plus_one(text_ctx.byte_advances[:], line.byte_end_idx) >= right_idx // not correct!!
				x_left: f32 = line.x_offset
				if is_first {
					x_left = advance_at_byte_minus_one(text_ctx.byte_advances[:], left_idx) + line.x_offset
				}
				x_right: f32 = ---
				if is_last {
					x_right = advance_at_byte_minus_one(text_ctx.byte_advances[:], right_idx) + line.x_offset
				} else {
					x_right = advance_at_byte_minus_one(text_ctx.byte_advances[:], line.byte_end_idx) + line.x_offset
				}
				rect_pos := Vec2{pos.x + x_left, pos.y + line.baseline_y - line.metrics.ascent}
				rect_size := Vec2{x_right - x_left, line.metrics.ascent - line.metrics.descent}


				q.add_rect(&vertices, &tris, rect_pos, rect_size, data.selection_color, {}, {}, {2, 2, 2, 2}, {})
				if is_last {
					break
				}
			}
		}

		// draw the cursor:
		should_draw_caret := !(data.pressed && left_idx != right_idx) // dont draw while selecting area.
		if should_draw_caret {
			caret_byte_idx := g_state.selection[0]

			care_line: ^q.LineRun
			for &line in text_ctx.lines {
				care_line = &line
				if line.byte_end_idx >= caret_byte_idx {
					break
				}
			}
			caret_advance: f32 =
				advance_at_byte_minus_one(text_ctx.byte_advances[:], caret_byte_idx) + care_line.x_offset
			pipe_pos := Vec2 {
				pos.x + caret_advance - data.caret_width / 2,
				pos.y + care_line.baseline_y - care_line.metrics.ascent,
			}
			pipe_size := Vec2{data.caret_width, care_line.metrics.ascent - care_line.metrics.descent}
			q.add_rect(&vertices, &tris, pipe_pos, pipe_size, data.caret_color, {}, {}, {2, 2, 2, 2}, {})
		}

		res := make([]q.CustomPrimitives, 1, context.temp_allocator)
		res[0] = q.CustomUiMesh{vertices[:], tris[:], 0}
		return res
	}

	byte_idx_plus_one :: proc(byte_advances: []f32, idx: int) -> int {
		// search forward skipping the 0.0s
		i := idx + 1
		byte_count := len(byte_advances)
		for i < byte_count && byte_advances[i] == 0 {
			i += 1
		}
		return i
	}

	advance_at_byte_minus_one :: proc(byte_advances: []f32, idx: int) -> (advance: f32) {
		// search back (most likely 1 byte) from caret byte idx to advance of previous letter
		i := idx
		for {
			if i == 0 {
				return 0.0
			}
			i -= 1
			advance = byte_advances[i]
			if advance != 0.0 {
				return advance
			}
		}
		return
	}
}


triangle_picker :: proc(weights: ^[3]f32, id: UiId = 0) -> Ui {
	side_len: f32 = 240

	//
	// id := id if id != 0 else u64(uintptr(value))
	// val: int = value^


	// f := (f32(val) - f32(min)) / (f32(max) - f32(min))

	text_to_show := fmt.tprintf("%.2f, %.2f, %.2f", weights.x, weights.y, weights.z)
	id := id if id != 0 else u64(uintptr(weights))
	res := q.ui_interaction(id)

	A_REL_POS :: Vec2{0, 1}
	B_REL_POS :: Vec2{1, 1}
	C_REL_POS :: Vec2{0.5, 0}


	if res.pressed {
		cursor_pos, _ := q.ui_cursor_pos()
		cached_pos, cached_size, _ := q.ui_get_cached_no_user_data(id)
		rel := (cursor_pos - cached_pos) / cached_size
		w := barycentric_coordinates_non_zero(A_REL_POS, B_REL_POS, C_REL_POS, rel)
		weights^ = w
		// text_to_show = fmt.tprintf("%f,%f", rel.x, rel.y)
	}
	knob_rel_pos := A_REL_POS * weights[0] + B_REL_POS * weights[1] + C_REL_POS * weights[2]
	ui := div(Div{flags = {.MainAlignCenter, .CrossAlignCenter}, padding = {8, 8, 8, 8}, gap = 8})
	tri_container := child_div(ui, Div{}, id)
	child(tri_container, equilateral_triangle(side_len, THEME.surface_border if res.pressed else THEME.surface))
	knob_zero_size_container := child_div(
		tri_container,
		Div {
			flags = {.ZeroSizeButInfiniteSizeForChildren, .Absolute, .MainAlignCenter, .CrossAlignCenter},
			absolute_unit_pos = knob_rel_pos,
		},
	)
	child_div(
		knob_zero_size_container,
		Div {
			flags = {.WidthPx, .HeightPx},
			color = THEME.background,
			width = 16,
			height = 16,
			border_radius = 8,
			border_width = 2,
			border_color = THEME.text if res.pressed else THEME.text_secondary,
		},
	)
	child_text(
		ui,
		Text{str = text_to_show, color = q.ColorLightGrey, font_size = THEME.font_size, shadow = THEME.text_shadow},
	)
	return ui
}

barycentric_coordinates_non_zero :: proc(a, b, c, p: Vec2) -> Vec3 {
	det := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	u := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / det
	v := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / det
	w := 1 - u - v

	if u >= 0 && v >= 0 && w >= 0 {
		return Vec3{u, v, w}
	}

	closest := a
	min_dist := max(f32)

	edges := [3][2]Vec2{{a, b}, {b, c}, {c, a}}
	for edge in edges {
		proj := _project_to_segment(p, edge[0], edge[1])
		dist := linalg.length2(p - proj)
		if dist < min_dist {
			min_dist = dist
			closest = proj
		}
	}

	u = ((b.y - c.y) * (closest.x - c.x) + (c.x - b.x) * (closest.y - c.y)) / det
	v = ((c.y - a.y) * (closest.x - c.x) + (a.x - c.x) * (closest.y - c.y)) / det
	w = 1 - u - v

	return Vec3{u, v, w}

	_project_to_segment :: proc(p, a, b: Vec2) -> Vec2 {
		ab := Vec2{b.x - a.x, b.y - a.y}
		ap := Vec2{p.x - a.x, p.y - a.y}
		t := linalg.dot(ap, ab) / linalg.dot(ab, ab)
		t = clamp(t, 0, 1)
		return Vec2{a.x + t * ab.x, a.y + t * ab.y}
	}
}

// just serves as a simple example of how you can integrate custom meshes into the ui
equilateral_triangle :: proc(side_length: f32, color: Color) -> Ui {
	RoundedEquilateralTriangle :: struct {
		side_length:  f32,
		color:        Color,
		border_color: Color,
	}
	widget_data := RoundedEquilateralTriangle {
		side_length  = side_length,
		color        = color,
		border_color = q.ColorDarkTeal,
	}
	v :: proc(pos: Vec2, color: q.Color) -> q.UiVertex {
		return q.UiVertex {
			pos = pos,
			color = color,
			border_radius = 0,
			border_width = q.BORDER_WIDTH_WHEN_NO_CORNER_FLAGS_SUPPLIED,
		}
	}
	set_size :: proc(data: ^RoundedEquilateralTriangle, max_size: Vec2) -> Vec2 {
		return Vec2{data.side_length, math.SQRT_THREE / 2 * data.side_length}
	}
	add_primitives :: proc(data: ^RoundedEquilateralTriangle, pos: Vec2, size: Vec2) -> []q.CustomPrimitives {
		// triangle:
		//      
		//      ^ c
		//     / \
		//    /   \
		//   /     \
		//  ---------
		// a        b
		//
		//	
		context.allocator = context.temp_allocator
		a := pos + Vec2{0, size.y}
		b := pos + size
		c := pos + Vec2{size.x / 2, 0}
		verts := make([]q.UiVertex, 3, allocator = context.temp_allocator)
		verts[0] = v(a, data.color)
		verts[1] = v(b, data.color)
		verts[2] = v(c, data.color)
		tris := make([]q.Triangle, 3, context.temp_allocator)
		tris[0] = {0, 1, 2}
		res := make([]q.CustomPrimitives, 1, context.temp_allocator)
		res[0] = q.CustomUiMesh{verts, tris, 0}
		return res
	}
	return q.ui_custom(widget_data, set_size, add_primitives)
}

NineSlice :: struct {
	tile:            TextureTile,
	tile_px_size:    Vec2,
	tile_inset_size: Vec2,
}
NineSliceMode :: enum {
	Stretch,
	Repeat,
}

// // Note: always fills its container completely, so pack it into a bounded thing
// nine_slice :: proc(_: NineSlice) -> NineSlice {
// 	RoundedEquilateralTriangle :: struct {
// 		side_length:  f32,
// 		color:        Color,
// 		border_color: Color,
// 	}
// 	widget_data := RoundedEquilateralTriangle {
// 		side_length  = side_length,
// 		color        = color,
// 		border_color = q.ColorDarkTeal,
// 	}
// 	v :: proc(pos: Vec2, color: q.Color) -> q.UiVertex {
// 		return q.UiVertex {
// 			pos = pos,
// 			color = color,
// 			border_radius = 0,
// 			border_width = q.BORDER_WIDTH_WHEN_NO_CORNER_FLAGS_SUPPLIED,
// 		}
// 	}
// 	set_size :: proc(data: ^RoundedEquilateralTriangle, max_size: Vec2) -> Vec2 {
// 		return max_size
// 	}
// 	add_primitives :: proc(
// 		data: ^RoundedEquilateralTriangle,
// 		pos: Vec2,
// 		size: Vec2,
// 	) -> []q.CustomPrimitives {
// 		// triangle:
// 		//      
// 		//      ^ c
// 		//     / \
// 		//    /   \
// 		//   /     \
// 		//  ---------
// 		// a        b
// 		//
// 		//	
// 		context.allocator = context.temp_allocator
// 		a := pos + Vec2{0, size.y}
// 		b := pos + size
// 		c := pos + Vec2{size.x / 2, 0}
// 		verts := make([]q.UiVertex, 3, allocator = context.temp_allocator)
// 		verts[0] = v(a, data.color)
// 		verts[1] = v(b, data.color)
// 		verts[2] = v(c, data.color)
// 		inds := make([]u32, 3, context.temp_allocator)
// 		inds[0] = 0
// 		inds[1] = 1
// 		inds[2] = 2
// 		res := make([]q.CustomPrimitives, 1, context.temp_allocator)
// 		res[0] = q.CustomUiMesh{verts, inds, 0}
// 		return res
// 	}
// 	return q.ui_custom(widget_data, set_size, add_primitives)
// }
