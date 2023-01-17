# utils.zig

This is a repo with miscellaneous code that I found useful while programming.

## `ArrayDeque(T)`

An array that supports `pushBack`, `pushFront`, `popBack`, and `popFront` in constant time.

## `Grid` and `ConstGrid`

A slice, but in two dimensions! I created this during Advent of Code.

Importantly, it has the concept of a row `stride` that allows making a rectangular
"slice". Combining this with the `set` and `copy` function makes
rendering to a bitmap easy, whether it is a grid of pixels or a
grid of characters.

In the future it may be extended to support arbitrary dimensions.