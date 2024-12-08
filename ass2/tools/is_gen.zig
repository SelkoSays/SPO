const std = @import("std");
const Allocator = std.mem.Allocator;

const AE = std.ArrayListUnmanaged(HashMap.Entry);
const AAE = std.ArrayListUnmanaged(AE);

const ld_f = 3;

const HashMap = struct {
    container: []AE = undefined,
    allocator: Allocator,
    cap: usize = 45,

    pub const Entry = struct {
        key: Opcode,
        val: u2,
    };

    const Self = @This();
    pub fn init(allocator: Allocator) !Self {
        var hm = Self{ .allocator = allocator };
        hm.container = try allocator.alloc(AE, hm.cap);

        for (hm.container) |*a| {
            a.* = try AE.initCapacity(allocator, ld_f);
        }

        return hm;
    }

    pub fn add(self: *Self, k: Opcode, v: u2) !void {
        var hash_ = hash(k) % self.cap;
        while (self.container[hash_].items.len >= ld_f) {
            try self.rehash();
            hash_ = hash(k) % self.cap;
        }

        try self.container[hash_].append(self.allocator, Entry{ .key = k, .val = v });
    }

    pub fn rehash(self: *Self) !void {
        self.cap *= 2;
        var container = try self.allocator.alloc(AE, self.cap);
        for (container) |*a| {
            a.* = try AE.initCapacity(self.allocator, ld_f);
        }

        for (self.container) |*a| {
            for (a.items) |*e| {
                const h = hash(e.key) % self.cap;
                try container[h].append(self.allocator, e.*);
            }
        }

        // discard old container because of ArenaAllocator
        self.container = container;
    }

    fn hash(k: Opcode) usize {
        return @intFromEnum(k) >> 4;
    }

    fn eq(k1: Opcode, k2: Opcode) bool {
        return k1 == k2;
    }

    pub fn assertLoadFactor(self: *const Self) void {
        for (self.container) |*a| {
            if (a.items.len > ld_f) {
                std.debug.panic("Load factor not respected. Should be {d}, but got {d}.", .{ ld_f, a.items.len });
            }
        }
    }

    pub fn toString(self: *const Self, alloc: Allocator) ![]const u8 {
        var str = std.ArrayList(u8).init(alloc);
        var buf = [_]u8{0} ** 100;

        try str.appendSlice(
            \\const std = @import("std");
            \\
            \\const container = [
        );

        try str.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{self.cap}));

        try str.appendSlice("][");

        try str.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{ld_f}));
        try str.appendSlice("]?Entry{\n");

        for (self.container) |*a| {
            try str.appendSlice("    [");
            try str.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{ld_f}));
            try str.appendSlice("]?Entry{");
            for (a.items) |*e| {
                try str.appendSlice(try std.fmt.bufPrint(&buf, " Entry{{ .key = .{s}, .val = {d} }},", .{ @tagName(e.key), e.val }));
            }

            for (a.items.len..ld_f) |_| {
                try str.appendSlice(" null,");
            }

            try str.appendSlice(" },\n");
        }

        try str.appendSlice(
            \\};
            \\
            \\pub const opTable = OpTable { .container = container, .cap = 
        );
        try str.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{self.cap}));

        try str.appendSlice(
            \\ };
            \\const Entry = struct {
            \\    key: Opcode,
            \\    val: u3,
            \\};
            \\
            \\const OpTable = struct {
            \\    container: [
        );

        try str.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{self.cap}));

        try str.appendSlice("][");

        try str.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{ld_f}));

        try str.appendSlice("]?Entry,\n");
        try str.appendSlice(
            \\    cap: usize,
            \\    
            \\    const Self = @This();
            \\    
            \\    fn hash(self: *const Self, k: Opcode) usize {
            \\        return @intFromEnum(k) % self.cap;
            \\    }
            \\    
            \\    pub fn get(self: *const Self, k: Opcode) ?u3 {
            \\        const hash_ = self.hash(k);
            \\    
            \\        for (&self.container[hash_]) |*e| {
            \\            if (e.* == null) break;
            \\            if (e.*.?.key == k) {
            \\                return e.*.?.val;
            \\            }
            \\        }
            \\    
            \\        return null;
            \\    }
            \\    
            \\    pub fn contains(self: *const Self, k: Opcode) bool {
            \\        const hash_ = self.hash(k);
            \\    
            \\        for (&self.container[hash_]) |*e| {
            \\            if (e.* == null) break;
            \\            if (e.*.?.key == k) {
            \\                return true;
            \\            }
            \\        }
            \\    
            \\        return false;
            \\    }
            \\};
            \\
            \\
        );

        try Opcode.genText(&str);

        try str.appendSlice(
            \\
            \\
            \\pub const Fmt = packed union {
            \\    f1: Fmt1,
            \\    f2: Fmt2,
            \\    fs: FmtSIC,
            \\    f3: Fmt3,
            \\    f4: Fmt4,
            \\
            \\    pub fn from_u32(n: u32) Fmt {
            \\        return Fmt{ .f4 = Fmt4{
            \\            .opcode = @truncate(n >> (32 - 6)),
            \\            .n = @bitCast(@as(u1, @truncate((n >> (32 - 7)) & 1))),
            \\            .i = @bitCast(@as(u1, @truncate((n >> (32 - 8)) & 1))),
            \\            .x = @bitCast(@as(u1, @truncate((n >> (32 - 9)) & 1))),
            \\            .b = @bitCast(@as(u1, @truncate((n >> (32 - 10)) & 1))),
            \\            .p = @bitCast(@as(u1, @truncate((n >> (32 - 11)) & 1))),
            \\            .e = @bitCast(@as(u1, @truncate((n >> (32 - 12)) & 1))),
            \\            .addr = @truncate(n & ((1 << 20) - 1)),
            \\        } };
            \\    }
            \\};
            \\
            \\const Fmt1 = packed struct(u32) { opcode: u8, _pad: u24 };
            \\const Fmt2 = packed struct(u32) { opcode: u8, r1: u4, r2: u4, _pad: u16 };
            \\const FmtSIC = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, addr: u15, _pad: u8 };
            \\const Fmt3 = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, b: bool, p: bool, e: bool, addr: u12, _pad: u8 };
            \\const Fmt4 = packed struct(u32) { opcode: u6, n: bool, i: bool, x: bool, b: bool, p: bool, e: bool, addr: u20 };
            // \\const Fmt1 = packed struct(u32) { _pad: u24, opcode: u8 };
            // \\const Fmt2 = packed struct(u32) { _pad: u16, r2: u4, r1: u4, opcode: u8 };
            // \\const FmtSIC = packed struct(u32) { _pad: u8, addr: u15, x: bool, i: bool, n: bool, opcode: u6 };
            // \\const Fmt3 = packed struct(u32) { _pad: u8, addr: u12, e: bool, p: bool, b: bool, x: bool, i: bool, n: bool, opcode: u6 };
            // \\const Fmt4 = packed struct(u32) { addr: u20, e: bool, p: bool, b: bool, x: bool, i: bool, n: bool, opcode: u6 };
        );

        return str.items;
    }
};

