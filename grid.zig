const std = @import("std");

pub fn posToIndex(comptime D: usize, strides: [D - 1]usize, pos: [D]usize) usize {
    var index: usize = 0;
    for (pos, [_]usize{1} ++ strides) |p, stride| {
        index += p * stride;
    }
    return index;
}

pub fn Grid(comptime D: usize, comptime T: type) type {
    return struct {
        data: [*]T,
        size: [D]usize,
        stride: [D - 1]usize,

        pub fn alloc(allocator: std.mem.Allocator, size: [D]usize) !@This() {
            var len: usize = 1;
            for (size) |s| {
                len *= s;
            }
            const data = try allocator.alloc(T, len);

            var strides: [D]usize = undefined;
            strides[0] = 1;
            for (strides[1..], strides[0 .. D - 1], size[0 .. D - 1]) |*stride, prev_stride, s| {
                stride.* = prev_stride * s;
            }
            return @This(){
                .data = data.ptr,
                .stride = strides[1..].*,
                .size = size,
            };
        }

        pub fn allocWithRowAlign(allocator: std.mem.Allocator, size: [D]usize, row_align: [D - 1]usize) !@This() {
            var size_aligned: [D - 1]usize = undefined;
            for (&size_aligned, size[0 .. D - 1], row_align) |*sa, s, r| {
                sa.* = std.mem.alignForward(s, r);
            }

            var len: usize = 1;
            for (size_aligned) |s| {
                len *= s;
            }
            const data = try allocator.alloc(T, len);

            var strides: [D]usize = undefined;
            strides[0] = 1;
            for (strides[1..], strides[0 .. D - 1], size_aligned[0 .. D - 1]) |*stride, prev_stride, s| {
                stride.* = prev_stride * s;
            }
            return @This(){
                .data = data.ptr,
                .stride = strides[1..].*,
                .size = size,
            };
        }

        pub fn dupe(allocator: std.mem.Allocator, src: ConstGrid(D, T)) !@This() {
            var this = try alloc(allocator, src.size);
            this.copy(src);
            return this;
        }

        pub fn free(this: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(this.getSliceOfData());
        }

        pub fn asConst(this: @This()) ConstGrid(D, T) {
            return ConstGrid(D, T){
                .data = this.data,
                .stride = this.stride,
                .size = this.size,
            };
        }

        pub fn copy(dest: @This(), src: ConstGrid(D, T)) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &src.size));

            var iter = dest.iterate();
            while (iter.next()) |e| {
                e.ptr.* = src.getPos(e.pos);
            }
        }

        pub fn set(dest: @This(), value: T) void {
            var iter = dest.iterate();
            while (iter.next()) |e| {
                e.ptr.* = value;
            }
        }

        pub fn setPos(this: @This(), pos: [D]usize, value: T) void {
            const posv = @as(@Vector(D, usize), pos);
            std.debug.assert(@reduce(.And, posv < this.size));

            this.data[posToIndex(D, this.stride, pos)] = value;
        }

        pub fn getPosPtr(this: @This(), pos: [D]usize) *T {
            const posv = @as(@Vector(D, usize), pos);
            std.debug.assert(@reduce(.And, posv < this.size));

            return &this.data[posToIndex(D, this.stride, pos)];
        }

        pub fn getPos(this: @This(), pos: [D]usize) T {
            return this.asConst().getPos(pos);
        }

        pub fn getRow(this: @This(), row: usize) []T {
            return this.data[this.stride[0] * row .. this.stride[0] * row + this.size[0]];
        }

        pub fn getRegion(this: @This(), pos: [D]usize, size: [D]usize) @This() {
            const posv: @Vector(D, usize) = pos;
            const sizev: @Vector(D, usize) = size;

            std.debug.assert(@reduce(.And, posv < this.size));
            std.debug.assert(@reduce(.And, posv + sizev <= this.size));

            const min_index = posToIndex(D, this.stride, pos);
            if (@reduce(.Or, sizev == @splat(D, @as(usize, 0)))) {
                return .{
                    .data = this.data[min_index..min_index].ptr,
                    .stride = this.stride,
                    .size = sizev,
                };
            }

            const max_pos = posv + sizev - @splat(D, @as(usize, 1));

            const end_index = posToIndex(D, this.stride, max_pos);

            std.debug.assert(end_index - min_index + 1 >= @reduce(.Mul, sizev));

            return @This(){
                .data = this.data[min_index..end_index].ptr,
                .stride = this.stride,
                .size = size,
            };
        }

        pub fn flip(this: *@This(), flipOnAxis: [2]bool) void {
            std.debug.assert(D == 2);
            // The x/y coordinate where we can stop copying. We should only need to swap half the pixels.
            const swap_to: [2]usize = if (flipOnAxis[1]) .{ this.size[0], this.size[1] / 2 } else if (flipOnAxis[0]) .{ this.size[0] / 2, this.size[1] } else return;

            for (0..swap_to[1]) |y0| {
                const y1 = if (flipOnAxis[1]) this.size[1] - 1 - y0 else y0;
                const row0 = this.data[y0 * this.stride ..][0..this.size[0]];
                const row1 = this.data[y1 * this.stride ..][0..this.size[0]];
                for (0..swap_to[0]) |x0| {
                    const x1 = if (flipOnAxis[0]) this.size[0] - 1 - x0 else x0;
                    std.mem.swap(T, &row0[x0], &row1[x1]);
                }
            }
        }

        pub fn add(dest: @This(), a: ConstGrid(D, T), b: ConstGrid(D, T)) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
            std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

            for (0..dest.size[1]) |row| {
                const a_slice = a.data[a.stride[0] * row .. a.stride[0] * row + a.size[1]];
                const b_slice = b.data[b.stride[0] * row .. b.stride[0] * row + b.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, a_slice, b_slice) |*rv, ra, rb| {
                    rv.* = ra + rb;
                }
            }
        }

        pub fn addSaturating(dest: @This(), a: ConstGrid(D, T), b: ConstGrid(D, T)) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
            std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

            for (0..dest.size[1]) |row| {
                const a_slice = a.data[a.stride[0] * row .. a.stride[0] * row + a.size[1]];
                const b_slice = b.data[b.stride[0] * row .. b.stride[0] * row + b.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, a_slice, b_slice) |*rv, ra, rb| {
                    rv.* = ra +| rb;
                }
            }
        }

        pub fn sub(dest: @This(), a: ConstGrid(D, T), b: ConstGrid(D, T)) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
            std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

            for (0..dest.size[1]) |row| {
                const a_slice = a.data[a.stride[0] * row .. a.stride[0] * row + a.size[1]];
                const b_slice = b.data[b.stride[0] * row .. b.stride[0] * row + b.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, a_slice, b_slice) |*rv, ra, rb| {
                    rv.* = ra - rb;
                }
            }
        }

        pub fn subSaturating(dest: @This(), a: ConstGrid(D, T), b: ConstGrid(D, T)) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
            std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

            for (0..dest.size[1]) |row| {
                const a_slice = a.data[a.stride[0] * row .. a.stride[0] * row + a.size[1]];
                const b_slice = b.data[b.stride[0] * row .. b.stride[0] * row + b.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, a_slice, b_slice) |*rv, ra, rb| {
                    rv.* = ra -| rb;
                }
            }
        }

        pub fn mul(dest: @This(), a: ConstGrid(D, T), b: ConstGrid(D, T)) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
            std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

            for (0..dest.size[1]) |row| {
                const a_slice = a.data[a.stride[0] * row .. a.stride[0] * row + a.size[1]];
                const b_slice = b.data[b.stride[0] * row .. b.stride[0] * row + b.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, a_slice, b_slice) |*rv, ra, rb| {
                    rv.* = ra * rb;
                }
            }
        }

        pub fn mulScalar(dest: @This(), src: ConstGrid(D, T), scalar: T) void {
            for (0..dest.size[1]) |row| {
                const src_slice = src.data[src.stride[0] * row .. src.stride[0] * row + src.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, src_slice) |*rd, rs| {
                    rd.* = rs * scalar;
                }
            }
        }

        pub fn div(dest: @This(), a: ConstGrid(D, T), b: ConstGrid(D, T)) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &a.size));
            std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));

            for (0..dest.size[1]) |row| {
                const a_slice = a.data[a.stride[0] * row .. a.stride[0] * row + a.size[1]];
                const b_slice = b.data[b.stride[0] * row .. b.stride[0] * row + b.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, a_slice, b_slice) |*rv, ra, rb| {
                    rv.* = ra / rb;
                }
            }
        }

        pub fn divScalar(dest: @This(), src: ConstGrid(D, T), scalar: T) void {
            for (0..dest.size[1]) |row| {
                const src_slice = src.data[src.stride[0] * row .. src.stride[0] * row + src.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, src_slice) |*rd, rs| {
                    rd.* = rs / scalar;
                }
            }
        }

        pub fn sqrt(dest: @This(), src: ConstGrid(D, T)) void {
            for (0..dest.size[1]) |row| {
                const src_slice = src.data[src.stride[0] * row .. src.stride[0] * row + src.size[1]];
                const dest_slice = dest.data[dest.stride[0] * row .. dest.stride[0] * row + dest.size[1]];

                for (dest_slice, src_slice) |*rd, rs| {
                    rd.* = @sqrt(rs);
                }
            }
        }

        pub fn withExtraDimensions(this: @This(), comptime EXTRA_DIMS: usize) Grid(D + EXTRA_DIMS, T) {
            return Grid(D + EXTRA_DIMS, T){
                .data = this.data,
                .stride = this.stride ++ [_]usize{undefined} ** EXTRA_DIMS,
                .size = this.size ++ [_]usize{1} ** EXTRA_DIMS,
            };
        }

        pub const Iterator = struct {
            grid: Grid(D, T),
            pos: [D]usize,

            pub const Entry = struct {
                pos: [D]usize,
                ptr: *T,
            };

            pub fn next(this: *@This()) ?Entry {
                for (this.pos[0 .. D - 1], this.pos[1..D], this.grid.size[0 .. D - 1]) |*pos, *next_pos, size| {
                    if (pos.* >= size) {
                        pos.* = 0;
                        next_pos.* += 1;
                    }
                }
                if (this.pos[D - 1] >= this.grid.size[D - 1]) {
                    return null;
                }
                const entry = Entry{
                    .pos = this.pos,
                    .ptr = this.grid.getPosPtr(this.pos),
                };
                this.pos[0] += 1;
                return entry;
            }
        };

        pub fn iterate(this: @This()) Iterator {
            return Iterator{
                .grid = this,
                .pos = [_]usize{0} ** D,
            };
        }

        fn getSliceOfData(this: @This()) []T {
            return this.data[0 .. this.stride[D - 2] * this.size[D - 1]];
        }
    };
}

