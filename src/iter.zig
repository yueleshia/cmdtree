// Runtime
const std = @import("std");
const CmdTree = @import("cmdtree.zig");

pub const ArgType = enum {
    eaten,
    positional,
};

root: *anyopaque,
pathstr: std.ArrayList(u8),
is_double_dash: bool = false,
is_leaf_node: bool = false,
current_option: ?struct {
    name: []const u8,
    type_def: CmdTree.TypeDef,
    offset: usize,
} = null,
details: *const std.StaticStringMap(CmdTree.Payload),

const Self = @This();

pub inline fn init(state: *anyopaque, details: *const std.StaticStringMap(CmdTree.Payload)) Self {
    const buffer = comptime blk: {
        var max_len = 0;
        for (details.keys()) |name| {
            max_len = @max(max_len, name.len);
        }
        const buffer: [max_len]u8 = @splat(0);
        break :blk buffer;
    };
    return .{
        .root = state,
        .pathstr = .initBuffer(@constCast(&buffer)),
        .details = details,
    };
}

pub fn next(self: *Self, arg: []const u8) !ArgType {
    // CLAP convention is double dash means skip all subsequent arguments
    if (self.is_double_dash) {
        return .positional;
    } else if (std.mem.eql(u8, "--", arg)) {
        self.is_double_dash = true;
        return .eaten;
    } else if (self.current_option) |opt| {
        // self.option_last indicates the previous arg was an --option/--alias
        self.current_option = null;
        switch (opt.type_def.def) {
            .Bool => unreachable,
            .Command => unreachable,
            .Custom => @panic("@TODO"),
            .Enum => |inner| {
                for (inner.valid_options) |enum_field| {
                    if (std.mem.eql(u8, enum_field[0], arg)) {
                        set_field(self.root, opt.type_def, opt.offset, u32, enum_field[1]);
                        return .eaten;
                    }
                }
                //self.err = .{ .option_name = opt.alias_last, .message = "Must be a one of the following values: @TODO make list" };
                return error.CmdTreeInvalidEnumVariant;
            },
            .String => set_field(self.root, opt.type_def, opt.offset, []const u8, arg),
        }
        return .eaten;
    } else {
        const preappend_len = self.pathstr.items.len;
        {
            if (self.pathstr.capacity < " ".len + arg.len) {
                return if (!self.is_leaf_node) error.CmdTreeUnexpectedCommand else .positional;
            }
            self.pathstr.appendAssumeCapacity(' ');
            self.pathstr.appendSliceAssumeCapacity(arg);
        }

        if (self.details.get(self.pathstr.items)) |field| {
            const is_cmd, self.current_option = if (field.type_def.is_array) switch (field.type_def.def) {
                .Bool => @panic("@TODO: array"),
                .Custom => @panic("@TODO"),
                .Command => unreachable,
                .Enum, .String => .{false, .{ .name = arg, .type_def = field.type_def, .offset = field.offset }},
            } else switch (field.type_def.def) {
                .Bool => blk: {
                    set_field(self.root, field.type_def, field.offset, bool, true);
                    break :blk .{false, null};
                },
                .Custom => @panic("@TODO"),
                .Command => .{ true, null },
                .Enum, .String => .{false, .{ .name = arg, .type_def = field.type_def, .offset = field.offset }},
            };
            if (!is_cmd) self.pathstr.shrinkRetainingCapacity(preappend_len);
            self.is_leaf_node = field.is_leaf_node;
            return .eaten;
        } else if (self.is_leaf_node) {
            self.pathstr.shrinkRetainingCapacity(preappend_len);
            return .positional;
            //self.err = .{ .option_name = arg, .message = " is unexpected command or option" };
        } else {
            self.pathstr.shrinkRetainingCapacity(preappend_len);
            return error.CmdTreeUnexpectedCommand;
        }
    }
}

fn set_field(root: *anyopaque, type_def: CmdTree.TypeDef, offset: usize, T: type, value: T) void {
    switch (type_def.def) {
        .Bool => {
            std.debug.assert(T == bool);
            const ptr: *T = @ptrFromInt(@intFromPtr(root) + offset);
            ptr.* = value;
        },
        .Command => unreachable,
        .Custom => @panic("@TODO"),
        .Enum => |inner| {
            if (inner.is_required) {
                const ptr: *T = @ptrFromInt(@intFromPtr(root) + offset);
                ptr.* = value;
            } else {
                const ptr: *?T = @ptrFromInt(@intFromPtr(root) + offset);
                ptr.* = value;
            }
        },
        .String => |inner| {
            if (inner.is_required) {
                const ptr: *T = @ptrFromInt(@intFromPtr(root) + offset);
                ptr.* = value;
            } else {
                const ptr: *?T = @ptrFromInt(@intFromPtr(root) + offset);
                ptr.* = value;
            }
        }
    }
    //std.debug.print("{*} {d} {d}\n",.{self.root, opt.offset, enum_field[1]});
}

pub fn done(self: *const Self, PathApp: type, pathstr_2_path: *const std.StaticStringMap(PathApp)) !PathApp {
    if (!self.is_leaf_node) {
        return error.CmdTreeExpectingMoreArgs;
    } else if (self.current_option) |_| {
        return error.CmdTreeExpectingMoreArgs;
    }

    return pathstr_2_path.get(self.pathstr.items) orelse std.debug.panic("@TODO: '{s}'", .{self.pathstr.items});
}
