pub const ArrayDeque = @import("./array_deque.zig").ArrayDeque;

pub const grid = @import("./grid.zig");
pub const vec = @import("./vec.zig");
pub const mat = @import("./mat.zig");
pub const mat4 = @import("./mat4.zig");

// Reference the imported files so they are tested
comptime {
    _ = ArrayDeque;
    _ = grid;
    _ = vec;
    _ = mat;
    _ = mat4;
}
