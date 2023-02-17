const std = @import("std");

pub fn Grid(comptime T: type) type {
    return struct {
        data: []T,
        stride: usize,
        size: [2]usize,

        pub fn alloc(allocator: std.mem.Allocator, size: [2]usize) !@This() {
            const data = try allocator.alloc(T, size[0] * size[1]);
            return @This(){
                .data = data,
                .stride = size[0],
                .size = size,
            };
        }

        pub fn allocWithRowAlign(allocator: std.mem.Allocator, size: [2]usize, row_align: usize) !@This() {
            const row_len_aligned = std.mem.alignForward(size[0], row_align);
            const data = try allocator.alloc(T, row_len_aligned * size[1]);
            return @This(){
                .data = data,
                .stride = row_len_aligned,
                .size = size,
            };
        }

        pub fn dupe(allocator: std.mem.Allocator, src: ConstGrid(T)) !@This() {
            const data = try allocator.alloc(T, src.size[0] * src.size[1]);
            errdefer allocator.free(data);
            var this = @This(){
                .data = data,
                .stride = src.size[0],
                .size = src.size,
            };
            this.copy(src);
            return this;
        }

        pub fn free(this: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(this.data);
        }

        pub fn asConst(this: @This()) ConstGrid(T) {
            return ConstGrid(T){
                .data = this.data,
                .stride = this.stride,
                .size = this.size,
            };
        }

        pub fn copy(dest: @This(), src: ConstGrid(T)) void {
            std.debug.assert(src.size[0] >= dest.size[0]);
            std.debug.assert(src.size[1] >= dest.size[1]);

            var row_index: usize = 0;
            while (row_index < dest.size[1]) : (row_index += 1) {
                const dest_row = dest.data[row_index * dest.stride ..][0..dest.size[0]];
                const src_row = src.data[row_index * src.stride ..][0..src.size[0]];
                std.mem.copy(T, dest_row, src_row);
            }
        }

        pub fn set(this: @This(), value: T) void {
            std.debug.assert(this.stride >= this.size[0]);
            var row_index: usize = 0;
            while (row_index < this.size[1]) : (row_index += 1) {
                const row = this.data[row_index * this.stride ..][0..this.size[0]];
                std.mem.set(T, row, value);
            }
        }

        pub fn setPos(this: @This(), pos: [2]usize, value: T) void {
            std.debug.assert(pos[0] < this.size[0] and pos[1] < this.size[1]);
            std.debug.assert(this.stride >= this.size[0]);
            this.data[pos[1] * this.stride + pos[0]] = value;
        }

        pub fn getPosPtr(this: @This(), pos: [2]usize) *T {
            std.debug.assert(pos[0] < this.size[0] and pos[1] < this.size[1]);
            return &this.tiles[pos[1] * this.stride + pos[0]];
        }

        pub fn getPos(this: @This(), pos: [2]usize) T {
            return this.asConst().getPos(pos);
        }

        pub fn getRegion(this: @This(), pos: [2]usize, size: [2]usize) @This() {
            const posv: @Vector(2, usize) = pos;
            const sizev: @Vector(2, usize) = size;

            std.debug.assert(@reduce(.And, posv < this.size));
            std.debug.assert(@reduce(.And, posv + sizev <= this.size));

            const min_index = posv[1] * this.stride + posv[0];
            if (@reduce(.Or, sizev == @splat(2, @as(usize, 0)))) {
                return .{
                    .data = this.data[min_index..min_index],
                    .stride = this.stride,
                    .size = sizev,
                };
            }

            const max_pos = posv + sizev - @Vector(2, usize){ 1, 1 };

            const end_index = max_pos[1] * this.stride + max_pos[0] + 1;

            std.debug.assert(end_index - min_index >= size[0] * size[1]);

            return @This(){
                .data = this.data[min_index..end_index],
                .stride = this.stride,
                .size = size,
            };
        }

        pub fn flip(this: *@This(), flipOnAxis: [2]bool) void {
            // The x/y coordinate where we can stop copying. We should only need to swap half the pixels.
            const swap_to: [2]usize = if (flipOnAxis[1]) .{ this.size[0], this.size[1] / 2 } else if (flipOnAxis[0]) .{ this.size[0] / 2, this.size[1] } else return;

            var y0: usize = 0;
            while (y0 < swap_to[1]) : (y0 += 1) {
                const y1 = if (flipOnAxis[1]) this.size[1] - 1 - y0 else y0;
                const row0 = this.data[y0 * this.stride ..][0..this.size[0]];
                const row1 = this.data[y1 * this.stride ..][0..this.size[0]];
                var x0: usize = 0;
                while (x0 < swap_to[0]) : (x0 += 1) {
                    const x1 = if (flipOnAxis[0]) this.size[0] - 1 - x0 else x0;
                    std.mem.swap(T, &row0[x0], &row1[x1]);
                }
            }
        }

        pub fn addSaturating(this: @This(), other: ConstGrid(T)) void {
            std.debug.assert(other.size[0] >= this.size[0]);
            std.debug.assert(other.size[1] >= this.size[1]);

            var row_index: usize = 0;
            while (row_index < this.size[1]) : (row_index += 1) {
                const this_row = this.data[row_index * this.stride ..][0..this.size[0]];
                const other_row = other.data[row_index * other.stride ..][0..other.size[0]];
                for (this_row) |*value, index| {
                    value.* +|= other_row[index];
                }
            }
        }

        pub fn add(this: @This(), other: ConstGrid(T)) void {
            std.debug.assert(other.size[0] >= this.size[0]);
            std.debug.assert(other.size[1] >= this.size[1]);

            var row_index: usize = 0;
            while (row_index < this.size[1]) : (row_index += 1) {
                const this_row = this.data[row_index * this.stride ..][0..this.size[0]];
                const other_row = other.data[row_index * other.stride ..][0..other.size[0]];
                for (this_row) |*value, index| {
                    value.* += other_row[index];
                }
            }
        }

        pub fn sub(this: @This(), other: ConstGrid(T)) void {
            std.debug.assert(other.size[0] >= this.size[0]);
            std.debug.assert(other.size[1] >= this.size[1]);

            var row_index: usize = 0;
            while (row_index < this.size[1]) : (row_index += 1) {
                const this_row = this.data[row_index * this.stride ..][0..this.size[0]];
                const other_row = other.data[row_index * other.stride ..][0..other.size[0]];
                for (this_row) |*value, index| {
                    value.* -= other_row[index];
                }
            }
        }

        pub fn mul(this: @This(), other: ConstGrid(T)) void {
            std.debug.assert(other.size[0] >= this.size[0]);
            std.debug.assert(other.size[1] >= this.size[1]);

            var row_index: usize = 0;
            while (row_index < this.size[1]) : (row_index += 1) {
                const this_row = this.data[row_index * this.stride ..][0..this.size[0]];
                const other_row = other.data[row_index * other.stride ..][0..other.size[0]];
                for (this_row) |*value, index| {
                    value.* *= other_row[index];
                }
            }
        }

        pub fn mulScalar(this: @This(), scalar: T) void {
            var slice_iter = this.iterateSlices();
            while (slice_iter.next()) |slice| {
                for (slice) |*value| {
                    value.* *= scalar;
                }
            }
        }

        pub fn div(this: @This(), other: ConstGrid(T)) void {
            std.debug.assert(other.size[0] >= this.size[0]);
            std.debug.assert(other.size[1] >= this.size[1]);

            var row_index: usize = 0;
            while (row_index < this.size[1]) : (row_index += 1) {
                const this_row = this.data[row_index * this.stride ..][0..this.size[0]];
                const other_row = other.data[row_index * other.stride ..][0..other.size[0]];
                for (this_row) |*value, index| {
                    value.* /= other_row[index];
                }
            }
        }

        pub fn divScalar(this: @This(), scalar: T) void {
            var slice_iter = this.iterateSlices();
            while (slice_iter.next()) |slice| {
                for (slice) |*value| {
                    value.* /= scalar;
                }
            }
        }

        pub fn getRow(this: @This(), row: usize) []T {
            std.debug.assert(row < this.size[1]);
            return this.data[row * this.stride ..][0..this.size[0]];
        }

        pub const RowIterator = struct {
            grid: Grid(T),
            row: usize,

            pub fn next(this: *@This()) ?[]T {
                if (this.row >= this.grid.size[1]) return null;
                const value = this.grid.data[this.row * this.grid.stride ..][0..this.grid.size[0]];
                this.row += 1;
                return value;
            }
        };

        pub fn iterateRows(this: @This()) RowIterator {
            return RowIterator{
                .grid = this,
                .row = 0,
            };
        }

        pub const SliceIterator = struct {
            grid: Grid(T),

            pub fn next(this: *@This()) ?[]T {
                // TODO: when n-dimensional grids are implemented, handle multiple strides
                if (this.grid.size[1] <= 0) return null;
                if (this.grid.size[0] == this.grid.stride) {
                    // Return all data as a single slice
                    const slice = this.grid.data[0 .. this.grid.size[0] * this.grid.size[1]];
                    this.grid.size[1] = 0;
                    return slice;
                } else {
                    const slice = this.grid.data[0..this.grid.size[0]];
                    // Move grid down one row
                    this.grid.data = this.grid.data[this.grid.stride..];
                    this.grid.size[1] -= 1;
                    return slice;
                }
            }
        };

        /// Iterate over each slice. This is similar to `iterateRows`, except it will attempt
        /// to return the fewest slices possible. This is especially effective in cases where
        /// the stride and the width are equal; in which case it will return only one slice.
        pub fn iterateSlices(this: @This()) SliceIterator {
            return SliceIterator{ .grid = this };
        }
    };
}