pub fn ConstGrid(comptime D: usize, comptime T: type) type {
    return struct {
        data: [*]const T,
        stride: [D - 1]usize,
        size: [D]usize,

        pub fn free(this: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(this.data[0 .. this.stride[D - 2] * this.size[D - 1]]);
        }

        pub fn getPosPtr(this: @This(), pos: [D]usize) *const T {
            const posv = @as(@Vector(D, usize), pos);
            std.debug.assert(@reduce(.And, posv < this.size));

            return &this.data[posToIndex(D, this.stride, pos)];
        }

        pub fn getPos(this: @This(), pos: [D]usize) T {
            const posv = @as(@Vector(D, usize), pos);
            std.debug.assert(@reduce(.And, posv < this.size));

            return this.data[posToIndex(D, this.stride, pos)];
        }

        pub fn getRegion(this: @This(), pos: [D]usize, size: [D]usize) @This() {
            const posv: @Vector(D, usize) = pos;
            const sizev: @Vector(D, usize) = size;

            std.debug.assert(@reduce(.And, posv < this.size));
            std.debug.assert(@reduce(.And, posv + sizev <= this.size));

            const min_index = posToIndex(D, this.stride, pos);
            if (@reduce(.Or, sizev == @splat(D, @as(usize, 0)))) {
                return .{
                    .data = this.data[min_index..min_index].ptr,
                    .stride = this.stride,
                    .size = sizev,
                };
            }

            const max_pos = posv + sizev - @splat(D, @as(usize, 1));

            const end_index = posToIndex(D, this.stride, max_pos);

            std.debug.assert(end_index - min_index + 1 >= @reduce(.Mul, sizev));

            return @This(){
                .data = this.data[min_index..end_index].ptr,
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

        pub fn withExtraDimensions(this: @This(), comptime EXTRA_DIMS: usize) ConstGrid(D + EXTRA_DIMS, T) {
            return ConstGrid(D + EXTRA_DIMS, T){
                .data = this.data,
                .stride = this.stride ++ [_]usize{undefined} ** EXTRA_DIMS,
                .size = this.size ++ [_]usize{1} ** EXTRA_DIMS,
            };
        }

        pub const Iterator = struct {
            grid: ConstGrid(D, T),
            pos: [D]usize,

            pub const Entry = struct {
                pos: [D]usize,
                ptr: *const T,
            };

            pub fn next(this: *@This()) ?Entry {
                for (this.pos[0 .. D - 1], this.pos[1..D], this.grid.size[0 .. D - 1]) |*pos, *next_pos, size| {
                    if (pos.* >= size) {
                        pos.* = 0;
                        next_pos.* += 1;
                    }
                }
                if (this.pos[D - 1] >= this.grid.size[D - 1]) {
                    return null;
                }
                const entry = Entry{
                    .pos = this.pos,
                    .ptr = this.grid.getPosPtr(this.pos),
                };
                this.pos[0] += 1;
                return entry;
            }
        };

        // TODO: Add test
        pub fn iterate(this: @This()) Iterator {
            return Iterator{
                .grid = this,
                .pos = [_]usize{0} ** D,
            };
        }
    };
}

test "Grid(f32).mul" {
    var grid = try Grid(2, f32).alloc(std.testing.allocator, .{ 3, 3 });
    defer grid.free(std.testing.allocator);

    for (grid.data, 0..9) |*elem, index| {
        elem.* = @intToFloat(f32, index);
    }

    grid.mul(grid.asConst(), .{
        .data = &[_]f32{
            1,  1,  2,
            3,  5,  8,
            14, 22, 36,
        },
        .size = .{ 3, 3 },
        .stride = .{3},
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 1, 4, 9, 20, 40, 84, 154, 288 },
        grid.getSliceOfData(),
    );
}

test "Grid(f32).mulScalar" {
    var grid = try Grid(2, f32).alloc(std.testing.allocator, .{ 3, 3 });
    defer grid.free(std.testing.allocator);

    for (grid.data, 0..9) |*elem, index| {
        elem.* = @intToFloat(f32, index);
    }

    grid.mulScalar(grid.asConst(), 10);

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 10, 20, 30, 40, 50, 60, 70, 80 },
        grid.getSliceOfData(),
    );
}

