const std = @import("std");
const cmdtree = @import("cmdtree");
const CT = cmdtree.CmdTree;


const ct_main = CT.command("", &.{
    .{ "-h, --help!", CT.option(bool, "Displays this help menu") },
    .{ "    --asdf! <example>", CT.option(?enum(u32) {a, b, c}, "Display example") },
    .{ "-m, --message! <string>", CT.option(?[]const u8, "A notification") },

    .{ "-H, --header! <http_header>...", CT.option([]const u8, "Add additional curl headers") },

    .{"connect, c", CT.command("Connect to a DB", &.{
        .{ "-u, --username! <name>", CT.option([]const u8, "Username to connect with") },

        .{"direct", CT.command("Connect directly to the database", &.{}) },
        .{"proxy", CT.command("Connect through a proxy", &.{}) },
    })},
    .{"version, ver", CT.command("Displays the version", &.{}) },
});

const app = cmdtree.app_cmdtree_init(ct_main);

//run: zig run % -- "cmdtree" "a.zig"

pub fn main() !void {

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    if (args.len != 3) std.process.fatal("wrong number of arguments", .{});

    const module_name = args[1];
    const output_file_path = args[2];

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.process.fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    var buffer: [4096]u8 = undefined;
    var writer = output_file.writer(&buffer);
    try cmdtree.print_file(.fmt, &writer.interface, module_name, ct_main);
    try writer.interface.flush();
}
