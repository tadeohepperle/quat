package example

import q "../quat"
import engine "../quat/engine"

Vec2 :: q.Vec2

main :: proc() {
	// engine.enable_max_fps()
	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.bloom_enabled = false
	settings.debug_ui_gizmos = true
	engine.init(settings)
	defer engine.deinit()

	can_texture := engine.load_texture_tile("./assets/can.png")
	camera := q.Camera {
		focus_pos = {0, 0},
		rotation  = 0,
		height    = 10,
	}
	sprite := q.Sprite {
		texture = can_texture,
		pos     = {1, 1},
		size    = q.Vec2{1, 2},
		color   = {1, 1, 1, 1},
		z       = -0.4,
	}
	terrain_textures := q.load_texture_array(
		{"./assets/t_0.png", "./assets/t_1.png", "./assets/t_2.png", "./assets/t_3.png"},
	)
	engine.set_tritex_textures(terrain_textures)
	terrain_mesh := q.tritex_mesh_create(
		{
			q.TritexVertex{pos = {0, 0}, indices = {0, 1, 2}, weights = {1, 0, 0}},
			q.TritexVertex{pos = {5, 7}, indices = {0, 1, 2}, weights = {0, 1, 0}},
			q.TritexVertex{pos = {10, 0}, indices = {0, 1, 2}, weights = {0, 0, 1}},
		},
	)
	draggables := draggable_sprites_create()

	bg_color := q.Color{0, 2, 10, 255}

	for engine.next_frame() {
		div := q.div(q.Div{padding = {20, 20, 20, 20}, color = {0, 0, 0.1, 1.0}})
		q.child(div, q.color_picker(&bg_color))
		engine.add_ui(div)

		// engine.add_ui(
		// 	engine.with_children(
		// 		engine.div(q.COVER_DIV),
		// 		{
		// 			engine.div(q.RED_BOX_DIV),
		// 			engine.button("Hello").ui,
		// 			engine.button("What").ui,
		// 			engine.button("Is").ui,
		// 			engine.button("This").ui,
		// 			engine.color_picker(&bg_color),
		// 			engine.colored_triangle(),
		// 		},
		// 	),
		// )
		// engine.set_clear_color(bg_color)


		// q.start_window("Hello World")
		// q.text("Camera Height")
		// q.slider(&camera.height, 0.1, 50.0)
		// q.end_window()

		motion := q.get_wasd()
		camera.focus_pos += motion * q.get_delta_secs() * 5.0
		camera.rotation += q.get_arrows().x * q.get_delta_secs()
		camera.height *= (1.0 - q.get_arrows().y * q.get_delta_secs() * 3.0)
		engine.set_camera(camera)
		engine.draw_gizmos_coords()
		engine.draw_tritex_mesh(terrain_mesh)


		// sprite.rotation = engine.get_osc(3, 0.5)
		sprite.pos = engine.get_hit_pos()
		engine.draw_sprite(sprite)

		draggable_sprites_update(&draggables)

		// if engine.is_key_just_pressed(.SPACE) {
		// 	q.print("Space pressed")
		// 	engine.set_clear_color(q.random_color())
		// }

	}
}

DraggableSprites :: struct {
	sprites:      [dynamic]q.Sprite,
	hoveredx:     int,
	dragging_idx: int,
	drag_offset:  Vec2,
}
draggable_sprites_create :: proc() -> (res: DraggableSprites) {
	res.dragging_idx = -1
	res.hoveredx = -1
	ball := engine.load_texture_as_sprite("./assets/ball_d_16.png")
	wall := engine.load_texture_as_sprite("./assets/wall_d_16.png")
	tower := engine.load_texture_as_sprite("./assets/tower_d_16.png")
	wall.color = q.ColorDarkTeal
	// tower.color = q.Color_Dark_Goldenrod
	ball.color = q.ColorSoftBlue
	append(&res.sprites, ball)

	ball.pos = {3, 2}
	ball.color = q.ColorLightGrey
	append(&res.sprites, ball)
	append(&res.sprites, wall)
	append(&res.sprites, tower)
	return res
}

draggable_sprites_update :: proc(using draggables: ^DraggableSprites) {
	// move ball to front or back:

	ball := &sprites[0]
	ball.z += q.get_rf() * q.get_delta_secs() * 0.1
	ball.z = clamp(ball.z, -2, 2)
	// q.print(ball.z)

	// drawing:
	for &s, i in sprites {
		is_hovered := q.from_collider_metadata(engine.get_hit().hit_collider, ^q.Sprite) == &s
		if is_hovered {
			hoveredx = i
		}
		if is_hovered && dragging_idx == -1 && q.is_left_pressed() {
			// start drag:
			dragging_idx = i
			drag_offset = s.pos - engine.get_hit_pos()
		}
		is_dragged := i == dragging_idx
		if is_dragged {
			// when dragging:
			s.pos = engine.get_hit_pos() + drag_offset
			if q.is_left_just_released() {
				// end drag:
				dragging_idx = -1
			}
		}
		// s.z = 10 if is_hovered || is_dragged else 0
		// s.color = {2, 2, 2, 1} if is_hovered else {1, 1, 1, 1}
		collider_meta := q.to_collider_metadata(&s)
		engine.add_rect_collider(q.rect(s.pos, s.size), collider_meta, int(s.z))
		engine.draw_sprite(s)
		// if i != draggables.dragging_idx {

		// } else {
		// 	engine.draw_sprite(s)
		// }
	}
}
