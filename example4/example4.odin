package example

import q "../quat"
import engine "../quat/engine"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

print :: fmt.println

div :: engine.div
Ui :: q.Ui
UiText :: engine.UiText
UiDiv :: engine.UiDiv
Div :: q.Div
child :: engine.child
child_div :: engine.child_div
child_text :: engine.child_text
text :: engine.text
Text :: q.Text
add_ui :: engine.add_ui

Vec2 :: [2]f32
Color :: [4]f32
Vertex :: q.SkinnedVertex
Affine2 :: q.Affine2
Mat2 :: matrix[2, 2]f32


// a table where the 4 regions (corner, left header, top header, field) can be scrolled to see different parts of the field
main :: proc() {
	engine.init()
	defer {engine.deinit()}
	engine.set_bloom_enabled(false)
	engine.set_tonemapping_mode(.Disabled)
	engine.set_clear_color({0.02, 0.02, 0.04, 1.0})
	TESTING_TEXTURE = engine.load_texture("./assets/testing_texture_bw.png")

	FIELD_SIZE :: Vec2{1200, 1000}
	CORNER_SIZE :: Vec2{80, 40}
	SQUEEZE_SIZE :: Vec2{700, 500}

	state: ScrollTableState
	top_slider_id := q.ui_id("top")
	left_slider_id := q.ui_id("left")

	for engine.next_frame() {
		add_ui(
			scroll_table(
				ScrollTableProps {
					field_size = FIELD_SIZE,
					corner_size = CORNER_SIZE,
					squeeze_into = SQUEEZE_SIZE,
					corner_ui = test_div(CORNER_SIZE, q.ColorOrange),
					top_header_ui = test_div(Vec2{FIELD_SIZE.x, CORNER_SIZE.y}, q.ColorLightBlue),
					side_header_ui = test_div(
						Vec2{CORNER_SIZE.x, FIELD_SIZE.y},
						q.ColorSoftPurpleBlue,
					),
					field_ui = test_div(FIELD_SIZE),
				},
				&state,
				top_slider_id,
				left_slider_id,
			),
		)

		// we have limited support for div rotations by setting a RotateByGap flag and 
		// using the gap value for rotation.
		// children are not rotated! Only good for wiggly icons or something...
		d := div(
			Div {
				width = 100,
				height = 80,
				texture = {TESTING_TEXTURE, {{0, 0}, {1, 0.8}}},
				color = q.ColorSoftOrange,
				absolute_unit_pos = {0.5, 0.5},
				gap = engine.get_osc(),
				flags = {
					.WidthPx,
					.HeightPx,
					.Absolute,
					.RotateByGap,
					.MainAlignCenter,
					.CrossAlignCenter,
				},
			},
		)
		child_text(d, Text{font_size = 24, str = "Hello", color = {1, 1, 1, 1}})
		add_ui(d)
	}
}
TESTING_TEXTURE: q.TextureHandle
test_div :: proc(size: Vec2 = {100, 100}, color: Color = q.ColorWhite) -> Ui {
	return div(
		Div {
			width = size.x,
			height = size.y,
			color = color,
			flags = {.WidthPx, .HeightPx},
			texture = q.TextureTile{handle = TESTING_TEXTURE, uv = q.Aabb{{0, 0}, size / 128.0}},
		},
	)
}

ScrollTableProps :: struct {
	field_size:     Vec2,
	corner_size:    Vec2,
	squeeze_into:   Vec2,
	corner_ui:      Ui,
	top_header_ui:  Ui,
	side_header_ui: Ui,
	field_ui:       Ui,
}
ScrollTableState :: struct {
	top_slider_f:  f32,
	left_slider_f: f32,
}

