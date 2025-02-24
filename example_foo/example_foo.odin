package example_foo

import q "../quat"
import "../quat/engine"
import "core:fmt"
print :: fmt.println


ENGINE_SETTINGS := engine.EngineSettings {
	platform = q.PlatformSettings {
		title                    = "Dplatform",
		initial_size             = {800, 600},
		clear_color              = {0.3, 0.3, 0.3, 1.0},
		shaders_dir_path         = "",
		default_font_path        = "",
		hot_reload_shaders       = false,
		power_preference         = .LowPower,
		present_mode             = .FifoRelaxed,
		tonemapping              = .Disabled,
		screen_ui_reference_size = {1920, 1080},
		// debug_fps_in_title = true,
	},
	bloom_enabled = false,
	debug_ui_gizmos = false,
	debug_collider_gizmos = true,
}
main :: proc() {
	engine.init()
	defer {engine.deinit()}

	for engine.next_frame() {
		engine.display_value("hello")
	}
}
