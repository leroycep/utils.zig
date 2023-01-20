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

            const max_pos = posv + sizev - @Vector(2, usize){ 1, 1 };

            const min_index = posv[1] * this.stride + posv[0];
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
