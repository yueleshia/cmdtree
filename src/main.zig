const std = @import("std");
const cmdtree = @import("cmdtree");

const APP_NAME = "test";

const tree = cmdtree.init(cmdtree.command("", "", &.{
    cmdtree.option("help", bool, &[_][]const u8{ "-h", "--help" }, "Displays this help menu"),
    cmdtree.option("asdf", ?enum(usize) { a, b, c }, &[_][]const u8{ "-a", "--asdf" }, ""),
    cmdtree.option("message", ?[]const u8, &[_][]const u8{ "-m", "--message" }, ""),
    cmdtree.option("header", ?[10000][]const u8, &[_][]const u8{ "-H", "--header" }, ""),

    cmdtree.command("connect", "", &.{
        cmdtree.option("username", []const u8, &.{"--username"}, "something"),
        cmdtree.command("direct", "", &.{}),
        cmdtree.command("proxy", "", &.{}),
    }),
    cmdtree.command("version", "Displays the version of this program", &.{}),
}));

var command: tree.Type = .{
    .header = undefined,
};

comptime {
    const tree2 = cmdtree.init(cmdtree.command("", "", &.{
        cmdtree.option("help", bool, &[_][]const u8{ "-h", "--help" }, "Displays this help menu"),
        cmdtree.option("asdf", ?enum(usize) { a, b, c }, &[_][]const u8{ "-a", "--asdf" }, ""),
        cmdtree.option("message", ?[]const u8, &[_][]const u8{ "-m", "--message" }, ""),
        cmdtree.option("header", ?[10000][]const u8, &[_][]const u8{ "-H", "--header" }, ""),

        cmdtree.command("connect", "", &.{
            cmdtree.command("direct", "", &.{}),
            cmdtree.command("proxy", "", &.{}),
        }),
        cmdtree.command("version", "Displays the version of this program", &.{}),
    }));
    for (tree2.parsing.keys()) |k| {
        //@compileLog(k);
        _ = k;
    }
}

//run: zig build run -- version
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    //for (tree.helping.keys()) |k| {
    //    std.debug.print("- '{s}'\n", .{k});
    //}
    //for (tree.initial.keys()) |k| {
    //    std.debug.print("- {s}\n", .{k});
    //}
    //for (tree.parsing.keys()) |k| {
    //    std.debug.print("- {s} {d}\n", .{k, tree.parsing.get(k).?.offset});
    //}
    //std.debug.print("{any}", .{tree.parsing.get("connectdirect")});

    var positionals = try std.ArrayList([]const u8).initCapacity(std.heap.page_allocator, args.len);
    var iter = tree.init_iter();

    for (args[1..]) |arg| {
        std.debug.print("Processing {s}\n", .{arg});
        const is_positional = iter.next(&command, arg) catch |err| switch (err) {
            error.CmdTreeUnexpectedCommand, error.CmdTreeInvalidEnumVariant => {
                std.process.fatal("{s}{s}", .{ iter.err.option_name, iter.err.message });
            },

            // If you want to process `-` for stdin instead you can do it here.
            // Here we fail on invalid option is informative to the user.
            error.CmdTreeDashArgument => {
                std.debug.print("{s}{s}\n", .{ iter.err.option_name, iter.err.message });
                const stderr = std.io.getStdErr();
                try iter.print_help(stderr, APP_NAME);
                std.process.exit(1);
            },
        };
        if (is_positional) positionals.appendAssumeCapacity(arg);
    }

    const path: tree.TypeCommand = iter.done() catch {
        std.process.fatal("{s}{s}", .{ iter.err.option_name, iter.err.message });
    };

    switch (path) {
        .connect => |connect| switch (connect) {
            .direct => {
                //std.debug.print("{any}", .{connect[1]});
                std.debug.print("direct\n", .{});

                const writer = std.io.getStdErr();
                if (command.help) try tree.print_help(writer, APP_NAME, &.{""});
            },
            .proxy => std.debug.print("proxy\n", .{}),
        },
        .version => std.debug.print("v1\n", .{}),
    }

    std.debug.print("\n\n=== ===\n", .{});
    //try tree.parsing.set(&command, "--help", true);
    //try tree.set(&command, " connect direct --username", "");
    print_cmd(0, command);
    //std.debug.print("{}\n", .{command.help});

}

fn print_cmd(padding: comptime_int, cmd: anytype) void {
    std.debug.print("struct {{\n", .{});
    inline for (@typeInfo(@TypeOf(cmd)).@"struct".fields) |field| {
        std.debug.print("{s}  {s}: ", .{ " " ** padding, field.name });

        switch (@typeInfo(field.type)) {
            .@"struct" => print_cmd(padding + 2, @field(cmd, field.name)),
            .pointer => std.debug.print("{s}\n", .{@field(cmd, field.name)}),
            .optional => |info| if (@field(cmd, field.name) == null) {
                std.debug.print("null\n", .{});
            } else std.debug.print("{s}{{...}}\n", .{@typeName(info.child)}),
            else => {
                //std.debug.print("{s}\n", .{@typeName(field.type)});
                std.debug.print("{any}\n", .{@field(cmd, field.name)});
            },
        }
        //if ()
        //print_cmd(@field(cmd, field.name));
    }
    std.debug.print("{s}}}\n", .{" " ** padding});
}

test "simple test" {
    _ = @import("tests.zig");
    std.testing.refAllDeclsRecursive(@This());
}
