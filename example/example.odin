package example

import q "../quat"
import engine "../quat/engine"


main :: proc() {

	q.print("Hello")
	// engine.enable_max_fps()
	engine.init()
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
		size    = q.Vec2{1, 2} * 0.1,
		color   = {1, 1, 1, 1},
	}

	for engine.next_frame() {

		q.start_window("Hello World")
		q.text("Camera Height")
		q.slider(&camera.height, 0.1, 50.0)
		q.end_window()

		motion := engine.get_wasd()
		camera.focus_pos += motion * engine.get_delta_secs() * 5.0
		camera.rotation += engine.get_arrows().x * engine.get_delta_secs()
		camera.height *= (1.0 + engine.get_arrows().y * engine.get_delta_secs() * 3.0)
		engine.set_camera(camera)
		engine.draw_gizmos_coords()


		sprite.rotation = engine.get_osc(3, 0.5)
		sprite.pos = engine.get_hit_pos()
		engine.draw_sprite(sprite)


		// if engine.is_key_just_pressed(.SPACE) {
		// 	q.print("Space pressed")
		// 	engine.set_clear_color(q.random_color())
		// }

	}
}
