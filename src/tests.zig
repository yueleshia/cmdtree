const std = @import("std");
const cmdtree = @import("cmdtree");

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

//run: zig build test
test "bool" {
    var command: tree.Type = .{};
    var iter = tree.init_iter();
    _ = try iter.next(&command, "--help");
    //_ = iter.done();
    try std.testing.expect(command.help);
}

test "propagate_option" {
    var command: tree.Type = .{};
    var iter = tree.init_iter();
    _ = try iter.next(&command, "connect");
    _ = try iter.next(&command, "--help");
    //_ = iter.done();
    try std.testing.expect(command.help);
}
