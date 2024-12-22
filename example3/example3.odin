package example

import q "../quat"
import E "../quat/engine"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import "core:time"

Vec2 :: [2]f32
Color :: [4]f32
Vertex :: q.SkinnedVertex
Affine2 :: q.Affine2
main :: proc() {

	E.init()
	defer {E.deinit()}
	E.set_bloom_enabled(false)
	E.set_clear_color({0.02, 0.02, 0.04, 1.0})

	cam := E.camera_controller_create()
	cam.settings.wasd_move_speed = 0.0


	texture := E.load_texture("assets/t_0.png")
	original_bones := [2]Bone{Bone{{0, 0}, {0, 2}}, Bone{{0, 2}, {0, 4}}}
	bone_poses := [3]BoneTransforms {
		transforms(q.AFFINE2_UNIT, q.AFFINE2_UNIT),
		transforms(
			q.affine_from_rotation(0.3, {0, 0}, {0, 0}),
			q.affine_from_rotation(0.3, {0, 2}, {0, 2}),
		),
		transforms(
			q.affine_from_vectors({0, 0}, {0, 2}, {1, 1}, {3, 2}),
			q.affine_from_vectors({0, 2}, {0, 4}, {0, 3}, {-1, 5}),
		),
	}
	vertices := []Vertex {
		v(0, -1),
		v(1, 0),
		v(-1, 0),
		v(1, 2, .Shared),
		v(-1, 2, .Shared),
		v(1, 4, .Two),
		v(-1, 4, .Two),
		v(1, 8, .Two),
		v(-1, 8, .Two),
	}
	tris := []q.IdxTriangle {
		{0, 1, 2},
		{1, 3, 4},
		{1, 4, 2},
		{3, 5, 6},
		{3, 6, 4},
		{5, 7, 8},
		{5, 8, 6},
	}

	skinned_mesh := E.create_skinned_mesh(tris, vertices, 2, texture)

	LERP_SPEED :: 20
	current_pose_mix: [3]f32 = {1, 0, 0}
	current_pose: BoneTransforms
	current_bones := original_bones

	KeyAndPoseTarget :: struct {
		key:      q.Key,
		pose_mix: [3]f32,
	}
	key_and_pose_targets := []KeyAndPoseTarget {
		{.W, {0, 0, 1}},
		{.A, {1, 0, 0}},
		{.S, [3]f32{1, 1, 1} / 3},
		{.D, {0, 1, 0}},
	}

	for E.next_frame() {

		for target in key_and_pose_targets {
			if E.is_key_pressed(target.key) {
				t := E.get_delta_secs() * LERP_SPEED
				current_pose_mix = q.lerp(current_pose_mix, target.pose_mix, t)
				break
			}
		}
		E.add_ui(E.triangle_picker(&current_pose_mix))

		// assign transforms that are a weighted mix of the 3 poses:
		for &transform, i in current_pose {
			transform =
				bone_poses[0][i] * current_pose_mix[0] +
				bone_poses[1][i] * current_pose_mix[1] +
				bone_poses[2][i] * current_pose_mix[2]
		}
		// update the positions of the current_bones:
		for &bone, i in current_bones {
			transform := current_pose[i]
			original := original_bones[i]
			bone.head = q.affine_apply(transform, original.head)
			bone.root = q.affine_apply(transform, original.root)
		}
		E.update_skinned_mesh_bones(skinned_mesh, current_pose[:])
		E.draw_skinned_mesh(skinned_mesh)

		E.draw_grid(1, q.Color{1, 1, 1, 0.2})
		write_v, write_i := E.access_color_mesh_write_buffers()
		start := u32(len(write_v))
		for v in vertices {
			pos := v.pos
			pos =
				v.weights[0] * q.affine_apply(current_pose[0], v.pos) +
				v.weights[1] * q.affine_apply(current_pose[1], v.pos)
			append(
				write_v,
				q.ColorMeshVertex{pos = pos, color = {v.weights[0], v.weights[1], 0, 0.1}},
			)
		}
		for tri in tris {
			append(write_i, tri.x + start)
			append(write_i, tri.y + start)
			append(write_i, tri.z + start)
		}
		for bone in current_bones {
			E.draw_gizmos_circle(bone.head, 0.2)
			E.draw_gizmos_circle(bone.root, 0.3)
			dir := linalg.normalize(bone.head - bone.root)
			perp := Vec2{-dir.y, dir.x} * 0.3
			E.draw_gizmos_triangle(bone.head, bone.root + perp, bone.root - perp)
		}
		E.camera_controller_update(&cam)
	}
}

BoneTransforms :: distinct [2]q.Affine2
transforms :: proc(a: Affine2, b: Affine2) -> BoneTransforms {
	b := q.affine_combine(a, b)
	return BoneTransforms{a, b}
}

Bone :: struct {
	root: Vec2,
	head: Vec2,
}


v :: proc(x: f32, y: f32, weights: enum {
		One,
		Two,
		Shared,
	} = .One) -> Vertex {
	w: Vec2
	switch weights {
	case .One:
		w = {1.0, 0.0}
	case .Two:
		w = {0.0, 1.0}
	case .Shared:
		w = {0.5, 0.5}
	}
	pos := Vec2{x, y}
	uv := pos
	return Vertex{pos, uv, {0, 1}, w}
}
