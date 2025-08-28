// All of this should be run at comptime
// @TODO: add validation that no commands/options can have spaces in their name
// @TODO: Refactor type_def into command or option tagged union?
const std = @import("std");

const CT = @This();
const Self = @This();

const EnumInner = u32;
const U32_MAX = std.math.maxInt(u32);
pub const HelpIndex = u32;
pub const AppWraper = enum { main };
pub fn PathWrap(PathCmdTree: type) type {
    return union(AppWraper) {
        main: PathCmdTree,
    };
}

const FieldDef = struct { [:0]const u8, Self };
const ValidType = enum { Bool, Command, Enum, String, Custom };

// Runtime information that can be used for CLAP. Also for help generation
pub const TypeDef = struct {
    is_array: bool,
    def: Def,

    const Def = union(ValidType) {
        Bool: void,
        Command: void,
        Enum: struct {
            is_required: bool,
            valid_options: []const struct { []const u8, EnumInner },
        },
        String: struct { is_required: bool },
        Custom: struct { is_required: bool },
    };
};

name: ?[]const u8, // The name of a command/option is up to the parent, so null by default
aliases: []const []const u8, // We flatten aliases, so fields with this null are aliases
help_hint: []const u8,
type_def: TypeDef, // Runtime data for a type
description: []const u8,
fields: []const Self,

// Adjusted to their true values in the 'App' struct init (see: build_comptime_lists)
offset: comptime_int,
help_index: comptime_int,

Path: type, // Path (union) to each sub-field
Type: type,
PathWrapped: type, // Wrap Path once to we can point to ourself

////////////////////////////////////////////////////////////////////////////////
// Name parsing

const V = struct {
    name: []const u8,
    aliases: []const []const u8,
    hint: []const u8,
    is_array: bool,
};

fn dupe_z(comptime s: []const u8) [:0]const u8 {
    var buf: [s.len + 1]u8 = undefined;
    buf[s.len] = 0;
    @memcpy(buf[0..s.len], s);
    return buf[0..s.len :0];
}

