const std = @import("std");
const Allocator = std.mem.Allocator;

const Actions = enum {
    Noop,
    Quit,
    Start,
    Step,
    Watch,
    WatchList,
    Undo,
    UndoSet,
    Breakpoint,
    BreakpointList,
    RegPrint,
    RegSet,
    RegClear,
    MemSet,
    MemPrint,
    MemClear,
};

// M - submenu, C - command
// q, quit
// start, run, r
// step  [count=]
// u, undo
// |-- step  [count=]
// \-- size  [val=]
// mem
// |-- set   addr= val= size=word|byte|number
// |-- print addr= [count=]
// \-- clear, clr
// cpu
// |-- print [reg=]
// |-- set   reg= val=
// \-- clear, clr
// b, breakpoint
// |-- set   addr=
// \-- list
// w, watch
// |-- set   addr= size=word|byte|number
// \-- list

const menu: Menu = Menu{
    .name = "",
    .submenus = &.{
        Menu{
            .name = "mem",
            .commands = &.{
                Cmd{
                    .name = "set",
                    .params = &.{
                        Param{
                            .name = "addr",
                        },
                        Param{
                            .name = "val",
                        },
                        Param{
                            .name = "size",
                            .limited = &.{ "word", "byte", "number" },
                        },
                    },
                    .action = .MemSet,
                    .help = "Put value 'val' on address 'addr' in memory as size 'size'",
                },
                Cmd{
                    .name = "print",
                    .alt = &.{"p"},
                    .params = &.{
                        Param{
                            .name = "addr",
                        },
                        Param{
                            .name = "count",
                            .optional = true,
                        },
                    },
                    .action = .MemPrint,
                    .help = "Print some memory at address 'addr', if 'count' provided, print 'count' bytes",
                },
                Cmd{
                    .name = "clear",
                    .alt = &.{"clr"},
                    .action = .RegClear,
                    .help = "Clear all memory",
                },
            },
        },
        Menu{
            .name = "cpu",
            .commands = &.{
                Cmd{
                    .name = "print",
                    .alt = &.{"p"},
                    .params = &.{
                        Param{
                            .name = "reg",
                            .optional = true,
                        },
                    },
                    .action = .RegPrint,
                    .help = "Print all registers or if specified, register 'reg'",
                },
                Cmd{
                    .name = "set",
                    .params = &.{
                        Param{
                            .name = "reg",
                        },
                        Param{
                            .name = "val",
                        },
                    },
                    .action = .RegSet,
                    .help = "Set register 'reg' with value 'val'",
                },
                Cmd{
                    .name = "clear",
                    .alt = &.{"clr"},
                    .action = .RegClear,
                    .help = "Clear all registers",
                },
            },
        },
        Menu{
            .name = "breakpoint",
            .alt = &.{"b"},
            .commands = &.{
                Cmd{
                    .name = "set",
                    .params = &.{
                        Param{
                            .name = "addr",
                        },
                    },
                    .action = .Breakpoint,
                    .help = "Set breakpoint at address 'addr'",
                },
                Cmd{
                    .name = "list",
                    .action = .BreakpointList,
                    .help = "List all breakpoints",
                },
            },
        },
        Menu{
            .name = "undo",
            .alt = &.{"u"},
            .commands = &.{
                Cmd{
                    .name = "step",
                    .params = &.{
                        Param{
                            .name = "count",
                            .optional = true,
                        },
                    },
                    .action = .Undo,
                    .help = "Undoes one instruction or at most 'count' instructions",
                },
                Cmd{
                    .name = "size",
                    .params = &.{
                        Param{
                            .name = "val",
                            .optional = true,
                        },
                    },
                    .action = .UndoSet,
                    .help = "Prints the size of undo buffer. If 'val' provided, sets the undo buffer size to 'val'",
                },
            },
        },
        Menu{
            .name = "watch",
            .alt = &.{"w"},
            .commands = &.{
                Cmd{
                    .name = "set",
                    .params = &.{
                        Param{ .name = "addr" },
                        Param{ .name = "size", .limited = &.{ "word", "byte", "number" } },
                    },
                    .action = .Watch,
                    .help = "Add 'addr' location to the watch list, with 'size'",
                },
                Cmd{
                    .name = "list",
                    .action = .WatchList,
                    .help = "List every item on the watchlist",
                },
            },
        },
    },
    .commands = &.{
        Cmd{
            .name = "quit",
            .alt = &.{"q"},
            .action = .Quit,
            .help = "Quit the program",
        },
        Cmd{
            .name = "start",
            .alt = &.{ "run", "r" },
            .action = .Start,
            .help = "Run simulation",
        },
        Cmd{
            .name = "step",
            .params = &.{Param{ .name = "count", .optional = true }},
            .action = .Step,
            .help = "Execute one instruction or 'count' instructions",
        },
    },
};

