package quat

import "core:math"
import "core:math/linalg"

// an orthographic 2d Camera2D
Camera2D :: struct {
	focus_pos: Vec2,
	height:    f32,
	rotation:  f32,
}
DEFAULT_CAMERA :: Camera2D {
	focus_pos = Vec2{0, 0},
	height    = 10.0,
	rotation  = 0.0,
}
Camera2DUniformData :: struct {
	proj_col_1: Vec3,
	_pad_1:     f32,
	proj_col_2: Vec3,
	_pad_2:     f32,
	proj_col_3: Vec3,
	_pad_3:     f32,
	pos:        Vec2,
	height:     f32,
	_pad_4:     f32,
}

#assert(size_of(Camera2DUniformData) == 64)

camera_2d_uniform_data :: proc(camera: Camera2D, screen_size: Vec2) -> Camera2DUniformData {
	proj_mat := camera_2d_projection_matrix(camera, screen_size)
	return Camera2DUniformData {
		proj_col_1 = proj_mat[0],
		proj_col_2 = proj_mat[1],
		proj_col_3 = proj_mat[2],
		pos = camera.focus_pos,
		height = camera.height,
	}
}
camera_lerp :: proc(a: Camera2D, b: Camera2D, s: f32) -> Camera2D {
	res := b
	res.rotation = lerp(a.rotation, b.rotation, s)
	res.focus_pos = lerp(a.focus_pos, b.focus_pos, s)
	res.height = lerp(a.height, b.height, s)
	return res
}
camera_2d_projection_matrix :: proc "contextless" (self: Camera2D, screen_size: Vec2) -> Mat3 {
	aspect_ratio := screen_size.x / screen_size.y
	scale_x := 2.0 / (self.height * aspect_ratio)
	scale_y := 2.0 / self.height
	cos_theta := math.cos(self.rotation)
	sin_theta := math.sin(self.rotation)

	translation := matrix[3, 3]f32{
		1, 0, -self.focus_pos.x,
		0, 1, -self.focus_pos.y,
		0, 0, 1,
	}
	rotation_scale := matrix[3, 3]f32{
		cos_theta * scale_x, -sin_theta * scale_x, 0,
		sin_theta * scale_y, cos_theta * scale_y, 0,
		0, 0, 1,
	}

	return rotation_scale * translation
}

camera_2d_screen_to_world_pos :: proc(camera: Camera2D, screen_pos: Vec2, screen_size: Vec2) -> Vec2 {
	// relative pos to camera in world:
	rel_pos := (screen_pos - (screen_size / 2)) * camera.height / screen_size.y
	rel_pos.y = -rel_pos.y
	// rotate the relative position by the cameras roation:
	cos_theta := math.cos(-camera.rotation)
	sin_theta := math.sin(-camera.rotation)
	rot_mat := Mat2{cos_theta, -sin_theta, sin_theta, cos_theta}
	// add focus pos of camera
	return (rot_mat * rel_pos) + camera.focus_pos
}
world_to_screen_pos :: proc(camera: Camera2D, world_pos: Vec2, screen_size: Vec2) -> Vec2 {
	rel_pos := world_pos - camera.focus_pos
	// inverse rotation matrix
	cos_theta := math.cos(-camera.rotation)
	sin_theta := math.sin(-camera.rotation)
	inv_rot_mat := Mat2{cos_theta, sin_theta, -sin_theta, cos_theta}
	rel_pos = inv_rot_mat * rel_pos
	rel_pos.y = -rel_pos.y
	// scale the relative position to screen space
	screen_pos := rel_pos * screen_size.y / camera.height
	// adjust for screen center
	return screen_pos + (screen_size / 2)
}

normalize :: linalg.normalize
cross :: linalg.cross
sin :: math.sin
cos :: math.cos
PI :: math.PI
dot :: linalg.dot
sqrt :: math.sqrt


Camera3D :: struct {
	eye_pos:    Vec3,
	target_pos: Vec3,
	up:         Vec3,
}