pub inline fn parse_key(def: TypeDef.Def, key: [:0]const u8) V {
    if (!@inComptime()) @compileError("Please call this function with comptime");

    var aliases: []const []const u8 = &.{};
    var cursor: u32 = 0;
    var state: enum { name, sepa, hint, post, dot1, dot2, dot3, done } = .name;
    var is_name_flagged = false;
    var has_hint = false;
    var is_array = false;

    for (0.., key) |i, c| {
        state = sw: switch (state) {
            .name => switch (c) {
                '0'...'9', '-', 'A'...'Z', 'a'...'z' => .name,
                ',', ' ', '!' => {
                    const to_add = key[cursor..i];
                    cursor = i;

                    // Add
                    if (to_add.len > 0) {
                        if (is_name_flagged) {
                            @compileError("You already specified '" ++ aliases[0] ++ "' as the struct field name");
                        }
                        if (c == '!') {
                            is_name_flagged = true;
                            aliases = [1][]const u8{to_add} ++ aliases[0..aliases.len];
                        } else {
                            aliases = aliases[0..aliases.len] ++ [1][]const u8{to_add};
                        }
                        break :sw .sepa;
                    } else if (c == '!') {
                        @compileError("You are specifying an empty struct field name with the postfix '!'. Please put a field name: " ++ key);
                    } else if (c == ',') {
                        @compileError("You are specifying an empty struct field name: " ++ key);
                    } else {
                        break :sw .sepa;
                    }
                },
                '<' => @compileError("Invalid character '<' for a field name. Add a space if you wish to specify a parameter hint"),
                else => @compileError("The character '" ++ .{c} ++ "' in @\"" ++ key ++ "is invalid for a field name"),
            },
            .sepa => switch (c) {
                '0'...'9', '-', 'A'...'Z', 'a'...'z' => {
                    cursor = i;
                    continue :sw .name;
                },
                ',', ' ' => .sepa,
                '<' => {
                    cursor = i;
                    break :sw .hint;
                },
                else => continue :sw .name,
            },
            .hint => switch (c) {
                '_', 'A'...'Z', 'a'...'z' => .hint,
                '>' => {
                    has_hint = true;
                    break :sw .post;
                },
                else => @compileError("The character '" ++ .{c} ++ "' in @\"" ++ key ++ "is invalid for a parameter hint"),
            },
            .post => switch (c) {
                '.' => continue :sw .dot1,
                else => @compileError("Not expecting any characters after then > parameter (hint). If you wish to specify do '--example <hint>...'"),
            },
            .dot1 => switch (c) {
                '.' => {
                    is_array = true;
                    break :sw .dot2;
                },
                else => @compileError("Not expecting any characters after then > parameter (hint). If you wish to specify do '--example <hint>...'"),
            },
            .dot2 => switch (c) {
                '.' => .dot3,
                else => continue :sw .dot1,
            },
            .dot3 => switch (c) {
                '.' => .done,
                else => continue :sw .dot1,
            },
            .done => @compileError("Not expecting any characters after '...': " ++ key),
        };
    }
    switch (state) {
        .name => aliases = aliases ++ &[1][]const u8{key[cursor..]},
        .sepa => {},
        .hint => @compileError("Incomplete parameter hint because missing closing '>'. It should be like: --example <path>"),
        .post => {},
        .dot1, .dot2, .dot3 => @compileError("You should use three dots if you want an array: " ++ key),
        .done => {},
    }

    switch (def) {
        .Bool => if (has_hint) @compileLog("'" ++ key ++ "' should not have a parameter hint. It is type 'bool'."),
        .Command => if (has_hint) @compileError("Commands should not have parameter hints: " ++ key),
        .Enum, .String => if (!has_hint) @compileError("Please specify a parameter hint for '" ++ @tagName(def) ++ "' in: " ++ key),
        .Custom => @compileError(".Custom is TODO"),
    }

    // Check invariants
    for (aliases) |alias| {
        for (alias) |c| {
            switch (c) {
                '0'...'9', '-', 'A'...'Z', 'a'...'z' => {},
                else => @compileError("'" ++ .{c} ++ "' is an invalid character: " ++ key),
            }
        }
    }
    if (is_name_flagged) {
        std.debug.assert(std.mem.count(u8, key, "!") == 1);
    } else {
        std.debug.assert(std.mem.count(u8, key, "!") == 0);
    }

    return .{
        .name = aliases[0],
        .aliases = aliases[1..],
        .hint = if (std.mem.indexOfScalar(u8, key, '!')) |idx| key[0..idx] ++ key[idx + 1 ..] else key,
        .is_array = is_array,
    };
}

////////////////////////////////////////////////////////////////////////////////
// CmdTree creation