test "Grid(f32).div" {
    var grid = try Grid(2, f32).alloc(std.testing.allocator, .{ 3, 3 });
    defer grid.free(std.testing.allocator);

    for (grid.data, 0..9) |*elem, index| {
        elem.* = @intToFloat(f32, index);
    }

    grid.div(grid.asConst(), .{
        .data = &[_]f32{
            1,  1,  2,
            3,  5,  8,
            14, 22, 36,
        },
        .size = .{ 3, 3 },
        .stride = .{3},
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 1, 1, 1, 0.8, 0.625, 0.42857142857142855, 0.3181818181818182, 0.2222222222222222 },
        grid.getSliceOfData(),
    );
}

test "Grid(f32).divScalar" {
    var grid = try Grid(2, f32).alloc(std.testing.allocator, .{ 3, 3 });
    defer grid.free(std.testing.allocator);

    for (grid.data, 0..9) |*elem, index| {
        elem.* = @intToFloat(f32, index);
    }

    grid.divScalar(grid.asConst(), 10);

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 },
        grid.getSliceOfData(),
    );
}

test "Grid(1, f32).sqrt" {
    var grid = try Grid(2, f32).alloc(std.testing.allocator, .{ 2, 2 });
    defer grid.free(std.testing.allocator);

    grid.sqrt(.{
        .data = &[_]f32{
            4,  9,
            16, 25,
        },
        .size = .{ 2, 2 },
        .stride = .{2},
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{ 2, 3, 4, 5 },
        grid.getSliceOfData(),
    );
}

test "Grid with extra dimensions" {
    var grid = try Grid(3, f32).alloc(std.testing.allocator, .{ 2, 2, 2 });
    defer grid.free(std.testing.allocator);

    const layer1 = ConstGrid(2, f32){
        .data = &[_]f32{
            2, 3,
            4, 5,
        },
        .size = .{ 2, 2 },
        .stride = .{2},
    };
    const layer2 = ConstGrid(2, f32){
        .data = &[_]f32{
            4,  9,
            16, 25,
        },
        .size = .{ 2, 2 },
        .stride = .{2},
    };

    grid.getRegion(.{ 0, 0, 0 }, .{ 2, 2, 1 }).copy(layer1.withExtraDimensions(1));
    grid.getRegion(.{ 0, 0, 1 }, .{ 2, 2, 1 }).copy(layer2.withExtraDimensions(1));

    try std.testing.expectEqualSlices(
        f32,
        &.{ 2, 3, 4, 5, 4, 9, 16, 25 },
        grid.getSliceOfData(),
    );
}

test "Grid(3, f32).set" {
    var grid = try Grid(3, f32).alloc(std.testing.allocator, .{ 3, 3, 3 });
    defer grid.free(std.testing.allocator);

    grid.set(42);

    var iter = grid.iterate();
    while (iter.next()) |e| {
        try std.testing.expectEqual(@as(f32, 42), e.ptr.*);
    }
}

test "Grid(3, f32).dupe" {
    var grid = try Grid(2, f32).dupe(std.testing.allocator, ConstGrid(2, f32){
        .data = &[_]f32{
            2, 3,
            4, 5,
        },
        .size = .{ 2, 2 },
        .stride = .{2},
    });
    defer grid.free(std.testing.allocator);

    try std.testing.expectEqualSlices(
        f32,
        &.{ 2, 3, 4, 5 },
        grid.getSliceOfData(),
    );
}
