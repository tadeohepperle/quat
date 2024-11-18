package quat

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:strings"
import edit "core:text/edit"


UiTheme :: struct {
	font_size:               f32,
	font_size_sm:            f32,
	font_size_lg:            f32,
	text_shadow:             f32,
	disabled_opacity:        f32,
	border_width:            BorderWidth,
	border_radius:           BorderRadius,
	border_radius_sm:        BorderRadius,
	control_standard_height: f32,
	text:                    Color,
	text_secondary:          Color,
	background:              Color,
	success:                 Color,
	highlight:               Color,
	surface:                 Color,
	surface_border:          Color,
	surface_deep:            Color,
}

// not a constant, so can be switched out.
THEME: UiTheme = UiTheme {
	font_size               = 22,
	font_size_sm            = 18,
	font_size_lg            = 28,
	text_shadow             = 0.4,
	disabled_opacity        = 0.4,
	border_width            = BorderWidth{2.0, 2.0, 2.0, 2.0},
	border_radius           = BorderRadius{8.0, 8.0, 8.0, 8.0},
	border_radius_sm        = BorderRadius{4.0, 4.0, 4.0, 4.0},
	control_standard_height = 36.0,
	text                    = color_from_hex("#EFF4F7"),
	text_secondary          = color_from_hex("#777F8B"),
	background              = color_from_hex("#252833"),
	success                 = color_from_hex("#68B767"),
	highlight               = color_from_hex("#F7EFB2"),
	surface                 = color_from_hex("#577383"),
	surface_border          = color_from_hex("#8CA6BE"),
	surface_deep            = color_from_hex("#16181D"),
}


button :: proc(title: string, id: string = "") -> Interaction {
	id := ui_id(id) if id != "" else ui_id(title)
	res := ui_interaction(id)

	color: Color = ---
	border_color: Color = ---
	if res.pressed {
		color = THEME.surface_deep
		border_color = THEME.text
	} else if res.hovered {
		color = THEME.surface_border
		border_color = THEME.text
	} else {
		color = THEME.surface
		border_color = THEME.surface_border
	}

	start_div(
		Div {
			lerp_speed = 16,
			flags = {.CrossAlignCenter, .HeightPx, .AxisX, .LerpStyle},
			padding = {12, 12, 0, 0},
			height = THEME.control_standard_height,
			color = color,
			border_color = border_color,
			border_radius = THEME.border_radius,
			border_width = THEME.border_width,
		},
		id,
	)
	text(
		Text {
			str = title,
			font_size = THEME.font_size,
			color = THEME.text,
			shadow = THEME.text_shadow,
		},
	)
	end_div()

	return res

}

toggle :: proc(value: ^bool, title: string) {
	id := u64(uintptr(value))
	res := ui_interaction(id)
	active := value^
	if res.just_pressed {
		active = !active
		value^ = active
	}


	start_div(
		Div {
			height = THEME.control_standard_height,
			flags = {.AxisX, .CrossAlignCenter, .HeightPx},
			gap = 8,
		},
	)

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
		pill_color = highlight(pill_color)
	}
	pill_flags: DivFlags = {.AxisX, .WidthPx, .HeightPx}
	if active {
		pill_flags |= {.MainAlignEnd}
	}
	start_div(
		Div {
			color = pill_color,
			width = 64,
			height = 32,
			padding = {4, 4, 4, 4},
			flags = pill_flags,
			border_radius = {16, 16, 16, 16},
		},
		id = id,
	)
	div(
		Div {
			color = circle_color,
			width = 24,
			height = 24,
			lerp_speed = 10,
			flags = {.WidthPx, .HeightPx, .LerpStyle, .LerpTransform, .PointerPassThrough},
			border_radius = {12, 12, 12, 12},
		},
		id = derived_id(id),
	)
	end_div()
	text(
		Text {
			str = title,
			color = text_color,
			font_size = THEME.font_size,
			shadow = THEME.text_shadow,
		},
	)
	end_div()
}


slider :: proc {
	slider_f32,
	slider_f64,
	slider_int,
}

