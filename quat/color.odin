package quat

// import "base:intrinsics"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:os"
import wgpu "vendor:wgpu"
Color :: [4]f32

color_from_u8 :: proc(r: u8, g: u8, b: u8) -> Color {
	return {color_map_to_srgb(r), color_map_to_srgb(g), color_map_to_srgb(b), 1.0}
}

// allocates in tmp allocator. THe mapping is likely wrong here, TODO! verify math
color_to_hex :: proc(color: Color) -> string {
	srgb_map :: proc(v: f32) -> u8 {
		if v <= 0.0031308 {
			return u8(v * 12.92 * 255)
		}
		return u8((1.055 * math.pow_f32(v, 1.0 / 2.4) - 0.055) * 255)
	}

	r := srgb_map(color[0])
	g := srgb_map(color[1])
	b := srgb_map(color[2])
	return fmt.aprintf("#%02x%02x%02x", r, g, b, allocator = context.temp_allocator)
}

color_from_hex :: proc(hex: string) -> Color {
	hex_digit_value :: proc(c: rune) -> u8 {
		switch c {
		case '0' ..= '9':
			return u8(c - '0')
		case 'a' ..= 'f':
			return u8(c - 'a' + 10)
		case 'A' ..= 'F':
			return u8(c - 'A' + 10)
		}

		return 0
	}

	parse_hex_pair :: proc(s: string, start: int) -> u8 {
		return 16 * hex_digit_value(rune(s[start])) + hex_digit_value(rune(s[start + 1]))
	}

	if len(hex) != 7 || hex[0] != '#' {
		fmt.panicf("Hex Color is expected to start with '#' and have 7 characters, got: %s", hex)
	}

	r := color_map_to_srgb(parse_hex_pair(hex, 1))
	g := color_map_to_srgb(parse_hex_pair(hex, 3))
	b := color_map_to_srgb(parse_hex_pair(hex, 5))
	return Color{r, g, b, 1.0}
}


@(private)
color_map_to_srgb :: proc(u: u8) -> f32 {
	return math.pow_f32((f32(u) / 255 + 0.055) / 1.055, 2.4)
}


Hsv :: struct {
	h: f64,
	s: f64,
	v: f64,
}

Rgb :: struct {
	r: f64,
	g: f64,
	b: f64,
}


// color_to_hsv :: proc(color: Color) -> HsvColor {

highlight :: proc(color: Color, add: f32 = 0.2) -> Color {
	return color + {add, add, add, 0.0}
}


// see https://docs.rs/color_space/latest/src/color_space/hsv.rs.html
hsv_to_rgb :: proc(using hsv: Hsv) -> Rgb {
	range := u8(h / 60.0)
	c := v * s
	x := c * (1.0 - abs((math.mod_f64(h / 60.0, 2.0)) - 1.0))
	m := v - c

	switch range {
	case 0:
		return Rgb{(c + m), (x + m), m}
	case 1:
		return Rgb{(x + m), (c + m), m}
	case 2:
		return Rgb{m, (c + m), (x + m)}
	case 3:
		return Rgb{m, (x + m), (c + m)}
	case 4:
		return Rgb{(x + m), m, (c + m)}
	case:
		return Rgb{(c + m), m, (x + m)}
	}
}

color_to_rgb :: proc(color: Color) -> Rgb {
	return Rgb{f64(color.r), f64(color.g), f64(color.b)}
}

rbg_to_color :: proc(using rgb: Rgb) -> Color {
	return Color{f32(r), f32(g), f32(b), 1.0}
}

rbg_to_hsv :: proc(using rgb: Rgb) -> Hsv {
	min := min(r, g, b)
	max := max(r, g, b)
	delta := max - min

	v: f64 = max
	s: f64 = delta / max if max > 0.001 else 0.0
	h2: f64 = 0
	if delta != 0 {
		if r == max {
			h2 = (g - b) / delta
		} else if g == max {
			h2 = 2.0 + (b - r) / delta
		} else {
			h2 = 4.0 + (r - g) / delta
		}
	}
	h := math.mod_f64((h2 * 60.0) + 360.0, 360.0)
	return Hsv{h, s, v}
}

color_from_hsv :: proc(hsv: Hsv) -> Color {
	return rbg_to_color(hsv_to_rgb(hsv))
}

ColorTransparent :: Color{0.0, 0.0, 0.0, 0.0}
ColorWhite :: Color{1, 1, 1, 1}
ColorBlack :: Color{0, 0, 0, 1}
ColorGreen :: Color{0, 1, 0, 1}
ColorPurple :: Color{1, 0, 1, 1}
ColorRed :: Color{1, 0, 0, 1}
ColorBlue :: Color{0, 0, 1, 1}
ColorOrange :: Color{1, 0.5, 0, 1}
ColorYellow :: Color{1, 1, 0, 1}

ColorSoftGreen := color_from_u8(113, 211, 91)
ColorSoftBlue := color_from_u8(87, 186, 255)
ColorSoftYellow := color_from_u8(255, 241, 126)
ColorSoftRed := color_from_u8(255, 133, 102)
ColorSoftOrange := color_from_u8(255, 155, 0)
ColorSoftPink := color_from_u8(251, 134, 232)
ColorSoftTeal := color_from_u8(0, 227, 189)
ColorSoftTeal2 := color_from_u8(111, 196, 172)
ColorSoftSkyBlue := color_from_u8(0, 219, 255)
ColorSoftPurpleBlue := color_from_u8(160, 166, 255)
ColorSoftLightGreen := color_from_u8(185, 255, 163)
ColorSoftLightPeach := color_from_u8(255, 185, 168)
ColorLightBlue := color_from_u8(118, 196, 245)
ColorLightGrey := color_from_u8(161, 166, 173)
ColorMiddleGrey := color_from_u8(96, 100, 105)
ColorDarkGrey := color_from_u8(28, 29, 31)
ColorDarkTeal := color_from_u8(42, 56, 56)
ColorNightBlue := color_from_u8(30, 38, 54)

// Returns a gray color.
//
// Parameters
// - `brightness`: The brightness of the color. `0.0` is black, `1.0` is white.
color_gray :: proc(brightness: f32) -> Color {
	b := brightness if brightness <= 1.0 else 1.0
	return {b, b, b, 1.0}
}


color_to_wgpu :: proc(color: Color) -> wgpu.Color {
	return wgpu.Color{f64(color.r), f64(color.g), f64(color.b), f64(color.a)}
}

random_color :: proc() -> Color {
	return color_from_hsv(Hsv{rand.float64() * 360.0, 1.0, 1.0})
}

pseudo_random_color :: proc(data: $T) -> Color {
	data := data
	h := hash.fnv64((cast([^]byte)&data)[:size_of(T)])
	state := rand.create(h)
	gen := rand.default_random_generator(&state)
	r := rand.float64(gen)
	return color_from_hsv(Hsv{r * 360.0, 1.0, 1.0})
}
