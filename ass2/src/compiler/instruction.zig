const std = @import("std");

// const ISet = @import("instruction_set");
const ISet = @import("instruction_set");
const Opcode = ISet.Opcode;

const mac = @import("../machine/machine.zig");
const RegSet = mac.RegIdx;
const AddrMode = mac.Machine.AddrMode;

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
};

pub const Expression = union(enum) {
    reg: RegSet,
    num: u24,
    sym: []const u8,
};
