const std = @import("std");

regs: RegTable,

const Regs = enum(u8) {
    A = 0x0,
    X = 0x1,
    L = 0x2,
    B = 0x3,
    S = 0x4,
    T = 0x5,
    F = 0x6,
    PC = 0x7,
    SW = 0x8,
};

const RegTable = struct {
    A: u24,
    X: u24,
    L: u24,
    B: u24,
    S: u24,
    T: u24,
    F: f64,
    PC: u24, // program counter
    SW: u24, // status register
};

pub const StatReg = packed struct(u24) {
    mode: u1,
    idle: u1,
    id: u4,
    cc: u2,
    mask: u4,
    _unused: u4,
    icode: u8,

    const Self = @This();

    pub fn asInt(self: Self) u24 {
        return @bitCast(self);
    }

    pub fn fromInt(i: u24) Self {
        return @bitCast(i);
    }
};
