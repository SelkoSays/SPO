const std = @import("std");
const Allocator = std.mem.Allocator;

const hl = @import("helper.zig");
const dev = @import("device.zig");
const Device = dev.Device;
const Devices = dev.Devices;
const Is = @import("instruction_set");
const Opcode = Is.Opcode;
const Fmt = Is.Fmt;
const obj = @import("obj_reader.zig");

pub const RegIdx = enum(u4) {
    A = 0x0,
    X = 0x1,
    L = 0x2,
    B = 0x3,
    S = 0x4,
    T = 0x5,
    F = 0x6,
    PC = 0x8,
    SW = 0x9,

    const Self = @This();

    pub fn asInt(self: Self) u4 {
        return @intFromEnum(self);
    }
};

pub const Ord = enum(u2) {
    Less = 0b00,
    Equal = 0b01,
    Greater = 0b10,
};

const Regs = struct {
    gpr: GPR = .{},
    F: f64 = 0.0,
    PC: u24 = 0, // program counter
    SW: SR = .{ .i = 0 }, // status register

    const GPR = struct { // General Purpose Registers
        A: u24 = 0,
        X: u24 = 0,
        L: u24 = 0,
        B: u24 = 0,
        S: u24 = 0,
        T: u24 = 0,

        pub fn asArray(self: *GPR) [*]u24 {
            return @ptrCast(self);
        }
    };

    const SR = packed union {
        i: u24,
        s: packed struct(u24) {
            mode: u1,
            idle: u1,
            id: u4,
            cc: Ord,
            mask: u4,
            _unused: u4,
            icode: u8,
        },
    };

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Set register
    pub fn set(self: *Self, ri: RegIdx, val: anytype) void {
        // TODO: don't panic -> log error instead?
        if (@TypeOf(val) == f64) {
            if (ri != RegIdx.F) std.debug.panic("Register {} cannot be set with a floating point number.", .{ri});
            self.F = val;
        } else if (@TypeOf(val) == u8) {
            if (ri != RegIdx.A) std.debug.panic("Register {} cannot be set with an 8-bit number.", .{ri});
            self.gpr.rt.A &= ~@as(u24, 0xFF);
            self.gpr.rt.A |= val;
        } else {
            switch (ri) {
                .F => @panic("Register F cannot be set with a word."),
                .SW => self.SW.i = val,
                .PC => self.PC = val,
                else => self.gpr.asArray()[ri.asInt()] = val,
            }
        }
    }

    /// Get register
    pub fn get(self: *Self, ri: RegIdx, comptime T: type) T {
        if (T == f64) {
            if (ri != RegIdx.F) std.debug.panic("Cannot read register {} as a floating point number.", .{ri});
            return self.F;
        } else if (T == u8) {
            if (ri != RegIdx.A) std.debug.panic("Cannot read register {} as an 8-bit number.", .{ri});
            return @intCast(self.gpr.rt.A & 0xFF);
        } else {
            return switch (ri) {
                .F => @panic("Cannot read register F as a word."),
                .SW => self.SW.i,
                .PC => self.PC,
                else => self.gpr.asArray()[ri.asInt()],
            };
        }
    }
};

