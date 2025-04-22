const std = @import("std");

const param_example = "[hint]";
const padding = " " ** 4;

pub const ValidType = enum {
    Bool,
    Command,
    Enum,
    // No number because it is not worth trying to support zig's u0-u128, i0-i128
    String,
};
pub const RuntimeType = union(ValidType) {
    Bool: void,
    Command: void,
    Enum: []const EnumFieldEvaltime, // Since we have a pointer, might as well use usize since it is the same alignment
    String: void,
};
const EnumFieldEvaltime = struct { []const u8, usize };

pub const FieldComptime = struct {
    name_raw: [:0]const u8,
    T: type,
    Union: type,
    data: Field,
    fields: []const FieldComptime,
};
pub const Field = struct {
    aliases: []const []const u8,
    aliases_help: []const u8,
    offset: u32,
    description: []const u8,
    extra: RuntimeType,
    is_required: bool,
    is_leaf_node: bool,
    repeat_max: u16, // We could increase this size, but do you really need 65535 items to be specified on the command line?
};

fn State(Union: type) type {
    return struct {
        help: []const KVHelp, // Help menu
        eval: []const KVEval, // Evaluate arguments
        flow: []const KVFlow, // Control flow

        const KVHelp = struct { []const u8, []const u8 };
        const KVEval = struct { []const u8, Field };
        const KVFlow = struct { []const u8, Union };
    };
}

////////////////////////////////////////////////////////////////////////////////
// Comptime: Struct construction
////////////////////////////////////////////////////////////////////////////////
pub fn option(name: [:0]const u8, T: type, aliases: []const []const u8, description: []const u8) FieldComptime {
    const is_required, const repeat_max, const T_child: type = blk: {
        // Remove ?
        const is_required, const ty_unwrapped = switch (@typeInfo(T)) {
            .bool => .{ false, T },
            .optional => |info| if (info.child == bool) {
                @compileError("We do not support ?bool, use bool instead");
            } else .{ false, info.child },
            else => .{ true, T },
        };
        // Remove the [1000]
        switch (@typeInfo(ty_unwrapped)) {
            .array => |info| break :blk .{ is_required, info.len, info.child },
            else => break :blk .{ is_required, 1, ty_unwrapped },
        }
    };

    const extra: RuntimeType = switch (@typeInfo(T_child)) {
        .bool => .{ .Bool = undefined },
        .@"enum" => |info| blk: {
            if (info.tag_type != usize) {
                @compileError("For enums, we only support enum(usize){..}");
            }
            var buf: [info.fields.len]struct { []const u8, usize } = undefined;
            for (&buf, info.fields) |*x, field| x.* = .{ field.name, field.value };

            const variants = buf; // This appeases the compiler warning about referencing undefined
            break :blk .{ .Enum = &variants };
        },
        .pointer => |info| if (info.child == u8) .{ .String = undefined } else {
            @compileError(@typeName(T) ++ " is unsupported. We only support []u8 for strings");
        },
        .optional => @compileError(@typeName(T) ++ " is unsupported. You can only put ? at very beginning of type."),
        else => @compileError(@typeName(T) ++ " is unsupported"),
    };

    const aliases_joined = blk: {
        var buf: []const u8 = if (aliases.len > 0) aliases[0] else {
            @compileError("Specify at least one string for aliases. This matches with the cli argument.");
        };
        for (aliases[1..]) |alias| buf = buf ++ ", " ++ alias;
        break :blk buf;
    };

    return .{
        .name_raw = name,
        .T = T,
        .Union = void,
        .data = .{
            .aliases = aliases,
            .aliases_help = aliases_joined,
            .offset = 0, // to be updated in by the parent Command()
            .description = description,
            .extra = extra,
            .is_required = is_required,
            .is_leaf_node = true,
            .repeat_max = repeat_max,
        },
        .fields = &.{},
    };
}

pub fn command(name: [:0]const u8, description: []const u8, fields: []const FieldComptime) FieldComptime {
    const T = make_struct(fields);
    var copy: [fields.len]FieldComptime = undefined;
    var is_leaf_node = true;
    for (&copy, fields) |*x, y| {
        x.* = y;
        x.data.offset = @offsetOf(T, y.name_raw);
        if (y.data.extra == .Command) is_leaf_node = false;
    }

    return .{
        .name_raw = name,
        .T = make_struct(fields),
        .Union = make_union(fields),
        .data = .{
            .aliases = &.{name},
            .aliases_help = name,
            .offset = 0,
            .description = description,
            .extra = .{ .Command = undefined },
            .is_required = false,
            .is_leaf_node = is_leaf_node,
            .repeat_max = 1,
        },
        .fields = &copy,
    };
}