pub fn ConstGrid(comptime T: type) type {
    return struct {
        data: []const T,
        stride: usize,
        size: [2]usize,

        pub fn free(this: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(this.data);
        }

        pub fn getPos(this: @This(), pos: [2]usize) T {
            std.debug.assert(pos[0] < this.size[0] and pos[1] < this.size[1]);
            return this.data[pos[1] * this.stride + pos[0]];
        }

        pub fn getRegion(this: @This(), pos: [2]usize, size: [2]usize) @This() {
            const posv: @Vector(2, usize) = pos;
            const sizev: @Vector(2, usize) = size;

            std.debug.assert(@reduce(.And, posv <= this.size));
            std.debug.assert(@reduce(.And, posv + sizev <= this.size));

            const min_index = posv[1] * this.stride + posv[0];
            if (@reduce(.Or, sizev == @splat(2, @as(usize, 0)))) {
                return .{
                    .data = this.data[min_index..min_index],
                    .stride = this.stride,
                    .size = sizev,
                };
            }

            const max_pos = posv + sizev - @Vector(2, usize){ 1, 1 };

            const end_index = max_pos[1] * this.stride + max_pos[0] + 1;

            std.debug.assert(end_index - min_index >= size[0] * size[1]);

            return @This(){
                .data = this.data[min_index..end_index],
                .stride = this.stride,
                .size = size,
            };
        }

        pub fn eql(a: @This(), b: @This()) bool {
            if (!std.mem.eql(usize, &a.size, &b.size)) return false;

            var map_iterator = a.iterateRows();
            var piece_iterator = b.iterateRows();
            var row_index: usize = 0;
            while (row_index < a.size[1]) : (row_index += 1) {
                const row_a = map_iterator.next().?;
                const row_b = piece_iterator.next().?;

                if (!std.mem.eql(T, row_a, row_b)) return false;
            }

            return true;
        }

        pub const RowIterator = struct {
            grid: ConstGrid(T),
            row: usize,

            pub fn next(this: *@This()) ?[]const T {
                if (this.row >= this.grid.size[1]) return null;
                const value = this.grid.data[this.row * this.grid.stride ..][0..this.grid.size[0]];
                this.row += 1;
                return value;
            }
        };

        pub fn iterateRows(this: @This()) RowIterator {
            return RowIterator{
                .grid = this,
                .row = 0,
            };
        }

        pub const ElementIterator = struct {
            grid: ConstGrid(T),
            pos: [2]usize,

            pub fn next(this: *@This()) ?T {
                if (this.pos[0] >= this.grid.size[0]) {
                    this.pos[0] = 0;
                    this.pos[1] += 1;
                }
                if (this.pos[1] >= this.grid.size[1]) return null;
                const value = this.grid.getPos(this.pos);
                this.pos[0] += 1;
                return value;
            }
        };

        pub fn iterateElements(this: @This()) ElementIterator {
            return ElementIterator{
                .grid = this,
                .pos = .{ 0, 0 },
            };
        }
    };
}

