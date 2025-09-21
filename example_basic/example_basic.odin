package example_basic

import "core:fmt"
import "core:mem"

import q "../quat"
import engine "../quat/engine"

Vec2 :: q.Vec2

main :: proc() {


	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	settings := engine.DEFAULT_ENGINE_SETTINGS
	settings.bloom_enabled = false
	settings.debug_ui_gizmos = true

	// q.platform_init(settings.platform)
	// defer q.platform_deinit()
	engine.init(settings)
	defer engine.deinit()


	reader := q.equirect_reader_create()
	defer q.equirect_reader_drop(&reader)


	q.equirect_reader_load_cube_texture(reader, "./assets/pure-sky.hdr", 1080)

	// for engine.next_frame() {
	// 	// div := q.div(q.Div{padding = {20, 20, 20, 20}, color = {0, 0, 0.1, 1.0}})
	// 	// q.child(div, q.button("Hello").ui)
	// 	// engine.add_ui(div)
	// 	// engine.draw_gizmos_coords()
	// }
}