pub fn init(root: FieldComptime) CmdTree(root.Union) {
    const state = State(root.Union){
        .eval = &.{},
        .help = &.{},
        .flow = &.{},
    };
    const compiled = compile(root.Union, state, root, &.{}, 0, &.{});
    var key_longest = 0;
    for (compiled.help) |x| key_longest = @max(key_longest, x[0].len);

    return .{
        .initial = std.StaticStringMap(root.Union).initComptime(compiled.flow),
        .parsing = std.StaticStringMap(Field).initComptime(compiled.eval),
        .helping = std.StaticStringMap([]const u8).initComptime(compiled.help),
        .key_longest = key_longest,
        .Type = root.T,
        .TypeCommand = root.Union,
    };
}

// Recursive part of `init()`
// Recurse over the entire command tree
// `s` holds data builds up over the entire recursion
// `path`, `offset`, `option_parents` differ depending on the tree branch
fn compile(Union: type, s: State(Union), cmd: FieldComptime, path: []const []const u8, offset: comptime_int, options_parents: []const FieldComptime) State(Union) {
    std.debug.assert(cmd.data.extra == .Command);
    std.debug.assert(@inComptime());

    const S = State(Union);

    var state = s;
    var joined: []const u8 = "";
    for (path) |x| joined = joined ++ " " ++ x;

    state.eval = state.eval ++ &[_]S.KVEval{.{ joined, cmd.data }};
    state.help = state.help ++ &[_]S.KVHelp{.{ joined, make_help_string(cmd) }};
    if (cmd.data.is_leaf_node) {
        state.flow = state.flow ++ &[_]S.KVFlow{.{ joined, init_union(Union, path) }};
    }

    // Proprogate options downwards so that parent option can be specified at any level
    // e.g. `cmd --help` should work even at `cmd subcmd --help`
    var options_all = options_parents;
    for (cmd.fields) |field| {
        switch (field.data.extra) {
            .Command => {},
            else => options_all = options_all ++ &[_]FieldComptime{field},
        }
    }

    //
    for (cmd.fields ++ options_parents) |field| {
        switch (field.data.extra) {
            .Command => {
                const path_subcmd = path ++ &[_][]const u8{field.name_raw};
                const offset_cmd = offset + @offsetOf(cmd.T, field.name_raw);
                state = compile(Union, state, field, path_subcmd, offset_cmd, options_all);
            },
            else => for (field.data.aliases) |alias| {
                const key = joined ++ " " ++ alias;
                state.eval = state.eval ++ &[_]S.KVEval{.{ key, field.data }};
            },
        }
    }
    return state;
}

////////////////////////////////////////////////////////////////////////////////
// Eval time: argument parsing
////////////////////////////////////////////////////////////////////////////////

// The API data structre for interacting with this library
pub fn CmdTree(Union: type) type {
    return struct {
        initial: std.StaticStringMap(Union),
        helping: std.StaticStringMap([]const u8), // For printing help menus
        parsing: std.StaticStringMap(Field), // For parsing command line arguments
        key_longest: comptime_int,
        Type: type, // So that the user can access the data-holder type easily
        TypeCommand: type,

        const Self = @This();

        pub inline fn init_iter(comptime self: *const Self) Iter(self.TypeCommand, self) {
            const len = comptime blk: {
                var len = 0;
                for (self.parsing.keys()) |k| len = @max(len, k.len);
                break :blk len;
            };

            // Inline allocate
            var path_buf: [len]u8 = undefined;
            var temp_buf: [len]u8 = undefined;
            var path_alloc = std.heap.FixedBufferAllocator.init(&path_buf);
            var temp_alloc = std.heap.FixedBufferAllocator.init(&temp_buf);
            return .{
                .err = .{ .option_name = "", .message = "" },
                .is_double_dash = false,
                .is_leaf_node = false,
                .option_last = null,
                .path = std.ArrayList(u8).initCapacity(path_alloc.allocator(), len) catch unreachable,
                .temp = std.ArrayList(u8).initCapacity(temp_alloc.allocator(), len) catch unreachable,
            };
        }

        pub inline fn print_help(self: *const Self, writer: anytype, root_name: []const u8, path: []const []const u8) !void {
            var path_buf: [self.key_longest]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&path_buf);
            var args_joined = std.ArrayList(u8).initCapacity(fba.allocator(), self.key_longest) catch unreachable;

            for (path) |arg| {
                args_joined.append(' ') catch return error.CmdTreeInvalidCommand;
                args_joined.appendSlice(arg) catch return error.CmdTreeInvalidCommand;
            }

            return help_base(self.helping, writer, root_name, args_joined.items);
        }

        pub fn set(self: *const Self, root: *self.Type, path_joined: []const u8, value: anytype) !void {
            const field = self.parsing.get(path_joined) orelse return error.CmdTreeInvalidcommand;
            const T = @TypeOf(value);
            const ptr: *T = @ptrFromInt(@intFromPtr(root) + field.offset);
            ptr.* = value;
        }
    };
}

