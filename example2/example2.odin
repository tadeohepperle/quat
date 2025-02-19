package example

import q "../quat"
import E "../quat/engine"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import "core:time"

Vec2 :: [2]f32
Color :: [4]f32

recorded_dt: [dynamic]f32

main :: proc() {
	settings := E.DEFAULT_ENGINE_SETTINGS
	settings.debug_ui_gizmos = true
	E.init(settings)
	defer {E.deinit()}
	E.set_bloom_enabled(false)

	corn := E.load_texture_tile("./assets/corn.png")
	sprite := E.load_texture_tile("./assets/can.png")
	cam := E.camera_controller_create()
	cam.settings.move_with_wasd = false
	cam.settings.min_size = 0.03
	player_pos := Vec2{0, 0}
	forest := [?]Vec2{{0, 0}, {2, 0}, {3, 0}, {5, 2}, {6, 3}}

	snake := snake_create({3, 3})

	text_to_edit: strings.Builder
	strings.write_string(&text_to_edit, "I made this UI from scratch in Odin!")

	background_color: Color = Color{0, 0.01, 0.02, 1.0}
	color2: Color = q.ColorSoftYellow
	color3: Color = q.ColorSoftLightPeach
	text_align: q.TextAlign

	tonemapping: q.TonemappingMode
	bloom_enabled := true
	bloom_blend_factor: f64 = 0.2
	snake_enabled := false
	for E.next_frame() {
		E.camera_controller_update(&cam)
		append(&recorded_dt, E.get_delta_secs() * 1000.0)

		E.add_window(
			"Example window",
			{
				E.enum_radio(&text_align, "Text Align"),
				E.enum_radio(&tonemapping, "Tonemapping"),
				E.color_picker(&background_color, "Background"),
				E.color_picker(&color2, "Color 2"),
				E.color_picker(&color3, "Color 3"),
				E.toggle(&bloom_enabled, "Bloom"),
				E.toggle(&snake_enabled, "Render Snake"),
				E.text("Bloom blend factor:"),
				E.slider(&bloom_blend_factor),
				E.text_edit(&text_to_edit, align = .Center, font_size = E.THEME.font_size),
			},
		)
		E.draw_annotation({2, -1}, "Hello from the engine!")
		E.add_world_ui(E.button("Click me!", "abcde").ui, {2, 1})

		E.set_tonemapping_mode(tonemapping)
		E.set_bloom_enabled(bloom_enabled)
		E.set_bloom_blend_factor(bloom_blend_factor)

		for y in -5 ..= 5 {
			E.draw_gizmos_line(Vec2{-5, f32(y)}, Vec2{5, f32(y)}, color2)
		}
		for x in -5 ..= 5 {
			E.draw_gizmos_line(Vec2{f32(x), -5}, Vec2{f32(x), 5}, color2)
		}

		E.draw_sprite(
			q.Sprite {
				texture = sprite,
				pos = {-3, 5},
				size = {1, 2.2},
				rotation = 0,
				color = q.ColorWhite,
			},
		)

		for pos, i in forest {
			E.draw_sprite(
				q.Sprite {
					texture = corn,
					pos = pos,
					size = {1, 2},
					rotation = E.get_osc(2),
					color = {1, 1, 1, 1},
				},
			)
		}

		player_pos += E.get_wasd() * 20 * E.get_delta_secs()

		// poly := [?]q.Vec2{{-5, -5}, {-5, 0}, {0, 0}, {-5, -5}, {0, 0}, {0, -5}}
		// q.draw_color_mesh(poly[:])

		if snake_enabled {
			snake_update_body(&snake, E.get_hit_pos())
			snake_draw(&snake)
		}

		E.set_clear_color(background_color)
	}

}

Snake :: struct {
	triangles: [dynamic]q.Triangle,
	vertices:  [dynamic]q.ColorMeshVertex,
	points:    [dynamic]Vec2,
}
SNAKE_PTS :: 50
SNAKE_PT_DIST :: 0.16
SNAKE_LERP_SPEED :: 40
snake_create :: proc(head_pos: Vec2) -> Snake {
	snake: Snake
	next_pt := head_pos
	dir := Vec2{1, 0}
	for i in 0 ..< SNAKE_PTS {
		append(&snake.points, next_pt)
		next_pt += dir * SNAKE_PT_DIST
	}
	// update_body(&snake, head_pos)

	return snake
}

