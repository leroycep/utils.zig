const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const install_benchmarks = b.option(bool, "install-benchmarks", "Install the benchmark binaries") orelse false;

    const module = b.addModule("utils.zig", .{
        .source_file = .{ .path = "utils.zig" },
    });

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "utils.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    const benchmark_grid_add = b.addExecutable(.{
        .name = "benchmark-grid-add",
        .root_source_file = .{ .path = "benchmarks/grid/add.zig" },
        .target = target,
        .optimize = optimize,
    });
    benchmark_grid_add.addModule("utils", module);
    if (install_benchmarks) {
        b.installArtifact(benchmark_grid_add);
    }

    const benchmark_grid_div = b.addExecutable(.{
        .name = "benchmark-grid-div",
        .root_source_file = .{ .path = "benchmarks/grid/div.zig" },
        .target = target,
        .optimize = optimize,
    });
    benchmark_grid_div.addModule("utils", module);
    if (install_benchmarks) {
        b.installArtifact(benchmark_grid_div);
    }
}
