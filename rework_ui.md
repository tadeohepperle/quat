### Starting point

right now, all the UI elements are in one big buffer,
consisting of `Div`s and `Text`.
For Divs we store the number of children and
the number of descendents (`sk` = skipped), which is the number of the children + children of children recursively.

```
Div      sk: 6, ch: 4
  Text
  Div    sk: 2, ch: 2
    Div
    Text
  Div    sk: 0, ch: 0
  Div    sk: 0, ch: 0
Div      sk: 1, ch: 1
  Div
```

This means, we cannot "create" a UI element, e.g. a div and attach it as a child of another div later.
It is hard to create Ui elements that take other Ui elements as arguments.
Example: a frame with two elements a and b on each side and a divider between them like this:

```
--------------------------------------
oooooooooooooooooooooooooooooooooooooo
--------------------------------------
|               |o  o|               |
|       A       |o  o|      B        |
|               |o  o|               |
--------------------------------------
oooooooooooooooooooooooooooooooooooooo
--------------------------------------
```

currently, this would require:

```odin
_start_frame :: proc() {
    start_div("frame")
    horiz_line()
    start_div("middle_segment", main_axis = .X)
    start_div("pad",padding = {8,8,8,8})
}
_middle_divider_of_frame :: proc() {
    end_div() // end pad
    vert_line() // decorative element between A and B
    start_div("pad",padding = {8,8,8,8})
}
_end_frame :: proc() {
    end_div() // end pad
    end_div() // middle_segment
    horiz_line()
    end_div() // end frame
}

// then call:
_start_frame()
A()
_middle_divider_of_frame()
B()
_end_frame()
```

This is ugly and we would prefer something where the Ui elements are values, (ptrs to slab-allocated UI elements)

```odin
_frame :: proc(a: Ui, b: Ui) -> Ui {
    frame := div("frame")
    add(frame, horiz_line())
    middle := add(frame, Div{main_axis = .X})
    add(middle, padded(a))
    add(middle, vert_line())
    add(middle, padded(b))
    add(frame, horiz_line())
    return frame

    padded :: proc(a: Ui) -> Ui {
        res := div(Div{padding = {8,8,8,8}})
        add(res, a)
        return res
    }
}

```

This would require that a div() call returns a ptr and stores a children array somewhere.

We could even potentially save some space, because if text elements are smaller than divs, we can have a seperate slap allocators for each of them.

child lists can be temp allocated.

The produced tree needs to be easily walkable.

## Linked lists (const space vs arrays?)

arrays:

```odin


Ui :: union #no_nil{
    ^Div,
    ^Text
}

UiComputed :: union #no_nil{
    ^DivComputed,
    ^TextComputed
}

DivComputed :: struct {
    div: Div,
    children: [dynamic]Ui
}

```