fn help_base(help: std.StaticStringMap([]const u8), writer: anytype, root_name: []const u8, path_joined: []const u8) !void {
    _ = try writer.write("Usage: ");
    _ = try writer.write(root_name);
    _ = try writer.write(path_joined);
    _ = try writer.write("\n");

    std.debug.print("Trying to lookup '{s}'\n", .{path_joined});
    const msg = help.get(path_joined) orelse return error.CmdTreeInvalidCommand;
    std.debug.print("Trying to lookup '{s}'\n", .{msg});
    _ = try writer.write(msg);
}

pub fn Iter(Union: type, cmdtree: *const CmdTree(Union)) type {
    return struct {
        //root: ptr,
        //command: ptr,
        err: Diagnostic,
        is_double_dash: bool,
        is_leaf_node: bool,
        option_last: ?struct {
            alias_last: []const u8,
            field: Field,
        },
        path: std.ArrayList(u8),
        temp: std.ArrayList(u8),

        const Self = @This();
        pub const Diagnostic = struct {
            option_name: []const u8,
            message: []const u8,
        };

        const ErrorSet = error{
            CmdTreeInvalidEnumVariant,
            CmdTreeDashArgument,
            CmdTreeUnexpectedCommand,
        };

        pub fn set(root: *cmdtree.Type, offset: usize, value: anytype) void {
            const T = @TypeOf(value);
            const ptr: *T = @ptrFromInt(@intFromPtr(root) + offset);
            ptr.* = value;
        }

        pub fn print_help(self: *Self, writer: anytype, root_name: []const u8) !void {
            return help_base(cmdtree.helping, writer, root_name, self.path.items) catch |err| switch (err) {
                error.CmdTreeInvalidCommand => std.debug.panic("Iterators should only be valid paths: '{s}'\n", .{self.path.items}),
                else => |e| return e,
            };
        }

        pub fn next(self: *Self, root: *cmdtree.Type, arg: []const u8) ErrorSet!bool {
            if (self.is_double_dash) {
                return true;
            } else if (std.mem.eql(u8, "--", arg)) {
                self.is_double_dash = true;
                return false;
            } else if (self.option_last) |pair| {
                self.option_last = null;
                switch (pair.field.extra) {
                    .Bool => unreachable,
                    .Command => unreachable,
                    .Enum => |variants| {
                        for (variants) |variant| {
                            if (std.mem.eql(u8, variant[0], arg)) {
                                set(root, pair.field.offset, variant[1]);
                                return false;
                            }
                        }
                        self.err = .{ .option_name = pair.alias_last, .message = "Must be a one of the following values: @TODO make list" };
                        return error.CmdTreeInvalidEnumVariant;
                    },
                    .String => set(root, pair.field.offset, arg),
                }
                return false;
            } else {
                self.temp.clearRetainingCapacity();
                self.temp.appendSliceAssumeCapacity(self.path.items);
                self.temp.appendAssumeCapacity(' ');
                self.temp.appendSliceAssumeCapacity(arg);

                //std.debug.print("DEBUG: inner1 {s} {s}\n", .{self.temp.items, arg});
                if (cmdtree.parsing.get(self.temp.items)) |field| {
                    //std.debug.print("DEBUG: inner2 {s} {d}\n", .{field.aliases, parsing.get(self.cmd_parent, self.temp.items) catch |err| std.debug.panic("ERROR {!} could not find ''\n", .{err})});
                    switch (field.extra) {
                        .Bool => set(root, field.offset, true),
                        .Command => {
                            std.debug.assert(!self.is_leaf_node);
                            self.is_leaf_node = field.is_leaf_node;
                            self.path.appendAssumeCapacity(' ');
                            self.path.appendSliceAssumeCapacity(arg);
                        },
                        .Enum, .String => self.option_last = .{ .alias_last = arg, .field = field },
                    }
                    return false;
                } else if (std.mem.startsWith(u8, arg, "-")) {
                    self.err = .{ .option_name = arg, .message = " is unexpected option" };
                    return error.CmdTreeDashArgument;
                } else if (self.is_leaf_node) {
                    return true;
                } else {
                    self.err = .{ .option_name = arg, .message = " is unexpected command or option" };
                    return error.CmdTreeUnexpectedCommand;
                }
            }
        }

        // You can use the return value to switch to get which subcommand was chosen
        // Alternatively you can use `.path` which contains a space-delimited
        // list of subcommand names (root is ""). This is what `.next()` does.
        pub fn done(self: *Self) !Union {
            if (self.option_last) |pair| {
                self.err = .{ .option_name = pair.alias_last, .message = " requires a parameter" };
                return error.CmdTreeMissingParameter;
            }

            if (cmdtree.initial.get(self.path.items)) |x| {
                return x;
            } else if (cmdtree.helping.get(self.path.items)) |msg| {
                self.err = .{ .option_name = "Please pick a subcommand", .message = msg };
                return error.Unfinished;
            } else {
                self.err = .{ .option_name = self.path.items, .message = " is missing a help entry" };
                return error.Unfinished;
            }
        }
    };
}

