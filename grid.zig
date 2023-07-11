const grid = @This();

pub fn posToIndex(comptime D: usize, strides: [D]usize, pos: [D]usize) usize {
    var index: usize = 0;
    for (pos, strides) |p, stride| {
        index += p * stride;
    }
    return index;
}

pub fn Buffer(comptime D: usize, comptime T: type) type {
    return BufferAligned(D, @alignOf(T), T);
}

pub fn BufferAligned(comptime D: usize, comptime A: usize, comptime T: type) type {
    return struct {
        data: [*]align(A) T,
        size: [D]usize,

        pub fn slice(this: @This()) []align(A) T {
            var len: usize = 1;

            for (this.size) |size| {
                len *= size;
            }

            return this.data[0..len];
        }

        pub fn asSlice(this: @This()) SliceAligned(D, A, T) {
            var strides: [D]usize = undefined;
            var len: usize = 1;
            for (&strides, this.size) |*stride, size| {
                stride.* = len;
                len *= size;
            }
            return Slice(D, T){
                .data = this.data,
                .stride = strides,
                .size = this.size,
            };
        }

        pub fn asConstSlice(this: @This()) ConstSliceAligned(D, A, T) {
            var strides: [D]usize = undefined;
            var len: usize = A;
            for (&strides, this.size) |*stride, size| {
                stride.* = len;
                len *= size;
            }
            return ConstSlice(D, T){
                .data = this.data,
                .stride = strides,
                .size = this.size,
            };
        }

        pub fn idx(this: @This(), pos: [D]usize) *align(A) T {
            const posv = @as(@Vector(D, usize), pos);
            std.debug.assert(@reduce(.And, posv < this.size));

            var strides: [D]usize = undefined;
            var len: usize = 1;
            for (&strides, this.size) |*stride, size| {
                stride.* = len;
                len *= size;
            }

            return &this.data[posToIndex(D, strides, pos)];
        }

        pub fn region(this: @This(), start: [D]usize, end: [D]usize) Slice(D, A, T) {
            const startv: @Vector(D, usize) = start;
            const endv: @Vector(D, usize) = end;

            std.debug.assert(@reduce(.And, startv < this.size));
            std.debug.assert(@reduce(.And, startv <= endv));
            std.debug.assert(@reduce(.And, endv <= this.size));

            const sizev: @Vector(D, usize) = endv - startv;

            var strides: [D]usize = undefined;
            var len: usize = 1;
            for (&strides, this.size) |*stride, size| {
                stride.* = len;
                len *= size;
            }

            const start_index = posToIndex(D, strides, start);
            const end_index = posToIndex(D, strides, end);

            return Slice(D, T){
                .data = this.data[start_index..end_index].ptr,
                .stride = this.stride,
                .size = sizev,
            };
        }

        pub fn add(dest: @This(), a: @This(), b: @This()) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &a.size));
            std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));

            for (dest.slice(), a.slice(), b.slice()) |*z, x, y| {
                z.* = x + y;
            }
        }

        pub fn div(dest: @This(), a: @This(), b: @This()) void {
            std.debug.assert(std.mem.eql(usize, &dest.size, &a.size));
            std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));

            for (dest.slice(), a.slice(), b.slice()) |*z, x, y| {
                z.* = x / y;
            }
        }
    };
}

pub fn Slice(comptime D: usize, comptime T: type) type {
    return SliceAligned(D, @alignOf(T), T);
}

pub fn SliceAligned(comptime D: usize, comptime A: usize, comptime T: type) type {
    return struct {
        data: [*]align(A) T,
        stride: [D]usize,
        size: [D]usize,

        pub fn asConstSlice(this: @This()) ConstSlice(D, T) {
            return ConstSlice(D, T){
                .data = this.data,
                .stride = this.stride,
                .size = this.size,
            };
        }

        pub fn idx(this: @This(), pos: [D]usize) *T {
            const posv = @as(@Vector(D, usize), pos);
            std.debug.assert(@reduce(.And, posv < this.size));

            return &this.data[posToIndex(D, this.stride, pos)];
        }

        pub fn region(this: @This(), start: [D]usize, end: [D]usize) @This() {
            const startv: @Vector(D, usize) = start;
            const endv: @Vector(D, usize) = end;

            std.debug.assert(@reduce(.And, startv < this.size));
            std.debug.assert(@reduce(.And, startv <= endv));
            std.debug.assert(@reduce(.And, endv <= this.size));

            const sizev: @Vector(D, usize) = endv - startv;

            const start_index = posToIndex(D, this.stride, start);
            const end_index = posToIndex(D, this.stride, end);

            return @This(){
                .data = this.data[start_index..end_index].ptr,
                .stride = this.stride,
                .size = sizev,
            };
        }
    };
}