const Opcode = enum(u16) {
    // ***** SIC format, SIC/XE format 3, and SIC/XE format 4 *****

    // load and store
    LDA = 0x003,
    LDX = 0x043,
    LDL = 0x083,
    STA = 0x0C3,
    STX = 0x103,
    STL = 0x143,

    // fixed point arithmetic
    ADD = 0x183,
    SUB = 0x1C3,
    MUL = 0x203,
    DIV = 0x243,
    COMP = 0x283,
    TIX = 0x2C3,

    // jumps
    JEQ = 0x303,
    JGT = 0x343,
    JLT = 0x383,
    J = 0x3C3,

    // bit manipulation
    AND = 0x403,
    OR = 0x443,

    // jump to subroutine
    JSUB = 0x483,
    RSUB = 0x4C3,

    // load and store
    LDCH = 0x503,
    STCH = 0x543,

    // ***** SICXE Format 3 and Format 4

    // floating point arithmetic
    ADDF = 0x583,
    SUBF = 0x5C3,
    MULF = 0x603,
    DIVF = 0x643,
    COMPF = 0x883,

    // load and store
    LDB = 0x683,
    LDS = 0x6C3,
    LDF = 0x703,
    LDT = 0x743,
    STB = 0x783,
    STS = 0x7C3,
    STF = 0x803,
    STT = 0x843,

    // special load and store
    LPS = 0xD03, // unhandeled
    STI = 0xD43, // unhandeled
    STSW = 0xE83,

    // devices
    RD = 0xD83,
    WD = 0xDC3,
    TD = 0xE03,

    // system
    SSK = 0xEC3, // unhandeled

    // ***** SIC/XE Format 2 *****
    ADDR = 0x902,
    SUBR = 0x942,
    MULR = 0x982,
    DIVR = 0x9C2,
    COMPR = 0xA02,
    SHIFTL = 0xA42,
    SHIFTR = 0xA82,
    RMO = 0xAC2,
    SVC = 0xB02, // unhandeled
    CLEAR = 0xB42,
    TIXR = 0xB82,

    // // ***** SIC/XE Format 1 *****
    FLOAT = 0xC01,
    FIX = 0xC41,
    NORM = 0xC81, // unhandeled
    SIO = 0xF01, // unhandeled
    HIO = 0xF41, // unhandeled
    TIO = 0xF81, // unhandeled

    // MY DBG INT
    INT = 0xE41, // TODO

    const Self = @This();
    pub fn genText(str: *std.ArrayList(u8)) !void {
        try str.appendSlice(
            \\pub const Opcode = enum(u8) {
            \\
        );

        var buf = [_]u8{0} ** 30;
        inline for (@typeInfo(Self).Enum.fields) |f| {
            try str.appendSlice("    ");
            try str.appendSlice(try std.fmt.bufPrint(&buf, "{s} = 0x{X},\n", .{ f.name, f.value >> 4 }));
        }
        try str.appendSlice(
            \\
            \\    const Self = @This();
            \\    
            \\    pub fn int(self: Self) u8 {
            \\        return @intFromEnum(self);
            \\    }
            \\
            \\};
        );
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var hm = try HashMap.init(alloc);

    inline for (@typeInfo(Opcode).Enum.fields) |f| {
        try hm.add(@field(Opcode, f.name), f.value & 0xF);
    }

    hm.assertLoadFactor();
    const text = try hm.toString(alloc);

    const output_file_path = "tools/instruction_set.zig";

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    try output_file.writeAll(text);

    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