// todo! int values are not correctly displayed (shown as floats as well)
slider_int :: proc(value: ^int, min: int = 0, max: int = 1, id: UiId = 0) {
	value_f32 := f32(value^)
	slider_f32(&value_f32, f32(min), f32(max))
	value^ = int(math.round(value_f32))
}

// todo! maybe the slider_f32 should be the wrapper instead.
slider_f64 :: proc(value: ^f64, min: f64 = 0, max: f64 = 1, id: UiId = 0) {
	value_f32 := f32(value^)
	id := id if id != 0 else u64(uintptr(value))
	slider_f32(&value_f32, f32(min), f32(max), id = id)
	value^ = f64(value_f32)
}


slider_f32 :: proc(value: ^f32, min: f32 = 0, max: f32 = 1, id: UiId = 0) {
	slider_width: f32 = 192
	knob_width: f32 = 24

	cache: ^UiCache = UI_MEMORY.cache
	id := id if id != 0 else u64(uintptr(value))
	val: f32 = value^

	f := (val - min) / (max - min)
	res := ui_interaction(id)

	scroll := cache.platform.scroll
	if res.just_pressed {
		cached := cache.cached[id]
		f = (cache.cursor_pos.x - knob_width / 2 - cached.pos.x) / (cached.size.x - knob_width)
		val = min + f * (max - min)
		cache.active_value.slider_value_start_drag = val
	} else if res.pressed || (scroll != 0 && res.hovered) {

		if res.pressed {
			cursor_x := cache.cursor_pos.x
			cursor_x_start_active := cache.cursor_pos_start_press.x
			f_shift := (cursor_x - cursor_x_start_active) / (slider_width - knob_width)
			start_f := (cache.active_value.slider_value_start_drag - min) / (max - min)
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


	start_div(
		Div {
			width = slider_width,
			height = THEME.control_standard_height,
			flags = {.WidthPx, .HeightPx, .AxisX, .CrossAlignCenter, .MainAlignCenter},
		},
	)
	div(
		Div {
			width = 1,
			height = 32,
			color = THEME.text_secondary,
			border_radius = THEME.border_radius_sm,
			flags = {.WidthFraction, .HeightPx, .Absolute},
			absolute_unit_pos = {0.5, 0.5},
		},
		id = id,
	)
	knob_border_color: Color = THEME.surface if !res.hovered else THEME.surface_border
	div(
		Div {
			width = knob_width,
			height = THEME.control_standard_height,
			color = THEME.surface_deep,
			border_width = THEME.border_width,
			border_color = knob_border_color,
			flags = {.WidthPx, .HeightPx, .Absolute, .LerpStyle, .PointerPassThrough},
			border_radius = THEME.border_radius_sm,
			absolute_unit_pos = {f, 0.5},
			lerp_speed = 20.0,
		},
		id = derived_id(id),
	)
	text_str := fmt.aprintf("%f", val, allocator = context.temp_allocator)
	text(
		Text {
			str = text_str,
			color = THEME.text,
			font_size = THEME.font_size,
			shadow = THEME.text_shadow,
		},
	)

	end_div()
}

end_window :: proc() {
	end_div()
}

start_window :: proc(title: string, window_width: f32 = 500) {
	id := ui_id(title)
	cache := UI_MEMORY.cache
	assert(UI_MEMORY.parent_stack_len == 0)
	res := ui_interaction(id)
	if res.just_pressed {
		cache.active_value.window_pos_start_drag = UI_MEMORY.cache.cached[id].pos
	}

	window_pos: Vec2 = ---
	cache_entry, ok := cache.cached[id]
	if ok {
		if res.pressed {
			window_pos =
				cache.active_value.window_pos_start_drag +
				cache.cursor_pos -
				cache.cursor_pos_start_press
		} else {
			window_pos = cache_entry.pos
		}
	} else {
		window_pos = Vec2{0, 0}
	}
	max_pos := cache.layout_extent - cache_entry.size
	window_pos.x = clamp(window_pos.x, 0, max_pos.x)
	window_pos.y = clamp(window_pos.y, 0, max_pos.y)

	start_div(
		Div {
			offset = window_pos,
			width = window_width,
			border_radius = THEME.border_radius,
			color = THEME.background,
			flags = {.Absolute, .WidthPx},
			padding = {16, 16, 8, 16},
			gap = 12,
		},
		id = id,
	)

	text(
		Text {
			color = Color_Gray if res.hovered else Color_Black,
			font_size = 18.0,
			str = title,
			shadow = 0.5,
		},
	)
}

red_box :: proc(size: Vec2 = {300, 200}) {
	div(Div{color = Color_Red, width = size.x, height = size.y, flags = {.WidthPx, .HeightPx}})
}

StringBuilder :: strings.Builder
edit_old :: proc(value: ^strings.Builder) {

	id := u64(uintptr(value))
	res := ui_interaction(id)

	platform := UI_MEMORY.cache.platform

	if res.focused {
		for c in platform.chars[:platform.chars_len] {
			strings.write_rune(value, c)
		}
		if .JustPressed in platform.keys[.BACKSPACE] ||
		   .JustRepeated in platform.keys[.BACKSPACE] {
			if strings.builder_len(value^) > 0 {
				strings.pop_rune(value)
			}
		}
	}

	text_str := strings.to_string(value^)
	bg_color := color_gray(0.4) if res.focused else color_gray(0.2)
	start_div(
		Div {
			width = 400,
			height = 300,
			flags = {.WidthPx, .HeightPx, .MainAlignCenter, .LayoutAsText},
			color = bg_color,
			border_radius = {4, 4, 4, 4},
		},
		id = id,
	)
	text(
		Text {
			str = text_str,
			color = Color_Black,
			font_size = 18.0,
			shadow = 0.0,
			align = .Right,
			line_break = .Never,
		},
	)
	div(Div{width = 8, height = 8, color = Color_Chocolate, flags = {.WidthPx, .HeightPx}})
	text(
		Text {
			str = text_str,
			color = Color_Black,
			font_size = 18.0,
			shadow = 0.0,
			align = .Right,
			line_break = .Never,
		},
	)
	end_div()
}


check_box :: proc(value: ^bool, title: string, id: UiId = 0) {
	id := id if id != 0 else u64(uintptr(value))
	val := value^
	res := _check_box_inner(val, title, id)
	if res.just_pressed {
		value^ = !val
	}
}

@(private)
_check_box_inner :: #force_inline proc(checked: bool, label: string, id: UiId) -> Interaction {
	res := ui_interaction(id)
	text_color: Color = ---
	knob_inner_color: Color = ---
	if checked || res.pressed {
		text_color = THEME.text
		knob_inner_color = THEME.surface_deep
	} else if res.hovered {
		text_color = THEME.highlight
		knob_inner_color = THEME.text_secondary
	} else {
		text_color = THEME.text_secondary
		knob_inner_color = THEME.text_secondary
	}
	start_div(
		Div {
			height = THEME.control_standard_height,
			gap = 8,
			flags = {.AxisX, .CrossAlignCenter, .HeightPx},
		},
		id = id,
	)
	div(
		Div {
			width = 24.0,
			height = 24.0,
			color = knob_inner_color,
			border_color = text_color,
			flags = {.WidthPx, .HeightPx, .MainAlignCenter, .CrossAlignCenter},
			border_radius = THEME.border_radius,
			border_width = {4, 4, 4, 4},
		},
	)
	text(
		Text {
			str = label,
			color = text_color,
			font_size = THEME.font_size,
			shadow = THEME.text_shadow,
		},
	)
	end_div()
	return res
}

enum_radio :: proc(value: ^$T, title: string = "") where intrinsics.type_is_enum(T) {
	start_div(Div{})
	if title != "" {
		text(
			Text {
				str = title,
				color = THEME.text,
				font_size = THEME.font_size_lg,
				shadow = THEME.text_shadow,
			},
		)
	}

	for variant in T {
		str := fmt.aprint(variant, allocator = context.temp_allocator)
		id := ui_id(str) ~ u64(uintptr(value))
		label := fmt.aprint(variant, allocator = context.temp_allocator)
		res := _check_box_inner(value^ == variant, label, id)
		if res.just_pressed {
			value^ = variant
		}
	}
	end_div()

}


// TODO: color picker last_hue caching is not working, if sat or val hit 0, the hue is also set to 0 right now.
color_picker :: proc(value: ^Color, title: string = "", id: UiId = 0) {
	// use some local variables to remember the last valid values, because:
	// - in HSV if value = 0 then saturation and hue not reconstructable
	// - if saturation = 0 then hue not reconstructable
	@(thread_local)
	g_id: UiId
	@(thread_local)
	g_hsv: Hsv

	id: UiId = u64(uintptr(value)) if id == 0 else id
	dialog_id := derived_id(id)
	square_id := derived_id(dialog_id)
	hue_slider_id := derived_id(square_id)
	text_edit_id := derived_id(hue_slider_id)

	cache := UI_MEMORY.cache
	color_picker_ids := [?]UiId{id, dialog_id, square_id, hue_slider_id, text_edit_id}
	show_dialog := cache_any_pressed_or_focused(cache, color_picker_ids[:])
	res_knob := ui_interaction(id)


	if show_dialog {
		res_dialog := ui_interaction(dialog_id)
		res_square := ui_interaction(square_id)
		res_hue_slider := ui_interaction(hue_slider_id)
		if id != g_id {
			g_id = id
			color_rgb := color_to_rgb(value^)
			g_hsv = rbg_to_hsv(color_rgb)
		}

		cached_square, ok := cache.cached[square_id]
		if ok {
			if res_square.pressed {
				unit_pos_in_square: Vec2 =
					(cache.cursor_pos - cached_square.pos) / cached_square.size
				unit_pos_in_square.x = clamp(unit_pos_in_square.x, 0, 1)
				unit_pos_in_square.y = clamp(unit_pos_in_square.y, 0, 1)
				g_hsv.s = f64(unit_pos_in_square.x)
				g_hsv.v = f64(1.0 - unit_pos_in_square.y)
			}
		}

		cached_hue_slider, h_ok := cache.cached[hue_slider_id]
		if h_ok {
			if res_hue_slider.pressed {
				fract_in_slider: f32 =
					(cache.cursor_pos.x - cached_square.pos.x) / cached_square.size.x
				fract_in_slider = clamp(fract_in_slider, 0, 1)
				g_hsv.h = f64(fract_in_slider) * 359.8 // so that we dont loop around
			}
		}
		value^ = color_from_hsv(g_hsv) // write the transformed color pack to ptr

		color_picker_str := color_to_hex(value^)

	}
	color := value^

	start_div(
		Div {
			height = THEME.control_standard_height,
			gap = 8,
			flags = {.AxisX, .CrossAlignCenter, .HeightPx},
		},
		id = id,
	)
	border_color: Color = ---
	if res_knob.hovered {
		border_color = THEME.text
	} else {
		border_color = THEME.surface_border
	}
	div(
		Div {
			color = color,
			border_radius = THEME.border_radius,
			border_color = border_color,
			border_width = THEME.border_width,
			width = 48,
			height = 32,
			flags = {.WidthPx, .HeightPx},
		},
		id = id,
	)

	if title != "" {
		text(
			Text {
				str = title,
				color = THEME.text_secondary,
				font_size = THEME.font_size,
				shadow = THEME.text_shadow,
			},
		)
	}

	if show_dialog {
		start_div(
			Div {
				padding           = Padding{16, 16, 16, 16},
				color             = THEME.surface_deep,
				border_width      = THEME.border_width,
				border_radius     = THEME.border_radius,
				border_color      = THEME.surface_border,
				absolute_unit_pos = Vec2{0, 0},
				z_bias            = 1,
				flags             = {.Absolute},
				offset            = {54, -100}, // {54, 4}
				gap               = 8,
			},
			id = dialog_id,
		)

		colors_n_x := 10
		colors_n_y := 10
		colors := make([]Color, colors_n_x * colors_n_y, allocator = context.temp_allocator)
		cross_hair_pos := Vec2{f32(g_hsv.s), 1.0 - f32(g_hsv.v)}
		for y in 0 ..< colors_n_y {
			for x in 0 ..< colors_n_x {
				va_fact := 1.0 - f64(y) / f64(colors_n_y - 1)
				sat_fact := f64(x) / f64(colors_n_x - 1)
				col := color_from_hsv(Hsv{g_hsv.h, sat_fact, va_fact})
				colors[y * colors_n_x + x] = col
			}
		}
		start_div(Div{}, id = square_id)
		color_gradient_rect(
			ColorGradientRect {
				width_px = 168,
				height_px = 168,
				colors_n_x = colors_n_x,
				colors_n_y = colors_n_y,
				colors = colors,
			},
		)
		crosshair_at_unit_pos(cross_hair_pos)
		end_div() // end sat-val square area.

		hue_colors_n := 20
		hue_colors := make([]Color, hue_colors_n * 2, allocator = context.temp_allocator)
		for x in 0 ..< hue_colors_n {
			hue_fact := f64(x) / f64(hue_colors_n - 1) * 360.0
			col := color_from_hsv(Hsv{hue_fact, 1, 1})
			hue_colors[x] = col
			hue_colors[x + hue_colors_n] = col
		}
		hue_slider_cross_hair_pos := Vec2{f32(g_hsv.h) / 360.0, 0.5}
		start_div(Div{}, id = hue_slider_id)
		color_gradient_rect(
			ColorGradientRect {
				width_px = 168,
				height_px = 16,
				colors_n_x = hue_colors_n,
				colors_n_y = 2,
				colors = hue_colors,
			},
		)
		crosshair_at_unit_pos(hue_slider_cross_hair_pos)
		end_div() // end hue slider area


		@(static) builder_created: bool
		@(static) color_hex_str: strings.Builder
		if !builder_created {
			builder_created = true
			color_hex_str := strings.builder_make(allocator = context.temp_allocator)
			strings.write_string(&color_hex_str, "#12030")
		}

		text_edit(&color_hex_str, text_edit_id, 168.0, 7, placeholder = "#000000", align = .Center)

		end_div() // end dialog
	}

	end_div()
}

crosshair_at_unit_pos :: proc(unit_pos: Vec2) {
	start_div(Div{flags = {.Absolute, .WidthPx, .HeightPx}, absolute_unit_pos = unit_pos})
	div(
		Div {
			width = 16,
			height = 16,
			color = {1.0, 1.0, 1.0, 0.0},
			border_radius = {8, 8, 8, 8},
			border_width = {2, 2, 2, 2},
			border_color = THEME.text,
			flags = {.WidthPx, .HeightPx, .Absolute},
			absolute_unit_pos = Vec2{0.5, 0.5},
		},
	)
	end_div()
}

ColorGradientRect :: struct {
	width_px:   f32,
	height_px:  f32,
	colors_n_x: int, // number of columns of colors
	colors_n_y: int, // number of rows of colors
	colors:     []Color, // the colors should be in here row-wise, e.g. first row [a,b,c] then second row [d,e,f], ...
}

color_gradient_rect :: proc(rect: ColorGradientRect, id: UiId = 0) {

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
	add_elements :: proc(
		data: ^ColorGradientRect,
		pos: Vec2,
		size: Vec2,
		primitives: ^Primitives,
		pre_batches: ^[dynamic]PreBatch,
	) {
		n_x := data.colors_n_x
		n_y := data.colors_n_y
		border_width := BorderWidth{-10.0, -10.0, -10.0, -10.0}
		vertex_idx := u32(len(primitives.vertices))
		// add vertices:
		for y in 0 ..< n_y {
			for x in 0 ..< n_x {
				i := y * n_x + x
				color := data.colors[i]
				unit_pos := Vec2{f32(x) / f32(n_x - 1), f32(y) / f32(n_y - 1)}
				vertex_pos := pos + size * unit_pos
				append(
					&primitives.vertices,
					UiVertex {
						pos = vertex_pos,
						color = color,
						border_radius = {0, 0, 0, 0},
						size = size,
						flags = 0,
						border_width = border_width,
						border_color = {},
					},
				)
			}
		}
		// add indices: 
		for y in 0 ..< n_y - 1 {
			for x in 0 ..< n_x - 1 {
				idx_0 := vertex_idx + u32(y * n_x + x)
				idx_1 := idx_0 + u32(n_x)
				idx_2 := idx_0 + u32(n_x) + 1
				idx_3 := idx_0 + 1
				append(&primitives.indices, idx_0)
				append(&primitives.indices, idx_1)
				append(&primitives.indices, idx_2)
				append(&primitives.indices, idx_0)
				append(&primitives.indices, idx_2)
				append(&primitives.indices, idx_3)
			}
		}
		append(pre_batches, PreBatch{kind = .Rect, end_idx = len(primitives.indices), handle = 0})
	}

	custom_ui_element(rect, set_size, add_elements)

}


text_edit :: proc(
	value: ^StringBuilder,
	id: UiId = 0,
	width_px: f32 = 240,
	max_characters: int = 10000,
	font_size: f32 = 0,
	align: TextAlign = TextAlign.Left,
	placeholder: string = "Type something...",
	line_break: LineBreak = .OnCharacter,
) {
	@(thread_local)
	g_id: UiId = 0
	@(thread_local)
	g_state_initialized: bool
	@(thread_local)
	g_state: edit.State = {}

	font_size := font_size if font_size != 0 else THEME.font_size_sm

	id := id if id != 0 else u64(uintptr(value))
	text_id := derived_id(id)
	res := ui_interaction(id)


	cache := UI_MEMORY.cache
	platform := UI_MEMORY.cache.platform
	if res.focused {
		if id != g_id {
			g_id = id
			if !g_state_initialized {
				g_state_initialized = true
				edit.init(&g_state, context.allocator, context.allocator)
			}
			edit.begin(&g_state, id, value)
		}
		for c in platform.chars[:platform.chars_len] {
			if strings.rune_count(strings.to_string(value^)) < max_characters {
				edit.input_rune(&g_state, c)
			}
		}

		is_ctrl_pressed := platform_is_pressed(platform, .LEFT_CONTROL)
		is_shift_pressed := platform_is_pressed(platform, .LEFT_SHIFT)

		if platform_just_pressed_or_repeated(platform, .BACKSPACE) {
			edit.delete_to(&g_state, .Left)
		}
		if platform_just_pressed_or_repeated(platform, .DELETE) {
			edit.delete_to(&g_state, .Right)
		}
		if platform_just_pressed_or_repeated(platform, .ENTER) {
			edit.perform_command(&g_state, .New_Line)
		}
		if platform_is_pressed(platform, .LEFT_CONTROL) {
			if platform_just_pressed(platform, .A) {
				edit.perform_command(&g_state, .Select_All)
			}
			// if input_just_pressed(input, .Z) { // nor working at the moment, I don't understand the undo API of text edit.
			// 	edit.perform_command(&g_state, .Undo)
			// }
			// if input_just_pressed(input, .Y) {
			// 	edit.perform_command(&g_state, .Redo)
			// }
			if platform_just_pressed(platform, .C) {
				platform_set_clipboard(platform, edit.current_selected_text(&g_state))
			}
			if platform_just_pressed(platform, .X) {
				platform_set_clipboard(platform, edit.current_selected_text(&g_state))
				edit.selection_delete(&g_state)
			}
			if platform_just_pressed(platform, .V) {
				edit.input_text(&g_state, platform_get_clipboard(platform))
			}
		}
		if platform_just_pressed_or_repeated(platform, .LEFT) {
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

		if platform_just_pressed_or_repeated(platform, .RIGHT) {
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


	} else {
		if g_id == id {
			g_id = 0
		}
	}

	str := strings.to_string(value^)


	border_color: Color = THEME.surface_border if res.focused else THEME.surface
	bg_color: Color = THEME.surface_deep

	caret_opacity: f32 = 1.0 if math.sin(platform.total_secs * 8.0) > 0.0 else 0.0
	markers_data: MarkersData = {
		text_id         = text_id,
		just_pressed    = res.just_pressed,
		just_released   = res.just_released,
		pressed         = res.pressed,
		caret_width     = 4,
		caret_color     = {THEME.text.r, THEME.text.g, THEME.text.b, caret_opacity},
		selection_color = THEME.surface,
		shift_pressed   = platform_is_pressed(platform, .LEFT_SHIFT),
	}
	start_div(
		Div {
			width = width_px,
			color = bg_color,
			border_color = border_color,
			border_width = THEME.border_width,
			border_radius = THEME.border_radius,
			padding = {8, 8, 4, 4},
			flags = {.AxisX, .WidthPx},
		},
		id = id,
	)
	if res.focused {
		custom_ui_element(markers_data, set_markers_size, add_markers_elements)
	}
	if !res.focused && len(str) == 0 {
		text(
			Text {
				str = placeholder,
				font_size = font_size,
				color = THEME.text_secondary,
				shadow = THEME.text_shadow,
				line_break = line_break,
				pointer_pass_through = true,
				align = align,
			},
			id = text_id,
		)
	} else {
		text(
			Text {
				str = str,
				font_size = font_size,
				color = THEME.text,
				shadow = THEME.text_shadow,
				line_break = line_break,
				pointer_pass_through = true,
				align = align,
			},
			id = text_id,
		)
	}

	end_div()

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

	add_markers_elements :: proc(
		data: ^MarkersData,
		pos: Vec2,
		size: Vec2,
		primitives: ^Primitives,
		pre_batches: ^[dynamic]PreBatch,
	) {

		text_ctx, ok := UI_MEMORY.text_ids_to_tmp_layouts[data.text_id] // nil if text is empty string!
		assert(ok)
		assert(text_ctx != nil)
		byte_count := len(text_ctx.byte_advances)

		// get the glyph we are currently on:
		cursor_pos := UI_MEMORY.cache.cursor_pos
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
				is_last :=
					byte_idx_plus_one(text_ctx.byte_advances[:], line.byte_end_idx) >= right_idx // not correct!!
				x_left: f32 = line.x_offset
				if is_first {
					x_left =
						advance_at_byte_minus_one(text_ctx.byte_advances[:], left_idx) +
						line.x_offset
				}
				x_right: f32 = ---
				if is_last {
					x_right =
						advance_at_byte_minus_one(text_ctx.byte_advances[:], right_idx) +
						line.x_offset
				} else {
					x_right =
						advance_at_byte_minus_one(text_ctx.byte_advances[:], line.byte_end_idx) +
						line.x_offset
				}
				rect_pos := Vec2{pos.x + x_left, pos.y + line.baseline_y - line.metrics.ascent}
				rect_size := Vec2{x_right - x_left, line.metrics.ascent - line.metrics.descent}
				add_rect(
					primitives,
					pre_batches,
					rect_pos,
					rect_size,
					data.selection_color,
					{},
					{},
					{2, 2, 2, 2},
					{},
				)
				if is_last {
					break
				}
			}
		}

		// draw the cursor:
		should_draw_caret := !(data.pressed && left_idx != right_idx) // dont draw while selecting area.
		if should_draw_caret {
			caret_byte_idx := g_state.selection[0]

			care_line: ^LineRun
			for &line in text_ctx.lines {
				care_line = &line
				if line.byte_end_idx >= caret_byte_idx {
					break
				}
			}
			caret_advance: f32 =
				advance_at_byte_minus_one(text_ctx.byte_advances[:], caret_byte_idx) +
				care_line.x_offset
			pipe_pos := Vec2 {
				pos.x + caret_advance - data.caret_width / 2,
				pos.y + care_line.baseline_y - care_line.metrics.ascent,
			}
			pipe_size := Vec2 {
				data.caret_width,
				care_line.metrics.ascent - care_line.metrics.descent,
			}
			add_rect(
				primitives,
				pre_batches,
				pipe_pos,
				pipe_size,
				data.caret_color,
				{},
				{},
				{2, 2, 2, 2},
				{},
			)
		}

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
