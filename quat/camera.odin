package quat

import "core:math"
import "core:math/linalg"

// an orthographic 2d Camera2D
Camera2D :: struct {
	focus_pos: Vec2,
	height:    f32,
	rotation:  f32,
}
DEFAULT_CAMERA_2D :: Camera2D {
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

DEFAULT_CAMERA_3D :: Camera3D {
	transform = Camera3DTransform{eye_pos = Vec3{0, 5, 10}, focus_pos = Vec3{0, 0, 0}, up = Vec3{0, 1, 0}},
	projection = Camera3DProjection{kind = .Perspective, z_near = 0.1, z_far = 100.0, fov_y = 0.7, height_y = 10.0},
}

Camera3D :: struct {
	using transform:  Camera3DTransform,
	using projection: Camera3DProjection,
}

Camera3DTransform :: struct {
	eye_pos:   Vec3,
	focus_pos: Vec3,
	up:        Vec3,
}
Camera3DProjection :: struct {
	kind:     Camera3DProjectionKind,
	z_near:   f32,
	z_far:    f32,
	//
	fov_y:    f32, // in radians, for .Perspective
	height_y: f32, // for .Orthographic
}


camera_3d_transform_lerp :: proc(a: Camera3DTransform, b: Camera3DTransform, s: f32) -> Camera3DTransform {
	return Camera3DTransform {
		eye_pos = lerp(a.eye_pos, b.eye_pos, s),
		focus_pos = lerp(a.focus_pos, b.focus_pos, s),
		up = lerp(a.up, b.up, s),
	}
}

camera_3d_projection_lerp :: proc(a: Camera3DProjection, b: Camera3DProjection, s: f32) -> Camera3DProjection {
	return Camera3DProjection {
		kind = b.kind,
		z_near = lerp(a.z_near, b.z_near, s),
		z_far = lerp(a.z_far, b.z_far, s),
		fov_y = lerp(a.fov_y, b.fov_y, s),
		height_y = lerp(a.height_y, b.height_y, s),
	}
}

Camera3DProjectionKind :: enum {
	Perspective,
	Orthographic,
}

Camera3DUniformData :: struct {
	view_proj: Mat4,
	view:      Mat4,
	proj:      Mat4,
	view_pos:  Vec4, // eye pos of the camera, extended by 1.0
	_pad:      Vec4, // because all the Mat4s are 32-byte aligned
}

camera_3d_uniform_data :: proc(camera: Camera3D, screen_size: Vec2) -> Camera3DUniformData {
	view := camera_3d_view_matrix(camera.transform)
	proj := camera_3d_projection_matrix(camera.projection, screen_size)
	view_proj := proj * view
	view_pos := Vec4{camera.eye_pos.x, camera.eye_pos.y, camera.eye_pos.z, 1.0}
	return Camera3DUniformData{view_proj = view_proj, view = view, proj = proj, view_pos = view_pos}
}

camera_3d_view_matrix :: proc(transform: Camera3DTransform) -> Mat4 {
	return linalg.matrix4_look_at_f32(transform.eye_pos, transform.focus_pos, transform.up, true)
}

camera_3d_projection_matrix :: proc(proj: Camera3DProjection, screen_size: Vec2) -> Mat4 {
	aspect := screen_size.x / screen_size.y
	switch proj.kind {
	case .Orthographic:
		half_size := Vec2{aspect * proj.height_y, proj.height_y} / 2
		return linalg.matrix_ortho3d_f32(-half_size.x, half_size.x, -half_size.y, half_size.y, proj.z_near, proj.z_far)
	case .Perspective:
		return linalg.matrix4_perspective_f32(proj.fov_y, aspect, proj.z_near, proj.z_far, true)
	}
	panic("invalid Camera3DProjectionKind")
}

matrix4_look_at_f32 :: proc "contextless" (eye: Vec3, centre: Vec3, up: Vec3, flip_z_axis := false) -> (m: Mat4) {
	f := linalg.normalize(centre - eye)
	s := linalg.normalize(linalg.cross(f, up))
	u := linalg.cross(s, f)
	fe := linalg.dot(f, eye)

	return matrix[4, 4]f32{
		+s.x, +s.y, +s.z, -dot(s, eye),
		+u.x, +u.y, +u.z, -dot(u, eye),
		-f.x, -f.y, -f.z, +fe if flip_z_axis else -fe,
		0, 0, 0, 1,
	}
}