test "Grid(f32).mul" {
    var grid = try Grid(f32).alloc(std.testing.allocator, .{ 3, 3 });
    defer grid.free(std.testing.allocator);

    for (grid.data) |*elem, index| {
        elem.* = @intToFloat(f32, index);
    }

    grid.mul(.{
        .data = &.{
            1,  1,  2,
            3,  5,  8,
            14, 22, 36,
        },
        .size = .{ 3, 3 },
        .stride = 3,
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 1, 4, 9, 20, 40, 84, 154, 288 },
        grid.data,
    );
}

test "Grid(f32).mulScalar" {
    var grid = try Grid(f32).alloc(std.testing.allocator, .{ 3, 3 });
    defer grid.free(std.testing.allocator);

    for (grid.data) |*elem, index| {
        elem.* = @intToFloat(f32, index);
    }

    grid.mulScalar(10);

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 10, 20, 30, 40, 50, 60, 70, 80 },
        grid.data,
    );
}

test "Grid(f32).div" {
    var grid = try Grid(f32).alloc(std.testing.allocator, .{ 3, 3 });
    defer grid.free(std.testing.allocator);

    for (grid.data) |*elem, index| {
        elem.* = @intToFloat(f32, index);
    }

    grid.div(.{
        .data = &.{
            1,  1,  2,
            3,  5,  8,
            14, 22, 36,
        },
        .size = .{ 3, 3 },
        .stride = 3,
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 1, 1, 1, 0.8, 0.625, 0.42857142857142855, 0.3181818181818182, 0.2222222222222222 },
        grid.data,
    );
}

