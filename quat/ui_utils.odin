package quat

UiTheme :: struct {
	font_size:               f32,
	font_size_sm:            f32,
	font_size_lg:            f32,
	text_shadow:             f32,
	disabled_opacity:        f32,
	border_width:            BorderWidth,
	border_radius:           BorderRadius,
	border_radius_sm:        BorderRadius,
	control_standard_height: f32,
	text:                    Color,
	text_secondary:          Color,
	background:              Color,
	success:                 Color,
	highlight:               Color,
	surface:                 Color,
	surface_border:          Color,
	surface_deep:            Color,
}

// not a constant, so can be switched out.
THEME: UiTheme = UiTheme {
	font_size               = 22,
	font_size_sm            = 18,
	font_size_lg            = 28,
	text_shadow             = 0.4,
	disabled_opacity        = 0.4,
	border_width            = BorderWidth{2.0, 2.0, 2.0, 2.0},
	border_radius           = BorderRadius{8.0, 8.0, 8.0, 8.0},
	border_radius_sm        = BorderRadius{4.0, 4.0, 4.0, 4.0},
	control_standard_height = 36.0,
	text                    = color_from_hex("#EFF4F7"),
	text_secondary          = color_from_hex("#777F8B"),
	background              = color_from_hex("#252833"),
	success                 = color_from_hex("#68B767"),
	highlight               = color_from_hex("#F7EFB2"),
	surface                 = color_from_hex("#577383"),
	surface_border          = color_from_hex("#8CA6BE"),
	surface_deep            = color_from_hex("#16181D"),
}
