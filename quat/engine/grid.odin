package engine
import q ".."

import "base:runtime"
import "core:math"
import "core:math/linalg"

draw_multi_level_grid :: proc() {
	draw_grid(1, {1, 1, 1, 0.2})
	draw_grid(5, {1, 1, 1, 0.7})
}

draw_grid :: proc(grid_size: int = 1, color: q.Color = q.ColorWhite) {
	aspect := q.get_aspect_ratio()
	camera := get_camera()
	y_size := camera.height * 2
	x_size := y_size * aspect
	cam_pos := camera.focus_pos
	min := cam_pos - q.Vec2{x_size, y_size} / 2
	max := cam_pos + q.Vec2{x_size, y_size} / 2
	x_min := int(min.x) - grid_size - (int(min.x) %% grid_size)
	y_min := int(min.y) - grid_size - (int(min.y) %% grid_size)
	x_max := int(max.x) + grid_size - (int(max.x) %% grid_size)
	y_max := int(max.y) + grid_size - (int(max.y) %% grid_size)

	for x := x_min; x <= x_max; x += grid_size {
		draw_gizmos_line(q.Vec2{f32(x), f32(y_min)}, q.Vec2{f32(x), f32(y_max)}, color)
	}

	for y := y_min; y <= y_max; y += grid_size {
		draw_gizmos_line(q.Vec2{f32(x_min), f32(y)}, q.Vec2{f32(x_max), f32(y)}, color)
	}
}
draw_line :: proc(from: Vec2, to: Vec2, color: Color = q.ColorRed, thickness: f32 = 0.02) {
	verts, tris, start := access_color_mesh_write_buffers()
	dir := linalg.normalize(to - from)
	perp := Vec2{dir.y, -dir.x} * thickness * 0.5
	a := from + perp
	b := from - perp
	c := to - perp
	d := to + perp
	append(
		verts,
		q.ColorMeshVertex{a, color},
		q.ColorMeshVertex{b, color},
		q.ColorMeshVertex{c, color},
		q.ColorMeshVertex{d, color},
	)
	append(tris, q.Triangle{start, start + 1, start + 2})
	append(tris, q.Triangle{start, start + 2, start + 3})
}


unit_circle_points :: proc "contextless" (segments: int) -> []Vec2 {
	context = runtime.default_context()
	pts := make_slice([]Vec2, segments)
	for &p, i in pts {
		angle := f32(i) / f32(segments) * math.PI * 2.0
		p = Vec2{math.cos(angle), math.sin(angle)}
	}
	return pts
}
CIRCLE_PTS := unit_circle_points(20)

draw_circle :: proc(pos: Vec2, radius: f32, color: Color = q.ColorRed) {
	verts, tris, start := access_color_mesh_write_buffers()
	append(verts, q.ColorMeshVertex{pos = pos, color = color})
	for c, i in CIRCLE_PTS {
		append(verts, q.ColorMeshVertex{pos = pos + c * radius, color = color})
		j := 0 if i == len(CIRCLE_PTS) - 1 else i + 1
		append(tris, q.Triangle{start, u32(j + 1) + start, u32(i + 1) + start})
	}
}

draw_rect :: proc(pos: Vec2, size: Vec2, rotation: f32 = 0.0, color: Color = q.ColorRed) {
	rect := q.rotated_rect(pos, size, rotation)
	verts, tris, s := access_color_mesh_write_buffers()
	append_elems(
		verts,
		q.ColorMeshVertex{pos = rect.a, color = color},
		q.ColorMeshVertex{pos = rect.b, color = color},
		q.ColorMeshVertex{pos = rect.c, color = color},
		q.ColorMeshVertex{pos = rect.d, color = color},
	)
	append_elems(tris, q.Triangle{s, s + 1, s + 2}, q.Triangle{s, s + 2, s + 3})
}

draw_rect_border :: proc(pos: Vec2, size: Vec2, border_width: f32, rotation: f32 = 0.0, color: Color = q.ColorRed) {
	outer := q.rotated_rect(pos, size, rotation)
	inner := q.rotated_rect(pos, size - border_width, rotation)
	verts, tris, s := access_color_mesh_write_buffers()
	append_elems(
		verts,
		q.ColorMeshVertex{pos = outer.a, color = color},
		q.ColorMeshVertex{pos = outer.b, color = color},
		q.ColorMeshVertex{pos = outer.c, color = color},
		q.ColorMeshVertex{pos = outer.d, color = color},
		q.ColorMeshVertex{pos = inner.a, color = color},
		q.ColorMeshVertex{pos = inner.b, color = color},
		q.ColorMeshVertex{pos = inner.c, color = color},
		q.ColorMeshVertex{pos = inner.d, color = color},
	)
	append_elems(
		tris,
		q.Triangle{s, s + 1, s + 5},
		q.Triangle{s, s + 5, s + 4},
		q.Triangle{s + 1, s + 2, s + 6},
		q.Triangle{s + 1, s + 6, s + 5},
		q.Triangle{s + 2, s + 3, s + 7},
		q.Triangle{s + 2, s + 7, s + 6},
		q.Triangle{s + 3, s, s + 4},
		q.Triangle{s + 3, s + 4, s + 7},
	)
}
