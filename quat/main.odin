package quat

main :: proc() {

	// print("Div", size_of(Div))
	// print("Text", size_of(Text))
	// print("CustomUi", size_of(CustomUi))
	// // print(size_of(Mat3))
	// // print("hello", cap(s), len(s))

	A := affine_create({2, 3}, {4, 5}, {2, 3}, {4, 2})
	p := Vec2{2, 3}
	print(p, "->", affine_apply(A, p))
}
