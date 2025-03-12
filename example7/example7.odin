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
	settings.debug_ui_gizmos = true
	engine.init(settings)
	defer engine.deinit()

	cam := engine.camera_controller_create()
	cam.settings.min_size = 0.1


	diffuse_img :=
		q.image_load("./assets/fire_flipbook.png") or_else panic("fire_flipbook.png not found")
	motion_img :=
		q.image_load("./assets/fire_flipbook_motion.png") or_else panic(
			"fire_flipbook_motion.png not found",
		)

	ta_size := IVec2{256, 256}
	ta := engine.motion_texture_allocator_create(ta_size, ta_size)

	diffuse_views := q.image_slice_into_tiles(diffuse_img, 2, 2)
	motion_views := q.image_slice_into_tiles(motion_img, 2, 2)

	frames, err := engine.motion_texture_allocator_allocate_frames(
		&ta,
		diffuse_views,
		motion_views,
	)
	assert(err == nil)

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
			t_offset = 0,
		},
		{
			pos = {1.5, 1},
			size = {1, 1},
			color = q.ColorRed,
			z = 0,
			rotation = 0,
			lifetime = 0,
			t_offset = 0,
		},
	}

	for engine.next_frame() {
		engine.camera_controller_update(&cam)
		engine.draw_gizmos_coords()
		engine.draw_motion_particles(particles, frames, ta.texture)
	}
}
