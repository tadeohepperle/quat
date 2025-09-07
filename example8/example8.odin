#+feature dynamic-literals
package example

import q "../quat"
import engine "../quat/engine"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"

print :: fmt.println

Vec2 :: [2]f32
IVec2 :: [2]int

// force-directed graph
main :: proc() {
	// E.enable_max_fps()
	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.debug_fps_in_title = true
	settings.bloom_enabled = false
	settings.debug_ui_gizmos = false
	settings.debug_collider_gizmos = false
	engine.init(settings)
	defer engine.deinit()

	cam := engine.camera_controller_create()
	cam.settings.min_size = 0.1
	cam.settings.move_with_arrows = false

	graph := make_graph_tree()
	nodes := graph.nodes
	edges := graph.edges

	dragging_node: NodeId


	n_force_updates_per_frame := 1
	for engine.next_frame() {
		engine.camera_controller_update(&cam)
		dt := q.get_delta_secs()
		hit_node := q.from_collider_metadata(engine.get_hit().hit_collider, NodeId)

		// start drag:
		if q.is_left_just_pressed() && hit_node != 0 && dragging_node == 0 {
			dragging_node = hit_node
		}
		// during drag:
		if dragging_node != 0 {
			if !q.is_left_pressed() {
				// end drag:
				dragging_node = 0
			} else {
				node := &nodes[dragging_node]
				node.pos = engine.get_hit_pos()
			}
		}
		engine.add_ui(q.slider_int(&n_force_updates_per_frame, 0, 8))


		for _ in 0 ..< n_force_updates_per_frame {
			force_update(&nodes, edges, 0.0166, dragging_node)
		}

		// draw edges:
		for edge in edges {
			pos_a := nodes[edge.a].pos
			pos_b := nodes[edge.b].pos
			engine.draw_line(pos_a, pos_b, q.ColorSoftLightPeach, 0.04)
		}
		// drawing nodes:
		for node_id, node in nodes {
			color := q.ColorMiddleGrey
			if node_id == dragging_node || (dragging_node == 0 && node_id == hit_node) {
				color = q.ColorLightBlue
			}
			engine.draw_circle(node.pos, 0.2, color)
			engine.add_circle_collider(node.pos, 0.2, q.to_collider_metadata(node_id), int(node_id))
			engine.draw_annotation(node.pos, fmt.tprint(node_id))
		}

		engine.display_value(int(q.PLATFORM.total_secs))
	}
}

None :: struct {}
NodeId :: distinct u64
Node :: struct {
	id:    NodeId,
	pos:   Vec2,
	force: Vec2,
}
Edge :: struct {
	a: NodeId,
	b: NodeId,
}

Graph :: struct {
	nodes: map[NodeId]Node,
	edges: map[Edge]None,
}

make_graph_random :: proc() -> Graph {
	nodes: map[NodeId]Node
	edges: map[Edge]None

	N_NODES :: 20
	N_CONNECTIONS :: N_NODES * 3
	FIELD_SIZE :: 20.0
	// randomly generate N_NODES:
	rand.reset(seed = 213)
	for idx in 0 ..< N_NODES {
		node_id := NodeId(idx + 1)
		pos := Vec2{rand.float32(), rand.float32()} * FIELD_SIZE - FIELD_SIZE / 2
		nodes[node_id] = Node {
			id  = node_id,
			pos = pos,
		}
	}
	for _ in 0 ..< N_CONNECTIONS {
		a := NodeId(rand.int_max(len(nodes)) + 1)
		b := NodeId(rand.int_max(len(nodes)) + 1)
		edges[Edge{a, b}] = None{}
	}
	return Graph{nodes, edges}
}


make_graph_tree :: proc() -> Graph {
	g: Graph


	BRANCHING :: 2
	MAX_DEPTH :: 5


	ORIGIN_NODE :: NodeId(1)
	g.nodes[ORIGIN_NODE] = Node {
		id  = ORIGIN_NODE,
		pos = {0, 0},
	}
	add_children(&g, ORIGIN_NODE, 0)

	add_children :: proc(graph: ^Graph, parent: NodeId, current_depth: int) {
		if current_depth >= MAX_DEPTH {
			return
		}
		parent := graph.nodes[parent]
		for _ in 0 ..< BRANCHING {
			next_id := NodeId(len(graph.nodes) + 1)
			pos := parent.pos + Vec2{rand.float32(), rand.float32()}
			graph.nodes[next_id] = Node {
				id  = next_id,
				pos = pos,
			}
			graph.edges[Edge{parent.id, next_id}] = None{}
			add_children(graph, next_id, current_depth + 1)
		}
	}

	return g
}


force_update :: proc(nodes: ^map[NodeId]Node, edges: map[Edge]None, dt: f32, dragging_node: NodeId) {
	k_repulsion: f32 = 1.0
	k_attraction: f32 = 1.0
	damping: f32 = 0.9
	max_force: f32 = 1000.0

	// Repulsive forces between all pairs of nodes
	for node_a_id, &node_a in nodes {
		node_a.force = Vec2{0, 0}
		for node_b_id, node_b in nodes {
			if node_a_id == node_b_id {
				continue
			}
			delta := node_a.pos - node_b.pos
			dist2 := delta.x * delta.x + delta.y * delta.y + 0.01
			force_mag := k_repulsion / dist2
			force := linalg.normalize0(delta) * force_mag
			node_a.force += force
		}
	}

	// Attractive forces along edges
	for edge in edges {
		node_a := &nodes[edge.a]
		node_b := &nodes[edge.b]
		delta := node_b.pos - node_a.pos
		dist := linalg.length(delta) + 0.01
		force_mag := k_attraction * dist
		force := linalg.normalize0(delta) * force_mag
		node_a.force += force
		node_b.force -= force
	}

	// Update positions
	for node_id, &node in nodes {
		if node_id == dragging_node {
			continue
		}
		if linalg.length2(node.force) > max_force * max_force {
			node.force = linalg.normalize0(node.force) * max_force
		}
		velocity := node.force * dt
		velocity *= damping
		node.pos += velocity
	}

}
