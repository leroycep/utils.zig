pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const Method = enum { iterator, for_slice, add_function, for_slice_vector };
    const method = std.meta.stringToEnum(Method, args[1]) orelse return error.UnknownMethod;
    const size = [2]usize{
        try std.fmt.parseInt(usize, args[2], 10),
        try std.fmt.parseInt(usize, args[3], 10),
    };

    var grids = [2]utils.Grid(2, f32){
        try utils.Grid(2, f32).alloc(gpa.allocator(), size),
        try utils.Grid(2, f32).alloc(gpa.allocator(), size),
    };
    defer {
        for (&grids) |*grid| {
            grid.free(gpa.allocator());
        }
    }
    var result = try utils.Grid(2, f32).alloc(gpa.allocator(), size);
    defer result.free(gpa.allocator());

    var prng = std.rand.DefaultPrng.init(789);
    for (&grids) |grid| {
        var iter = grid.iterate();
        while (iter.next()) |e| {
            e.ptr.* = prng.random().float(f32);
        }
    }

    const start = try std.time.Instant.now();

    switch (method) {
        .iterator => {
            var iter = result.iterate();
            while (iter.next()) |e| {
                e.ptr.* = grids[0].getPos(e.pos) + grids[1].getPos(e.pos);
            }
        },
        .for_slice => {
            const a_slice = grids[0].data[0 .. grids[0].stride[0] * grids[0].size[1]];
            const b_slice = grids[1].data[0 .. grids[1].stride[0] * grids[1].size[1]];
            const result_slice = result.data[0 .. result.stride[0] * result.size[1]];

            for (result_slice, a_slice, b_slice) |*res, a, b| {
                res.* = a + b;
            }
        },
        .add_function => result.add(grids[0].asConst(), grids[1].asConst()),
        .for_slice_vector => {
            const S = comptime std.simd.suggestVectorSize(f32) orelse 4;

            const num_elements = grids[0].stride[0] * grids[0].size[1];
            const num_vectors = num_elements / S;

            for (0..num_vectors) |vi| {
                const a: @Vector(S, f32) = grids[0].data[vi * S .. (vi + 1) * S][0..S].*;
                const b: @Vector(S, f32) = grids[1].data[vi * S .. (vi + 1) * S][0..S].*;
                const res: *[S]f32 = result.data[vi * S .. (vi + 1) * S][0..S];

                res.* = a + b;
            }

            const num_unfinished = num_vectors * S;
            const a_slice = grids[0].data[num_unfinished .. grids[0].stride[0] * grids[0].size[1]];
            const b_slice = grids[1].data[num_unfinished .. grids[1].stride[0] * grids[1].size[1]];
            const result_slice = result.data[num_unfinished .. result.stride[0] * result.size[1]];

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