pub fn ConstSlice(comptime D: usize, comptime T: type) type {
    return ConstSliceAligned(D, @alignOf(T), T);
}

pub fn ConstSliceAligned(comptime D: usize, comptime A: usize, comptime T: type) type {
    return struct {
        data: [*]align(A) const T,
        stride: [D]usize,
        size: [D]usize,

        pub const Pos = [D]usize;

        pub fn getPos(this: @This(), pos: [D]usize) T {
            const posv = @as(@Vector(D, usize), pos);
            std.debug.assert(@reduce(.And, posv < this.size));

            return this.data[posToIndex(D, this.stride, pos)];
        }

        pub fn idx(this: @This(), pos: [D]usize) *align(A) const T {
            const posv = @as(@Vector(D, usize), pos);
            std.debug.assert(@reduce(.And, posv < this.size));

            return &this.data[posToIndex(D, this.stride, pos)];
        }

        pub fn region(this: @This(), start: [D]usize, end: [D]usize) @This() {
            const startv: @Vector(D, usize) = start;
            const endv: @Vector(D, usize) = end;

            std.debug.assert(@reduce(.And, startv < this.size));
            std.debug.assert(@reduce(.And, startv <= endv));
            std.debug.assert(@reduce(.And, endv <= this.size));

            const sizev: @Vector(D, usize) = endv - startv;

            const start_index = posToIndex(D, this.stride, start);
            const end_index = posToIndex(D, this.stride, end);

            return @This(){
                .data = this.data[start_index..end_index].ptr,
                .stride = this.stride,
                .size = sizev,
            };
        }
    };
}

pub fn alloc(comptime D: usize, comptime T: type, allocator: std.mem.Allocator, size: [D]usize) !Buffer(D, T) {
    return allocAligned(D, @alignOf(T), T, allocator, size);
}

pub fn allocAligned(comptime D: usize, comptime A: u29, comptime T: type, allocator: std.mem.Allocator, size: [D]usize) !BufferAligned(D, A, T) {
    var len: usize = 1;
    for (size) |s| {
        len *= s;
    }
    const data = try allocator.allocWithOptions(T, len, A, null);

    return .{
        .data = data.ptr,
        .size = size,
    };
}

pub fn copy(comptime D: usize, comptime T: type, dest: Slice(D, T), src: ConstSlice(D, T)) void {
    std.debug.assert(std.mem.eql(usize, &dest.size, &src.size));

    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = src.idx(pos).*;
    }
}

pub fn dupe(comptime D: usize, comptime T: type, allocator: std.mem.Allocator, src: ConstSlice(D, T)) !Buffer(D, T) {
    var result = try alloc(D, T, allocator, src.size);
    copy(D, T, result.asSlice(), src);
    return result;
}

test dupe {
    var result = try dupe(2, f32, std.testing.allocator, .{
        .data = &[_]f32{
            2, 3, 0,
            4, 5, 0,
        },
        .size = .{ 2, 2 },
        .stride = .{ 1, 3 },
    });
    defer std.testing.allocator.free(result.slice());

    try std.testing.expectEqualSlices(
        f32,
        &.{ 2, 3, 4, 5 },
        result.slice(),
    );
}

pub fn set(comptime D: usize, comptime T: type, dest: Slice(D, T), value: T) void {
    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = value;
    }
}

test set {
    var result = try alloc(3, f32, std.testing.allocator, .{ 3, 3, 3 });
    defer std.testing.allocator.free(result.slice());

    set(3, f32, result.asSlice(), 42);

    try std.testing.expectEqualSlices(f32, &([_]f32{42} ** 27), result.data[0..27]);
}

pub fn flip(comptime T: type, dest: Slice(2, T), flipOnAxis: [2]bool) void {
    // The x/y coordinate where we can stop copying. We should only need to swap half the pixels.
    const swap_to: [2]usize = if (flipOnAxis[1]) .{ dest.size[0], dest.size[1] / 2 } else if (flipOnAxis[0]) .{ dest.size[0] / 2, dest.size[1] } else return;

    for (0..swap_to[1]) |y0| {
        const y1 = if (flipOnAxis[1]) dest.size[1] - 1 - y0 else y0;
        const row0 = dest.data[y0 * dest.stride ..][0..dest.size[0]];
        const row1 = dest.data[y1 * dest.stride ..][0..dest.size[0]];
        for (0..swap_to[0]) |x0| {
            const x1 = if (flipOnAxis[0]) dest.size[0] - 1 - x0 else x0;
            std.mem.swap(T, &row0[x0], &row1[x1]);
        }
    }
}

