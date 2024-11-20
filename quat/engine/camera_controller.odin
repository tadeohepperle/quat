package engine

import q "../"
import "core:math/linalg"


DEFAULT_CAMERA_CONTROLLER_SETTINGS := CameraSettings {
	min_size           = 2.0,
	max_size           = 700.0,
	default_size       = 10.0,
	lerp_speed         = 40.0,
	zoom_sensitivity   = 0.24,
	scroll_sensitivity = 0.2,
}

CameraSettings :: struct {
	min_size:           f32,
	max_size:           f32,
	default_size:       f32,
	lerp_speed:         f32,
	zoom_sensitivity:   f32,
	scroll_sensitivity: f32,
}

CameraController :: struct {
	settings: CameraSettings,
	target:   q.Camera,
	current:  q.Camera,
}

camera_controller_create :: proc(
	camera: q.Camera = q.DEFAULT_CAMERA,
	settings: CameraSettings = DEFAULT_CAMERA_CONTROLLER_SETTINGS,
) -> CameraController {
	return CameraController{settings = settings, target = camera, current = camera}
}

camera_controller_set_immediately :: proc(cam: ^CameraController) {
	cam.current = cam.target
}

camera_controller_update :: proc(cam: ^CameraController) {
	screen_size := get_screen_size_f32()
	pan_button_pressed := .Pressed in get_mouse_btn(.Middle)
	cursor_pos := get_cursor_pos()
	cursor_delta := get_cursor_delta()


	if pan_button_pressed && cursor_delta != {0, 0} {
		cursor_pos_before := cursor_pos - cursor_delta


		point_before := q.camera_cursor_hit_pos(cam.current, cursor_pos_before, screen_size)
		point_after := q.camera_cursor_hit_pos(cam.current, cursor_pos, screen_size)
		diff := point_before - point_after
		cam.target.focus_pos += diff
	}

	scroll := get_scroll()
	if abs(scroll) > 0 && !is_shift_pressed() && !is_ctrl_pressed() {
		// calculate new size
		size_before := cam.current.height
		size_after := size_before - scroll * size_before * cam.settings.zoom_sensitivity
		size_after = clamp(size_after, cam.settings.min_size, cam.settings.max_size)
		cam.target.height = size_after

		// calculate plane point shift
		point_before := q.camera_cursor_hit_pos(cam.current, cursor_pos, screen_size)
		point_after := q.camera_cursor_hit_pos(cam.target, cursor_pos, screen_size)
		diff := point_before - point_after
		cam.target.focus_pos += diff
	}


	dt := get_delta_secs()

	move := get_wasd()
	if move != {0, 0} {
		cam.target.focus_pos += move * 20 * dt
	}

	s := dt * cam.settings.lerp_speed
	cam.current.focus_pos = q.lerp(cam.current.focus_pos, cam.target.focus_pos, s)
	cam.current.height = q.lerp(cam.current.height, cam.target.height, s)

	set_camera(cam.current)
}
