package engine

import q "../"
import "core:math/linalg"


DEFAULT_CAMERA_CONTROLLER_SETTINGS := Camera2DSettings {
	min_size          = 2.0,
	max_size          = 700.0,
	default_size      = 10.0,
	lerp_speed        = 40.0,
	zoom_sensitivity  = 0.24,
	move_speed        = 1.0, // is multiplied with current height, to have same speed on different scales
	move_with_wasd    = true,
	move_with_arrows  = true,
	scroll_when_on_ui = false,
	zoom_enabled      = true,
}

Camera2DSettings :: struct {
	min_size:          f32,
	max_size:          f32,
	default_size:      f32,
	lerp_speed:        f32,
	zoom_enabled:      bool,
	zoom_sensitivity:  f32,
	move_speed:        f32,
	move_with_wasd:    bool,
	move_with_arrows:  bool,
	scroll_when_on_ui: bool,
}

Camera2DController :: struct {
	settings:    Camera2DSettings,
	target:      q.Camera2D,
	current:     q.Camera2D,
	is_dragging: bool,
}

camera_controller_create :: proc(
	camera: q.Camera2D = q.DEFAULT_CAMERA,
	settings: Camera2DSettings = DEFAULT_CAMERA_CONTROLLER_SETTINGS,
) -> Camera2DController {
	return Camera2DController{settings = settings, target = camera, current = camera}
}

camera_controller_set_immediately :: proc(cam: ^Camera2DController) {
	cam.current = cam.target
}

camera_controller_update :: proc(cam: ^Camera2DController) {
	screen_size := q.get_screen_size()
	pan_btn := get_mouse_btn(.Middle)
	is_on_ui := get_hit().is_on_screen_ui
	cursor_pos := q.get_cursor_pos()
	cursor_delta := q.get_cursor_delta()

	if .JustPressed in pan_btn && !is_on_ui {
		cam.is_dragging = true
	}
	if cam.is_dragging {
		if .Pressed not_in pan_btn {
			cam.is_dragging = false
		} else if cursor_delta != {0, 0} {

			cursor_pos_before := cursor_pos - cursor_delta


			point_before := q.camera_2d_screen_to_world_pos(cam.current, cursor_pos_before, screen_size)
			point_after := q.camera_2d_screen_to_world_pos(cam.current, cursor_pos, screen_size)
			diff := point_before - point_after
			cam.target.focus_pos += diff
		}
	}

	scroll := get_scroll()
	if !cam.settings.scroll_when_on_ui && is_on_ui {
		scroll = 0.0
	}
	if abs(scroll) > 0 && !q.is_shift_pressed() && !q.is_ctrl_pressed() && cam.settings.zoom_enabled {
		// calculate new size
		size_before := cam.current.height
		size_after := size_before - scroll * size_before * cam.settings.zoom_sensitivity
		size_after = clamp(size_after, cam.settings.min_size, cam.settings.max_size)
		cam.target.height = size_after

		// calculate plane point shift
		point_before := q.camera_2d_screen_to_world_pos(cam.current, cursor_pos, screen_size)
		point_after := q.camera_2d_screen_to_world_pos(cam.target, cursor_pos, screen_size)
		diff := point_before - point_after
		cam.target.focus_pos += diff
	}


	dt := q.get_delta_secs()

	move: Vec2
	if cam.settings.move_with_wasd {
		move += q.get_wasd()
	}
	if cam.settings.move_with_arrows {
		move += q.get_arrows()
	}
	if cam.settings.move_speed != 0 && move != {0, 0} {
		cam.target.focus_pos += move * cam.settings.move_speed * cam.current.height * dt
	}


	s := dt * cam.settings.lerp_speed
	cam.current.focus_pos = q.lerp(cam.current.focus_pos, cam.target.focus_pos, s)
	cam.current.height = q.lerp(cam.current.height, cam.target.height, s)

	set_camera(cam.current)
}
