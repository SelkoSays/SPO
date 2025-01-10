const std = @import("std");

// const ISet = @import("instruction_set");
const ISet = @import("../../tools/instruction_set.zig");
const Opcode = ISet.Opcode;

const RegSet = @import("../machine/machine.zig").RegIdx;

pub const Instruction = struct {
    loc: u32,
    opcode: Opcode,
    extended: bool = false,
    base: bool = false,
    arg1: ?Expression = null,
    arg2: ?Expression = null,
};

pub const Expression = union(enum) {
    reg: RegSet,
    num: u24,
};
