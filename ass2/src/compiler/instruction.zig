const std = @import("std");

// const ISet = @import("instruction_set");
const ISet = @import("../../tools/instruction_set.zig");
const Opcode = ISet.Opcode;

const mac = @import("../machine/machine.zig");
const RegSet = mac.RegIdx;
const AddrMode = mac.Machine.AddrMode;

pub const Instruction = struct {
    kind: enum { Start, End, Byte, Word, Equ, Org, Base, NoBase, Normal } = .Normal,
    loc: u32 = 0,
    opcode: Opcode = undefined,
    sic: bool = false,
    extended: bool = false,
    base: bool = false,
    addr_mode: AddrMode = .Normal,
    arg1: ?Expression = null,
    arg2: ?Expression = null,
};

pub const Expression = union(enum) {
    reg: RegSet,
    num: u24,
    sym: []const u8,
};
