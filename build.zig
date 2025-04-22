const std = @import("std");
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run all tests in all modes.");

    const lib_mod = blk: {
        const mod = b.addModule("cmdtree", .{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        });
        const tests = b.addTest(.{
            .root_module = mod,
            .use_llvm = builtin.mode != .Debug,
        });
        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);
        break :blk mod;
    };

    const modules = [_]*std.Build.Module{
        b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    };
    for (modules) |mod| {
        const tests = b.addTest(.{
            .root_module = mod,
            .use_llvm = builtin.mode != .Debug,
        });
        mod.addImport("cmdtree", lib_mod);
        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);

    }
    const exe = b.addExecutable(.{
        .name = "examples",
        .root_module = modules[0],
        .use_llvm = builtin.mode != .Debug,
        .use_lld = builtin.mode != .Debug,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);
}
