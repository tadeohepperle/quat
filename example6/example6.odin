#+feature dynamic-literals
package example

import q "../quat"
import engine "../quat/engine"
import "core:math"
import "core:math/linalg"
import "core:math/noise"
import "core:math/rand"
import "core:slice"

Vec2 :: [2]f32
Vec3 :: [3]f32

main :: proc() {
	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.bloom_enabled = false
	settings.debug_ui_gizmos = false
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
	L :: 0.00
	H :: 3.0
	HTIP :: 0.02

	WX :: 3
	WY :: 0.75


	
	// odinfmt:disable

	when true {
	    v_positions := []Vec3{
	    	{-3,0,L}, {-2,-WY,L}, {2,-WY,L}, {3,0,L}, {2,WY,L}, {-2,WY,L},
	    	{-3,0,H}, {-2,-WY,H}, {2,-WY,H}, {3,0,H}, {2,WY,H}, {-2,WY,H},
	    	{-WY,0,H+HTIP}, {WY,0,H+HTIP}
	    }
	    triangles:= []q.Triangle{
	    	{0,5,1},{1,5,4},{1,4,2},{2,4,3},// bottom
	    	{0,1,7},{0,7,6},{1,2,8},{1,8,7},{2,3,9},{2,9,8},{3,4,10},{3,10,9},{4,5,11},{4,11,10},{5,0,6},{5,6,11}, //sides
	    	{6,7,12},{6,12,11},{9,10,13},{9,13,8},{7,8,13},{7,13,12},{10,11,12},{10,12,13}, // roof
	    }
	}else{
		W :: 3.0
		v_positions := []Vec3{
			{-W,-W, H},{W,-W, H},{W,W, H},{-W,W, H},
		}
		triangles := []q.Triangle{
			{0,1,2}, {0,2,3}
		}
	}


	// odinfmt:enable

	mesh := engine.create_3d_mesh()
	mesh.triangles = slice.clone_to_dynamic(triangles)
	for pos in v_positions {
		append(&mesh.vertices, v(pos))
	}
	q.mesh_3d_unshare_vertices(&mesh)
	q.mesh_3d_sync(&mesh)
	mesh_vertices_unshared := slice.clone(mesh.vertices[:])

	corn := engine.load_texture_tile("./assets/corn.png")
	engine.set_clear_color(q.Color{0.4, 0.4, 0.6, 1.0})
	cam := engine.camera_controller_create()

	terrain_textures := engine.load_texture_array(
		{
			"./assets/t_0.png",
			"./assets/t_1.png",
			"./assets/t_2.png",
			"./assets/t_undiscovered_dark.png",
		},
	)
	engine.set_tritex_textures(terrain_textures)


	hex_chunk_positions := [][2]i32{{-1, 0}, {0, 0}, {1, 0}, {1, 1}, {0, 1}}

	hex_chunks := make([]q.HexChunkUniform, len(hex_chunk_positions))
	for chunk_pos, idx in hex_chunk_positions {
		hex_chunks[idx] = random_hex_chunk(chunk_pos)
	}
	engine.access_shader_globals_xxx().y = 1
	engine.access_shader_globals_xxx().z = 0

	total: f32 = 0
	active_chunk_idx := 0
	for engine.next_frame() {

		dt := engine.get_delta_secs()
		if engine.is_key_pressed(.SPACE) {
			dt = 0.0
		}
		total += dt
		hit_pos := engine.get_hit_pos()

		engine.camera_controller_update(&cam)
		engine.draw_gizmos_coords()


		if engine.is_key_just_pressed(.COMMA) {
			active_chunk_idx -= 1
		}
		if engine.is_key_just_pressed(.PERIOD) {
			active_chunk_idx += 1
		}

		active_chunk_idx = active_chunk_idx %% len(hex_chunks)
		for chunk, idx in hex_chunks {
			a_hex_pos := chunk.chunk_pos * q.CHUNK_SIZE
			a := q.hex_to_world_pos(a_hex_pos)
			b := q.hex_to_world_pos(a_hex_pos + [2]i32{q.CHUNK_SIZE, 0})
			c := q.hex_to_world_pos(a_hex_pos + q.CHUNK_SIZE)
			d := q.hex_to_world_pos(a_hex_pos + [2]i32{0, q.CHUNK_SIZE})

			if idx == active_chunk_idx {
				color := q.ColorOrange
				engine.draw_gizmos_line(a, b, color)
				engine.draw_gizmos_line(b, c, color)
				engine.draw_gizmos_line(c, d, color)
				engine.draw_gizmos_line(d, a, color)

			}
			engine.draw_hex_chunk(chunk)
		}

		shader_xxx := engine.access_shader_globals_xxx()
		engine.add_window(
			"Shader Variables",
			{
				engine.row(
					{engine.slider(&shader_xxx.x), engine.text_from_string("transition")},
					gap = 8,
				),
				engine.row(
					{engine.slider(&shader_xxx.y), engine.text_from_string("noise")},
					gap = 8,
				),
				engine.row(
					{engine.slider(&shader_xxx.z), engine.text_from_string("mesh h")},
					gap = 8,
				),
			},
		)


		rf := engine.get_rf()
		if rf != 0 {
			shader_xxx.z += rf * engine.get_delta_secs() * 3
		}
		shader_xxx.z = clamp(shader_xxx.z, 0, 1)


		// shader_xxx.z = hit_pos.x
		// shader_xxx.w = hit_pos.y
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
		// height_fact := &
		for original_v, idx in mesh_vertices_unshared {
			new_pos := original_v.pos + Vec3{hit_pos.x, hit_pos.y, 0}
			new_pos.z *= shader_xxx.z
			mesh.vertices[idx].pos = new_pos
		}
		q.mesh_3d_sync(&mesh)
		engine.draw_mesh_3d_hex_chunk_masked(mesh, hex_chunks[active_chunk_idx].bind_group)
	}
}
IVec2 :: [2]i32
random_hex_chunk :: proc(chunk_pos: IVec2) -> q.HexChunkUniform {
	chunk_data: q.HexChunkData
	chunk_data.chunk_pos = chunk_pos

	for y in 0 ..< i32(q.CHUNK_SIZE_PADDED) {
		for x in 0 ..< i32(q.CHUNK_SIZE_PADDED) {
			pos := IVec2{x - 1, y - 1} + chunk_pos * q.CHUNK_SIZE

			sample_pos_f32 := q.hex_to_world_pos(pos)
			sample_pos: [2]f64 = {f64(sample_pos_f32.x), f64(sample_pos_f32.y)}
			noise_t := (noise.noise_2d(42, sample_pos / 0.3) + 1.0) / 2.0
			// noise_t2 := (noise.noise_2d(122323, sample_pos / 0.12) + 1.0) / 2.0
			noise_v := (noise.noise_2d(32421, sample_pos / 21.0) + 1.0) / 2.0

			new_ter: u16
			old_ter: u16
			if noise_t > 0.6 {
				old_ter = 1
			} else if noise_t > 0.2 {
				old_ter = 2
			} else {
				old_ter = 3
			}
			new_ter = old_ter

			// if noise_t2 > 0.6 {
			// 	new_ter = 2
			// } else if noise_t > 0.2 {
			// 	new_ter = 1
			// } else {
			// 	new_ter = 3
			// }
			// Q :: 3
			// vis := f32(int(noise_v * Q)) / Q
			// vis: f32 = 1.0 if noise_v > 0.66 else 0.5 if noise_v > 0.33 else 0.0
			// vis: f16 = 1.0 if noise_v > 0.5 else 0.0

			vis: f16 = 1.0 if noise_v > 0.5 else 0.0
			// vis := clamp(f16(noise_v), 0, 1)
			new_fact: f16 = 1
			if vis < 0.5 {
				old_ter = 4
			} else {
				vis = 1.0
			}

			idx := x + y * q.CHUNK_SIZE_PADDED
			chunk_data.tiles[idx] = q.HexTileData{old_ter, new_ter, new_fact, vis}
		}
	}
	uniform := q.hex_chunk_uniform_create(
		engine.ENGINE.platform.device,
		engine.ENGINE.platform.queue,
		chunk_pos,
	)
	q.hex_chunk_uniform_write_data(&uniform, &chunk_data)
	return uniform
}

// obj_file 

/*


*/
