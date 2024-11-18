package quat

import "core:math"
import "core:math/linalg"


ColliderMetadata :: [24]u8
NO_COLLIDER: ColliderMetadata = {}

Collider :: struct {
	shape:    ColliderShape,
	metadata: ColliderMetadata,
	z:        int,
}

ColliderShape :: union {
	Circle,
	Aabb,
	Triangle,
	RotatedRect,
}

collider_roughly_in_aabb :: proc "contextless" (collider: ^ColliderShape, aabb: Aabb) -> bool {
	switch c in collider {
	case Circle:
		return aabb_contains(aabb, c.pos)
	case Aabb:
		return aabb_intersects(aabb, c)
	case Triangle:
		center := (c.a + c.b + c.c) / 3
		return aabb_contains(aabb, center)
	case RotatedRect:
		return aabb_contains(aabb, c.center)
	}
	return false
}

collider_overlaps_point :: proc "contextless" (collider: ^ColliderShape, pt: Vec2) -> bool {
	switch c in collider {
	case Circle:
		return linalg.length2(c.pos - pt) < c.radius * c.radius
	case Aabb:
		return pt.x >= c.min.x && pt.x <= c.max.x && pt.y >= c.min.y && pt.y <= c.max.y
	case Triangle:
		return point_in_triangle(pt, c.a, c.b, c.c)
	case RotatedRect:
		if linalg.length2(c.center - pt) > c.radius_sq {
			return false
		}
		return point_in_triangle(pt, c.a, c.b, c.c) || point_in_triangle(pt, c.a, c.c, c.d)
	}
	return false
}


Triangle :: struct {
	a: Vec2,
	b: Vec2,
	c: Vec2,
}

Circle :: struct {
	pos:    Vec2,
	radius: f32,
}

RotatedRect :: struct {
	a:         Vec2,
	b:         Vec2,
	c:         Vec2,
	d:         Vec2,
	center:    Vec2,
	radius_sq: f32,
}

rotated_rect :: #force_inline proc(center: Vec2, size: Vec2, angle: f32) -> RotatedRect {
	half_x := size.x / 2
	half_y := size.y / 2
	cos_a := math.cos(angle)
	sin_a := math.sin(angle)
	a_off := Vec2{cos_a * half_x - sin_a * half_y, sin_a * half_x + cos_a * half_y}
	b_off := Vec2{-a_off.y, a_off.x}
	c_off := Vec2{-a_off.x, -a_off.y}
	d_off := Vec2{a_off.y, -a_off.x}
	return RotatedRect {
		a = center + a_off,
		b = center + b_off,
		c = center + c_off,
		d = center + d_off,
		center = center,
		radius_sq = half_x * half_x + half_y * half_y,
	}
}


point_in_triangle :: #force_inline proc "contextless" (
	pt: Vec2,
	a: Vec2,
	b: Vec2,
	c: Vec2,
) -> bool {
	sign :: #force_inline proc "contextless" (p1: Vec2, p2: Vec2, p3: Vec2) -> f32 {
		return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
	}
	d1 := sign(pt, a, b)
	d2 := sign(pt, b, c)
	d3 := sign(pt, c, a)

	has_neg := (d1 < 0.0) || (d2 < 0.0) || (d3 < 0.0)
	has_pos := (d1 > 0.0) || (d2 > 0.0) || (d3 > 0.0)

	return !(has_neg && has_pos)
}