const Args = struct {
    action: Actions = .Noop,
    args: std.StringArrayHashMap(Val),

    const Val = union(enum) {
        Str: []const u8,
        Int: u64,
        Flt: f64,
    };

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return Self{
            .args = std.StringArrayHashMap(Val).init(alloc),
        };
    }

    pub fn keys(self: *const Self) [][]const u8 {
        return self.args.keys();
    }

    pub fn contains(self: *const Self, key: []const u8) bool {
        return self.args.contains(key);
    }

    pub fn get(self: *const Self, key: []const u8) ?Val {
        return self.args.get(key);
    }

    pub fn parseAndAdd(self: *Self, key: []const u8, val: []const u8, shoudParse: bool) !void {
        var v: Val = .{ .Str = val };
        if (shoudParse) {
            const int: ?u64 = std.fmt.parseUnsigned(u64, val, 0) catch null;
            const flt: ?f64 = if (int != null) std.fmt.parseFloat(f64, val) catch null else null;
            if (int != null) {
                v = .{ .Int = int.? };
            } else if (flt != null) {
                v = .{ .Flt = flt.? };
            }
        }

        try self.args.put(key, v);
    }

    pub fn deinit(self: *Self) void {
        self.args.deinit();
    }
};

pub fn parseArgs(line: []const u8, alloc: Allocator) !Args {
    var it = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);

    var args = Args.init(alloc);
    errdefer args.deinit();

    var cur_menu: *const Menu = &menu;
    var cmd: ?*const Cmd = null;

    var n = it.next();

    if (n == null) return error.E;

    const w = std.io.getStdOut().writer().any();

    // checking menus and command
    while (n) |name| {
        if (std.mem.eql(u8, name, "?")) {
            const s = cur_menu.str(alloc, true) catch {
                std.debug.print("InternalError: Cannot create help message. Try again.\n", .{});
                return error.E;
            };
            defer alloc.free(s);

            printOut(w, "{s}\n", .{s});
            return error.E;
        }

        if (cur_menu.getSubMenu(name)) |m| {
            cur_menu = m;
        } else if (cur_menu.getCommand(name)) |c| {
            cmd = c;
            break;
        } else {
            if (std.mem.indexOf(u8, name, "=") != null) {
                printOut(w, "Error: menus do not accept parameters.\n", .{});
            } else {
                printOut(w, "Error: unknown menu/command '{s}'.\n", .{name});
                const l = try cur_menu.list(alloc);
                printOut(w, "Available submenus and commands: {s}.\n", .{l});
            }
            return error.E;
        }

        n = it.next();
    }

    if (cmd == null) {
        printOut(w, "Error: '{s}' is not a command\n", .{cur_menu.name});
        return error.E;
    }

    args.action = cmd.?.action;

    // checking command arguments
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "?")) {
            const s = cmd.?.str(alloc, true) catch {
                std.debug.print("InternalError: Cannot create help message. Try again.\n", .{});
                return error.E;
            };
            defer alloc.free(s);

            printOut(w, "{s}\n", .{s});
            return error.E;
        }

        var ait = std.mem.tokenizeScalar(u8, arg, '=');
        const name = ait.next();
        if (name == null) unreachable; // 'it' should not return empty slices

        const param = cmd.?.getParam(name.?);
        if (param == null) {
            printOut(w, "Error: Command '{s}' does not accept parameter '{s}'.\n", .{ cmd.?.name, name.? });
            return error.E;
        }

        const val = ait.next();
        if (val == null or val.?.len == 0) {
            printOut(w, "Error: Parameter '{s}' expects value, but got none.\n", .{name.?});
            return error.E;
        }

        if (!param.?.checkValue(val.?)) {
            const s = param.?.listLimited(alloc) catch {
                std.debug.print("InternalError: Cannot create param string. Try again.\n", .{});
                return error.E;
            };
            defer alloc.free(s);
            printOut(w, "Error: Value '{s}' is incorrect. Should be {s}.", .{ val.?, s });
            return error.E;
        }

        args.parseAndAdd(name.?, val.?, param.?.canBeNum) catch {
            std.debug.print("InternalError: Cannot append arg. Try again.\n", .{});
            return error.E;
        };
    }

    for (cmd.?.params) |*p| {
        if (!p.optional and !args.contains(p.name)) {
            printOut(w, "Error: Command '{s}' requires parameter '{s}'.", .{ cmd.?.name, p.name });
            return error.E;
        }
    }

    return args;
}

