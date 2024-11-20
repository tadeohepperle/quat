package example

import q "../quat"
import engine "../quat/engine"

Vec2 :: q.Vec2

main :: proc() {

	q.print("Hello")
	// engine.enable_max_fps()
	engine.init()
	defer engine.deinit()
	engine.set_bloom_enabled(false)

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
	draggables := draggable_sprites_create()

	for engine.next_frame() {
		q.start_window("Hello World")
		q.text("Camera Height")
		q.slider(&camera.height, 0.1, 50.0)
		q.end_window()

		motion := engine.get_wasd()
		camera.focus_pos += motion * engine.get_delta_secs() * 5.0
		camera.rotation += engine.get_arrows().x * engine.get_delta_secs()
		camera.height *= (1.0 - engine.get_arrows().y * engine.get_delta_secs() * 3.0)
		engine.set_camera(camera)
		engine.draw_gizmos_coords()


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
	sprites:      [dynamic]q.DepthSprite,
	hovered_idx:  int,
	dragging_idx: int,
	drag_offset:  Vec2,
}
draggable_sprites_create :: proc() -> (res: DraggableSprites) {
	res.dragging_idx = -1
	res.hovered_idx = -1
	ball := engine.load_depth_sprite("./assets/ball_d_16.png", "./assets/t_2.png")
	wall := engine.load_depth_sprite("./assets/wall_d_16.png")
	tower := engine.load_depth_sprite("./assets/tower_d_16.png")
	wall.color = q.Color_Dark_Goldenrod
	// tower.color = q.Color_Dark_Goldenrod
	ball.color = q.Color_Aquamarine
	append(&res.sprites, ball)

	ball.pos = {3, 2}
	ball.color = q.Color_Blue_Violet
	append(&res.sprites, ball)
	append(&res.sprites, wall)
	append(&res.sprites, tower)
	return res
}

draggable_sprites_update :: proc(using draggables: ^DraggableSprites) {
	// move ball to front or back:

	ball := &sprites[0]
	ball.z += engine.get_rf() * engine.get_delta_secs() * 0.1
	ball.z = clamp(ball.z, -2, 2)
	// q.print(ball.z)

	// drawing:
	for &s, i in sprites {
		is_hovered := q.from_collider_metadata(engine.get_hit().hit_collider, ^q.DepthSprite) == &s
		if is_hovered {
			hovered_idx = i
		}
		if is_hovered && dragging_idx == -1 && engine.is_left_pressed() {
			// start drag:
			dragging_idx = i
			drag_offset = s.pos - engine.get_hit_pos()
		}
		is_dragged := i == dragging_idx
		if is_dragged {
			// when dragging:
			s.pos = engine.get_hit_pos() + drag_offset
			if engine.is_left_just_released() {
				// end drag:
				dragging_idx = -1
			}
		}
		// s.z = 10 if is_hovered || is_dragged else 0
		// s.color = {2, 2, 2, 1} if is_hovered else {1, 1, 1, 1}
		collider_meta := q.to_collider_metadata(&s)
		engine.add_rect_collider(q.rect(s.pos, s.size), collider_meta, int(s.z))
		engine.draw_depth_sprite(s)
		// if i != draggables.dragging_idx {

		// } else {
		// 	engine.draw_sprite(s)
		// }
	}
}