pub fn option(T: type, description: []const u8) Self {
    const is_required, const Unmaybe = switch (@typeInfo(T)) {
        .bool => .{ false, T },
        .optional => |info| if (info.child == bool) {
            @compileError("We do not support ?bool, use bool instead");
        } else .{ false, info.child },
        else => .{ true, T },
    };
    const type_def: TypeDef.Def = switch (@typeInfo(Unmaybe)) {
        .bool => .{ .Bool = {} },
        .@"enum" => |info| blk: {
            if (info.tag_type != EnumInner) {
                @compileLog(info.tag_type);
                @compileError("For enums, we only support enum(" ++ @typeName(EnumInner) ++ "){..}");
            }
            var buf: [info.fields.len]struct { []const u8, EnumInner } = @splat(.{ ""[0..0], 0 });
            for (&buf, info.fields) |*x, field| x.* = .{ field.name, field.value };

            const variants = buf; // This appeases the compiler warning about referencing undefined
            break :blk .{ .Enum = .{ .is_required = is_required, .valid_options = &variants } };
        },
        .pointer => |info| if (info.child == u8) .{ .String = .{ .is_required = is_required } } else {
            @compileError(@typeName(T) ++ " is unsupported. We only support []u8 for strings");
        },
        .optional => @compileError(@typeName(T) ++ " is unsupported. You can only put ? at very beginning of type."),
        else => @compileError(@typeName(T) ++ " is unsupported"),
    };

    return .{
        .name = null,
        .aliases = &.{},
        .help_hint = "",
        .help_index = U32_MAX,
        .type_def = .{ .is_array = false, .def = type_def },
        .description = description,
        .fields = &.{},
        .offset = undefined,
        .Path = void,
        .Type = T,
        .PathWrapped = void,
    };
}
pub fn command(description: []const u8, field_defs: []const FieldDef) Self {
    const fields, const Struct = blk: {
        //var fields: [field_defs.len]Self = undefined;
        var fields: []const Self = &.{};
        var idx = 1;
        for (field_defs) |def| {
            const key, var field = def;
            const entry = parse_key(field.type_def.def, key);
            field.name = entry.name;
            field.aliases = entry.aliases;
            field.help_hint = entry.hint;
            field.type_def.is_array = entry.is_array;

            switch (field.type_def.def) {
                .Command => {
                    field.help_index = idx;
                    idx += 1;
                },
                .Bool, .Enum, .String, .Custom => {},
            }

            if (entry.is_array) {
                // We do not want 'CT.option(?type, ...)'
                const is_compile_error = switch (field.type_def.def) {
                    .Bool => false,
                    .Command => false,
                    .Enum => |inner| !inner.is_required,
                    .String => |inner| !inner.is_required,
                    .Custom => |inner| !inner.is_required,
                };
                if (is_compile_error) {
                    @compileError("'" ++ key ++ "' is already an array, it does not make sense to set its type to an optional. Remove the question mark: " ++ @typeName(field.Type));
                }

                switch (field.type_def.def) {
                    .Bool, .Command => {},
                    .Enum => |*inner| inner.is_required = false,
                    .String => |*inner| inner.is_required = false,
                    .Custom => |*inner| inner.is_required = false,
                }
                field.Type = std.ArrayList(field.Type);
            }

            fields = fields ++ .{field};
        }
        const Struct = make_struct(fields);

        break :blk .{ fields, Struct };
    };
    const Path = make_union(fields);

    return .{
        .name = null,
        .aliases = &.{},
        .help_hint = "",
        .help_index = U32_MAX,
        .type_def = .{ .is_array = false, .def = .{ .Command = {} } },
        .description = description,
        .fields = fields,
        .offset = 0,
        .Path = Path,
        .Type = Struct,
        .PathWrapped = PathWrap(Path),
    };
}

fn adjust_offset(Struct: type, base_offset: comptime_int, fields: []const Self) []const Self {
    var ret: []const Self = &.{};
    for (fields) |f| {
        var field = f;

        const offset: comptime_int = base_offset + @offsetOf(Struct, field.name.?);
        field.offset = offset;
        field.fields = adjust_offset(field.Type, offset, field.fields);

        ret = ret ++ .{field};
    }
    return ret;
}

// Recursively add help_strings
fn adjust_help_index(help_idx: *comptime_int, fields: []const Self) []const Self {
    var ret: []const Self = &.{};

    for (fields) |f| {
        var field = f;

        switch (field.type_def.def) {
            .Command => {
                field.help_index = help_idx.*;
                help_idx.* += 1;

                field.fields = adjust_help_index(help_idx, field.fields);
            },
            .Bool, .Enum, .String, .Custom => {},
        }
        ret = ret ++ .{field};
    }
    return ret;
}

pub fn make_struct(fields: []const Self) type {
    var reified: [fields.len]std.builtin.Type.StructField = undefined;
    for (&reified, fields) |*r, entry| {
        r.* = std.builtin.Type.StructField{
            .name = dupe_z(entry.name.?),
            .type = entry.Type,

            // Might actually be better to force people to init their structs
            // (.default_value_ptr == null) to have a reified example of all fields
            .default_value_ptr = null,
            //.default_value_ptr = blk: {
            //    if (entry.type_def.count == -1) {
            //        break :blk if (entry.type_def.is_required) null else &@as(entry.T, null);
            //        //break :blk null;
            //    } else break :blk switch (entry.type_def) {
            //        .Bool => &false,
            //        .Command => &@as(entry.T, entry.T{}),
            //        .Enum => if (entry.data.is_required) null else &@as(entry.T, null),
            //        .String => if (entry.data.is_required) @ptrCast(&@as(entry.T, ""[0..])) else &@as(entry.T, null),
            //    };
            //},
            .is_comptime = false,
            .alignment = @alignOf(entry.Type),
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &reified,
        .decls = &.{},
        .is_tuple = false,
    } });
}

