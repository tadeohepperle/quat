#+feature dynamic-literals
package example

import q "../quat"
import engine "../quat/engine"
import "core:fmt"
import "core:math"

print :: fmt.println

Vec2 :: [2]f32
IVec2 :: [2]int

main :: proc() {
	// E.enable_max_fps()
	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.debug_fps_in_title = false
	settings.bloom_enabled = false
	settings.debug_ui_gizmos = false
	engine.init(settings)
	defer engine.deinit()

	cam := engine.camera_controller_create()
	cam.settings.min_size = 0.1
	cam.settings.move_with_arrows = false

	// diffuse_img :=
	// 	q.image_load("./assets/fire_flipbook.png") or_else panic("fire_flipbook.png not found")
	// motion_img :=
	// 	q.image_load("./assets/fire_flipbook_motion.png") or_else panic(
	// 		"fire_flipbook_motion.png not found",
	// 	)

	// credit: https://www.klemenlozar.com/frame-blending-with-motion-vectors/
	flipbook_img :=
		q.image_load("./assets/smoke_flipbook.png") or_else panic("fire_flipbook.png not found")
	assert(flipbook_img.size == {1024, 512}) // diffuse and motion next to each other
	diffuse_img := q.image_view(flipbook_img, max = {512, 512})
	motion_img := q.image_view(flipbook_img, min = {512, 0}, max = {1024, 512})
	assert(diffuse_img.size == {512, 512})
	assert(motion_img.size == {512, 512})

	TA_SIZE := IVec2{512, 512}
	ta := engine.motion_texture_allocator_create(TA_SIZE, TA_SIZE)

	flipbook, err := engine.motion_texture_allocator_allocate_flipbook(
		&ta,
		diffuse_img,
		motion_img,
		8,
		8,
		64,
	)
	print(diffuse_img.size, motion_img.size)
	assert(err == nil, fmt.tprint(err))

	particles := []q.MotionParticleInstance {
		{
			pos = {0, 1},
			size = {1, 1},
			color = q.ColorLightBlue,
			z = 0,
			rotation = 0,
			lifetime = 0,
			t_offset = 0,
		},
		{
			pos = {-1.5, 1},
			size = {1, 1},
			color = q.ColorWhite,
			z = 0,
			rotation = 0,
			lifetime = 0,
			t_offset = 0.1,
		},
		{
			pos = {1.5, 1},
			size = {1, 1},
			color = q.ColorRed,
			z = 0,
			rotation = 0,
			lifetime = 0,
			t_offset = 3.0,
		},
	}

	for engine.next_frame() {
		if engine.is_key_pressed(.SPACE) {
			flipbook.time += engine.get_delta_secs() * 0.05
		}
		if engine.is_key_just_pressed_or_repeated(.LEFT) {
			flipbook.time -= 1.0 / f32(flipbook.n_tiles)
		}
		if engine.is_key_just_pressed_or_repeated(.RIGHT) {
			flipbook.time += 1.0 / f32(flipbook.n_tiles)
		}
		engine.add_window(
			"Settings",
			[]q.Ui {
				engine.slider_f32(&flipbook.time, slider_width = 600),
				engine.slider_f32(&engine.access_shader_globals_xxx().x),
			},
			window_width = 700,
		)
		flipbook.time = math.wrap(flipbook.time, 1.0)

		engine.camera_controller_update(&cam)
		engine.draw_gizmos_coords()
		engine.draw_motion_particles(particles, flipbook, ta.texture)
	}
}
