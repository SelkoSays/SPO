const std = @import("std");
const Allocator = std.mem.Allocator;

const Actions = enum {
    Quit,
    PrintAllRegs,
    PrintReg,
    PrintMemAt,
    PrintCurSpeed,
    SetReg,
    SetSpeed,
    ClearMem,
    ClearRegs,
    ClearAll,
    MachineStep,
    MachineStart,
    MachineRunNSteps,
    MachineRunUntilPCPos,
    MachineRunUntilOpcode,
    MachineStop,
    PrintCurInstruction,
};

// M - submenu, C - command
// q, quit
// start, run, r
// step  [count=]
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
// \-- print
// w, watch  addr= size=word|byte|number
// wl, watchlist

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
                    .help = "Print some memory at address 'addr', if 'count' provided, print 'count' bytes",
                },
                Cmd{
                    .name = "clear",
                    .alt = &.{"clr"},
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
                    .help = "Set register 'reg' with value 'val'",
                },
                Cmd{
                    .name = "clear",
                    .alt = &.{"clr"},
                    .help = "Clear all registers",
                },
            },
        },
        Menu{
            .name = "b",
            .alt = &.{"breakpoint"},
            .commands = &.{
                Cmd{
                    .name = "set",
                    .params = &.{
                        Param{
                            .name = "addr",
                        },
                    },
                    .help = "Set breakpoint at address 'addr'",
                },
                Cmd{
                    .name = "print",
                    .alt = &.{"p"},
                    .help = "Print all breakpoints",
                },
            },
        },
    },
    .commands = .{
        Cmd{
            .name = "quit",
            .alt = &.{"q"},
            .help = "Quit the program",
        },
        Cmd{
            .name = "start",
            .alt = &.{ "run", "r" },
            .help = "Run simulation",
        },
        Cmd{
            .name = "step",
            .params = &.{Param{ .name = "count", .optional = true }},
            .help = "Execute one instruction or 'count' instructions",
        },
        Cmd{
            .name = "watch",
            .alt = &.{"w"},
            .params = &.{
                Param{ .name = "addr" },
                Param{ .name = "size", .limited = &.{ "word", "byte", "number" } },
            },
            .help = "Add 'addr' location to the watch list, with 'size'",
        },
        Cmd{
            .name = "watchlist",
            .alt = &.{"wl"},
            .help = "Print every item on the watchlist",
        },
    },
};

pub fn parseArgs(line: []const u8) void {
    _ = line;
}

const Menu = struct {
    name: []const u8,
    alt: [][]const u8 = &.{},
    submenus: []const Menu = &.{},
    commands: []const Cmd = &.{},

    pub fn str(self: *Menu, alloc: Allocator, contents: bool) ![]const u8 {
        if (!contents) {
            var buf = " " ** 14;
            // try std.fmt.allocPrint(alloc, "{s:<13} ", .{" "});
            var b = try std.fmt.bufPrint(buf, ", {s}", .{self.name});
            var len = b.len;

            for (self.alt) |a| {
                b = try std.fmt.bufPrint(buf[len..], ", {s}", .{a});
                len += b.len;
            }

            return alloc.dupe(u8, buf);
        }

        var s = std.ArrayList(u8).init(alloc);
        errdefer s.deinit();

        var buf = try std.fmt.allocPrint(alloc, "{s:<8} {s:<13} PARAMS\n", .{ "TYPE", "NAME" });
        s.appendSlice(buf);
        alloc.free(buf);

        for (self.submenus) |m| {
            buf = try std.fmt.allocPrint(alloc, "{s:<8} ", .{"M"});
            try s.appendSlice(buf);
            alloc.free(buf);
            try s.appendSlice(m.name);
            try s.appendSlice("\n");
        }

        for (self.commands) |c| {
            buf = try std.fmt.allocPrint(alloc, "{s:<8} ", .{"C"});
            try s.appendSlice(buf);
            alloc.free(buf);

            buf = try c.str(alloc);
            try s.appendSlice(buf);
            alloc.free(buf);

            try s.appendSlice("\n");
        }
    }
};

const Cmd = struct {
    name: []const u8,
    alt: [][]const u8 = &.{},
    params: []const Param = &.{},
    help: []const u8 = "No message",

    pub fn str(self: *Cmd, alloc: Allocator) ![]const u8 {
        var s = std.ArrayList(u8).init(alloc);
        errdefer s.deinit();

        var buf = " " ** 14;
        // try std.fmt.allocPrint(alloc, "{s:<13} ", .{" "});
        var b = try std.fmt.bufPrint(buf, ", {s}", .{self.name});
        var len = b.len;

        for (self.alt) |a| {
            b = try std.fmt.bufPrint(buf[len..], ", {s}", .{a});
            len += b.len;
        }

        try s.appendSlice(buf);
        // alloc.free(buf);

        for (self.params) |param| {
            buf = try param.str(alloc);
            try s.appendSlice(" ");
            try s.appendSlice(buf);
            alloc.free(buf);
        }

        return s.toOwnedSlice();
    }
};

const Param = struct {
    name: []const u8,
    optional: bool = false,
    limited: ?[][]const u8 = null,

    pub fn str(self: *Param, alloc: Allocator) ![]const u8 {
        var s = std.ArrayList(u8).init(alloc);
        errdefer s.deinit();

        if (self.optional) {
            try s.appendSlice("[");
        }

        try s.appendSlice(self.name);
        try s.appendSlice("=");
        if (self.limited) |list| {
            for (list, 0..) |v, i| {
                try s.appendSlice(v);
                if (i < list.len - 1) {
                    try s.appendSlice("|");
                }
            }
        }

        if (self.optional) {
            try s.appendSlice("]");
        }

        return s.toOwnedSlice();
    }
};