// For the switch statement after parsing
pub fn make_union(fields: []const Self) type {
    std.debug.assert(@inComptime());

    var enums: [fields.len]std.builtin.Type.EnumField = undefined;
    var reified: [fields.len]std.builtin.Type.UnionField = undefined;
    var len = 0;
    for (fields) |field| {
        if (field.type_def.def != .Command) continue;
        enums[len] = .{
            .name = dupe_z(field.name.?),
            .value = len,
        };
        reified[len] = .{
            .name = dupe_z(field.name.?),
            .type = field.Path,
            .alignment = @alignOf(field.Path),
        };
        len += 1;
    }
    if (len == 0) {
        return HelpIndex;
    }

    const Tags = @Type(.{ .@"enum" = .{
        .tag_type = u32,
        .fields = enums[0..len],
        .decls = &.{},
        .is_exhaustive = true,
    } });

    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = Tags,
        .fields = reified[0..len],
        .decls = &.{},
    } });
}

pub fn stringify(ct: *const Self, indent: comptime_int) []const u8 {
    if (!@inComptime()) @compileError("Must run this in comptime");

    var acc: []const u8 = "";
    acc = acc ++ if (ct.type_def.is_array) "std.ArrayList(" else switch (ct.type_def.def) {
        .Bool => "",
        .Command => "",
        .Enum => |inner| if (!inner.is_required) "?" else "",
        .String => |inner| if (!inner.is_required) "?" else "",
        .Custom => |inner| if (!inner.is_required) "?" else "",
    };
    const pad = "    " ** indent;

    switch (ct.type_def.def) {
        .Bool => acc = acc ++ "bool",
        .Command => {
            acc = acc ++ "struct {";
            if (ct.fields.len > 0) acc = acc ++ "\n";
            for (ct.fields) |field| {
                if (std.mem.indexOfScalar(u8, field.name.?, '-')) |_| {
                    acc = acc ++ pad ++ "    @\"" ++ field.name.? ++ "\": ";
                } else {
                    acc = acc ++ pad ++ "    " ++ field.name.? ++ ": ";
                }
                acc = acc ++ field.stringify(indent + 1);
                acc = acc ++ ",\n";
            }
            if (ct.fields.len > 0) acc = acc ++ pad;
            acc = acc ++ "}";
        },
        .Enum => |extra| {
            acc = acc ++ "enum(" ++ @typeName(EnumInner) ++ ") {\n";
            for (extra.valid_options) |field| {
                const name, const val = field;
                acc = acc ++ std.fmt.comptimePrint("{s}    {s} = {d},\n", .{ pad, name, val });
            }
            acc = acc ++ pad ++ "}";
        },
        .String => acc = acc ++ "[]const u8",
        .Custom => {},
    }
    if (ct.type_def.is_array) acc = acc ++ ")";

    return acc;
}

test "parse_exclamation" {
    const ct_plain = command("Connect to a DB", &.{
        .{ "-u, --username <name>", option([]const u8, "Username to connect with") },
        .{ "-p, --password <pass>", option([]const u8, "Password to connect with") },
    });
    const ct_override = command("Connect to a DB", &.{
        .{ "-u, --username! <name>", option([]const u8, "Username to connect with") },
        .{ "-p, --password! <pass>", option([]const u8, "Password to connect with") },
    });

    try std.testing.expect(@hasField(ct_plain.Type, "-u"));
    try std.testing.expect(@hasField(ct_plain.Type, "-p"));
    try std.testing.expect(@hasField(ct_override.Type, "--username"));
    try std.testing.expect(@hasField(ct_override.Type, "--password"));
}

test "stringify" {
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

    try std.testing.expectEqualStrings(@as([]const u8,
        \\struct {
        \\    @"--help": bool,
        \\    @"--asdf": ?enum(u32) {
        \\        a = 0,
        \\        b = 1,
        \\        c = 2,
        \\    },
        \\    @"--message": ?[]const u8,
        \\    @"--header": std.ArrayList([]const u8),
        \\    connect: struct {
        \\        @"--username": []const u8,
        \\        direct: struct {},
        \\        proxy: struct {},
        \\    },
        \\    version: struct {},
        \\}
    ), comptime ct_main.stringify(0));
}