pub fn add(comptime D: usize, comptime T: type, dest: Slice(D, T), a: ConstSlice(D, T), b: ConstSlice(D, T)) void {
    std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
    std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = a.idx(pos).* + b.idx(pos).*;
    }
}

test add {
    var result = try alloc(2, f32, std.testing.allocator, .{ 3, 2 });
    defer std.testing.allocator.free(result.slice());

    add(2, f32, result.asSlice(), .{
        .data = &[_]f32{
            1, 2, 3,
            4, 5, 6,
        },
        .size = .{ 3, 2 },
        .stride = .{ 1, 3 },
    }, .{
        .data = &[_]f32{
            1, 1, 2,
            3, 5, 8,
        },
        .size = .{ 3, 2 },
        .stride = .{ 1, 3 },
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{
            2, 3,  5,
            7, 10, 14,
        },
        result.data[0..6],
    );
}

pub fn addSaturating(comptime D: usize, comptime T: type, dest: Slice(D, T), a: ConstSlice(D, T), b: ConstSlice(D, T)) void {
    std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
    std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = a.idx(pos).* +| b.idx(pos).*;
    }
}

pub fn sub(comptime D: usize, comptime T: type, dest: Slice(D, T), a: ConstSlice(D, T), b: ConstSlice(D, T)) void {
    std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
    std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = a.idx(pos).* - b.idx(pos).*;
    }
}

pub fn subSaturating(comptime D: usize, comptime T: type, dest: Slice(D, T), a: ConstSlice(D, T), b: ConstSlice(D, T)) void {
    std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
    std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = a.idx(pos).* -| b.idx(pos).*;
    }
}

pub fn mul(comptime D: usize, comptime T: type, dest: Slice(D, T), a: ConstSlice(D, T), b: ConstSlice(D, T)) void {
    std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));
    std.debug.assert(std.mem.eql(usize, &a.size, &b.size));

    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = a.idx(pos).* * b.idx(pos).*;
    }
}

test mul {
    var result = try alloc(2, f32, std.testing.allocator, .{ 3, 3 });
    defer std.testing.allocator.free(result.slice());

    mul(2, f32, result.asSlice(), .{
        .data = &[_]f32{
            0, 1, 2,
            3, 4, 5,
            6, 7, 8,
        },
        .size = .{ 3, 3 },
        .stride = .{ 1, 3 },
    }, .{
        .data = &[_]f32{
            1,  1,  2,
            3,  5,  8,
            14, 22, 36,
        },
        .size = .{ 3, 3 },
        .stride = .{ 1, 3 },
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 1, 4, 9, 20, 40, 84, 154, 288 },
        result.slice(),
    );
}

pub fn mulScalar(comptime D: usize, comptime T: type, dest: Slice(D, T), src: ConstSlice(D, T), scalar: T) void {
    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = src.idx(pos).* * scalar;
    }
}

test mulScalar {
    var result = try alloc(2, f32, std.testing.allocator, .{ 3, 3 });
    defer std.testing.allocator.free(result.slice());

    mulScalar(2, f32, result.asSlice(), .{
        .data = &[_]f32{
            0, 1, 2,
            3, 4, 5,
            6, 7, 8,
        },
        .stride = .{ 1, 3 },
        .size = .{ 3, 3 },
    }, 10);

    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 10, 20, 30, 40, 50, 60, 70, 80 },
        result.slice(),
    );
}

pub fn div(comptime D: usize, comptime T: type, dest: Slice(D, T), a: ConstSlice(D, T), b: ConstSlice(D, T)) void {
    std.debug.assert(std.mem.eql(usize, &dest.size, &a.size));
    std.debug.assert(std.mem.eql(usize, &dest.size, &b.size));

    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = a.idx(pos).* / b.idx(pos).*;
    }
}