/// Does not own buf
const Mem = struct {
    buf: [*]u8,

    pub const MAX_ADDR = 1 << 20; // 1MB

    const Self = @This();

    pub fn get(self: *const Self, addr: u24, comptime T: type) T {
        const size = hl.sizeOf(T);
        // TODO: check address
        var ret = std.mem.bytesToValue(T, self.buf[addr .. addr + size]);

        if (@typeInfo(T) == .Int) {
            ret = std.mem.bigToNative(T, ret);
        }

        return ret;
    }

    pub fn setSlice(self: *Self, addr: u24, slice: []const u8) void {
        @memcpy(self.buf[addr .. addr + slice.len], slice);
    }

    pub fn set(self: *Self, addr: u24, val: anytype) void {
        const T: type = @TypeOf(val);
        const size = hl.sizeOf(T);

        // std.debug.print("addr = {X}\n", .{addr});

        var v = val;

        if (@typeInfo(T) == .Int) {
            v = std.mem.nativeToBig(T, v);
        }

        const ptr = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]);
        ptr.* = v;
    }

    pub fn getE(self: *const Self, addr: u24, comptime T: type, comptime enidan: std.builtin.Endian) T {
        const size = hl.sizeOf(T);
        // TODO: check address
        var ret = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]).*;

        if (@typeInfo(T) == .Int) {
            ret = std.mem.bigToNative(T, ret);
            ret = std.mem.nativeTo(T, ret, enidan);
        }

        return ret;
    }

    pub fn setE(self: *Self, addr: u24, val: anytype, comptime enidan: std.builtin.Endian) void {
        const T: type = @TypeOf(val);
        const size = hl.sizeOf(T);

        // std.debug.print("addr = {X}\n", .{addr});

        var v = val;

        if (@typeInfo(T) == .Int) {
            // v = std.mem.nativeToBig(T, v);
            v = std.mem.nativeTo(T, v, enidan);
        }

        const ptr = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]);
        ptr.* = v;
    }

    pub fn setF(self: *Self, addr: u24, val: f64) void {
        const v: u48 = @truncate(@as(u64, @bitCast(val)) >> (@bitSizeOf(u64) - @bitSizeOf(u48)));
        self.set(addr, v);
    }

    pub fn getF(self: *const Self, addr: u24) f64 {
        return @bitCast(@as(u64, self.get(addr, u48)) << (@bitSizeOf(u64) - @bitSizeOf(u48)));
    }
};