////////////////////////////////////////////////////////////////////////////////

const HELP_PADDING = " " ** 2;
const HELP_COL_GAP = " " ** 2;

pub const Payload = struct {
    help_idx: HelpIndex,
    offset: usize,
    type_def: TypeDef,
    is_leaf_node: bool,
};
pub fn KVs(T: type) type {
    return []const struct { []const u8, T };
}

pub fn ComptimeParsed(Path: type) type {
    return struct {
        kvs_details: KVs(Payload),
        kvs_path: KVs(Path),
        help_strings: []const []const u8,
    };
}
pub inline fn build_comptime_lists(src: Self) ComptimeParsed(src.PathWrapped) {
    if (!@inComptime()) @compileError("Must run this in comptime");

    var ct = src;
    ct.offset = 0;
    ct.fields = adjust_offset(ct.Type, 0, ct.fields);

    const main_help = build_help(ct.fields, &.{});
    var idx = 1;
    ct.help_index = 0;
    ct.fields = adjust_help_index(&idx, ct.fields);

    return build_kv_from_tree(
        ct.PathWrapped,
        &ct,
        ComptimeParsed(ct.PathWrapped){
            .kvs_details = &.{},
            .kvs_path = &.{},
            .help_strings = &[1][]const u8{main_help},
        },
        "", // Start all paths with "" for the main app
        &.{""}, // Start all paths with "", e.g. " part2" == &.{"", "part2"}
        &.{},
    );
}

// Recursively create all the runtime data (Payload) for each field in the entire tree
//
// The reason we have parent_option is so that in the following
// ```
//     CT.command(&.{
//       .{"--log-level", &.{}, CT.option(enum { debug, error }), ""},
//       .{"sub", &.{}, CT.command("", &.{}) },
//     })
// ```
// both of the following are valid
//    app --log-level debug
//    app sub --log-level debug
//
pub fn build_kv_from_tree(
    Union: type, // Keep this constant across recursive calls
    ct: *const Self,
    data: ComptimeParsed(Union),

    // This is the key that will appear in the std.StaticStringMap
    // Different aliases will have different 'pathstr_key'
    pathstr_key: []const u8,

    // This are real-names only so all aliases have the same 'path_names'
    path_names: []const []const u8,
    parent_fields: []const Self,
) ComptimeParsed(Union) {
    if (!@inComptime()) @compileError("Must run this in comptime");

    var ret = data;

    ////////////////////////////////////////////////////////////////////////
    // Parse current cmdtree node 'ct'
    var parents = parent_fields;
    var is_leaf_node = true;
    for (ct.fields) |field| {
        if (field.type_def.def == .Command) {
            is_leaf_node = false;
            continue;
        }
        parents = parents ++ [1]Self{field};
    }

    const payload = Payload{
        .offset = ct.offset,
        .help_idx = ct.help_index,
        .type_def = ct.type_def,
        .is_leaf_node = is_leaf_node,
    };
    if (ct.type_def.def == .Command and ct.help_index >= data.help_strings.len) {
        // The execution order of 'adjust_help_index()' should be the same 'build_kv_from_tree()'
        std.debug.assert(ct.help_index == data.help_strings.len);
        ret.help_strings = ret.help_strings ++ .{build_help(ct.fields, parent_fields)};
    }

    ret.kvs_details = ret.kvs_details ++ .{.{ pathstr_key, payload }};
    if (is_leaf_node and ct.type_def.def == .Command) {
        ret.kvs_path = ret.kvs_path ++ .{.{ pathstr_key, init_union(Union, path_names, ct.help_index) }};
        //ret.kvs_path = ret.kvs_path ++ .{ .{ pathstr_key, undefined } };
    }

    ////////////////////////////////////////////////////////////////////////
    //

    // Add ct's fields to the list of parent_options
    var mine_and_parents = ct.fields;
    for (parent_fields) |field| {
        if (field.type_def.def == .Command) unreachable;
        mine_and_parents = mine_and_parents ++ [1]Self{field};
        //for (field.aliases) |alias| {
        //    var f = field;
        //    f.name = alias;
        //    mine_and_parents = mine_and_parents ++ [1]Self{f};
        //}
    }

    // Recurse over each field
    for (mine_and_parents) |field| {
        // Only commands have extra options
        const parent_opts = if (field.type_def.def == .Command) parents else &[0]Self{};

        const pathstr_major = path_names ++ .{field.name.?};
        ret = build_kv_from_tree(Union, &field, ret, pathstr_key ++ " " ++ field.name.?, pathstr_major, parent_opts);

        for (field.aliases) |alias| {
            ret = build_kv_from_tree(Union, &field, ret, pathstr_key ++ " " ++ alias, pathstr_major, parent_opts);
        }
    }
    return ret;
}