test div {
    var result = try alloc(2, f32, std.testing.allocator, .{ 3, 3 });
    defer std.testing.allocator.free(result.slice());

    div(2, f32, result.asSlice(), .{
        .data = &[_]f32{
            0, 1, 2,
            3, 4, 5,
            6, 7, 8,
        },
        .size = .{ 3, 3 },
        .stride = .{ 1, 3 },
    }, .{
        .data = &[_]f32{
            1,  1,  2,
            3,  5,  8,
            14, 22, 36,
        },
        .size = .{ 3, 3 },
        .stride = .{ 1, 3 },
    });

    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0, 1, 1, 1, 0.8, 0.625, 0.42857142857142855, 0.3181818181818182, 0.2222222222222222 },
        result.slice(),
    );
}

pub fn divScalar(comptime D: usize, comptime T: type, dest: Slice(D, T), src: ConstSlice(D, T), scalar: T) void {
    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = src.idx(pos).* / scalar;
    }
}

test divScalar {
    var result = try alloc(2, f32, std.testing.allocator, .{ 3, 3 });
    defer std.testing.allocator.free(result.slice());

    divScalar(2, f32, result.asSlice(), .{
        .data = &[_]f32{
            0, 1, 2,
            3, 4, 5,
            6, 7, 8,
        },
        .stride = .{ 1, 3 },
        .size = .{ 3, 3 },
    }, 10);

    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 },
        result.slice(),
    );
}

pub fn sqrt(comptime D: usize, comptime T: type, dest: Slice(D, T), src: ConstSlice(D, T)) void {
    var iter = iterateRange(D, dest.size);
    while (iter.next()) |pos| {
        dest.idx(pos).* = @sqrt(src.idx(pos).*);
    }
}

test sqrt {
    var result = try alloc(2, f32, std.testing.allocator, .{ 2, 2 });
    defer std.testing.allocator.free(result.slice());

    sqrt(2, f32, result.asSlice(), .{
        .data = &[_]f32{
            4,  9,
            16, 25,
        },
        .size = .{ 2, 2 },
        .stride = .{ 1, 2 },
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{ 2, 3, 4, 5 },
        result.data[0..4],
    );
}

pub fn matrixMul(comptime T: type, dest: Slice(2, T), a: ConstSlice(2, T), b: ConstSlice(2, T)) void {
    std.debug.assert(dest.size[0] == b.size[0]);
    std.debug.assert(a.size[1] == b.size[0]);
    std.debug.assert(dest.size[1] == a.size[1]);

    for (0..dest.size[1]) |k| {
        for (0..dest.size[0]) |i| {
            dest.idx(.{ i, k }).* = 0;
            for (0..a.size[0]) |l| {
                dest.idx(.{ i, k }).* += a.idx(.{ l, k }).* * b.idx(.{ i, l }).*;
            }
        }
    }
}

test matrixMul {
    // Multiplying a 3x2 matrix by a 2x3 matrix:
    //            [ 1  2]
    //            [ 3  4]
    //            [ 5  6]
    //            -------
    // [-2 5 6] | [43 52]
    // [ 5 2 7] | [46 60]
    const c = try alloc(2, f32, std.testing.allocator, .{ 2, 2 });
    defer std.testing.allocator.free(c.slice());

    matrixMul(f32, c.asSlice(), .{
        .data = &[_]f32{
            -2, 5, 6,
            5,  2, 7,
        },
        .stride = .{ 1, 3 },
        .size = .{ 3, 2 },
    }, .{
        .data = &[_]f32{
            1, 2,
            3, 4,
            5, 6,
        },
        .stride = .{ 1, 2 },
        .size = .{ 2, 3 },
    });

    try std.testing.expectEqualSlices(f32, &[_]f32{
        43, 52,
        46, 60,
    }, c.data[0..4]);
}

pub fn RangeIterator(comptime D: usize) type {
    return struct {
        pos: [D]usize,
        size: [D]usize,

        pub fn next(this: *@This()) ?[D]usize {
            for (this.pos[0 .. D - 1], this.pos[1..D], this.size[0 .. D - 1]) |*axis, *next_axis, size| {
                if (axis.* >= size) {
                    axis.* = 0;
                    next_axis.* += 1;
                }
            }
            if (this.pos[D - 1] >= this.size[D - 1]) {
                return null;
            }
            defer this.pos[0] += 1;
            return this.pos;
        }
    };
}

pub fn iterateRange(comptime D: usize, size: [D]usize) RangeIterator(D) {
    return RangeIterator(D){
        .pos = [_]usize{0} ** D,
        .size = size,
    };
}

const std = @import("std");