pub const Machine = struct {
    regs: Regs = .{},
    mem: Mem,
    devs: *OSDevices,
    clock_speed: u64 = 1, // [kHz]
    stopped: bool = true,
    code: ?obj.Code = null,

    pub const OSDevices = Devices(256);

    const AddrMode = enum(u2) {
        None = 0b00,
        Immediate = 0b01,
        Normal = 0b10,
        Indirect = 0b11,
    };

    const Self = @This();

    pub fn init(buf: [*]u8, devs: *OSDevices) Self {
        return .{
            .mem = .{ .buf = buf },
            .devs = devs,
        };
    }

    pub fn load(self: *Self, path: []const u8, comptime is_str: bool, alloc: Allocator) !void {
        const r_code = try if (is_str) blk: {
            break :blk obj.from_str(path, alloc);
        } else blk: {
            const cur_dir = std.fs.cwd();
            const f = cur_dir.openFile(path, .{ .mode = .read_only }) catch |err| {
                std.log.err("{}", .{err});
                return;
            };
            defer f.close();

            break :blk try obj.from_reader(f.reader().any(), alloc);
        };

        if (r_code.is_err()) {
            _ = try r_code.try_unwrap();
        }

        const code = r_code.unwrap();
        defer code.deinit(alloc);

        for (code.records) |r| {
            switch (r) {
                .T => |t| {
                    self.mem.setSlice(t.addr, t.code);
                },
                // .M => |m| {},
                else => return error.UnsupportedRecord,
            }
        }

        self.regs.PC = code.start_addr;
    }

    pub fn setSpeed(self: *Self, speed_kHz: u64) void {
        self.clock_speed = speed_kHz;
        if (speed_kHz == 0) {
            self.clock_speed += 1;
        }
    }

    inline fn sleep_time(self: *const Self) u64 {
        return std.time.us_per_s / self.clock_speed;
    }

    pub fn start(self: *Self) void {
        self.stopped = false;
        while (!self.stopped) {
            const t_start = std.time.microTimestamp();
            self.step();
            const elapsed = std.time.microTimestamp() - t_start;
            const t = (self.sleep_time() -| @as(u64, @intCast(elapsed)));
            std.time.sleep(t);
        }
    }

    pub fn stop(self: *Self) void {
        self.stopped = true;
    }

    pub fn nStep(self: *Self, n: u32) void {
        var nn = n;
        self.stopped = true;
        while (!self.stopped and nn > 0) {
            self.step();
            nn -= 1;
        }
    }

    pub fn step(self: *Self) void {
        const opcode_ni = self.fetch();
        const opcode: Opcode = std.meta.intToEnum(Opcode, (opcode_ni >> 2) << 2) catch {
            self.stop();
            return;
        };

        var address_mode = AddrMode.Normal;
        const n = (opcode_ni & 0b10) > 0;
        const i = (opcode_ni & 0b01) > 0;

        if (!n and i) {
            address_mode = .Immediate;
        } else if (n and !i) {
            address_mode = .Indirect;
        }

        const sic = !n and !i;

        var ins_sz = Is.opTable.get(opcode) orelse 0;
        if (ins_sz > 2) {
            const e = ((self.mem.get(self.regs.PC, u8) >> 4) & 1);
            if (e == 1) ins_sz += 1;
        }

        const operand = switch (opcode) {
            .STA, .STX, .STL, .JSUB, .STCH, .STB, .STS, .STT, .STSW, .J, .JEQ, .JGT, .JLT => self.getAddr(u24, sic, true, address_mode),
            .LDCH, .ADDF, .SUBF, .MULF, .DIVF, .COMPF, .RD, .WD, .TD => 0,
            else => if (ins_sz > 2) self.getAddr(u24, sic, false, address_mode) else 0,
        };

        const regs = if (ins_sz == 2) self.fetch() else 0;

        switch (opcode) {
            // load and store
            .LDA => self.regs.gpr.A = operand,
            .LDX => self.regs.gpr.X = operand,
            .LDL => self.regs.gpr.L = operand,
            .STA => if (address_mode != .Immediate) {
                self.mem.set(operand, self.regs.gpr.A);
            },
            .STX => if (address_mode != .Immediate) {
                self.mem.set(operand, self.regs.gpr.X);
            },
            .STL => if (address_mode != .Immediate) {
                self.mem.set(operand, self.regs.gpr.L);
            },
            // fixed point arithmetic
            .ADD => self.regs.gpr.A +%= operand,
            .SUB => self.regs.gpr.A -%= operand,
            .MUL => self.regs.gpr.A *%= operand,
            .DIV => self.regs.gpr.A /= operand,
            .COMP => self.regs.SW.s.cc = comp(self.regs.gpr.A, operand),
            .TIX => {
                self.regs.gpr.X +%= 1;
                self.regs.SW.s.cc = comp(self.regs.gpr.X, operand);
            },
            // jumps
            .JEQ => if (self.regs.SW.s.cc == .Equal) {
                self.regs.PC = operand;
            },
            .JGT => if (self.regs.SW.s.cc == .Greater) {
                self.regs.PC = operand;
            },
            .JLT => if (self.regs.SW.s.cc == .Less) {
                self.regs.PC = operand;
            },
            .J => {
                if (self.regs.PC == (operand + ins_sz)) self.stop();
                self.regs.PC = operand;
            },
            // bit manipulation
            .AND => self.regs.gpr.A &= operand,
            .OR => self.regs.gpr.A |= operand,
            // jump to subroutine
            .JSUB => {
                self.regs.gpr.L = self.regs.PC + ins_sz - 1;
                self.regs.PC = operand;
            },
            .RSUB => self.regs.PC = self.regs.gpr.L,
            // load and store byte
            .LDCH => {
                self.regs.gpr.A &= ~@as(u24, 0xFF);
                self.regs.gpr.A |= self.getAddr(u8, sic, false, address_mode);
            },
            .STCH => if (address_mode != .Immediate) {
                self.mem.set(operand, @as(u8, @truncate(self.regs.gpr.A & 0xFF)));
            },
            // floating point arithmetic
            .ADDF => {
                self.regs.F += self.getAddr(f64, sic, false, address_mode);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .SUBF => {
                self.regs.F -= self.getAddr(f64, sic, false, address_mode);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .MULF => {
                self.regs.F *= self.getAddr(f64, sic, false, address_mode);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .DIVF => {
                self.regs.F /= self.getAddr(f64, sic, false, address_mode);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .COMPF => {
                const f = self.getAddr(f64, sic, false, address_mode);
                self.regs.SW.s.cc = comp(self.regs.F, f);
            },

            // load and store
            .LDB => self.regs.gpr.B = operand,
            .LDS => self.regs.gpr.S = operand,
            // .LDF => self.regs.F = self.getAddrF(instr, instr_size, sic, getFnF),
            .LDT => self.regs.gpr.T = operand,
            .STB => if (address_mode != .Immediate) {
                self.mem.set(operand, self.regs.gpr.B);
            },
            .STS => if (address_mode != .Immediate) {
                self.mem.set(operand, self.regs.gpr.S);
            },
            .STF => self.mem.setF(operand, self.regs.F),
            .STT => if (address_mode != .Immediate) {
                self.mem.set(operand, self.regs.gpr.T);
            },
            // special load and store
            // .LPS => {},
            // .STI => {},
            .STSW => if (address_mode != .Immediate) {
                self.mem.set(operand, self.regs.SW);
            },
            // devices
            .RD => {
                const dev_ = self.getAddr(u8, sic, false, address_mode);
                self.regs.gpr.A = self.devs.getDevice(dev_).read();
            },
            .WD => {
                const dev_ = self.getAddr(u8, sic, false, address_mode);
                self.devs.getDevice(dev_).write(@truncate(self.regs.gpr.A & 0xFF));
            },
            .TD => {
                const dev_ = self.getAddr(u8, sic, false, address_mode);
                const t = self.devs.getDevice(dev_).@"test"();
                if (!t) {
                    self.regs.SW.s.cc = .Greater;
                }
            },
            // system
            // .SSK => {},

            // ***** SIC/XE Format 1 *****
            .FLOAT => {
                self.regs.F = @floatFromInt(self.regs.gpr.A);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .FIX => self.regs.gpr.A = @intFromFloat(self.regs.F),
            // .NORM => {}, ???

            // ***** SIC/XE Format 2 *****
            .ADDR => {
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.set(reg2(regs), r2 +% r1);
            },
            .SUBR => {
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.set(reg2(regs), r2 -% r1);
            },
            .MULR => {
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.set(reg2(regs), r2 *% r1);
            },
            .DIVR => {
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.set(reg2(regs), r2 / r1);
            },
            .COMPR => {
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.SW.s.cc = comp(r1, r2);
            },
            .SHIFTL => {
                const r1 = self.regs.get(reg1(regs), u24);
                self.regs.set(reg2(regs), r1 << @truncate(regs & 0xF));
            },
            .SHIFTR => {
                const r1 = self.regs.get(reg1(regs), u24);
                self.regs.set(reg2(regs), r1 >> @truncate(regs & 0xF));
            },
            .RMO => {
                const r1 = self.regs.get(reg1(regs), u24);
                self.regs.set(reg2(regs), r1);
            },
            // .SVC => {},
            .CLEAR => self.regs.set(reg1(regs), @as(u24, 0)),
            .TIXR => {
                self.regs.gpr.X +%= 1;
                const r1 = self.regs.get(reg1(regs), u24);
                self.regs.SW.s.cc = comp(self.regs.gpr.X, r1);
            },

            // .HIO => {},
            // .SIO => {},
            // .TIO => {},

            else => @panic("unhandeled instruction"),
        }
    }

    inline fn mv_back(self: *Self, n: u24) void {
        self.regs.PC -%= n;
    }

    inline fn reg1(r: u8) RegIdx {
        return @enumFromInt(r >> 4);
    }

    inline fn reg2(r: u8) RegIdx {
        return @enumFromInt(r & 0xF);
    }

    fn comp(v1: anytype, v2: @TypeOf(v1)) Ord {
        if (v1 < v2) {
            return .Less;
        } else if (v1 > v2) {
            return .Greater;
        } else {
            return .Equal;
        }
    }

    fn get(self: *Self, comptime T: type, addr: u24, addr_mode: AddrMode, comptime addr_size: usize) T {
        if (T == f64) {
            const shift = @bitSizeOf(u48) - (@bitSizeOf(u24) - addr_size);

            return switch (addr_mode) {
                .Immediate => @bitCast(@as(u64, addr) << shift), // ????????
                .Normal => self.mem.getF(addr),
                .Indirect => self.mem.getF(self.mem.get(addr, u24)),
                .None => unreachable,
            };
        }
        return switch (addr_mode) {
            .Immediate => @truncate(addr),
            .Normal => self.mem.get(addr, T),
            .Indirect => self.mem.get(self.mem.get(addr, u24), T),
            .None => unreachable, // Error
        };
    }

    fn getAddr(self: *Self, comptime T: type, sic: bool, comptime is_store: bool, addr_mode: AddrMode) T {
        const am: AddrMode = if (is_store) @enumFromInt(@intFromEnum(addr_mode) -| 1) else addr_mode;

        const xbpe_addr = self.fetch();
        const x = (xbpe_addr & 0x80) >> 7;
        const b = (xbpe_addr & 0x40) >> 6;
        const p = (xbpe_addr & 0x20) >> 5;
        const e = (xbpe_addr & 0x10) >> 4;

        const a = self.fetch();

        var plus = self.regs.gpr.X * x;

        if (sic) {
            const addr = (@as(u24, xbpe_addr & 0x7F) << 8) | a;
            return self.get(T, addr + plus, am, @bitSizeOf(u15));
        }

        plus += self.regs.gpr.B * b;

        if (e > 0) {
            const addr: i20 = @bitCast(((@as(u20, xbpe_addr & 0xF) << 16) | (@as(u20, a) << 8)) | self.fetch());
            plus += self.regs.PC * p;
            return self.get(T, @truncate(@as(u25, @bitCast(@as(i25, addr) + @as(i25, plus)))), am, @bitSizeOf(u20));
        }

        plus += self.regs.PC * p;

        const addr: i12 = @bitCast((@as(u12, xbpe_addr & 0xF) << 8) | a);
        return self.get(T, @truncate(@as(u25, @bitCast(@as(i25, addr) + @as(i25, plus)))), am, @bitSizeOf(u12));
    }

    fn fetch(self: *Self) u8 {
        const ret = self.mem.get(self.regs.PC, u8);
        self.regs.PC += 1;
        return ret;
    }
};

test "Regs.set, Regs.get" {
    var m = Machine.init(undefined, undefined);

    m.regs.set(.A, 1);
    try std.testing.expectEqual(1, m.regs.gpr.A);
    try std.testing.expectEqual(1, m.regs.get(.A, u24));

    m.regs.set(.B, 2);
    try std.testing.expectEqual(2, m.regs.gpr.B);
    try std.testing.expectEqual(2, m.regs.get(.B, u24));

    try std.testing.expectEqualSlices(u24, &.{ 1, 0, 0, 2, 0, 0 }, m.regs.gpr.asArray()[0..6]);

    m.regs.set(.F, @as(f64, 1.1));
    try std.testing.expectEqual(1.1, m.regs.F);
    try std.testing.expectEqual(1.1, m.regs.get(.F, f64));
}

test "Mem.set, Mem.get" {
    var buf = [_]u8{0} ** 20;
    var mem = Mem{ .buf = &buf };

    mem.set(0, @as(u24, 10));

    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 10 }, buf[0..3]);

    const v = mem.get(0, u24);

    try std.testing.expectEqual(10, v);

    mem.setF(0, 1.0);

    const f = mem.getF(0);
    try std.testing.expectEqual(1.0, f);

    const expected = std.mem.toBytes(std.mem.nativeToBig(u48, @truncate(@as(u64, @bitCast(@as(f64, 1.0))) >> 16)))[0..hl.sizeOf(u48)];
    try std.testing.expectEqualSlices(u8, expected, buf[0..hl.sizeOf(u48)]);
}

// test "Machine.step" {
//     var buf = [_]u8{0} ** 100;

//     var m = Machine.init(&buf, undefined);

//     m.mem.set(10, @as(u24, 20));

//     try std.testing.expectEqual(20, m.mem.get(10, u24));

//     m.mem.set(0, Is.Fmt{ .f3 = .{
//         .opcode = @truncate(Opcode.LDA.int()),
//         .n = false,
//         .i = true,
//         .x = false,
//         .b = false,
//         .p = false,
//         .e = false,
//         .addr = 1,
//         ._pad = 0,
//     } });

//     try std.testing.expectEqual(@as(u32, @bitCast(Is.Fmt{ .f3 = .{
//         .opcode = @truncate(Opcode.LDA.int()),
//         .n = false,
//         .i = true,
//         .x = false,
//         .b = false,
//         .p = false,
//         .e = false,
//         .addr = 1,
//         ._pad = 0,
//     } })), m.mem.getE(0, u32, .big));

//     m.mem.set(3, Is.Fmt{ .f3 = .{
//         .opcode = @truncate(Opcode.ADD.int()),
//         .n = true,
//         .i = true,
//         .x = false,
//         .b = false,
//         .p = false,
//         .e = false,
//         .addr = 10,
//         ._pad = 0,
//     } });

//     try std.testing.expectEqual(@as(u32, @bitCast(Is.Fmt{ .f3 = .{
//         .opcode = @truncate(Opcode.ADD.int()),
//         .n = true,
//         .i = true,
//         .x = false,
//         .b = false,
//         .p = false,
//         .e = false,
//         .addr = 10,
//         ._pad = 0,
//     } })), m.mem.getE(3, u32, .big));

//     m.mem.set(6, Is.Fmt{ .f3 = .{
//         .opcode = @truncate(Opcode.STA.int()),
//         .n = true,
//         .i = true,
//         .x = false,
//         .b = false,
//         .p = false,
//         .e = false,
//         .addr = 10,
//         ._pad = 0,
//     } });

//     try std.testing.expectEqual(@as(u32, @bitCast(Is.Fmt{ .f3 = .{
//         .opcode = @truncate(Opcode.STA.int()),
//         .n = true,
//         .i = true,
//         .x = false,
//         .b = false,
//         .p = false,
//         .e = false,
//         .addr = 10,
//         ._pad = 0,
//     } })), m.mem.getE(6, u32, .big));

//     m.step();
//     try std.testing.expectEqual(1, m.regs.gpr.A);

//     m.step();
//     try std.testing.expectEqual(21, m.regs.gpr.A);

//     m.step();
//     try std.testing.expectEqual(21, m.mem.get(10, u24));
// }

// test "STA" {
//     var buf = [_]u8{0} ** 100;

//     var m = Machine.init(&buf, undefined);

//     m.regs.gpr.A = 10;

//     m.mem.set(0, Is.Fmt{ .f3 = .{
//         .opcode = @truncate(Opcode.STA.int()),
//         .n = true,
//         .i = true,
//         .x = false,
//         .b = false,
//         .p = false,
//         .e = false,
//         .addr = 3,
//         ._pad = 0,
//     } });

//     m.step();
//     try std.testing.expectEqual(10, m.mem.get(3, u24));
// }

test "Machine.load" {
    var buf = [_]u8{0} ** 100;
    const str =
        \\Hprg   000001000011
        \\T00000111B400510000510001510002510003510004
        \\E000001
    ;

    var m = Machine.init(&buf, undefined);

    try m.load(str, true, std.testing.allocator);

    const prog = m.mem.get(1, [17]u8);
    try std.testing.expectEqualSlices(u8, &.{
        0xB4, 0x00, 0x51, 0x00, 0x00, 0x51, 0x00, 0x01,
        0x51, 0x00, 0x02, 0x51, 0x00, 0x03, 0x51, 0x00,
        0x04,
    }, &prog);

    try std.testing.expectEqual(1, m.regs.PC);
}

test "test_arith" {
    var buf = [_]u8{0} ** 200;
    var m = Machine.init(&buf, undefined);

    const str =
        \\HARITH 00000000006F
        \\T00000006000007000004
        \\T0000151E4B200F4B20184B20214B202A4B20333F2FFD032FD61B2FD60F2FD64F0000
        \\T0000331E032FCA1F2FCA0F2FCD4F0000032FBE232FBE0F2FC44F0000032FB2272FB2
        \\T0000511E0F2FBB4F0000032FA6272FA6232FA30F2FAF032F9A1F2FA90F2FA64F0000
        \\E000015
    ;

    try m.load(str, true, std.testing.allocator);

    m.start();

    const res = [_]u8{ 0, 0, 7, 0, 0, 4, 0, 0, 11, 0, 0, 3, 0, 0, 28, 0, 0, 1, 0, 0, 3 };
    try std.testing.expectEqualSlices(u8, &res, &m.mem.get(0, [7 * 3]u8));
}

// test "test_horner" {
//     var buf = [_]u8{0} ** 300;
//     var m = Machine.init(&buf, undefined);

//     const str =
//         \\HHORNER000000000059
//         \\T0000001E0000010000020000030000040000050000020000000500000100051D0001
//         \\T00001E1EAC05692FDDB400A01533201F37201C6D0003984190311B8000232FD59431
//         \\T00003C1D6D00039C416D000190413F2FDC6D0003984190311B80000F2FBC3F2FFD
//         \\E000015
//     ;

//     try m.load(str, true, std.testing.allocator);

//     m.start();

//     try std.testing.expectEqual(57, m.mem.get(0x12, u24));
// }