snake_update_body :: proc(snake: ^Snake, head_pos: Vec2) {
	prev_pos: Vec2
	snake.points[0] = head_pos
	s := E.get_delta_secs() * SNAKE_LERP_SPEED
	s = clamp(s, 0, 1)
	for i in 1 ..< SNAKE_PTS {
		follow_pos := snake.points[i - 1]
		current_pos := snake.points[i]
		desired_pos := follow_pos + linalg.normalize(current_pos - follow_pos) * SNAKE_PT_DIST
		snake.points[i] = q.lerp(current_pos, desired_pos, s)
	}

	color := q.Color{0, 0, 2.0, 1.0} + 1
	if color.a > 1 {
		color.a = 1 // learned: when alpha > 1 in two regions overlapping -> alpha blending makes alpha be 0 insteaq. (happ)
	}
	clear(&snake.vertices)
	clear(&snake.triangles)
	for i in 0 ..< SNAKE_PTS {
		pt := snake.points[i]
		is_first := i == 0
		is_last := i == SNAKE_PTS - 1
		dir: Vec2
		if is_first {
			dir = snake.points[1] - pt
		} else if is_last {
			dir = pt - snake.points[i - 1]
		} else {
			dir = snake.points[i + 1] - snake.points[i - 1]
		}

		dir = linalg.normalize(dir)
		dir_t := Vec2{-dir.y, dir.x}

		f := f32(i) / f32(SNAKE_PTS)
		body_width: f32 = 0.4 * (1.0 - f)
		append(&snake.vertices, q.ColorMeshVertex{pos = pt + dir_t * body_width, color = color})
		append(&snake.vertices, q.ColorMeshVertex{pos = pt - dir_t * body_width, color = color})
		base_idx := u32(i * 2)
		if i != SNAKE_PTS - 1 {
			append(&snake.triangles, [3]u32{base_idx, base_idx + 1, base_idx + 2})
			append(&snake.triangles, [3]u32{base_idx + 2, base_idx + 3, base_idx + 1})
		}
	}
	// add a circle for the head:
	circle_left := snake.vertices[0].pos
	circle_right := snake.vertices[1].pos
	dir := (circle_right - circle_left) / 2
	mapping_matrix: matrix[2, 2]f32 = {dir.x, dir.y, dir.y, -dir.x} // (1,0) mapped to dir.x, dir.y.   (0,1) mapped to dir.y, -dir.x
	head_pt := snake.points[0]
	CIRCLE_N :: 10
	for i in 1 ..< CIRCLE_N {
		angle := math.PI * f32(i) / f32(CIRCLE_N)
		unit_circle_pt := Vec2{math.cos(angle), math.sin(angle)}
		pos := head_pt + mapping_matrix * unit_circle_pt
		append(&snake.vertices, q.ColorMeshVertex{pos = pos, color = color})

		v_idx_next := u32(len(snake.vertices))
		v_idx := v_idx_next - 1
		if i == CIRCLE_N - 1 {
			v_idx_next = 0 // right side of circle (second pt of mesh)
		}
		append(&snake.triangles, [3]u32{1, v_idx, v_idx_next})
	}
}

snake_draw :: proc(snake: ^Snake) {
	// for p in snake.vertices {
	// 	q.draw_sprite(
	// 		q.Sprite {
	// 			texture = white,
	// 			pos = p.pos,
	// 			size = {0.1, 0.1},
	// 			rotation = 0,
	// 			color = {1, 0, 0, 1},
	// 		},
	// 	)
	// }
	// q.draw_color_mesh_indexed(snake.vertices[:], snake.indices[:])


	// new_vertices := make([dynamic]q.ColorMeshVertex)
	// defer {delete(new_vertices)}
	// for i in snake.indices {
	// 	append(&new_vertices, snake.vertices[i])
	// }
	// q.draw_color_mesh(new_vertices[:])
	E.draw_color_mesh_indexed(snake.vertices[:], snake.triangles[:])
}


// save_frame_times_to_csv :: proc(times: [][q.FrameSection]q.Duration, filename := "times.csv") {
// 	buf: ^strings.Builder = new(strings.Builder)
// 	defer {
// 		strings.builder_destroy(buf)
// 		free(buf)
// 	}
// 	for t in q.FrameSection {
// 		fmt.sbprintf(buf, "%s,", t)
// 	}
// 	fmt.sbprint(buf, "\n")
// 	for sample, i in times {
// 		for t, t_i in q.FrameSection {
// 			ns := f64(sample[t])
// 			ms := ns / f64(time.Millisecond)
// 			fmt.sbprintf(buf, "%.3f,", ms)
// 		}
// 		if i != len(times) - 1 {
// 			fmt.sbprint(buf, "\n")
// 		}
// 	}
// 	os.write_entire_file(filename, buf.buf[:])
// }