test "Grid(f32).divScalar" {
    var grid = try Grid(f32).alloc(std.testing.allocator, .{ 3, 3 });
    defer grid.free(std.testing.allocator);

    for (grid.data) |*elem, index| {
        elem.* = @intToFloat(f32, index);
    }

    grid.divScalar(10);

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 },
        grid.data,
    );
}

test "iterateSlices returns 1 slice for a contiguous grid" {
    var contiguous_grid = try Grid(f32).alloc(std.testing.allocator, .{ 32, 32 });
    defer contiguous_grid.free(std.testing.allocator);

    const expected_len = contiguous_grid.size[0] * contiguous_grid.size[1];

    var iter = contiguous_grid.iterateSlices();
    const slice = iter.next() orelse return error.UnexpectedNull;

    try std.testing.expectEqual(@as(?[]f32, null), iter.next());
    try std.testing.expectEqual(expected_len, slice.len);
}

test "iterateSlices returns multiple slices for a split grid" {
    var split_grid = try Grid(f32).allocWithRowAlign(std.testing.allocator, .{ 32, 32 }, 64);
    defer split_grid.free(std.testing.allocator);

    const expected_total_len = split_grid.size[0] * split_grid.size[1];
    var total_len: usize = 0;
    var number_of_slices: usize = 0;

    var iter = split_grid.iterateSlices();
    while (iter.next()) |slice| {
        total_len += slice.len;
        number_of_slices += 1;
    }

    try std.testing.expect(number_of_slices > 1);
    try std.testing.expectEqual(expected_total_len, total_len);
}