scroll_table :: proc(
	using props: ScrollTableProps,
	state: ^ScrollTableState,
	top_slider_id: q.UiId,
	left_slider_id: q.UiId,
) -> Ui {
	SCROLL_BAR_WIDTH: f32 : 16.0
	KNOB_BORDER_RADIUS :: q.BorderRadius {
		SCROLL_BAR_WIDTH / 2,
		SCROLL_BAR_WIDTH / 2,
		SCROLL_BAR_WIDTH / 2,
		SCROLL_BAR_WIDTH / 2,
	}

	total_size_uncut := SCROLL_BAR_WIDTH + corner_size + field_size
	total_size := Vec2 {
		min(squeeze_into.x, total_size_uncut.x),
		min(squeeze_into.y, total_size_uncut.y),
	}
	visible_field_size := total_size - props.corner_size - SCROLL_BAR_WIDTH
	assert(visible_field_size.x > props.corner_size.x + SCROLL_BAR_WIDTH)
	assert(visible_field_size.y > props.corner_size.y + SCROLL_BAR_WIDTH)
	top_slider_knob_w := visible_field_size.x * visible_field_size.x / field_size.x
	left_slider_knob_h := visible_field_size.y * visible_field_size.y / field_size.y

	top_slider_interaction := q.ui_interaction(top_slider_id)
	left_slider_interaction := q.ui_interaction(left_slider_id)
	cursor_pos, start_drag_cursor_pos := q.ui_cursor_pos()
	top_slider_c_pos, top_slider_c_size, _ := q.ui_get_cached_no_user_data(top_slider_id)
	left_slider_c_pos, left_slider_c_size, _ := q.ui_get_cached_no_user_data(left_slider_id)

	if top_slider_interaction.pressed {
		state.top_slider_f = math.remap_clamped(
			cursor_pos.x,
			top_slider_c_pos.x + top_slider_knob_w / 2,
			top_slider_c_pos.x + top_slider_c_size.x - top_slider_knob_w / 2,
			0,
			1,
		)
	}
	if left_slider_interaction.pressed {
		state.left_slider_f = math.remap_clamped(
			cursor_pos.y,
			left_slider_c_pos.y + left_slider_knob_h / 2,
			left_slider_c_pos.y + left_slider_c_size.y - left_slider_knob_h / 2,
			0,
			1,
		)
	}

	// calculate by how many pixels the cropped content should be offsetted:
	y_offset: f32 = state.left_slider_f * (field_size.y - visible_field_size.y)
	x_offset: f32 = state.top_slider_f * (field_size.x - visible_field_size.x)

	container := div(
		Div {
			width = total_size.x,
			height = total_size.y,
			flags = {.WidthPx, .HeightPx},
			color = q.ColorDarkGrey,
		},
	)
	top_slider := child_div(
		container,
		Div {
			offset = Vec2{SCROLL_BAR_WIDTH + corner_size.x, 0},
			width = visible_field_size.x,
			height = SCROLL_BAR_WIDTH,
			flags = {.WidthPx, .HeightPx, .Absolute},
			color = q.ColorBlack,
		},
		top_slider_id,
	)
	top_slider_knob := child_div(
		top_slider,
		Div {
			width = top_slider_knob_w,
			height = SCROLL_BAR_WIDTH,
			absolute_unit_pos = {state.top_slider_f, 0},
			flags = {.WidthPx, .HeightPx, .Absolute},
			color = q.ColorMiddleGrey,
			border_radius = KNOB_BORDER_RADIUS,
		},
	)

	left_slider := child_div(
		container,
		Div {
			offset = Vec2{0, SCROLL_BAR_WIDTH + corner_size.y},
			width = SCROLL_BAR_WIDTH,
			height = visible_field_size.y,
			flags = {.WidthPx, .HeightPx, .Absolute},
			color = q.ColorBlack,
		},
		left_slider_id,
	)
	left_slider_knob := child_div(
		left_slider,
		Div {
			width = SCROLL_BAR_WIDTH,
			height = left_slider_knob_h,
			absolute_unit_pos = {0, state.left_slider_f},
			flags = {.WidthPx, .HeightPx, .Absolute},
			color = q.ColorMiddleGrey,
			border_radius = KNOB_BORDER_RADIUS,
		},
	)
	corner_container := child_div(
		container,
		q.Div {
			width = corner_size.x,
			height = corner_size.y,
			offset = Vec2{SCROLL_BAR_WIDTH, SCROLL_BAR_WIDTH},
			flags = {.Absolute, .WidthPx, .HeightPx},
		},
	)
	if corner_ui != nil {
		child(corner_container, corner_ui)
	}
	top_header_container := child_div(
		container,
		q.Div {
			width = visible_field_size.x,
			height = corner_size.y,
			offset = Vec2{SCROLL_BAR_WIDTH + corner_size.x, SCROLL_BAR_WIDTH},
			flags = {.Absolute, .WidthPx, .HeightPx, .ClipContent},
		},
	)
	_add_offsetted_child({-x_offset, 0}, top_header_container, top_header_ui)
	side_header_container := child_div(
		container,
		q.Div {
			width = corner_size.x,
			height = visible_field_size.y,
			offset = Vec2{SCROLL_BAR_WIDTH, SCROLL_BAR_WIDTH + corner_size.y},
			flags = {.Absolute, .WidthPx, .HeightPx, .ClipContent},
		},
	)
	_add_offsetted_child({0, -y_offset}, side_header_container, side_header_ui)
	field_container := child_div(
		container,
		q.Div {
			width = visible_field_size.x,
			height = visible_field_size.y,
			offset = corner_size + SCROLL_BAR_WIDTH,
			flags = {.Absolute, .WidthPx, .HeightPx, .ClipContent},
		},
	)
	_add_offsetted_child({-x_offset, -y_offset}, field_container, field_ui)
	return container

	_add_offsetted_child :: proc(offset_px: Vec2, parent: ^q.DivElement, child: Ui) {
		if child == nil do return
		assert(parent != nil)
		wrapper := child_div(parent, q.Div{offset = offset_px, flags = {.Absolute}})
		q.ui_add_child(wrapper, child)
	}

}