const Menu = struct {
    name: []const u8,
    alt: []const []const u8 = &.{},
    submenus: []const Menu = &.{},
    commands: []const Cmd = &.{},

    pub fn getSubMenu(self: *const Menu, submenu_name: []const u8) ?*const Menu {
        for (self.submenus) |*m| {
            if (std.mem.eql(u8, m.name, submenu_name)) {
                return m;
            }

            for (m.alt) |a| {
                if (std.mem.eql(u8, a, submenu_name)) {
                    return m;
                }
            }
        }

        return null;
    }

    pub fn getCommand(self: *const Menu, command_name: []const u8) ?*const Cmd {
        for (self.commands) |*c| {
            if (std.mem.eql(u8, c.name, command_name)) {
                return c;
            }

            for (c.alt) |a| {
                if (std.mem.eql(u8, a, command_name)) {
                    return c;
                }
            }
        }

        return null;
    }

    /// List of submenus and commands
    pub fn list(self: *const Menu, alloc: Allocator) ![]const u8 {
        var l = std.ArrayList(u8).init(alloc);
        errdefer l.deinit();

        for (self.submenus, 0..) |*m, i| {
            if (i < self.submenus.len - 1) {
                try l.append(' ');
            }
            try l.appendSlice(m.name);
        }

        for (self.commands, 0..) |*c, i| {
            if (i < self.commands.len - 1) {
                try l.append(' ');
            }
            try l.appendSlice(c.name);
        }

        return l.toOwnedSlice();
    }

    pub fn str(self: *const Menu, alloc: Allocator, contents: bool) ![]const u8 {
        if (!contents) {
            var buf = try std.fmt.allocPrint(alloc, "{s:<13}", .{" "});
            defer alloc.free(buf);

            var b = try std.fmt.bufPrint(buf, "{s}", .{self.name});
            var len = b.len;

            for (self.alt) |a| {
                b = try std.fmt.bufPrint(buf[len..], ", {s}", .{a});
                len += b.len;
            }

            return alloc.dupe(u8, buf);
        }

        var s = std.ArrayList(u8).init(alloc);
        errdefer s.deinit();

        const buff: []const u8 = try std.fmt.allocPrint(alloc, "{s:<8} {s:<13} PARAMS\n", .{ "TYPE", "NAME" });
        defer alloc.free(buff);
        try s.appendSlice(buff);

        var buf: []const u8 = undefined;
        for (self.submenus) |m| {
            buf = try std.fmt.allocPrint(alloc, "{s:<8} ", .{"M"});
            try s.appendSlice(buf);
            alloc.free(buf);
            try s.appendSlice(m.name);
            try s.append('\n');
        }

        for (self.commands) |c| {
            buf = try std.fmt.allocPrint(alloc, "{s:<8} ", .{"C"});
            try s.appendSlice(buf);
            alloc.free(buf);

            buf = try c.str(alloc, false);
            try s.appendSlice(buf);
            alloc.free(buf);

            try s.append('\n');
        }

        return s.toOwnedSlice();
    }
};

