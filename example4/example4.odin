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

	for engine.next_frame() {
		add_ui(
			scroll_table(
				ScrollTable {
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
					x_n_steps = 16,
					y_n_steps = 20,
				},
			),
		)
	}
}
TESTING_TEXTURE: q.TextureHandle
test_div :: proc(size: Vec2 = {100, 100}, color: Color = q.ColorWhite) -> Ui {
	color := color
	color[3] = 0.01

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


ScrollTable :: struct {
	field_size:     Vec2,
	corner_size:    Vec2,
	squeeze_into:   Vec2,
	corner_ui:      Ui,
	top_header_ui:  Ui,
	side_header_ui: Ui,
	field_ui:       Ui,
	// how many rows/cols are there on the x and y axis to scroll to/from
	x_n_steps:      int,
	y_n_steps:      int,
	// position where the two scrolls are currently
	x_cur_step:     int,
	y_cur_step:     int,
}
scroll_table :: proc(using props: ScrollTable) -> Ui {
	SCROLL_BAR_WIDTH: f32 : 8.0


	total_size_uncut := SCROLL_BAR_WIDTH + corner_size + field_size

	total_size := Vec2 {
		min(squeeze_into.x, total_size_uncut.x),
		min(squeeze_into.y, total_size_uncut.y),
	}

	container := div(
		Div {
			width = total_size.x,
			height = total_size.y,
			flags = {.WidthPx, .HeightPx},
			color = q.ColorDarkGrey,
		},
	)

	visible_field_size := total_size - props.corner_size - SCROLL_BAR_WIDTH
	assert(visible_field_size.x > props.corner_size.x + SCROLL_BAR_WIDTH)
	assert(visible_field_size.y > props.corner_size.y + SCROLL_BAR_WIDTH)
	top_slider := child_div(
		container,
		Div {
			offset = Vec2{SCROLL_BAR_WIDTH + corner_size.x, 0},
			width = visible_field_size.x,
			height = SCROLL_BAR_WIDTH,
			flags = {.WidthPx, .HeightPx, .Absolute},
			color = q.ColorSoftOrange,
		},
	)
	left_slider := child_div(
		container,
		Div {
			offset = Vec2{0, SCROLL_BAR_WIDTH + corner_size.y},
			width = SCROLL_BAR_WIDTH,
			height = visible_field_size.y,
			flags = {.WidthPx, .HeightPx, .Absolute},
			color = q.ColorSoftOrange,
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
	if top_header_ui != nil {
		child(top_header_container, top_header_ui)
	}
	side_header_container := child_div(
		container,
		q.Div {
			width = corner_size.x,
			height = visible_field_size.y,
			offset = Vec2{SCROLL_BAR_WIDTH, SCROLL_BAR_WIDTH + corner_size.y},
			flags = {.Absolute, .WidthPx, .HeightPx, .ClipContent},
		},
	)
	if side_header_ui != nil {
		child(side_header_container, side_header_ui)
	}
	field_container := child_div(
		container,
		q.Div {
			width = visible_field_size.x,
			height = visible_field_size.y,
			offset = corner_size + SCROLL_BAR_WIDTH,
			flags = {.Absolute, .WidthPx, .HeightPx, .ClipContent},
		},
	)
	if field_ui != nil {
		child(field_container, field_ui)
	}
	return container
}
