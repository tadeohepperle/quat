package quat
import "vendor:glfw"

import "core:fmt"
import "core:strings"
import "core:time"

DOUBLE_CLICK_MAX_INTERVAL_MS :: 280
PressFlags :: bit_set[PressFlag;u8]

PressFlag :: enum u8 {
	Pressed,
	JustPressed,
	JustRepeated,
	JustReleased,
}

MouseButton :: enum {
	Left,
	Right,
	Middle,
}

glfw_int_to_mouse_button :: proc "contextless" (glfw_mouse_button: i32) -> Maybe(MouseButton) {
	switch glfw_mouse_button {
	case glfw.MOUSE_BUTTON_LEFT:
		return .Left
	case glfw.MOUSE_BUTTON_RIGHT:
		return .Right
	case glfw.MOUSE_BUTTON_MIDDLE:
		return .Middle
	case:
		return nil
	}
}

glfw_int_to_key :: proc "contextless" (glfw_key: i32) -> Maybe(Key) {
	switch glfw_key {
	case glfw.KEY_0:
		return ._0
	case glfw.KEY_1:
		return ._1
	case glfw.KEY_2:
		return ._2
	case glfw.KEY_3:
		return ._3
	case glfw.KEY_4:
		return ._4
	case glfw.KEY_5:
		return ._5
	case glfw.KEY_6:
		return ._6
	case glfw.KEY_7:
		return ._7
	case glfw.KEY_8:
		return ._8
	case glfw.KEY_9:
		return ._9
	case glfw.KEY_A:
		return .A
	case glfw.KEY_B:
		return .B
	case glfw.KEY_C:
		return .C
	case glfw.KEY_D:
		return .D
	case glfw.KEY_E:
		return .E
	case glfw.KEY_F:
		return .F
	case glfw.KEY_G:
		return .G
	case glfw.KEY_H:
		return .H
	case glfw.KEY_I:
		return .I
	case glfw.KEY_J:
		return .J
	case glfw.KEY_K:
		return .K
	case glfw.KEY_L:
		return .L
	case glfw.KEY_M:
		return .M
	case glfw.KEY_N:
		return .N
	case glfw.KEY_O:
		return .O
	case glfw.KEY_P:
		return .P
	case glfw.KEY_Q:
		return .Q
	case glfw.KEY_R:
		return .R
	case glfw.KEY_S:
		return .S
	case glfw.KEY_T:
		return .T
	case glfw.KEY_U:
		return .U
	case glfw.KEY_V:
		return .V
	case glfw.KEY_W:
		return .W
	case glfw.KEY_X:
		return .X
	case glfw.KEY_Y:
		return .Y
	case glfw.KEY_Z:
		return .Z
	case glfw.KEY_SPACE:
		return .SPACE
	case glfw.KEY_APOSTROPHE:
		return .APOSTROPHE
	case glfw.KEY_COMMA:
		return .COMMA
	case glfw.KEY_MINUS:
		return .MINUS
	case glfw.KEY_PERIOD:
		return .PERIOD
	case glfw.KEY_SLASH:
		return .SLASH
	case glfw.KEY_SEMICOLON:
		return .SEMICOLON
	case glfw.KEY_EQUAL:
		return .EQUAL
	case glfw.KEY_LEFT_BRACKET:
		return .LEFT_BRACKET
	case glfw.KEY_BACKSLASH:
		return .BACKSLASH
	case glfw.KEY_RIGHT_BRACKET:
		return .RIGHT_BRACKET
	case glfw.KEY_GRAVE_ACCENT:
		return .GRAVE_ACCENT
	case glfw.KEY_WORLD_1:
		return .WORLD_1
	case glfw.KEY_WORLD_2:
		return .WORLD_2
	case glfw.KEY_ESCAPE:
		return .ESCAPE
	case glfw.KEY_ENTER:
		return .ENTER
	case glfw.KEY_TAB:
		return .TAB
	case glfw.KEY_BACKSPACE:
		return .BACKSPACE
	case glfw.KEY_INSERT:
		return .INSERT
	case glfw.KEY_DELETE:
		return .DELETE
	case glfw.KEY_RIGHT:
		return .RIGHT
	case glfw.KEY_LEFT:
		return .LEFT
	case glfw.KEY_DOWN:
		return .DOWN
	case glfw.KEY_UP:
		return .UP
	case glfw.KEY_PAGE_UP:
		return .PAGE_UP
	case glfw.KEY_PAGE_DOWN:
		return .PAGE_DOWN
	case glfw.KEY_HOME:
		return .HOME
	case glfw.KEY_END:
		return .END
	case glfw.KEY_CAPS_LOCK:
		return .CAPS_LOCK
	case glfw.KEY_SCROLL_LOCK:
		return .SCROLL_LOCK
	case glfw.KEY_NUM_LOCK:
		return .NUM_LOCK
	case glfw.KEY_PRINT_SCREEN:
		return .PRINT_SCREEN
	case glfw.KEY_PAUSE:
		return .PAUSE
	case glfw.KEY_F1:
		return .F1
	case glfw.KEY_F2:
		return .F2
	case glfw.KEY_F3:
		return .F3
	case glfw.KEY_F4:
		return .F4
	case glfw.KEY_F5:
		return .F5
	case glfw.KEY_F6:
		return .F6
	case glfw.KEY_F7:
		return .F7
	case glfw.KEY_F8:
		return .F8
	case glfw.KEY_F9:
		return .F9
	case glfw.KEY_F10:
		return .F10
	case glfw.KEY_F11:
		return .F11
	case glfw.KEY_F12:
		return .F12
	case glfw.KEY_F13:
		return .F13
	case glfw.KEY_F14:
		return .F14
	case glfw.KEY_F15:
		return .F15
	case glfw.KEY_F16:
		return .F16
	case glfw.KEY_F17:
		return .F17
	case glfw.KEY_F18:
		return .F18
	case glfw.KEY_F19:
		return .F19
	case glfw.KEY_F20:
		return .F20
	case glfw.KEY_F21:
		return .F21
	case glfw.KEY_F22:
		return .F22
	case glfw.KEY_F23:
		return .F23
	case glfw.KEY_F24:
		return .F24
	case glfw.KEY_F25:
		return .F25
	case glfw.KEY_KP_0:
		return .KP_0
	case glfw.KEY_KP_1:
		return .KP_1
	case glfw.KEY_KP_2:
		return .KP_2
	case glfw.KEY_KP_3:
		return .KP_3
	case glfw.KEY_KP_4:
		return .KP_4
	case glfw.KEY_KP_5:
		return .KP_5
	case glfw.KEY_KP_6:
		return .KP_6
	case glfw.KEY_KP_7:
		return .KP_7
	case glfw.KEY_KP_8:
		return .KP_8
	case glfw.KEY_KP_9:
		return .KP_9
	case glfw.KEY_KP_DECIMAL:
		return .KP_DECIMAL
	case glfw.KEY_KP_DIVIDE:
		return .KP_DIVIDE
	case glfw.KEY_KP_MULTIPLY:
		return .KP_MULTIPLY
	case glfw.KEY_KP_SUBTRACT:
		return .KP_SUBTRACT
	case glfw.KEY_KP_ADD:
		return .KP_ADD
	case glfw.KEY_KP_ENTER:
		return .KP_ENTER
	case glfw.KEY_KP_EQUAL:
		return .KP_EQUAL
	case glfw.KEY_LEFT_SHIFT:
		return .LEFT_SHIFT
	case glfw.KEY_LEFT_CONTROL:
		return .LEFT_CONTROL
	case glfw.KEY_LEFT_ALT:
		return .LEFT_ALT
	case glfw.KEY_LEFT_SUPER:
		return .LEFT_SUPER
	case glfw.KEY_RIGHT_SHIFT:
		return .RIGHT_SHIFT
	case glfw.KEY_RIGHT_CONTROL:
		return .RIGHT_CONTROL
	case glfw.KEY_RIGHT_ALT:
		return .RIGHT_ALT
	case glfw.KEY_RIGHT_SUPER:
		return .RIGHT_SUPER
	case glfw.KEY_MENU:
		return .MENU
	case:
		return nil
	}
}
Key :: enum i32 {
	_0            = glfw.KEY_0,
	_1            = glfw.KEY_1,
	_2            = glfw.KEY_2,
	_3            = glfw.KEY_3,
	_4            = glfw.KEY_4,
	_5            = glfw.KEY_5,
	_6            = glfw.KEY_6,
	_7            = glfw.KEY_7,
	_8            = glfw.KEY_8,
	_9            = glfw.KEY_9,
	A             = glfw.KEY_A,
	B             = glfw.KEY_B,
	C             = glfw.KEY_C,
	D             = glfw.KEY_D,
	E             = glfw.KEY_E,
	F             = glfw.KEY_F,
	G             = glfw.KEY_G,
	H             = glfw.KEY_H,
	I             = glfw.KEY_I,
	J             = glfw.KEY_J,
	K             = glfw.KEY_K,
	L             = glfw.KEY_L,
	M             = glfw.KEY_M,
	N             = glfw.KEY_N,
	O             = glfw.KEY_O,
	P             = glfw.KEY_P,
	Q             = glfw.KEY_Q,
	R             = glfw.KEY_R,
	S             = glfw.KEY_S,
	T             = glfw.KEY_T,
	U             = glfw.KEY_U,
	V             = glfw.KEY_V,
	W             = glfw.KEY_W,
	X             = glfw.KEY_X,
	Y             = glfw.KEY_Y,
	Z             = glfw.KEY_Z,
	SPACE         = glfw.KEY_SPACE,
	APOSTROPHE    = glfw.KEY_APOSTROPHE,
	COMMA         = glfw.KEY_COMMA,
	MINUS         = glfw.KEY_MINUS,
	PERIOD        = glfw.KEY_PERIOD,
	SLASH         = glfw.KEY_SLASH,
	SEMICOLON     = glfw.KEY_SEMICOLON,
	EQUAL         = glfw.KEY_EQUAL,
	LEFT_BRACKET  = glfw.KEY_LEFT_BRACKET,
	BACKSLASH     = glfw.KEY_BACKSLASH,
	RIGHT_BRACKET = glfw.KEY_RIGHT_BRACKET,
	GRAVE_ACCENT  = glfw.KEY_GRAVE_ACCENT,
	WORLD_1       = glfw.KEY_WORLD_1,
	WORLD_2       = glfw.KEY_WORLD_2,
	ESCAPE        = glfw.KEY_ESCAPE,
	ENTER         = glfw.KEY_ENTER,
	TAB           = glfw.KEY_TAB,
	BACKSPACE     = glfw.KEY_BACKSPACE,
	INSERT        = glfw.KEY_INSERT,
	DELETE        = glfw.KEY_DELETE,
	RIGHT         = glfw.KEY_RIGHT,
	LEFT          = glfw.KEY_LEFT,
	DOWN          = glfw.KEY_DOWN,
	UP            = glfw.KEY_UP,
	PAGE_UP       = glfw.KEY_PAGE_UP,
	PAGE_DOWN     = glfw.KEY_PAGE_DOWN,
	HOME          = glfw.KEY_HOME,
	END           = glfw.KEY_END,
	CAPS_LOCK     = glfw.KEY_CAPS_LOCK,
	SCROLL_LOCK   = glfw.KEY_SCROLL_LOCK,
	NUM_LOCK      = glfw.KEY_NUM_LOCK,
	PRINT_SCREEN  = glfw.KEY_PRINT_SCREEN,
	PAUSE         = glfw.KEY_PAUSE,
	F1            = glfw.KEY_F1,
	F2            = glfw.KEY_F2,
	F3            = glfw.KEY_F3,
	F4            = glfw.KEY_F4,
	F5            = glfw.KEY_F5,
	F6            = glfw.KEY_F6,
	F7            = glfw.KEY_F7,
	F8            = glfw.KEY_F8,
	F9            = glfw.KEY_F9,
	F10           = glfw.KEY_F10,
	F11           = glfw.KEY_F11,
	F12           = glfw.KEY_F12,
	F13           = glfw.KEY_F13,
	F14           = glfw.KEY_F14,
	F15           = glfw.KEY_F15,
	F16           = glfw.KEY_F16,
	F17           = glfw.KEY_F17,
	F18           = glfw.KEY_F18,
	F19           = glfw.KEY_F19,
	F20           = glfw.KEY_F20,
	F21           = glfw.KEY_F21,
	F22           = glfw.KEY_F22,
	F23           = glfw.KEY_F23,
	F24           = glfw.KEY_F24,
	F25           = glfw.KEY_F25,
	KP_0          = glfw.KEY_KP_0,
	KP_1          = glfw.KEY_KP_1,
	KP_2          = glfw.KEY_KP_2,
	KP_3          = glfw.KEY_KP_3,
	KP_4          = glfw.KEY_KP_4,
	KP_5          = glfw.KEY_KP_5,
	KP_6          = glfw.KEY_KP_6,
	KP_7          = glfw.KEY_KP_7,
	KP_8          = glfw.KEY_KP_8,
	KP_9          = glfw.KEY_KP_9,
	KP_DECIMAL    = glfw.KEY_KP_DECIMAL,
	KP_DIVIDE     = glfw.KEY_KP_DIVIDE,
	KP_MULTIPLY   = glfw.KEY_KP_MULTIPLY,
	KP_SUBTRACT   = glfw.KEY_KP_SUBTRACT,
	KP_ADD        = glfw.KEY_KP_ADD,
	KP_ENTER      = glfw.KEY_KP_ENTER,
	KP_EQUAL      = glfw.KEY_KP_EQUAL,
	LEFT_SHIFT    = glfw.KEY_LEFT_SHIFT,
	LEFT_CONTROL  = glfw.KEY_LEFT_CONTROL,
	LEFT_ALT      = glfw.KEY_LEFT_ALT,
	LEFT_SUPER    = glfw.KEY_LEFT_SUPER,
	RIGHT_SHIFT   = glfw.KEY_RIGHT_SHIFT,
	RIGHT_CONTROL = glfw.KEY_RIGHT_CONTROL,
	RIGHT_ALT     = glfw.KEY_RIGHT_ALT,
	RIGHT_SUPER   = glfw.KEY_RIGHT_SUPER,
	MENU          = glfw.KEY_MENU,
}
