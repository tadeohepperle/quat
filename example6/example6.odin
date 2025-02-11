#+feature dynamic-literals
package example

import q "../quat"
import engine "../quat/engine"
import "core:math"
import "core:math/noise"
import "core:math/rand"
import "core:slice"

Vec2 :: [2]f32
Vec3 :: [3]f32

main :: proc() {
	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.bloom_enabled = false
	settings.debug_ui_gizmos = true
	settings.debug_fps_in_title = true
	// settings.present_mode = .Immediate
	engine.init(settings)

	defer engine.deinit()

	v :: proc(pos: Vec3) -> q.Mesh3dVertex {
		return q.Mesh3dVertex {
			pos = pos,
			color = q.Color{pos.x / 3.0, pos.y / 3.0, pos.z / 3.0, 1.0},
		}
	}
	H :: 3
	// odinfmt:disable
	v_positions := []Vec3{
		{-3,0,0}, {-2,-1,0}, {2,-1,0}, {3,0,0}, {2,1,0}, {-2,1,0},
		{-3,0,H}, {-2,-1,H}, {2,-1,H}, {3,0,H}, {2,1,H}, {-2,1,H},
		{-1,0,H+1}, {1,0,H+1}
	}
	triangles:= []q.Triangle{
		{0,5,1},{1,5,4},{1,4,2},{2,4,3},// bottom
		{0,1,7},{0,7,6},{1,2,8},{1,8,7},{2,3,9},{2,9,8},{3,4,10},{3,10,9},{4,5,11},{4,11,10},{5,0,6},{5,6,11}, //sides
		{6,7,12},{6,12,11},{9,10,13},{9,13,8},{7,8,13},{7,13,12},{10,11,12},{10,12,13}, // roof
	}
	// odinfmt:enable

	mesh := engine.create_3d_mesh()
	mesh.triangles = slice.clone_to_dynamic(triangles)
	for pos in v_positions {
		append(&mesh.vertices, v(pos))
	}
	q.mesh_3d_unshare_vertices(&mesh)
	q.mesh_3d_sync(&mesh)


	corn := engine.load_texture_tile("./assets/corn.png")
	engine.set_clear_color(q.Color{0.4, 0.4, 0.6, 1.0})
	cam := engine.camera_controller_create()

	terrain_textures := engine.load_texture_array(
		{"./assets/t_0.png", "./assets/t_1.png", "./assets/t_2.png", "./assets/t_3.png"},
	)
	engine.set_tritex_textures(terrain_textures)


	hex_chunks := []q.HexChunkUniform {
		random_hex_chunk({0, 0}),
		random_hex_chunk({1, 0}),
		// random_hex_chunk({2, 0}),
		// random_hex_chunk({2, 1}),
		// random_hex_chunk({2, 2}),
		// random_hex_chunk({1, 3}),
		random_hex_chunk({0, 1}),
		random_hex_chunk({1, 1}),
		random_hex_chunk({2, 0}),
		random_hex_chunk({2, 1}),
	}
	// q.hex_chunk_uniform_write_terrain_data()

	total: f32 = 0
	for engine.next_frame() {
		dt := engine.get_delta_secs()
		if engine.is_key_pressed(.SPACE) {
			dt = 0.0
		}
		total += dt


		engine.camera_controller_update(&cam)
		engine.draw_gizmos_coords()


		for chunk in hex_chunks {
			engine.draw_hex_chunk(chunk)
		}


		// corn_sprite := q.Sprite {
		// 	pos      = Vec2{math.sin(total) * 2.0, math.cos(total) * 2.0},
		// 	size     = {2, 2},
		// 	color    = {1, 1, 1, 0.8},
		// 	texture  = corn,
		// 	rotation = 0.0,
		// 	z        = 1.0,
		// }
		// if !engine.is_shift_pressed() {
		// 	engine.draw_sprite(corn_sprite)
		// } else {
		// 	engine.draw_transparent_sprite(corn_sprite)
		// }
		// engine.draw_shine_sprite(corn_sprite)

		// q.mesh_3d_rotate_around_z_axis(&mesh, 0.4 * dt, {0, 0})
		// q.mesh_3d_sync(&mesh)
		// engine.draw_3d_mesh(mesh)
	}
}
IVec2 :: [2]i32
random_hex_chunk :: proc(chunk_pos: IVec2) -> q.HexChunkUniform {
	terrain: q.HexChunkTerrainData
	visibility: q.HexChunkVisibilityData

	for y in 0 ..< i32(q.CHUNK_SIZE_PADDED) {
		for x in 0 ..< i32(q.CHUNK_SIZE_PADDED) {
			pos := IVec2{x - 1, y - 1} + chunk_pos * q.CHUNK_SIZE


			sample_pos_f32 := q.hex_to_world_pos(pos)
			sample_pos: [2]f64 = {f64(sample_pos_f32.x), f64(sample_pos_f32.y)}
			noise_t := (noise.noise_2d(42, sample_pos / 0.3) + 1.0) / 2.0
			noise_v := (noise.noise_2d(32421, sample_pos / 20.7) * 100 + 1.0) / 2.0

			ter: u32
			if noise_t > 0.6 {
				ter = 2
			} else if noise_t > 0.2 {

				ter = 3
			} else {
				ter = 1
			}

			Q :: 3
			// vis := f32(int(noise_v * Q)) / Q
			// vis: f32 = 1.0 if noise_v > 0.66 else 0.5 if noise_v > 0.33 else 0.0
			vis: f32 = 1.0 if noise_v > 0.5 else 0.0
			// vis = clamp(noise_v, 0, 1)
			idx := x + y * q.CHUNK_SIZE_PADDED
			terrain[idx] = ter
			visibility[idx] = vis
		}
	}

	uniform := q.hex_chunk_uniform_create(
		engine.ENGINE.platform.device,
		engine.ENGINE.platform.queue,
		chunk_pos,
	)
	q.hex_chunk_uniform_write_terrain_data(&uniform, &terrain)
	q.hex_chunk_uniform_write_visibility_data(&uniform, &visibility)
	return uniform
}

// obj_file 

/*


*/
