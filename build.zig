const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cmdtree_mod = b.addModule("cmdtree", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmdtree_obj = b.addTest(.{ .root_module = cmdtree_mod });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(cmdtree_obj).step);


    const example_step = b.step("examples", "Build examples");
    {
        // Filegen example - run (to test file generation)
        const eg_filegen_dep = b.dependency("cmdtree_filegen", .{ .target = target, .optimize = optimize });
        const eg_filegen_exe = b.addExecutable(.{
            .name = "cmdtree_filegen",
            .root_module = eg_filegen_dep.module("main"),
        });
        const eg_filegen_install = b.addInstallArtifact(eg_filegen_exe, .{});
        example_step.dependOn(&eg_filegen_install.step);
        test_step.dependOn(&b.addRunArtifact(eg_filegen_exe).step);

        // Other examples - build all on test
        for ([_][]const u8{
            "full",
            "project",
        }) |eg_name| {
            const eg_obj = b.createModule(.{
                .root_source_file = b.path(b.fmt("example/{s}.zig", .{eg_name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "cmdtree", .module = cmdtree_mod },
                },
            });
            const eg_exe = b.addExecutable(.{ .name = eg_name, .root_module = eg_obj });
            const eg_install = b.addInstallArtifact(eg_exe, .{});
            example_step.dependOn(&eg_exe.step);
            example_step.dependOn(&eg_install.step);

            const test_exe = b.addTest(.{ .root_module = eg_obj });
            test_step.dependOn(&b.addRunArtifact(test_exe).step);
        }
    }

    {
        const docs_step = b.step("docs", "Generate docs.");
        const install_docs = b.addInstallDirectory(.{
            .source_dir = cmdtree_obj.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });
        docs_step.dependOn(&install_docs.step);
    }
}
