const std = @import("std");

const ISet = @import("instruction_set");
// const ISet = @import("../../tools//instruction_set.zig");
const Opcode = ISet.Opcode;

const mac = @import("../machine/machine.zig");
const RegSet = mac.RegIdx;
const AddrMode = mac.Machine.AddrMode;

var buffer: [1024]u8 = [1024]u8{0} ** 1024;

pub const Instruction = struct {
    kind: enum { Start, End, Byte, Word, Equ, Org, Base, NoBase, Resb, Resw, Normal } = .Normal,
    label: ?[]const u8 = null,
    loc: u32 = 0,
    opcode: Opcode = undefined,
    sic: bool = false,
    extended: bool = false,
    base: bool = false,
    addr_mode: AddrMode = .Normal,
    arg1: ?Expression = null,
    arg2: ?Expression = null,
    res_arg1: ?Expression = null, // resolved argument

    pub fn display(self: *const Instruction) void {
        std.debug.print("{{\n  label: {?s}\n  kind: {s}\n  opcode: {?s}\n  loc: {X:02}\n  arg1: {?}\n  arg2: {?}\n}}\n", .{
            self.label,
            @tagName(self.kind),
            std.enums.tagName(Opcode, self.opcode),
            self.loc,
            self.arg1,
            self.arg2,
        });
    }

    pub fn bytes(self: *const Instruction, len: *u3) [4]u8 {
        var b = [4]u8{ 0, 0, 0, 0 };
        b[0] = self.opcode.int();

        const ln = ISet.opTable.get(self.opcode) orelse unreachable;
        len.* = ln;

        if (ln == 1) return b;

        if (ln == 2) {
            std.log.debug("OPCODE: {s}", .{@tagName(self.opcode)});
            b[1] = (@as(u8, self.arg1.?.reg.asInt()) << 4);
            if (self.arg2 != null) {
                b[1] |= self.arg2.?.reg.asInt();
            }
            return b;
        }

        switch (self.addr_mode) {
            .Immediate => b[0] |= 0b01,
            .Normal => if (self.sic) {
                b[0] |= 0b00;
            } else {
                b[0] |= 0b11;
            },
            .Indirect => b[0] |= 0b10,
            else => {},
        }

        if (self.arg1 == null) return b;

        if (self.arg2 != null) { // use X
            b[1] |= 1 << 7;
        }

        if (!self.sic and self.addr_mode != .None and self.addr_mode != .Immediate) {
            if (self.extended) {
                b[1] |= 1 << 4;
            }

            if (self.base) {
                b[1] |= 1 << 6;
            } else {
                b[1] |= 1 << 5;
            }
        }

        var n: u24 = 0;
        if (self.arg1.? == .num) {
            n = self.arg1.?.num;
        } else {
            n = self.res_arg1.?.num;
        }

        if (self.sic) {
            b[2] = @truncate(n & 0xFF);
            b[1] |= @truncate((n >> 8) & 0x7F);
        } else {
            if (!self.extended) {
                b[2] = @truncate(n & 0xFF);
                b[1] |= @truncate((n >> 8) & 0x0F);
            } else {
                b[3] = @truncate(n & 0xFF);
                b[2] = @truncate((n >> 8) & 0xFF);
                b[1] |= @truncate((n >> 16) & 0x0F);
            }
        }

        if (self.extended) len.* += 1;

        return b;
    }

    pub fn lst_str(self: *const Instruction, w: std.io.AnyWriter) !void {
        try w.print("{X:0>6}  ", .{self.loc});
        switch (self.kind) {
            .Start, .End, .Base, .NoBase, .Org, .Equ => {
                try w.print("          ", .{});
            },
            .Resb, .Resw => {
                try w.print("000000    ", .{});
            },
            .Byte => {
                if (self.arg1.? == .num) {
                    try w.print("{X:0>2}        ", .{self.arg1.?.num});
                } else {
                    try w.print("{X:0>2}        ", .{self.res_arg1.?.num});
                }
            },
            .Word => {
                if (self.arg1.? == .num) {
                    try w.print("{X:0>6}    ", .{self.arg1.?.num});
                } else {
                    try w.print("{X:0>6}    ", .{self.res_arg1.?.num});
                }
            },
            .Normal => {
                var len: u3 = 0;
                const b = self.bytes(&len);
                for (0..len) |i| {
                    try w.print("{X:0>2}", .{b[i]});
                }
                for (0..(4 - len)) |_| {
                    _ = try w.write("  ");
                }

                _ = try w.write("  ");
            },
        }

        try w.print("{s: <6}  ", .{self.label orelse ""});

        switch (self.kind) {
            .Start => {
                _ = try w.write("START    ");
            },
            .End => {
                _ = try w.write("END      ");
            },
            .Base => {
                _ = try w.write("BASE     ");
            },
            .NoBase => {
                _ = try w.write("NOBASE   ");
            },
            .Org => {
                _ = try w.write("ORG      ");
            },
            .Equ => {
                _ = try w.write("EQU      ");
            },
            .Resb => {
                _ = try w.write("RESB     ");
            },
            .Resw => {
                _ = try w.write("RESW     ");
            },
            .Byte => {
                _ = try w.write("BYTE     ");
            },
            .Word => {
                _ = try w.write("WORD     ");
            },
            .Normal => {
                try w.print("{s: <7}  ", .{@tagName(self.opcode)});
            },
        }

        if (self.arg1 == null) return;

        switch (self.addr_mode) {
            .Immediate => try w.writeByte('#'),
            .Indirect => try w.writeByte('@'),
            else => {},
        }

        switch (self.arg1.?) {
            .num => |n| try w.print("{d}", .{n}),
            .sym => |s| _ = try w.write(s),
            .reg => |r| _ = try w.write(@tagName(r)),
        }

        if (self.arg2 == null) return;

        try w.writeByte(',');
        switch (self.arg2.?) {
            .reg => |r| _ = try w.write(@tagName(r)),
            else => unreachable,
        }
    }
};

pub const Expression = union(enum) {
    reg: RegSet,
    num: u24,
    sym: []const u8,
};
