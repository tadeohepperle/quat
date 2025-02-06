package quat

import "core:math"

@(private)
C1: f32 : 1.70158
@(private)
C2: f32 : C1 * 1.525
@(private)
C3: f32 : C1 + 1.0
@(private)
C4: f32 : (2.0 * math.PI) / 3.0
@(private)
C5: f32 : (2.0 * math.PI) / 4.5
pow2 :: #force_inline proc "contextless" (t: f32) -> f32 {
	return t * t
}
pow3 :: #force_inline proc "contextless" (t: f32) -> f32 {
	return t * t * t
}

// https://easings.net/#easeInBack
ease_back_in :: proc "contextless" (t: f32) -> f32 {
	return C3 * t * t * t - C1 * t * t
}
// https://easings.net/#easeOutBack
ease_back_out :: proc "contextless" (t: f32) -> f32 {
	return 1.0 + C3 * pow3(t - 1.0) + C1 * pow2(t - 1.0)
}
// https://easings.net/#easeInOutBack
ease_back_in_out :: proc "contextless" (t: f32) -> f32 {
	if t < 0.5 {
		return (pow2((2.0 * t)) * ((C2 + 1.0) * 2.0 * t - C2)) / 2.0
	} else {
		return (pow2(2.0 * t - 2.0) * ((C2 + 1.0) * (t * 2.0 - 2.0) + C2) + 2.0) / 2.0
	}
}
// https://easings.net/#easeInElastic
ease_elastic_in :: proc "contextless" (t: f32) -> f32 {
	if t <= 0.0 {
		return 0.0
	} else if 1.0 <= t {
		return 1.0
	} else {
		return math.pow_f32(-2, 10.0 * t - 10.0) * math.sin(((t * 10.0 - 10.75) * C4))
	}
}
// https://easings.net/#easeOutElastic
ease_elastic_out :: proc "contextless" (t: f32) -> f32 {
	if t <= 0.0 {
		return 0.0
	} else if 1.0 <= t {
		return 1.0
	} else {
		return math.pow_f32(2, -10.0 * t) * sin((t * 10.0 - 0.75) * C4) + 1.0
	}
}
// https://easings.net/#easeInOutElastic
ease_elastic_in_out :: proc "contextless" (t: f32) -> f32 {
	if t <= 0.0 {
		return 0.0
	} else if 1.0 <= t {
		return 1.0
	} else if t < 0.5 {
		return -(math.pow_f32(2, 20.0 * t - 10.0) * math.sin((20.0 * t - 11.125) * C5)) / 2.0
	} else {
		return (math.pow_f32(2, -20.0 * t + 10.0) * math.sin((20.0 * t - 11.125) * C5)) / 2.0 + 1.0
	}
}
// https://easings.net/#easeInCubic
ease_cubic_in :: proc "contextless" (t: f32) -> f32 {
	return t * t * t
}
// https://easings.net/#easeOutCubic
ease_cubic_out :: proc "contextless" (t: f32) -> f32 {
	return 1.0 - pow3(1.0 - t)
}
// https://easings.net/#easeInOutCubic
ease_cubic_in_out :: proc "contextless" (t: f32) -> f32 {
	if t < 0.5 {
		return 4.0 * t * t * t
	} else {
		return 1.0 - pow3(-2.0 * t + 2.0) / 2.0
	}
}
