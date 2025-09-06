package example

import q "../quat"
import engine "../quat/engine"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

Vec2 :: [2]f32
Color :: [4]f32

main :: proc() {

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}


	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.debug_ui_gizmos = true
	engine.init(settings)
	defer {engine.deinit()}

	corn := engine.load_texture_tile("./assets/corn.png")
	sprite := engine.load_texture_tile("./assets/can.png")
	cam := engine.camera_controller_create()
	cam.settings.move_with_wasd = false
	cam.settings.min_size = 0.03
	player_pos := Vec2{0, 0}
	forest := [?]Vec2{{0, 0}, {2, 0}, {3, 0}, {5, 2}, {6, 3}}


	n_snake_pts := 20
	snake := snake_create({3, 3}, n_snake_pts)
	defer {
		snake_drop(snake)
	}

	text_to_edit: strings.Builder
	strings.write_string(&text_to_edit, "I made this UI from scratch in Odin!")
	defer strings.builder_destroy(&text_to_edit)

	background_color: Color = Color{0, 0.01, 0.02, 1.0}
	color2: Color = q.ColorSoftYellow
	color3: Color = q.ColorSoftLightPeach
	text_align: q.TextAlign

	tonemapping: q.TonemappingMode
	bloom_enabled := false
	bloom_blend_factor: f64 = 0.2
	snake_enabled := false


	drop_down_idx := 0
	drop_down_values := []string{"English", "German", "French"}

	allocated_str := strings.clone("")
	for engine.next_frame() {
		engine.camera_controller_update(&cam)
		allocated_str_edit := q.text_edit(&allocated_str, align = .Center, font_size = q.UI_THEME.font_size)
		if allocated_str_edit.just_edited {
			fmt.println("Edited allocated string:", allocated_str)
		}

		n_snake_pts_before := n_snake_pts
		engine.add_window(
			"Example window",
			{
				q.button("I do nothing").ui,
				q.enum_radio(&text_align, "Text Align"),
				q.enum_radio(&tonemapping, "Tonemapping"),
				q.color_picker(&background_color, "Background"),
				q.color_picker(&color2, "Color 2"),
				q.color_picker(&color3, "Color 3"),
				q.toggle(&bloom_enabled, "Bloom"),
				q.toggle(&snake_enabled, "Render Snake"),
				q.text_from_string("Bloom blend factor:"),
				q.slider(&bloom_blend_factor),
				q.slider_int(&n_snake_pts, 10, 30),
				q.text_edit(&text_to_edit, align = .Center, font_size = q.UI_THEME.font_size).ui,
				q.dropdown(drop_down_values, &drop_down_idx),
				allocated_str_edit.ui,
			},
		)

		if n_snake_pts_before != n_snake_pts {
			snake_drop(snake)
			snake = snake_create({5, 5}, n_snake_pts)
		}

		// engine.draw_annotation({2, -1}, "Hello from the engine!")
		// engine.add_world_ui({2, 1}, q.button("Hey", "btn1").ui)
		engine.add_world_ui(
			Vec2{0, 2},
			q.button("Click me!", "btn2").ui,
			scale = engine.get_osc(0.4, 0.4, 1.0),
			rotation = engine.get_osc(1.3),
		)

		engine.set_tonemapping_mode(tonemapping)
		engine.set_bloom_enabled(bloom_enabled)
		engine.set_bloom_blend_factor(bloom_blend_factor)
		// engine.display_value(engine.get_hit().is_on_screen_ui, engine.get_hit().is_on_world_ui)

		for y in -5 ..= 5 {
			engine.draw_gizmos_line(Vec2{-5, f32(y)}, Vec2{5, f32(y)}, color2)
		}
		for x in -5 ..= 5 {
			engine.draw_gizmos_line(Vec2{f32(x), -5}, Vec2{f32(x), 5}, color2)
		}

		engine.draw_sprite(
			q.Sprite{texture = sprite, pos = {-3, 5}, size = {1, 2.2}, rotation = 0, color = q.ColorWhite},
		)

		for pos, i in forest {
			engine.draw_sprite(
				q.Sprite{texture = corn, pos = pos, size = {1, 2}, rotation = engine.get_osc(2), color = {1, 1, 1, 1}},
			)
		}

		player_pos += q.get_wasd() * 20 * q.get_delta_secs()

		// poly := [?]q.Vec2{{-5, -5}, {-5, 0}, {0, 0}, {-5, -5}, {0, 0}, {0, -5}}
		// q.draw_color_mesh(poly[:])

		if snake_enabled {
			snake_update_body(&snake, engine.get_hit_pos())
			snake_draw(&snake)
		}

		engine.set_clear_color(background_color)
	}

}

Snake :: struct {
	triangles: [dynamic]q.Triangle,
	vertices:  [dynamic]q.ColorMesh2DVertex,
	points:    [dynamic]Vec2,
}
SNAKE_PT_DIST :: 0.16
SNAKE_LERP_SPEED :: 40
snake_create :: proc(head_pos: Vec2, n_pts: int = 50) -> Snake {
	snake: Snake
	next_pt := head_pos
	dir := Vec2{1, 0}
	for i in 0 ..< n_pts {
		append(&snake.points, next_pt)
		next_pt += dir * SNAKE_PT_DIST
	}
	// update_body(&snake, head_pos)

	return snake
}

snake_drop :: proc(snake: Snake) {
	delete(snake.points)
	delete(snake.triangles)
	delete(snake.vertices)
}

snake_update_body :: proc(snake: ^Snake, head_pos: Vec2) {
	prev_pos: Vec2
	snake.points[0] = head_pos
	s := q.get_delta_secs() * SNAKE_LERP_SPEED
	s = clamp(s, 0, 1)

	n_pts := len(snake.points)
	for i in 1 ..< n_pts {
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
	for i in 0 ..< n_pts {
		pt := snake.points[i]
		is_first := i == 0
		is_last := i == n_pts - 1
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

		f := f32(i) / f32(n_pts)
		body_width: f32 = 0.4 * (1.0 - f)
		append(&snake.vertices, q.ColorMesh2DVertex{pos = pt + dir_t * body_width, color = color})
		append(&snake.vertices, q.ColorMesh2DVertex{pos = pt - dir_t * body_width, color = color})
		base_idx := u32(i * 2)
		if i != n_pts - 1 {
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
		append(&snake.vertices, q.ColorMesh2DVertex{pos = pos, color = color})

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
	engine.draw_color_mesh_indexed(snake.vertices[:], snake.triangles[:])
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
