#+feature dynamic-literals
package example

import q "../quat"
import engine "../quat/engine"
import "core:math"
import "core:slice"

Vec2 :: [2]f32
Vec3 :: [3]f32

main :: proc() {
	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.debug_fps_in_title = false
	settings.bloom_enabled = false
	settings.debug_ui_gizmos = true
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

	cam := engine.camera_controller_create()
	for engine.next_frame() {
		q.mesh_3d_rotate_around_z_axis(&mesh, 0.6 * engine.get_delta_secs(), {0, 0})
		q.mesh_3d_sync(&mesh)

		engine.draw_3d_mesh(mesh)
		engine.camera_controller_update(&cam)
		engine.draw_gizmos_coords()
	}
}


// obj_file 

/*


*/
