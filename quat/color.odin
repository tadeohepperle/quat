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


Color_Transparent :: Color{0.0, 0.0, 0.0, 0.0}
Color_Alice_Blue :: Color{0.941176, 0.972549, 1.0, 1.0}
Color_Antique_White :: Color{0.980392, 0.921569, 0.843137, 1.0}
Color_Aqua :: Color{0.0, 1.0, 1.0, 1.0}
Color_Aquamarine :: Color{0.498039, 1.0, 0.831373, 1.0}
Color_Azure :: Color{0.941176, 1.0, 1.0, 1.0}
Color_Beige :: Color{0.960784, 0.960784, 0.862745, 1.0}
Color_Bisque :: Color{1.0, 0.894118, 0.768627, 1.0}
Color_Black :: Color{0.0, 0.0, 0.0, 1.0}
Color_Blanched_Almond :: Color{1.0, 0.921569, 0.803922, 1.0}
Color_Blue :: Color{0.0, 0.0, 1.0, 1.0}
Color_Blue_Violet :: Color{0.541176, 0.168627, 0.886275, 1.0}
Color_Brown :: Color{0.647059, 0.164706, 0.164706, 1.0}
Color_Burly_Wood :: Color{0.870588, 0.721569, 0.529412, 1.0}
Color_Cadet_Blue :: Color{0.372549, 0.619608, 0.627451, 1.0}
Color_Chartreuse :: Color{0.498039, 1.0, 0.0, 1.0}
Color_Chocolate :: Color{0.823529, 0.411765, 0.117647, 1.0}
Color_Coral :: Color{1.0, 0.498039, 0.313725, 1.0}
Color_Cornflower_Blue :: Color{0.392157, 0.584314, 0.929412, 1.0}
Color_Cornsilk :: Color{1.0, 0.972549, 0.862745, 1.0}
Color_Crimson :: Color{0.862745, 0.0784314, 0.235294, 1.0}
Color_Cyan :: Color{0.0, 1.0, 1.0, 1.0}
Color_Dark_Blue :: Color{0.0, 0.0, 0.545098, 1.0}
Color_Dark_Cyan :: Color{0.0, 0.545098, 0.545098, 1.0}
Color_Dark_Goldenrod :: Color{0.721569, 0.529412, 0.0431373, 1.0}
Color_Dark_Gray :: Color{0.01, 0.01, 0.018, 1.0}
Color_Dark_Green :: Color{0.0, 0.392157, 0.0, 1.0}
Color_Dark_Khaki :: Color{0.741176, 0.717647, 0.419608, 1.0}
Color_Dark_Magenta :: Color{0.545098, 0.0, 0.545098, 1.0}
Color_Dark_Olive_Green :: Color{0.333333, 0.419608, 0.184314, 1.0}
Color_Dark_Orange :: Color{1.0, 0.54902, 0.0, 1.0}
Color_Dark_Orchid :: Color{0.6, 0.196078, 0.8, 1.0}
Color_Dark_Red :: Color{0.545098, 0.0, 0.0, 1.0}
Color_Dark_Salmon :: Color{0.913725, 0.372549, 0.478431, 1.0}
Color_Dark_Sea_Green :: Color{0.560784, 0.737255, 0.560784, 1.0}
Color_Dark_Slate_Blue :: Color{0.282353, 0.239216, 0.545098, 1.0}
Color_Dark_Slate_Gray :: Color{0.184314, 0.309804, 0.309804, 1.0}
Color_Dark_Turquoise :: Color{0.0, 0.807843, 0.819608, 1.0}
Color_Dark_Violet :: Color{0.580392, 0.0, 0.827451, 1.0}
Color_Deep_Pink :: Color{1.0, 0.0784314, 0.576471, 1.0}
Color_Deep_Sky_Blue :: Color{0.0, 0.74902, 1.0, 1.0}
Color_Dim_Gray :: Color{0.411765, 0.411765, 0.411765, 1.0}
Color_Dodger_Blue :: Color{0.117647, 0.564706, 1.0, 1.0}
Color_Firebrick :: Color{0.698039, 0.133333, 0.133333, 1.0}
Color_Floral_White :: Color{1.0, 0.980392, 0.941176, 1.0}
Color_Forest_Green :: Color{0.133333, 0.545098, 0.133333, 1.0}
Color_Fuchsia :: Color{1.0, 0.0, 1.0, 1.0}
Color_Gainsboro :: Color{0.862745, 0.862745, 0.862745, 1.0}
Color_Ghost_White :: Color{0.972549, 0.972549, 1.0, 1.0}
Color_Gold :: Color{1.0, 0.843137, 0.0, 1.0}
Color_Goldenrod :: Color{0.854902, 0.647059, 0.12549, 1.0}
Color_Gray :: Color{0.501961, 0.501961, 0.501961, 1.0}
Color_Green :: Color{0.0, 0.501961, 0.0, 1.0}
Color_Green_Yellow :: Color{0.678431, 1.0, 0.184314, 1.0}
Color_Honeydew :: Color{0.941176, 1.0, 0.941176, 1.0}
Color_Hot_Pink :: Color{1.0, 0.411765, 0.705882, 1.0}
Color_Indian_Red :: Color{0.803922, 0.360784, 0.360784, 1.0}
Color_Indigo :: Color{0.294118, 0.0, 0.509804, 1.0}
Color_Ivory :: Color{1.0, 1.0, 0.941176, 1.0}
Color_Khaki :: Color{0.941176, 0.901961, 0.54902, 1.0}
Color_Lavender :: Color{0.901961, 0.901961, 0.941176, 1.0}
Color_Lavender_Blush :: Color{1.0, 0.941176, 0.960784, 1.0}
Color_Lawn_Green :: Color{0.486275, 0.988235, 0.0, 1.0}
Color_Lemon_Chiffon :: Color{1.0, 0.980392, 0.803922, 1.0}
Color_Light_Blue :: Color{0.678431, 0.847059, 0.901961, 1.0}
Color_Light_Coral :: Color{0.941176, 0.501961, 0.501961, 1.0}
Color_Light_Cyan :: Color{0.878431, 1.0, 1.0, 1.0}
Color_Light_Goldenrod_Yellow :: Color{0.980392, 0.980392, 0.823529, 1.0}
Color_Light_Gray :: Color{0.827451, 0.827451, 0.827451, 1.0}
Color_Light_Green :: Color{0.564706, 0.933333, 0.564706, 1.0}
Color_Light_Pink :: Color{1.0, 0.713726, 0.756863, 1.0}
Color_Light_Salmon :: Color{1.0, 0.627451, 0.478431, 1.0}
Color_Light_Sea_Green :: Color{0.12549, 0.698039, 0.666667, 1.0}
Color_Light_Sky_Blue :: Color{0.529412, 0.807843, 0.937255, 1.0}
Color_Light_Slate_Gray :: Color{0.466667, 0.533333, 0.6, 1.0}
Color_Light_Steel_Blue :: Color{0.690196, 0.768627, 0.870588, 1.0}
Color_Light_Yellow :: Color{1.0, 1.0, 0.878431, 1.0}
Color_Lime :: Color{0.0, 1.0, 0.0, 1.0}
Color_Lime_Green :: Color{0.196078, 0.803922, 0.196078, 1.0}
Color_Linen :: Color{0.980392, 0.941176, 0.901961, 1.0}
Color_Magenta :: Color{1.0, 0.0, 1.0, 1.0}
Color_Maroon :: Color{0.501961, 0.0, 0.0, 1.0}
Color_Medium_Aquamarine :: Color{0.4, 0.803922, 0.666667, 1.0}
Color_Medium_Blue :: Color{0.0, 0.0, 0.803922, 1.0}
Color_Medium_Orchid :: Color{0.729412, 0.333333, 0.827451, 1.0}
Color_Medium_Purple :: Color{0.576471, 0.439216, 0.858824, 1.0}
Color_Medium_Sea_Green :: Color{0.235294, 0.701961, 0.443137, 1.0}
Color_Medium_Slate_Blue :: Color{0.482353, 0.407843, 0.933333, 1.0}
Color_Medium_Spring_Green :: Color{0.0, 0.980392, 0.603922, 1.0}
Color_Medium_Turquoise :: Color{0.282353, 0.819608, 0.8, 1.0}
Color_Medium_Violet_Red :: Color{0.780392, 0.0823529, 0.780392, 1.0}
Color_Midnight_Blue :: Color{0.0980392, 0.0980392, 0.439216, 1.0}
Color_Mint_Cream :: Color{0.960784, 0.980392, 0.968627, 1.0}
Color_Misty_Rose :: Color{1.0, 0.894118, 0.882353, 1.0}
Color_Moccasin :: Color{1.0, 0.894118, 0.709804, 1.0}
Color_Mono_Game_Orange :: Color{0.0, 0.235294, 0.905882, 1.0}
Color_Navajo_White :: Color{1.0, 0.870588, 0.678431, 1.0}
Color_Navy :: Color{0.0, 0.0, 0.501961, 1.0}
Color_Old_Lace :: Color{0.992157, 0.960784, 0.901961, 1.0}
Color_Olive :: Color{0.501961, 0.501961, 0.0, 1.0}
Color_Olive_Drab :: Color{0.419608, 0.556863, 0.137255, 1.0}
Color_Orange :: Color{1.0, 0.647059, 0.0, 1.0}
Color_Orange_Red :: Color{1.0, 0.270588, 0.0, 1.0}
Color_Orchid :: Color{0.854902, 0.439216, 0.839216, 1.0}
Color_Pale_Goldenrod :: Color{0.933333, 0.913725, 0.666667, 1.0}
Color_Pale_Green :: Color{0.596078, 0.984314, 0.596078, 1.0}
Color_Pale_Turquoise :: Color{0.686275, 0.933333, 0.933333, 1.0}
Color_Pale_Violet_Red :: Color{0.858824, 0.439216, 0.576471, 1.0}
Color_Papaya_Whip :: Color{1.0, 0.937255, 0.835294, 1.0}
Color_Peach_Puff :: Color{1.0, 0.854902, 0.72549, 1.0}
Color_Peru :: Color{0.803922, 0.521569, 0.247059, 1.0}
Color_Pink :: Color{1.0, 0.752941, 0.796078, 1.0}
Color_Plum :: Color{0.866667, 0.627451, 0.866667, 1.0}
Color_Powder_Blue :: Color{0.690196, 0.878431, 0.901961, 1.0}
Color_Purple :: Color{0.501961, 0.0, 0.501961, 1.0}
Color_Red :: Color{1.0, 0.0, 0.0, 1.0}
Color_Rosy_Brown :: Color{0.737255, 0.560784, 0.560784, 1.0}
Color_Royal_Blue :: Color{0.411765, 0.34902, 0.803922, 1.0}
Color_Saddle_Brown :: Color{0.0745098, 0.27451, 0.545098, 1.0}
Color_Salmon :: Color{0.980392, 0.501961, 0.447059, 1.0}
Color_Sandy_Brown :: Color{0.956863, 0.643137, 0.376471, 1.0}
Color_Sea_Green :: Color{0.180392, 0.545098, 0.341176, 1.0}
Color_Sea_Shell :: Color{1.0, 0.960784, 0.933333, 1.0}
Color_Sienna :: Color{0.627451, 0.321569, 0.176471, 1.0}
Color_Silver :: Color{0.752941, 0.752941, 0.752941, 1.0}
Color_Sky_Blue :: Color{0.529412, 0.807843, 0.921569, 1.0}
Color_Slate_Blue :: Color{0.415686, 0.352941, 0.803922, 1.0}
Color_Slate_Gray :: Color{0.439216, 0.501961, 0.564706, 1.0}
Color_Snow :: Color{1.0, 0.980392, 0.980392, 1.0}
Color_Spring_Green :: Color{0.0, 1.0, 0.498039, 1.0}
Color_Steel_Blue :: Color{0.27451, 0.509804, 0.705882, 1.0}
Color_Tan :: Color{0.823529, 0.705882, 0.54902, 1.0}
Color_Teal :: Color{0.0, 0.501961, 0.501961, 1.0}
Color_Thistle :: Color{0.847059, 0.74902, 0.847059, 1.0}
Color_Tomato :: Color{1.0, 0.388235, 0.278431, 1.0}
Color_Turquoise :: Color{0.25098, 0.878431, 0.819608, 1.0}
Color_Violet :: Color{0.933333, 0.509804, 0.933333, 1.0}
Color_Wheat :: Color{0.960784, 0.870588, 0.701961, 1.0}
Color_White :: Color{1.0, 1.0, 1.0, 1.0}
Color_White_Smoke :: Color{0.960784, 0.960784, 0.960784, 1.0}
Color_Yellow :: Color{1.0, 1.0, 0.0, 1.0}
Color_Yellow_Green :: Color{0.603922, 0.803922, 0.196078, 1.0}

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
