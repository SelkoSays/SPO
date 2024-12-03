const std = @import("std");
const hl = @import("helper.zig");
const dev = @import("device.zig");
const Device = dev.Device;
const Devices = dev.Devices;
const Is = @import("instruction_set");
const Opcode = Is.Opcode;
const Fmt = Is.Fmt;

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

    pub fn setSpeed(self: *Self, speed_kHz: u64) void {
        self.clock_speed = speed_kHz;
        if (speed_kHz == 0) {
            self.clock_speed += 1;
        }
    }

    inline fn sleep_time(self: *Self) u64 {
        return std.time.us_per_s / self.clock_speed;
    }

    pub fn start(self: *Self) void {
        self.stopped = false;
        while (!self.stopped) {
            const t_start = std.time.microTimestamp();
            self.step();
            const elapsed = std.time.microTimestamp() - t_start;
            std.time.sleep((self.sleep_time() -| @as(u64, @intCast(elapsed))) * std.time.ns_per_us);
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
        const instr = self.mem.get(self.regs.PC, Fmt);
        const opcode: Opcode = std.meta.intToEnum(Opcode, instr.f3.opcode) catch blk: {
            break :blk @enumFromInt(instr.f1.opcode);
        };

        var instr_size = Is.opTable.get(opcode) orelse 0;
        if (instr_size > 2 and instr.f3.e) {
            instr_size += 1;
        }
        self.regs.PC += instr_size;

        var address_mode = AddrMode.Normal;

        if (!instr.f3.n and instr.f3.i) {
            address_mode = .Immediate;
        } else if (instr.f3.n and !instr.f3.i) {
            address_mode = .Indirect;
        }

        const sic = !instr.f3.n and !instr.f3.i;

        const n = self.getAddr(u24, instr, instr_size, sic, false, address_mode);

        switch (opcode) {
            // load and store
            .LDA => self.regs.gpr.A = n,
            .LDX => self.regs.gpr.X = n,
            .LDL => self.regs.gpr.L = n,
            .STA => if (address_mode != .Immediate) {
                self.mem.set(
                    self.getAddr(u24, instr, instr_size, sic, true, address_mode),
                    self.regs.gpr.A,
                );
            },
            .STX => if (address_mode != .Immediate) {
                self.mem.set(
                    self.getAddr(u24, instr, instr_size, sic, true, address_mode),
                    self.regs.gpr.X,
                );
            },
            .STL => if (address_mode != .Immediate) {
                self.mem.set(
                    self.getAddr(u24, instr, instr_size, sic, true, address_mode),
                    self.regs.gpr.L,
                );
            },
            // fixed point arithmetic
            .ADD => self.regs.gpr.A +%= n,
            .SUB => self.regs.gpr.A -%= n,
            .MUL => self.regs.gpr.A *%= n,
            .DIV => self.regs.gpr.A /= n,
            .COMP => self.regs.SW.s.cc = comp(self.regs.gpr.A, n),
            .TIX => {
                self.regs.gpr.X +%= 1;
                self.regs.SW.s.cc = comp(self.regs.gpr.X, n);
            },
            // jumps
            .JEQ => if (self.regs.SW.s.cc == .Equal) {
                self.regs.PC = n;
            },
            .JGT => if (self.regs.SW.s.cc == .Greater) {
                self.regs.PC = n;
            },
            .JLT => if (self.regs.SW.s.cc == .Less) {
                self.regs.PC = n;
            },
            .J => {
                if (self.regs.PC == (n - instr_size)) self.stop();
                self.regs.PC = n;
            },
            // bit manipulation
            .AND => self.regs.gpr.A &= n,
            .OR => self.regs.gpr.A |= n,
            // jump to subroutine
            .JSUB => {
                self.regs.gpr.L = self.regs.PC;
                self.regs.PC = n;
            },
            .RSUB => self.regs.PC = self.regs.gpr.L,
            // load and store byte
            .LDCH => {
                self.regs.gpr.A &= ~@as(u24, 0xFF);
                self.regs.gpr.A |= self.getAddr(u8, instr, instr_size, sic, false, address_mode);
            },
            .STCH => if (address_mode != .Immediate) {
                self.mem.set(
                    self.getAddr(u24, instr, instr_size, sic, true, address_mode),
                    @as(u8, @truncate(self.regs.gpr.A & 0xFF)),
                );
            },
            // floating point arithmetic
            .ADDF => {
                self.regs.F += self.getAddr(f64, instr, instr_size, sic, false, address_mode);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .SUBF => {
                self.regs.F -= self.getAddr(f64, instr, instr_size, sic, false, address_mode);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .MULF => {
                self.regs.F *= self.getAddr(f64, instr, instr_size, sic, false, address_mode);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .DIVF => {
                self.regs.F /= self.getAddr(f64, instr, instr_size, sic, false, address_mode);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .COMPF => {
                const f = self.getAddr(f64, instr, instr_size, sic, false, address_mode);
                self.regs.SW.s.cc = comp(self.regs.F, f);
            },

            // load and store
            .LDB => self.regs.gpr.B = n,
            .LDS => self.regs.gpr.S = n,
            // .LDF => self.regs.F = self.getAddrF(instr, instr_size, sic, getFnF),
            .LDT => self.regs.gpr.T = n,
            .STB => if (address_mode != .Immediate) {
                self.mem.set(
                    self.getAddr(u24, instr, instr_size, sic, true, address_mode),
                    self.regs.gpr.B,
                );
            },
            .STS => if (address_mode != .Immediate) {
                self.mem.set(
                    self.getAddr(u24, instr, instr_size, sic, true, address_mode),
                    self.regs.gpr.S,
                );
            },
            // .STF => self.mem.setF(n, self.regs.F),
            .STT => if (address_mode != .Immediate) {
                self.mem.set(
                    self.getAddr(u24, instr, instr_size, sic, true, address_mode),
                    self.regs.gpr.T,
                );
            },
            // special load and store
            // .LPS => {},
            // .STI => {},
            .STSW => if (address_mode != .Immediate) {
                self.mem.set(
                    self.getAddr(u24, instr, instr_size, sic, true, address_mode),
                    self.regs.SW,
                );
            },
            // devices
            .RD => {
                const dev_ = self.getAddr(u8, instr, instr_size, sic, false, address_mode);
                self.regs.gpr.A = self.devs.getDevice(dev_).read();
            },
            .WD => {
                const dev_ = self.getAddr(u8, instr, instr_size, sic, false, address_mode);
                self.devs.getDevice(dev_).write(@truncate(self.regs.gpr.A & 0xFF));
            },
            .TD => {
                const dev_ = self.getAddr(u8, instr, instr_size, sic, false, address_mode);
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
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r2 +% r1);
            },
            .SUBR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r2 -% r1);
            },
            .MULR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r2 *% r1);
            },
            .DIVR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r2 / r1);
            },
            .COMPR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.SW.s.cc = comp(r1, r2);
            },
            .SHIFTL => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r1 << instr.f2.r2);
            },
            .SHIFTR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r1 >> instr.f2.r2);
            },
            .RMO => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r1);
            },
            // .SVC => {},
            .CLEAR => self.regs.set(@enumFromInt(instr.f2.r1), @as(u24, 0)),
            .TIXR => {
                self.regs.gpr.X +%= 1;
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                self.regs.SW.s.cc = comp(self.regs.gpr.X, r1);
            },

            // .HIO => {},
            // .SIO => {},
            // .TIO => {},

            else => @panic("unhandeled instruction"),
        }
    }

    fn notSicErr(self: *Self) void {
        // TODO: handle
        _ = self;
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

    fn getAddr(self: *Self, comptime T: type, instr: Is.Fmt, instr_size: u3, sic: bool, comptime is_store: bool, addr_mode: AddrMode) T {
        if (instr_size <= 2) {
            unreachable;
        }

        const am: AddrMode = if (is_store) @enumFromInt(@intFromEnum(addr_mode) -| 1) else addr_mode;

        var plus = self.regs.gpr.X * @intFromBool(instr.fs.x);

        if (sic) {
            return self.get(T, instr.fs.addr + plus, am, @bitSizeOf(u15));
        }

        plus += self.regs.gpr.B * @intFromBool(instr.f3.b);
        plus += self.regs.PC * @intFromBool(instr.f3.p);

        if (instr.f3.e) {
            return self.get(T, @truncate(@as(i25, instr.f4.addr) + @as(i25, plus)), am, @bitSizeOf(u20));
        }

        return self.get(T, @truncate(@as(i25, instr.f3.addr) + @as(i25, plus)), am, @bitSizeOf(u12));
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

test "Machine.step" {
    var buf = [_]u8{0} ** 100;

    var m = Machine.init(&buf, undefined);

    m.mem.set(10, @as(u24, 20));

    try std.testing.expectEqual(20, m.mem.get(10, u24));

    m.mem.set(0, Is.Fmt{ .f3 = .{
        .opcode = @truncate(Opcode.LDA.int()),
        .n = false,
        .i = true,
        .x = false,
        .b = false,
        .p = false,
        .e = false,
        .addr = 1,
        ._pad = 0,
    } });

    try std.testing.expectEqual(@as(u32, @bitCast(Is.Fmt{ .f3 = .{
        .opcode = @truncate(Opcode.LDA.int()),
        .n = false,
        .i = true,
        .x = false,
        .b = false,
        .p = false,
        .e = false,
        .addr = 1,
        ._pad = 0,
    } })), m.mem.getE(0, u32, .big));

    m.mem.set(3, Is.Fmt{ .f3 = .{
        .opcode = @truncate(Opcode.ADD.int()),
        .n = true,
        .i = true,
        .x = false,
        .b = false,
        .p = false,
        .e = false,
        .addr = 10,
        ._pad = 0,
    } });

    try std.testing.expectEqual(@as(u32, @bitCast(Is.Fmt{ .f3 = .{
        .opcode = @truncate(Opcode.ADD.int()),
        .n = true,
        .i = true,
        .x = false,
        .b = false,
        .p = false,
        .e = false,
        .addr = 10,
        ._pad = 0,
    } })), m.mem.getE(3, u32, .big));

    m.mem.set(6, Is.Fmt{ .f3 = .{
        .opcode = @truncate(Opcode.STA.int()),
        .n = false,
        .i = true,
        .x = false,
        .b = false,
        .p = false,
        .e = false,
        .addr = 10,
        ._pad = 0,
    } });

    try std.testing.expectEqual(@as(u32, @bitCast(Is.Fmt{ .f3 = .{
        .opcode = @truncate(Opcode.STA.int()),
        .n = false,
        .i = true,
        .x = false,
        .b = false,
        .p = false,
        .e = false,
        .addr = 10,
        ._pad = 0,
    } })), m.mem.getE(6, u32, .big));

    m.step();
    try std.testing.expectEqual(1, m.regs.gpr.A);

    m.step();
    try std.testing.expectEqual(21, m.regs.gpr.A);

    m.step();
    try std.testing.expectEqual(21, m.mem.get(10, u24));
}

test "STA" {
    var buf = [_]u8{0} ** 100;

    var m = Machine.init(&buf, undefined);

    m.mem.set(0, Is.Fmt{ .f3 = .{} });

    m.regs.gpr.A = 10;
}