////////////////////////////////////////////////////////////////////////////////
// Helpers
////////////////////////////////////////////////////////////////////////////////
pub inline fn make_struct(fields: []const FieldComptime) type {
    std.debug.assert(@inComptime());

    var reified: [fields.len]std.builtin.Type.StructField = undefined;
    for (0.., fields) |i, entry| {
        reified[i] = .{
            .name = entry.name_raw,
            .type = entry.T,
            .default_value_ptr = blk: {
                if (entry.data.repeat_max != 1) {
                    break :blk if (entry.data.is_required) null else &@as(entry.T, null);
                    //break :blk null;
                }

                break :blk switch (entry.data.extra) {
                    .Bool => &false,
                    .Command => &@as(entry.T, entry.T{}),
                    .Enum => if (entry.data.is_required) null else &@as(entry.T, null),
                    .String => if (entry.data.is_required) @ptrCast(&@as(entry.T, ""[0..])) else &@as(entry.T, null),
                };
            },
            .is_comptime = false,
            .alignment = @alignOf(entry.T),
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &reified,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn make_union(fields: []const FieldComptime) type {
    std.debug.assert(@inComptime());

    var enums: [fields.len]std.builtin.Type.EnumField = undefined;
    var reified: [fields.len]std.builtin.Type.UnionField = undefined;
    var len = 0;
    for (fields) |entry| {
        if (entry.data.extra == .Command) {
            enums[len] = .{
                .name = entry.name_raw,
                .value = len,
            };
            reified[len] = .{
                .name = entry.name_raw,
                .type = entry.Union,
                .alignment = @alignOf(entry.Union),
            };
            len += 1;
        }
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

// Automates @unionInit(T, "field1", @union(T.field1, "field2", @union(T.field1.field2, ...)))
fn init_union(T: type, path: []const []const u8) T {
    var types: [path.len + 1]type = undefined;
    var Ty = T;
    types[0] = T;
    for (types[1..types.len], path) |*x, entry| {
        Ty = @FieldType(Ty, entry);
        x.* = Ty;
    }

    var ret: Ty = undefined;
    var ptr: *anyopaque = &ret;
    ptr = ptr;
    for (0..types.len - 1) |i| {
        const old = @as(*Ty, @ptrCast(@alignCast(ptr))).*;
        Ty = types[types.len - i - 2];
        const entry = path[path.len - i - 1];

        var new: Ty = @unionInit(Ty, entry, old);
        ptr = @ptrCast(&new);
    }
    const old = @as(*Ty, @ptrCast(@alignCast(ptr))).*;
    return old;
}

fn make_help_string(cmd: FieldComptime) []const u8 {
    const col_width, const subcmd_count, const option_count = blk: {
        var max, var cmd_count, var opt_count = .{ 0, 0, 0 };
        for (cmd.fields) |x| {
            max = @max(max, switch (x.data.extra) {
                .Bool, .Command => x.data.aliases_help.len,
                .Enum, .String => x.data.aliases_help.len + " ".len + param_example.len,
            });
            if (x.data.extra == .Command) cmd_count += 1 else opt_count += 1;
        }
        break :blk .{ max + padding.len, cmd_count, opt_count };
    };

    var ret: []const u8 = "";

    if (subcmd_count > 0) {
        ret = ret ++ "\nCommand\n\n";
        for (cmd.fields) |x| {
            if (x.data.extra == .Command) {
                ret = ret ++ format_row(col_width, x);
            }
        }
    }

    if (option_count > 0) {
        ret = ret ++ "\nOptions\n\n";
        for (cmd.fields) |x| {
            if (x.data.extra != .Command) {
                ret = ret ++ format_row(col_width, x);
            }
        }
    }
    return ret;
}

fn format_row(col_width: comptime_int, x: FieldComptime) []const u8 {
    var buf: []const u8 = "  ";
    buf = buf ++ x.data.aliases_help;
    switch (x.data.extra) {
        .Bool, .Command => {
            buf = buf ++ " " ** (col_width - x.data.aliases_help.len);
        },
        .Enum, .String => {
            buf = buf ++ " " ++ param_example;
            buf = buf ++ " " ** (col_width - x.data.aliases_help.len - " ".len - param_example.len);
        },
    }
    buf = buf ++ x.data.description ++ "\n";
    return buf;
}
