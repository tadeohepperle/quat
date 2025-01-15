#+feature dynamic-literals
package example

import q "../quat"
import engine "../quat/engine"
import "core:math"

Vec2 :: [2]f32
IVec2 :: [2]int

H :: math.SQRT_THREE / 2
S :: 1
Vertex :: q.TritexVertex

hex_to_world_pos :: proc(pos: IVec2) -> Vec2 {
	FOR_X :: Vec2{1.5 * S, -H}
	FOR_Y :: Vec2{0.0, 2 * H}
	return FOR_X * f32(pos.x) + FOR_Y * f32(pos.y)
}

Tile :: enum {
	None,
	Rock,
	Grass,
	Sand,
	Mars,
}
World :: map[IVec2]Tile
None :: struct {}

// neighbors:
NX :: IVec2{1, 0}
NXY :: IVec2{1, 1}
NY :: IVec2{0, 1}
NMX :: IVec2{-1, 0}
NMYX :: IVec2{-1, -1}
NMY :: IVec2{0, -1}

// 2 triangles in top right of P between P, P+NX, P+NXY   and P, P+NXY, P+NY
HexQuad :: struct {
	pos: IVec2,
	t:   Tile,
	tx:  Tile,
	txy: Tile,
	ty:  Tile,
}
world_hex_quads :: proc(world: World) -> []HexQuad {
	extended: map[IVec2]None // positions in world and neighboring it:
	for pos in world {
		extended[pos] = None{}
		for offset in ([3]IVec2{NMX, NMYX, NMY}) {
			extended[pos + offset] = None{}
		}
	}
	quads := make([]HexQuad, len(extended))
	i: int
	for pos in extended {
		quad := HexQuad {
			pos = pos,
			t   = world[pos],
			tx  = world[pos + NX],
			txy = world[pos + NXY],
			ty  = world[pos + NY],
		}
		quads[i] = quad
		i += 1
	}
	return quads
}

world_vertices :: proc(world: World) -> []Vertex {
	quads := world_hex_quads(world)
	verts := make([]Vertex, len(quads) * 6)
	for q, i in quads {
		p := hex_to_world_pos(q.pos)
		px := hex_to_world_pos(q.pos + NX)
		pxy := hex_to_world_pos(q.pos + NXY)
		py := hex_to_world_pos(q.pos + NY)

		t1_indices := [3]u32{u32(q.t), u32(q.tx), u32(q.txy)}
		t2_indices := [3]u32{u32(q.t), u32(q.txy), u32(q.ty)}
		vi := i * 6
		verts[vi] = Vertex {
			pos     = p,
			indices = t1_indices,
			weights = {1, 0, 0},
		}
		verts[vi + 1] = Vertex {
			pos     = px,
			indices = t1_indices,
			weights = {0, 1, 0},
		}
		verts[vi + 2] = Vertex {
			pos     = pxy,
			indices = t1_indices,
			weights = {0, 0, 1},
		}
		verts[vi + 3] = Vertex {
			pos     = p,
			indices = t2_indices,
			weights = {1, 0, 0},
		}
		verts[vi + 4] = Vertex {
			pos     = pxy,
			indices = t2_indices,
			weights = {0, 1, 0},
		}
		verts[vi + 5] = Vertex {
			pos     = py,
			indices = t2_indices,
			weights = {0, 0, 1},
		}
	}

	return verts
}

main :: proc() {
	// E.enable_max_fps()
	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.debug_fps_in_title = false
	settings.bloom_enabled = false
	settings.debug_ui_gizmos = true
	engine.init(settings)
	defer engine.deinit()
	terrain_textures := engine.load_texture_array(
		{"./assets/t_0.png", "./assets/t_1.png", "./assets/t_2.png", "./assets/t_3.png"},
	)
	engine.set_tritex_textures(terrain_textures)

	world := World {
		{0, 0} = .Grass,
		{1, 0} = .Sand,
		{0, 1} = .Rock,
		{0, 2} = .Grass,
		{1, 2} = .Rock,
		{2, 0} = .Grass,
		{2, 1} = .Sand,
		{0, 1} = .Rock,
		{0, 1} = .Rock,
		{1, 1} = .Mars,
		{5, 6} = .Grass,
		{6, 6} = .Grass,
		{7, 7} = .Sand,
		{7, 8} = .Sand,
		{8, 8} = .Sand,
		{8, 6} = .Sand,
		{8, 7} = .Sand,
	}
	terrain_mesh := engine.create_tritex_mesh(world_vertices(world))
	cam := engine.camera_controller_create()
	for engine.next_frame() {
		engine.camera_controller_update(&cam)
		engine.draw_gizmos_coords()
		engine.draw_tritex_mesh(&terrain_mesh)
	}
}
