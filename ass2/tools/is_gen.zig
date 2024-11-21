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
            \\        for (self.container[hash_]) |*e| {
            \\            if (e.* == null) break;
            \\            if (e.key == k) {
            \\                return e.val;
            \\            }
            \\        }
            \\    
            \\        return null;
            \\    }
            \\    
            \\    pub fn contains(self: *const Self, k: Opcode) bool {
            \\        const hash_ = self.hash(k);
            \\    
            \\        for (self.container[hash_]) |*e| {
            \\            if (e.* == null) break;
            \\            if (e.key == k) {
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
            \\};
            \\
            \\const Fmt1 = packed struct(u32) { _pad: u24, opcode: u8 };
            \\const Fmt2 = packed struct(u32) { _pad: u16, r2: u4, r1: u4, opcode: u8 };
            \\const FmtSIC = packed struct(u32) { _pad: u8, addr: u15, x: bool, i: bool, n: bool, opcode: u6 };
            \\const Fmt3 = packed struct(u32) { _pad: u8, addr: u12, e: bool, p: bool, b: bool, x: bool, i: bool, n: bool, opcode: u6 };
            \\const Fmt4 = packed struct(u32) { addr: u20, e: bool, p: bool, b: bool, x: bool, i: bool, n: bool, opcode: u6 };
        );

        return str.items;
    }
};

const Opcode = enum(u16) {
    ADD = 0x183,
    ADDF = 0x583,
    ADDR = 0x902,
    AND = 0x403,
    CLEAR = 0xB42,
    COMP = 0x283,
    COMPF = 0x883,
    COMPR = 0xA02,
    DIV = 0x243,
    DIVF = 0x643,
    DIVR = 0x9C2,
    FIX = 0xC41,
    FLOAT = 0xC01,
    // HIO = 0xF41,
    J = 0x3C3,
    JEQ = 0x303,
    LGT = 0x343,
    JLT = 0x383,
    JSUB = 0x483,
    LDA = 0x003,
    LDB = 0x683,
    LDCH = 0x503,
    LDF = 0x703,
    LDL = 0x083,
    LDS = 0x6C3,
    LDT = 0x743,
    LDX = 0x043,
    // LPS = 0xD03,
    MUL = 0x203,
    MULF = 0x603,
    MULR = 0x982,
    NORM = 0xC81,
    OR = 0x443,
    RD = 0xDB3,
    RMO = 0xAC2,
    RSUB = 0x4C3,
    SHIFTL = 0xA42,
    SHIFTR = 0xA82,
    // SIO = 0xF01,
    // SSK = 0xEC3,
    STA = 0x0C3,
    STB = 0x783,
    STCH = 0x543,
    STF = 0x803,
    // STI = 0xD43,
    STL = 0x143,
    STS = 0x7C3,
    STSW = 0xE83,
    STT = 0x843,
    STX = 0x103,
    SUB = 0x1C3,
    SUBF = 0x5C3,
    SUBR = 0x942,
    // SVC = 0xB02,
    TD = 0xE03,
    // TIO = 0xF81,
    TIX = 0x2C3,
    TIXR = 0xB82,
    WD = 0xDC3,

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
        try str.appendSlice("};");
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
