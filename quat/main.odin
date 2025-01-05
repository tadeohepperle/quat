package quat

import "core:math"

main :: proc() {

	// print("Div", size_of(Div))
	// print("Text", size_of(Text))
	// print("CustomUi", size_of(CustomUi))
	// // print(size_of(Mat3))
	// // print("hello", cap(s), len(s))
	// print(align_of(Affine2), size_of(Affine2))
	// A := affine_from_vectors({2, 3}, {4, 5}, {2, 3}, {4, 2})
	B := affine_from_rotation(math.PI / 2, {1, 0}, {0, 0})
	print(B)
	// around, offset := affine_around_and_offset(B)
	// print("around: ", around, "offset: ", offset)
}
