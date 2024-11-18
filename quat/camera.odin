package quat

import "core:math"
import "core:math/linalg"

// an orthographic 2d Camera
Camera :: struct {
	focus_pos: Vec2,
	height:    f32,
	rotation:  f32,
}
DEFAULT_CAMERA :: Camera {
	focus_pos = Vec2{0, 0},
	height    = 10.0,
	rotation  = 0.0,
}
CameraRaw :: struct {
	proj: Mat3,
	pos:  Vec2,
}
camera_lerp :: proc(a: Camera, b: Camera, s: f32) -> Camera {
	res := b
	res.rotation = lerp(a.rotation, b.rotation, s)
	res.focus_pos = lerp(a.focus_pos, b.focus_pos, s)
	res.height = lerp(a.height, b.height, s)
	return res
}
camera_to_raw :: proc "contextless" (self: Camera, screen_size: Vec2) -> (raw: CameraRaw) {
	aspect_ratio := screen_size.x / screen_size.y
	scale_x := 2.0 / (self.height * aspect_ratio)
	scale_y := 2.0 / self.height
	cos_theta := math.cos(self.rotation)
	sin_theta := math.sin(self.rotation)
	
	// odinfmt: disable
	translation := Mat3{
		1, 0, -self.focus_pos.x, 
		0, 1, -self.focus_pos.y, 
		0, 0, 1,
	}
	rotation_scale := Mat3 {
		cos_theta * scale_x, -sin_theta * scale_x, 0,
		sin_theta * scale_y, cos_theta * scale_y, 0,
		0, 0, 1,
	}
	// odinfmt: enable

	raw.proj = rotation_scale * translation
	raw.pos = self.focus_pos
	return raw

}
camera_cursor_hit_pos :: proc(camera: Camera, cursor_pos: Vec2, screen_size: Vec2) -> Vec2 {
	// relative pos to camera in world:
	rel_pos := (cursor_pos - (screen_size / 2)) * camera.height / screen_size.y
	// rotate the relative position by the cameras roation:
	cos_theta := math.cos(-camera.rotation)
	sin_theta := math.sin(-camera.rotation)
	rot_mat := Mat2{cos_theta, -sin_theta, sin_theta, cos_theta}
	// add focus pos of camera
	return (rot_mat * rel_pos) + camera.focus_pos
}


normalize :: linalg.normalize
cross :: linalg.cross
sin :: math.sin
cos :: math.cos
PI :: math.PI
dot :: linalg.dot
sqrt :: math.sqrt
