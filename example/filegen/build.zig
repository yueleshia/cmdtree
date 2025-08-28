const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const run_step = b.step("run", "Run the app");

    const cmdtree_mod = b.createModule(.{
        .root_source_file = b.path("../../src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cmdtree = "cmdtree";
    const filegen = blk: {
        const filegen = b.addExecutable(.{
            .name = "filegen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cli_gen.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = cmdtree, .module = cmdtree_mod },
                },
            }),
        });
        const filegen_step = b.addRunArtifact(filegen);
        filegen_step.addArg(cmdtree);
        const output_path = filegen_step.addOutputFileArg("cmdtree_gen.zig");

        // This command is not necessary
        // Copy the generated file into <prefix> i.e. 'zig-out/cmdtree_gen.zig'
        // This is so you can view it easily
        const filegen_install = b.addInstallDirectory(.{
            .install_dir = .prefix,
            .install_subdir = "",
            .source_dir = output_path.dirname(),
        });
        run_step.dependOn(&filegen_install.step);
        break :blk output_path; // Go naming convention
    };

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.addModule("main", .{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);
    // Not sure what the difference between anonymous and regular imports are
    exe.root_module.addAnonymousImport("codegen_tree", .{
        .root_source_file = filegen,
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = cmdtree, .module = cmdtree_mod } },
    });
    exe.root_module.addImport(cmdtree, cmdtree_mod);

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
