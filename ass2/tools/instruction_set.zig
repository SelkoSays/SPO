const std = @import("std");

const container = [45][3]?Entry{
    [3]?Entry{ Entry{ .key = .CLEAR, .val = 2 }, Entry{ .key = .LDA, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .COMPF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .SUBF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .JEQ, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDX, .val = 3 }, Entry{ .key = .TIXR, .val = 2 }, null, },
    [3]?Entry{ null, null, null, },
    [3]?Entry{ Entry{ .key = .MULF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .LGT, .val = 3 }, Entry{ .key = .STSW, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .LDL, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .ADDR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .DIVF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .JLT, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .FLOAT, .val = 1 }, Entry{ .key = .STA, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .SUBR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .J, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .FIX, .val = 1 }, Entry{ .key = .STX, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .MULR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDS, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .AND, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .NORM, .val = 1 }, Entry{ .key = .STL, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .DIVR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .OR, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .ADD, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .COMPR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDT, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .JSUB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .SUB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .SHIFTL, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .STB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .RSUB, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .MUL, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .SHIFTR, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .STS, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .LDCH, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .DIV, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .RMO, .val = 2 }, null, null, },
    [3]?Entry{ Entry{ .key = .STF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .RD, .val = 3 }, Entry{ .key = .STCH, .val = 3 }, null, },
    [3]?Entry{ Entry{ .key = .COMP, .val = 3 }, Entry{ .key = .WD, .val = 3 }, null, },
    [3]?Entry{ null, null, null, },
    [3]?Entry{ Entry{ .key = .STT, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .ADDF, .val = 3 }, null, null, },
    [3]?Entry{ Entry{ .key = .TD, .val = 3 }, Entry{ .key = .TIX, .val = 3 }, null, },
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
    ADD = 0x18,
    ADDF = 0x58,
    ADDR = 0x90,
    AND = 0x40,
    CLEAR = 0xB4,
    COMP = 0x28,
    COMPF = 0x88,
    COMPR = 0xA0,
    DIV = 0x24,
    DIVF = 0x64,
    DIVR = 0x9C,
    FIX = 0xC4,
    FLOAT = 0xC0,
    J = 0x3C,
    JEQ = 0x30,
    LGT = 0x34,
    JLT = 0x38,
    JSUB = 0x48,
    LDA = 0x0,
    LDB = 0x68,
    LDCH = 0x50,
    LDF = 0x70,
    LDL = 0x8,
    LDS = 0x6C,
    LDT = 0x74,
    LDX = 0x4,
    MUL = 0x20,
    MULF = 0x60,
    MULR = 0x98,
    NORM = 0xC8,
    OR = 0x44,
    RD = 0xDB,
    RMO = 0xAC,
    RSUB = 0x4C,
    SHIFTL = 0xA4,
    SHIFTR = 0xA8,
    STA = 0xC,
    STB = 0x78,
    STCH = 0x54,
    STF = 0x80,
    STL = 0x14,
    STS = 0x7C,
    STSW = 0xE8,
    STT = 0x84,
    STX = 0x10,
    SUB = 0x1C,
    SUBF = 0x5C,
    SUBR = 0x94,
    TD = 0xE0,
    TIX = 0x2C,
    TIXR = 0xB8,
    WD = 0xDC,

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
};

const Fmt1 = packed struct(u32) { opcode: u8, _pad: u24 };
const Fmt2 = packed struct(u32) { opcode: u8, r1: u4, r2: u4, _pad: u16 };
const FmtSIC = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, addr: u15, _pad: u8 };
const Fmt3 = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, b: bool, p: bool, e: bool, addr: u12, _pad: u8 };
const Fmt4 = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, b: bool, p: bool, e: bool, addr: u20 };