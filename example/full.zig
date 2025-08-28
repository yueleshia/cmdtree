const std = @import("std");
const ct = @import("cmdtree");

const ct_main = ct.command("", &.{
    .{ "-h, --help!", ct.option(bool, "Displays this help menu") },
    .{ "    --asdf! <example>", ct.option(?enum(u32) { a, b, c }, "Display example") },
    .{ "-m, --message! <string>", ct.option(?[]const u8, "A notification") },

    .{ "-H, --header! <http_header>...", ct.option([]const u8, "Add additional curl headers") },

    .{ "connect, c", ct_connect },
    .{ "version, ver", ct.command("Displays the version", &.{}) },
});

const APP_NAME = "cmdtree-full";
const ct_connect = ct.command("Connect to a DB", &.{
    .{ "-u, --username! <name>", ct.option([]const u8, "Username to connect with") },

    .{ "direct", ct.command("Connect directly to the database", &.{}) },
    .{ "proxy", ct.command("Connect through a proxy", &.{}) },
});

var buffers = struct {
    positionals: [100][]const u8 = undefined,
    headers: [1024][]const u8 = undefined,
    stderr: [4096]u8 = undefined,
}{};

var state: ct_main.Type = .{
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

var stdio_buffer: [4096]u8 = undefined;

const app = ct.app_cmdtree_init(ct_main);


//run: zig build examples

pub fn main() !void {
    var iter = app.iter_init(&state);
    var positionals = std.ArrayList([]const u8).initBuffer(&buffers.positionals);

    for (&[_][]const u8{ "connect", "--username", "proxy" }) |arg| {
        const arg_type = iter.next(arg) catch |err| switch (err) {
            error.CmdTreeInvalidEnumVariant => @panic("@TODO"),
            error.CmdTreeUnexpectedCommand => @panic("@TODO"),
        };
        switch (arg_type) {
            .eaten => {},
            .positional => positionals.appendAssumeCapacity(arg),
        }
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
            .direct => std.debug.print("direct connect branch", .{}),
            .proxy => std.debug.print("proxy connect branch", .{}),
        },
        .version => {},
    }
    std.debug.print("{s}\n", .{iter.pathstr.items});
    ct.debug_print_state(&state);
}

test {
    std.testing.refAllDecls(@This());
}