// Translates e.g. " connect proxy" into
//     @unionInit(Path, "main",
//         @unionInit(Path, "connect",
//             @unionInit(@FieldType(Path, "connect"), "proxy",
//                 void
//             )
//         )
//     )
fn init_union(T: type, path: []const []const u8, help_index: HelpIndex) T {
    std.debug.assert(path[0].len == 0);

    var Ty = @FieldType(T, "main");
    var types: [path.len - 1]type = undefined;
    for (&types, path[1..]) |*x, part| {
        x.* = Ty;
        Ty = @FieldType(Ty, part);
    }
    std.debug.assert(types[0] == @FieldType(T, "main"));
    std.debug.assert(Ty == HelpIndex); // Is a leaf node, i.e. has no subcommands

    return T{ .main = init_union_recursive(&types, path[1..], help_index) };
    //return T{ .main = undefined };
}

// Automates @unionInit(T, "field1", @union(T.field1, "field2", @union(T.field1.field2, ...)))
fn init_union_recursive(comptime tys: []type, parts: []const []const u8, help_index: HelpIndex) tys[0] {
    std.debug.assert(tys.len == parts.len);
    if (tys.len == 1) {
        return @unionInit(tys[0], parts[0], help_index);
    } else {
        return @unionInit(tys[0], parts[0], init_union_recursive(tys[1..], parts[1..], help_index));
    }
}

////////////////////////////////////////////////////////////////////////////////
// Help
////////////////////////////////////////////////////////////////////////////////

fn build_help(fields: []const Self, parent_fields: []const Self) []const u8 {
    if (!@inComptime()) @compileError("Must run this in comptime");

    const col_width, const subcmd_count = blk: {
        var max_width, var cmd_count = .{ 0, 0 };
        for (fields ++ parent_fields) |field| {
            max_width = @max(max_width, field.help_hint.len);
            switch (field.type_def.def) {
                .Command => cmd_count += 1,
                else => {},
            }
        }
        break :blk .{ max_width, cmd_count };
    };
    const whitespace: [col_width + HELP_COL_GAP.len]u8 = @splat(' ');

    var ret: []const u8 = "";

    if (subcmd_count > 0) {
        ret = ret ++ "\nCommand\n\n";
        for (fields) |field| {
            switch (field.type_def.def) {
                .Command => {},
                .Bool, .Enum, .String, .Custom => continue,
            }
            //const col_sep = std.fmt.comptimePrint("{d}", col_width - field.help_hint.len);

            ret = ret ++ HELP_PADDING ++ field.help_hint;
            ret = ret ++ whitespace[field.help_hint.len..];
            ret = ret ++ field.description ++ "\n";
        }
    }
    if (fields.len > subcmd_count) {
        ret = ret ++ "\nOptions\n\n";
        for (fields) |field| {
            switch (field.type_def.def) {
                .Command => continue,
                .Bool, .Enum, .String, .Custom => {},
            }
            ret = ret ++ HELP_PADDING ++ field.help_hint;
            ret = ret ++ whitespace[field.help_hint.len..];
            ret = ret ++ field.description ++ "\n";
        }
    }

    if (parent_fields.len > 0) {
        ret = ret ++ "\nGlobal Options\n\n";
        for (parent_fields) |field| {
            switch (field.type_def.def) {
                .Command => @compileError("There should be no subcommands in parent_fields"),
                .Bool, .Enum, .String, .Custom => {},
            }
            ret = ret ++ HELP_PADDING ++ field.help_hint;
            ret = ret ++ whitespace[field.help_hint.len..];
            ret = ret ++ field.description ++ "\n";
        }
    }
    return ret;
}
