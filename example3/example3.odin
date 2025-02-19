package example

import q "../quat"
import E "../quat/engine"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

Vec2 :: [2]f32
Color :: [4]f32
Vertex :: q.SkinnedVertex
Affine2 :: q.Affine2
Mat2 :: matrix[2, 2]f32

main :: proc() {
	E.init()
	defer {E.deinit()}
	E.set_bloom_enabled(false)
	E.set_clear_color({0.02, 0.02, 0.04, 1.0})

	cam := E.camera_controller_create()
	cam.settings.move_with_wasd = false
	cam.target.focus_pos = {0, 3}
	cam.current.focus_pos = cam.target.focus_pos

	texture := E.load_texture("assets/t_0.png")
	base_bones := []Bone{Bone{{0, 0}, {0, 2}}, Bone{{0, 2}, {0, 4}}}
	pose1_bones := []Bone{Bone{{0, 0}, {1.5, 1.5}}, Bone{{1.5, 1.5}, {1, 3}}}
	pose2_bones := []Bone{Bone{{0, 0}, {0, 3}}, Bone{{0, 3}, {-1, 5}}}

	poses := [3][]Affine2 {
		make_pose(base_bones, base_bones),
		make_pose(base_bones, pose1_bones),
		make_pose(base_bones, pose2_bones),
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
	triangles := []q.Triangle {
		{0, 1, 2},
		{1, 3, 4},
		{1, 4, 2},
		{3, 5, 6},
		{3, 6, 4},
		{5, 7, 8},
		{5, 8, 6},
	}

	skinned_mesh := E.create_skinned_mesh(triangles, vertices, 2, 0)

	LERP_SPEED :: 20
	current_pose_mix: [3]f32 = {1, 0, 0}
	current_pose: []Affine2 = slice.clone(poses[0])
	current_bones := slice.clone(base_bones)

	KeyAndPoseTarget :: struct {
		key:      q.Key,
		pose_mix: [3]f32,
	}
	key_and_pose_targets := []KeyAndPoseTarget{{.A, {1, 0, 0}}, {.S, {0, 1, 0}}, {.D, {0, 0, 1}}}

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
			m: Mat2
			offset: Vec2
			transform = q.affine_sum(
				q.affine_mul(poses[0][i], current_pose_mix[0]),
				q.affine_mul(poses[1][i], current_pose_mix[1]),
				q.affine_mul(poses[2][i], current_pose_mix[2]),
			)
		}
		// update the positions of the current_bones:
		// fmt.println(base_bones, current_bones)
		for &bone, i in current_bones {
			transform := current_pose[i]
			original := base_bones[i]
			bone.head = q.affine_apply(transform, original.head)
			bone.root = q.affine_apply(transform, original.root)
		}

		E.set_skinned_mesh_bones(skinned_mesh, current_pose[:])
		E.draw_skinned_mesh(skinned_mesh, {0, 0}, {1, 1, 1, 0.3})
		E.draw_grid(1, q.Color{1, 1, 1, 0.2})
		if !E.is_key_pressed(.SPACE) {
			E.set_current_mesh_2d_texture(texture)
			verts, tris, start := E.access_mesh_2d_write_buffers()
			for v in vertices {
				pos := v.pos
				pos =
					v.weights[0] * q.affine_apply(current_pose[0], v.pos) +
					v.weights[1] * q.affine_apply(current_pose[1], v.pos)
				append(
					verts,
					q.Mesh2dVertex {
						pos = pos,
						uv = pos,
						color = {v.weights[0], v.weights[1], 0, 0.5},
					},
				)
			}
			for tri in triangles {
				append(tris, tri + start)
			}
		}
		for bone in current_bones {
			E.draw_gizmos_circle(bone.head, 0.2)
			E.draw_gizmos_circle(bone.root, 0.3)
			dir := linalg.normalize(bone.head - bone.root)
			perp := Vec2{-dir.y, dir.x} * 0.3
			E.draw_gizmos_triangle(bone.head, bone.root + perp, bone.root - perp)
		}
		E.camera_controller_update(&cam)

		file_paths := E.get_dropped_file_paths()
		if file_paths != nil {
			fmt.println(file_paths)
		}
	}
}


Bone :: struct {
	root: Vec2,
	head: Vec2,
}
make_pose :: proc(base_bones: []Bone, bones: []Bone) -> []Affine2 {
	assert(len(base_bones) == len(bones))
	pose := make([]Affine2, len(bones))
	for base, i in base_bones {
		cur := bones[i]
		pose[i] = affine_from_vectors(base.root, base.head, cur.root, cur.head)
	}
	return pose
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

// creates a new affine transform from two offsetted vectors, mapping the `from` to the `to` when the 
// resulting affine transform A is applied, so: 
// - `to_root === affine_apply(A, from_root)`
// - `to_head === affine_apply(A, from_head)`
//
// solution: M = A^-1 * B  
affine_from_vectors :: proc(
	from_root: Vec2,
	from_head: Vec2,
	to_root: Vec2,
	to_head: Vec2,
) -> (
	res: Affine2,
) {
	a := from_head - from_root
	b := to_head - to_root

	A := Mat2{a.x, -a.y, a.y, a.x}
	A_DET := A[0, 0] * A[1, 1] - A[1, 0] * A[0, 1]
	A_INV := (f32(1.0) / A_DET) * Mat2{A[1, 1], -A[0, 1], -A[1, 0], A[0, 0]}

	// if true, the scaling only applies in the direction of the bone, not sideways to it.
	// if false, a bone being made longer, makes its hull also thicker.
	NO_SIDE_SCALING :: true
	when NO_SIDE_SCALING {
		a_len := linalg.length(a)
		b_len := linalg.length(b)

		len_factor := a_len / b_len
		B := Mat2{b.x * len_factor, -b.y, b.y * len_factor, b.x}
	} else {
		B := Mat2{b.x, -b.y, b.y, b.x}
	}
	return Affine2{A_INV * B, (res.m * (-from_root)) + to_root}
}
