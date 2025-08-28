const std = @import("std");
const cmdtree = @import("cmdtree");
const codegen_tree = @import("codegen_tree");

const APP_NAME = "cmdtree-filegen";
const app: cmdtree.App(codegen_tree.Path) = .init(
    &codegen_tree.pathstr_2_details,
    &codegen_tree.pathstr_2_path,
    codegen_tree.help_strings,
);

var buffers = struct {
    stderr: [4096]u8 = undefined,
    headers: [1024][]const u8 = undefined,
}{};

var state: codegen_tree.Main = .{
    .@"--help" = false,
    .@"--asdf" = null,
    .@"--message" = null,
    .@"--header" = std.ArrayList([]const u8).initBuffer(&buffers.headers),
    .connect = .{
        .@"--username" = "",
        .direct = .{},
        .proxy = .{},
    },
    .version = .{},
};

pub fn main() !void {
    const args =  &[_][]const u8{"main.exe", "connect", "--username", "admin", "proxy"};
    var iter = app.iter_init(&state);
    var positionals = blk: {
        var buf: [100][]const u8 = undefined;
        break :blk std.ArrayList([]const u8).initBuffer(&buf);
    };
    for (args[1..]) |arg| {
        const arg_type = iter.next(arg) catch |err| switch (err) {
            error.CmdTreeInvalidEnumVariant => @panic("@TODO"),
            error.CmdTreeUnexpectedCommand => @panic("@TODO"),
        };
        switch (arg_type) {
            .eaten => {},
            .positional => positionals.appendAssumeCapacity(arg),
        }
    }
    if (state.@"--help") {
        const details = app.pathstr_2_details.get(iter.pathstr.items) orelse unreachable;
        std.debug.print("{s}", .{app.help_strings[details.help_idx]});
        std.process.cleanExit();
    }

    const path = app.iter_done(&iter) catch |err| switch (err) {
        error.CmdTreeExpectingMoreArgs => {
            var stderr_writer = std.fs.File.stderr().writer(&buffers.stderr);
            std.debug.print("Not enough args.\n", .{});
            try app.print_help(&stderr_writer.interface, APP_NAME, iter.pathstr.items);
            std.process.exit(1);
        },
    };
    switch (path.main) {
        .connect => |connect| switch (connect) {
            .direct => std.debug.print("Connect via direct\n", .{}),
            .proxy => std.debug.print("Connect via proxy\n", .{}),
        },
        .version => std.debug.print("{s} v0.1.0\n", .{args[0]}),
    }
}


test "main" {
    const args =  &[_][]const u8{"main.exe", "connect", "--username", "admin", "proxy"};
    var iter = app.iter_init(&state);
    var positionals = cmdtree.init_bounded_array([]const u8, 100);
    for (args[1..]) |arg| {
        const arg_type = iter.next(arg) catch |err| switch (err) {
            error.CmdTreeInvalidEnumVariant => @panic("@TODO"),
            error.CmdTreeUnexpectedCommand => @panic("@TODO"),
        };
        switch (arg_type) {
            .eaten => {},
            .positional => positionals.appendAssumeCapacity(arg),
        }
    }
    if (state.@"--help") {
        const details = app.pathstr_2_details.get(iter.pathstr.items) orelse unreachable;
        std.debug.print("{s}", .{app.help_strings[details.help_idx]});
        std.process.cleanExit();
    }

    const path = app.iter_done(&iter);
    switch (path.main) {
        .connect => |connect| switch (connect) {
            .direct => {},
            .proxy => {},
        },
        .version => std.debug.print("{s} v0.1.0\n", .{args[0]}),
    }
}
