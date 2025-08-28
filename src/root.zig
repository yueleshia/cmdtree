const std = @import("std");

pub const CmdTree = @import("cmdtree.zig");
pub const Iter = @import("iter.zig");

pub const command = CmdTree.command;
pub const option = CmdTree.option;
pub const Payload = CmdTree.Payload;

pub inline fn app_cmdtree_init(ct: CmdTree) App(ct.PathWrapped) {
    comptime {
        const data = ct.build_comptime_lists();

        return .init(&.initComptime(data.kvs_details), &.initComptime(data.kvs_path), data.help_strings);
    }
}

pub fn App(PathApp: type) type {
    return struct {
        pathstr_2_details: *const std.StaticStringMap(Payload),
        pathstr_2_path: *const std.StaticStringMap(PathApp),
        help_strings: []const []const u8,

        pub fn init(pathstr_2_details: *const std.StaticStringMap(Payload), pathstr_2_path: *const std.StaticStringMap(PathApp), help_strings: []const []const u8) @This() {
            return .{
                .pathstr_2_details = pathstr_2_details,
                .pathstr_2_path = pathstr_2_path,
                .help_strings = help_strings,
            };
        }

        pub inline fn iter_init(comptime self: *const @This(), root: *anyopaque) Iter {
            return .init(root, self.pathstr_2_details);
        }

        pub fn iter_done(self: *const @This(), iter: *const Iter) !PathApp {
            return iter.done(PathApp, self.pathstr_2_path);
        }

        pub fn print_help(self: *const @This(), writer: *std.Io.Writer, app_name: []const u8, pathstr: []const u8) !void {
            try writer.print("Usage: {s}{s}\n", .{app_name, pathstr});

            const details = self.pathstr_2_details.get(pathstr) orelse return error.CmdTreeInvalidCommand;
            try writer.print("{s}\n", .{self.help_strings[details.help_idx]});

        }
    };
}

////////////////////////////////////////////////////////////////////////////////
// Codegen
////////////////////////////////////////////////////////////////////////////////

// Tested via examples

const Op = enum { count, fmt };
fn Printer(op: Op) type {
    return switch (op) {
        .count => comptime_int,
        .fmt => std.Io.Writer,
    };
}

pub fn print_file(comptime op: Op, self: *Printer(op), module_path: []const u8, ct: CmdTree) !void {
    const data = comptime ct.build_comptime_lists();

    try append(op, self,
        \\const std = @import("std");
        \\const CT = @import("{s}");
        \\
        \\pub const Main = {s};
        \\
        \\
    , .{ module_path, comptime ct.stringify(0) });

    {
        try append(op, self, "pub const Path = ", .{});
        try append_path(op, self, ct.PathWrapped, 0);
        try append(op, self, ";\n\n", .{});
    }

    {
        const payload_src = "std.StaticStringMap(CT." ++ "Payload" ++ ")";
        try append(op, self, "pub const pathstr_2_details = ", .{});
        try append_map_details(op, self, payload_src, data.kvs_details);
        try append(op, self, ";\n\n", .{});
    }
    {
        const path_src = "std.StaticStringMap(Path)";
        try append(op, self, "pub const pathstr_2_path = ", .{});
        try append_map_path(op, self, ct.PathWrapped, path_src, data.kvs_path);
        try append(op, self, ";\n\n", .{});
    }
    {
        try append(op, self, "pub const help_strings: []const []const u8 = &.{{", .{});
        for (data.help_strings) |help_str| {
            //ret = ret ++ std.fmt.comptimePrint("{d} ", .{i}) ++ s;
            var iter = std.mem.splitScalar(u8, help_str, '\n');
            while (iter.next()) |s| {
                try append(op, self, "\n    \\\\{s}", .{s});
            }
            try append(op, self, "\n    ,", .{});
        }
        if (data.help_strings.len > 0) try append(op, self, "\n", .{});
        try append(op, self, "}};\n", .{});
    }
}

pub fn append(comptime op: Op, self: *Printer(op), comptime fmt: []const u8, args: anytype) !void {
    switch (op) {
        .count => self.* += std.fmt.count(fmt, args),
        .fmt => try self.print(fmt, args),
    }
}

fn calc_max_depth(max_depth: u8, comptime ct: *const CmdTree) u8 {
    var depth = max_depth;
    for (ct.fields) |field| {
        switch (field.type_def.def) {
            .Command => depth = @max(depth, calc_max_depth(depth, &field) + 1),
            .Bool, .Enum, .String, .Custom => {},
        }
    }
    return depth;
}

pub fn append_path(comptime op: Op, self: *Printer(op), T: type, indent: u16) !void {
    const pad = "    ";
    switch (@typeInfo(T)) {
        .@"union" => |info| {
            try append(op, self, "union((enum {{ ", .{});
            inline for (0.., @typeInfo(info.tag_type.?).@"enum".fields) |i, field| {
                if (i > 0) try append(op, self, ", ", .{});
                try append(op, self, "{s}", .{field.name});
            }
            try append(op, self, " }})) {{\n", .{});
            inline for (info.fields) |field| {
                for (0..indent) |_| try append(op, self, pad, .{});
                try append(op, self, pad ++ "{s}: ", .{field.name});
                try append_path(op, self, field.type, indent + 1);
                try append(op, self, ",\n", .{});
            }
            for (0..indent) |_| try append(op, self, pad, .{});
            try append(op, self, "}}", .{});
        },
        .int => {
            try append(op, self, "{}", .{CmdTree.HelpIndex});
        },
        else => @compileError("unsupported"),
    }
}