const Cmd = struct {
    name: []const u8,
    alt: []const []const u8 = &.{},
    params: []const Param = &.{},
    action: Actions,
    help: []const u8 = "No message",

    pub fn getParam(self: *const Cmd, param_name: []const u8) ?*const Param {
        for (self.params) |*p| {
            if (std.mem.eql(u8, p.name, param_name)) {
                return p;
            }
        }

        return null;
    }

    pub fn str(self: *const Cmd, alloc: Allocator, andHelp: bool) ![]const u8 {
        var s = std.ArrayList(u8).init(alloc);
        errdefer s.deinit();

        var buff = try std.fmt.allocPrint(alloc, "{s:<13}", .{" "});
        defer alloc.free(buff);

        var b = try std.fmt.bufPrint(buff, "{s}", .{self.name});
        var len = b.len;

        for (self.alt) |a| {
            b = try std.fmt.bufPrint(buff[len..], ", {s}", .{a});
            len += b.len;
        }

        try s.appendSlice(buff);

        var buf: []const u8 = undefined;
        for (self.params) |param| {
            buf = try param.str(alloc);
            try s.append(' ');
            try s.appendSlice(buf);
            alloc.free(buf);
        }

        if (andHelp) {
            try s.append('\n');
            try s.appendSlice(self.help);
        }

        return s.toOwnedSlice();
    }
};

const Param = struct {
    name: []const u8,
    optional: bool = false,
    canBeNum: bool = false,
    limited: ?[]const []const u8 = null,

    pub fn checkValue(self: *const Param, val: []const u8) bool {
        if (self.limited == null) return true; // no limitation

        for (self.limited.?) |v| {
            if (std.mem.eql(u8, val, v)) return true;
        }

        if (self.canBeNum) {
            return isNum(val);
        }

        return false;
    }

    fn isNum(val: []const u8) bool {
        _ = std.fmt.parseUnsigned(u64, val, 0) catch {
            _ = std.fmt.parseFloat(f64, val) catch return false;
        };
        return true;
    }

    fn listLimited(self: *const Param, alloc: Allocator) ![]const u8 {
        var s = std.ArrayList(u8).init(alloc);
        errdefer s.deinit();

        try self._listLimited(&s);

        return s.toOwnedSlice();
    }

    fn _listLimited(self: *const Param, s: *std.ArrayList(u8)) !void {
        if (self.limited) |list| {
            for (list, 0..) |v, i| {
                try s.appendSlice(v);
                if (i < list.len - 1) {
                    try s.append('|');
                }
            }
        }

        if (self.canBeNum) {
            if (self.limited != null) {
                try s.append('|');
            }
            try s.appendSlice("number");
        }
    }

    pub fn str(self: *const Param, alloc: Allocator) ![]const u8 {
        var s = std.ArrayList(u8).init(alloc);
        errdefer s.deinit();

        if (self.optional) {
            try s.append('[');
        }

        try s.appendSlice(self.name);
        try s.append('=');
        try self._listLimited(&s);

        if (self.optional) {
            try s.append(']');
        }

        return s.toOwnedSlice();
    }
};

fn printOut(w: std.io.AnyWriter, comptime format: []const u8, args: anytype) void {
    std.io.AnyWriter.print(w, format, args) catch {
        std.debug.print("InternalError: Unable to write to standard output. Try again.\n", .{});
    };
}
