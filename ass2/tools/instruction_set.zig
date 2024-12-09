const std = @import("std");

const container = [45][3]?Entry{
    [3]?Entry{ Entry{ .key = .LDA, .val = 3 }, Entry{ .key = .CLEAR, .val = 2 }, null, },
    [3]?Entry{ Entry{ .key = .COMPF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .SUBF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .JEQ, .val = 3 }, Entry{ .key = .INT, .val = 1 }, null, },
    [3]?Entry{ Entry{ .key = .LDX, .val = 3 }, Entry{ .key = .TIXR, .val = 2 }, null, },
    [3]?Entry{ null, null, null, },
    [3]?Entry{ Entry{ .key = .MULF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .JGT, .val = 3 }, Entry{ .key = .STSW, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .LDL, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .ADDR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .DIVF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .JLT, .val = 3 }, Entry{ .key = .SSK, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .STA, .val = 3 }, Entry{ .key = .FLOAT, .val = 1 }, null, },
    [3]?Entry{ Entry{ .key = .SUBR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .J, .val = 3 }, Entry{ .key = .SIO, .val = 1 }, null, },
    [3]?Entry{ Entry{ .key = .STX, .val = 3 }, Entry{ .key = .FIX, .val = 1 }, null, },
    [3]?Entry{ Entry{ .key = .MULR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDS, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .AND, .val = 3 }, Entry{ .key = .HIO, .val = 1 }, null, },
    [3]?Entry{ Entry{ .key = .STL, .val = 3 }, Entry{ .key = .NORM, .val = 1 }, null, },
    [3]?Entry{ Entry{ .key = .DIVR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .OR, .val = 3 }, Entry{ .key = .TIO, .val = 1 }, null, },
    [3]?Entry{ Entry{ .key = .ADD, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .COMPR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDT, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .JSUB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .SUB, .val = 3 }, Entry{ .key = .LPS, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .SHIFTL, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .STB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .RSUB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .MUL, .val = 3 }, Entry{ .key = .STI, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .SHIFTR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .STS, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDCH, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .DIV, .val = 3 }, Entry{ .key = .RD, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .RMO, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .STF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .STCH, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .COMP, .val = 3 }, Entry{ .key = .WD, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .SVC, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .STT, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .ADDF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .TIX, .val = 3 }, Entry{ .key = .TD, .val = 3 }, null, },
};

pub const opTable = OpTable { .container = container, .cap = 45 };
const Entry = struct {
    key: Opcode,
    val: u3,
};

const OpTable = struct {
    container: [45][3]?Entry,
    cap: usize,
    
    const Self = @This();
    
    fn hash(self: *const Self, k: Opcode) usize {
        return @intFromEnum(k) % self.cap;
    }
    
    pub fn get(self: *const Self, k: Opcode) ?u3 {
        const hash_ = self.hash(k);
    
        for (&self.container[hash_]) |*e| {
            if (e.* == null) break;
            if (e.*.?.key == k) {
                return e.*.?.val;
            }
        }
    
        return null;
    }
    
    pub fn contains(self: *const Self, k: Opcode) bool {
        const hash_ = self.hash(k);
    
        for (&self.container[hash_]) |*e| {
            if (e.* == null) break;
            if (e.*.?.key == k) {
                return true;
            }
        }
    
        return false;
    }
};

pub const Opcode = enum(u8) {
    LDA = 0x0,
    LDX = 0x4,
    LDL = 0x8,
    STA = 0xC,
    STX = 0x10,
    STL = 0x14,
    ADD = 0x18,
    SUB = 0x1C,
    MUL = 0x20,
    DIV = 0x24,
    COMP = 0x28,
    TIX = 0x2C,
    JEQ = 0x30,
    JGT = 0x34,
    JLT = 0x38,
    J = 0x3C,
    AND = 0x40,
    OR = 0x44,
    JSUB = 0x48,
    RSUB = 0x4C,
    LDCH = 0x50,
    STCH = 0x54,
    ADDF = 0x58,
    SUBF = 0x5C,
    MULF = 0x60,
    DIVF = 0x64,
    COMPF = 0x88,
    LDB = 0x68,
    LDS = 0x6C,
    LDF = 0x70,
    LDT = 0x74,
    STB = 0x78,
    STS = 0x7C,
    STF = 0x80,
    STT = 0x84,
    LPS = 0xD0,
    STI = 0xD4,
    STSW = 0xE8,
    RD = 0xD8,
    WD = 0xDC,
    TD = 0xE0,
    SSK = 0xEC,
    ADDR = 0x90,
    SUBR = 0x94,
    MULR = 0x98,
    DIVR = 0x9C,
    COMPR = 0xA0,
    SHIFTL = 0xA4,
    SHIFTR = 0xA8,
    RMO = 0xAC,
    SVC = 0xB0,
    CLEAR = 0xB4,
    TIXR = 0xB8,
    FLOAT = 0xC0,
    FIX = 0xC4,
    NORM = 0xC8,
    SIO = 0xF0,
    HIO = 0xF4,
    TIO = 0xF8,
    INT = 0xE4,

    const Self = @This();
    
    pub fn int(self: Self) u8 {
        return @intFromEnum(self);
    }

};

pub const Fmt = packed union {
    f1: Fmt1,
    f2: Fmt2,
    fs: FmtSIC,
    f3: Fmt3,
    f4: Fmt4,

    pub fn from_u32(n: u32) Fmt {
        return Fmt{ .f4 = Fmt4{
            .opcode = @truncate(n >> (32 - 6)),
            .n = @bitCast(@as(u1, @truncate((n >> (32 - 7)) & 1))),
            .i = @bitCast(@as(u1, @truncate((n >> (32 - 8)) & 1))),
            .x = @bitCast(@as(u1, @truncate((n >> (32 - 9)) & 1))),
            .b = @bitCast(@as(u1, @truncate((n >> (32 - 10)) & 1))),
            .p = @bitCast(@as(u1, @truncate((n >> (32 - 11)) & 1))),
            .e = @bitCast(@as(u1, @truncate((n >> (32 - 12)) & 1))),
            .addr = @truncate(n & ((1 << 20) - 1)),
        } };
    }
};

const Fmt1 = packed struct(u32) { opcode: u8, _pad: u24 };
const Fmt2 = packed struct(u32) { opcode: u8, r1: u4, r2: u4, _pad: u16 };
const FmtSIC = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, addr: u15, _pad: u8 };
const Fmt3 = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, b: bool, p: bool, e: bool, addr: u12, _pad: u8 };
const Fmt4 = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, b: bool, p: bool, e: bool, addr: u20 };