pub fn append_map_details(comptime op: Op, self: *Printer(op), map_src: []const u8, kvs: CmdTree.KVs(Payload)) !void {
    try append(op, self, "{s}.initComptime(&[_]struct{{ []const u8, CT.Payload }}{{", .{map_src});

    if (kvs.len > 0) try append(op, self, "\n", .{});
    for (kvs) |kv| {
        const key, const val = kv;
        try append(op, self, "    .{{ \"{s}\", .{{ .help_idx = {d}, .offset = {d}, .is_leaf_node = {}, ", .{ key, val.help_idx, val.offset, val.is_leaf_node });
        try append(op, self, ".type_def = .{{ .is_array = {}, .def = .{{ .{t} = ", .{ val.type_def.is_array, val.type_def.def });
        switch (val.type_def.def) {
            .Bool => try append(op, self, "{{}} ", .{}),
            .Command => try append(op, self, "{{}} ", .{}),
            .Enum => |x| {
                try append(op, self, ".{{ .is_required = {}, .valid_options = &.{{\n", .{x.is_required});
                for (x.valid_options) |opt| {
                    try append(op, self, "        .{{ \"{s}\", {d} }},\n", opt);
                }
                try append(op, self, "}} }} ", .{});
            },
            .String => |x| try append(op, self, ".{{ .is_required = {} }} ", .{x.is_required}),
            .Custom => @panic("@TODO: Custom printer"),
        }

        try append(op, self, "}} }} ", .{});
        try append(op, self, "}} }},\n", .{});
    }
    try append(op, self, "}})", .{});
}

pub fn append_map_path(comptime op: Op, self: *Printer(op), Path: type, map_src: []const u8, kvs: CmdTree.KVs(Path)) !void {
    try append(op, self, "{s}.initComptime(&[_]struct{{ []const u8, Path }}{{", .{map_src});
    if (kvs.len > 0) try append(op, self, "\n", .{});
    for (kvs) |kv| {
        const key, const val = kv;
        try append(op, self, "    .{{ \"{s}\", {} }},\n", .{ key, val });
    }
    try append(op, self, "}})", .{});
}



////////////////////////////////////////////////////////////////////////////////
// Testing and Debugging
////////////////////////////////////////////////////////////////////////////////

pub fn debug_print_state(cmd: anytype) void {
    print_val(cmd.*, 0);
}

fn print_val(val: anytype, padding: comptime_int) void {
    switch (@typeInfo(@TypeOf(val))) {
        .@"struct" => |info| {
            std.debug.print(".{{", .{});
            if (info.fields.len > 0) std.debug.print("\n", .{});

            inline for (info.fields) |field| {
                std.debug.print("{s}    {s}: ", .{ " " ** padding, field.name });
                print_val(@field(val, field.name), padding + 4);
                std.debug.print(",\n", .{});
            }
            if (info.fields.len > 0) std.debug.print("{s}", .{" " ** padding});
            std.debug.print("}}", .{});
        },
        .pointer => std.debug.print("?", .{}), //std.debug.print("str({s})", .{val}),
        .optional => if (val == null) std.debug.print("null", .{}) else print_val(val.?, padding),
        else => {
            //std.debug.print("{s}\n", .{@typeName(field.type)});
            std.debug.print("{any}", .{val});
        },
    }
}

test {
    std.testing.refAllDecls(@This());
}

test "offsets" {
    const ct_connect = command("Connect to a DB", &.{
        .{ "--username, -u <name>", option([]const u8, "Username to connect with") },

        .{ "direct", command("Connect directly to the database", &.{}) },
        .{ "proxy", command("Connect through a proxy", &.{}) },
    });
    const ct_main = command("", &.{
        .{ "--help, -h", option(bool, "Displays this help menu") },
        .{ "--asdf, -a <hint>", option(?enum(u32) { a, b, c }, "Display example") },
        .{ "--message, -m <string>", option(?[]const u8, "A notification") },

        .{ "--header, -H <http_header>...", option([]const u8, "Add additional curl headers") },

        .{ "connect", ct_connect },
        .{ "version", command("Displays the version", &.{}) },
    });

    const T1 = ct_main.Type;
    const T2 = ct_connect.Type;
    @setEvalBranchQuota(10000);
    const app = app_cmdtree_init(ct_main);

    const get = struct {
        fn lambda(path: []const u8) usize {
            const payload = app.pathstr_2_details.get(path) orelse unreachable;
            return payload.offset;
        }
    }.lambda;
    try std.testing.expectEqual(get(" --help"), @offsetOf(T1, "--help"));
    try std.testing.expectEqual(get(" --asdf"), @offsetOf(T1, "--asdf"));
    try std.testing.expectEqual(get(" --message"), @offsetOf(T1, "--message"));
    try std.testing.expectEqual(get(" --header"), @offsetOf(T1, "--header"));
    try std.testing.expectEqual(get(" connect"), @offsetOf(T1, "connect"));
    try std.testing.expectEqual(get(" version"), @offsetOf(T1, "version"));
    try std.testing.expectEqual(get(" connect --username"), @offsetOf(T1, "connect") + @offsetOf(T2, "--username"));
    try std.testing.expectEqual(get(" connect proxy --username"), @offsetOf(T1, "connect") + @offsetOf(T2, "--username"));
    try std.testing.expectEqual(get(" connect direct"), @offsetOf(T1, "connect") + @offsetOf(T2, "direct"));
    try std.testing.expectEqual(get(" connect proxy"), @offsetOf(T1, "connect") + @offsetOf(T2, "proxy"));
    try std.testing.expectEqual(get(" connect --asdf"), @offsetOf(T1, "--asdf"));
    try std.testing.expectEqual(get(" connect proxy --help"), @offsetOf(T1, "--help"));
    try std.testing.expectEqual(get(" connect proxy --message"), @offsetOf(T1, "--message"));
    try std.testing.expectEqual(get(" version"), @offsetOf(T1, "version"));
}
