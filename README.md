# quat - a small specialized game framework

Project overview:

- `/quat` building blocks, tries to avoid global state
- `/quat/engine` offers a global state and quick utility functions

How to use in a project:

```odin
import "../quat/engine"
main :: proc() {
    engine.init()
    defer engine.deinit()

    for engine.next_frame() {
        engine.draw_gizmos_coords()
        camera := engine.get_camera()
    	camera.focus_pos += engine.get_wasd() * engine.get_delta_secs() * 5.0
    	engine.set_camera(camera)
    }
}
```
