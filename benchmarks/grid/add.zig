pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const Method = enum {
        iterator,
        for_slice,
        function,
        for_slice_vector,
    };
    const method = std.meta.stringToEnum(Method, args[1]) orelse return error.UnknownMethod;
    const size = [2]usize{
        try std.fmt.parseInt(usize, args[2], 10),
        try std.fmt.parseInt(usize, args[3], 10),
    };

    var grids = [2]utils.grid.Buffer(2, f32){
        try utils.grid.alloc(2, f32, gpa.allocator(), size),
        try utils.grid.alloc(2, f32, gpa.allocator(), size),
    };
    defer {
        for (&grids) |grid| {
            gpa.allocator().free(grid.slice());
        }
    }
    var result = try utils.grid.alloc(2, f32, gpa.allocator(), size);
    defer gpa.allocator().free(result.slice());

    var prng = std.rand.DefaultPrng.init(789);
    for (&grids) |grid| {
        for (grid.slice()) |*num| {
            num.* = prng.random().float(f32);
        }
    }

    const start = try std.time.Instant.now();

    switch (method) {
        .iterator => {
            var iter = utils.grid.iterateRange(2, result.size);
            while (iter.next()) |pos| {
                result.idx(pos).* = grids[0].idx(pos).* + grids[1].idx(pos).*;
            }
        },
        .for_slice => {
            for (result.slice(), grids[0].slice(), grids[1].slice()) |*res, a, b| {
                res.* = a / b;
            }
        },
        .function => result.add(grids[0], grids[1]),
        .for_slice_vector => {
            const S = comptime std.simd.suggestVectorSize(f32) orelse 4;

            const num_elements = grids[0].size[0] * grids[0].size[1];
            const num_vectors = num_elements / S;

            for (0..num_vectors) |vi| {
                const a: @Vector(S, f32) = grids[0].data[vi * S .. (vi + 1) * S][0..S].*;
                const b: @Vector(S, f32) = grids[1].data[vi * S .. (vi + 1) * S][0..S].*;
                const res: *[S]f32 = result.data[vi * S .. (vi + 1) * S][0..S];

                res.* = a + b;
            }

            const num_unfinished = num_vectors * S;
            const a_slice = grids[0].data[num_unfinished .. grids[0].size[0] * grids[0].size[1]];
            const b_slice = grids[1].data[num_unfinished .. grids[1].size[0] * grids[1].size[1]];
            const result_slice = result.data[num_unfinished .. result.size[0] * result.size[1]];

            for (result_slice, a_slice, b_slice) |*res, a, b| {
                res.* = a + b;
            }
        },
    }

    const end = try std.time.Instant.now();

    std.debug.print("time: {}\n", .{std.fmt.fmtDuration(end.since(start))});
}

const utils = @import("utils");
const std = @import("std");
