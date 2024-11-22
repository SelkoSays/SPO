const std = @import("std");
const hlp = @import("helper.zig");
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
        const size = hlp.sizeOf(T);
        // TODO: check address
        var ret = std.mem.bytesToValue(T, self.buf[addr .. addr + size]);

        if (@typeInfo(T) == .Int) {
            ret = std.mem.bigToNative(T, ret);
        }

        return ret;
    }

    pub fn set(self: *Self, addr: u24, val: anytype) void {
        const T: type = @TypeOf(val);
        const size = hlp.sizeOf(T);

        // std.debug.print("addr = {X}\n", .{addr});

        var v = val;

        if (@typeInfo(T) == .Int) {
            v = std.mem.nativeToBig(T, v);
        }

        const ptr = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]);
        ptr.* = v;
    }

    pub fn getE(self: *const Self, addr: u24, comptime T: type, comptime enidan: std.builtin.Endian) T {
        const size = hlp.sizeOf(T);
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
        const size = hlp.sizeOf(T);

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

    const OSDevices = Devices(256);

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

        var getFn = &Self.getNormal;
        var getFnB = &Self.getNormalB;
        var getFnF = &Self.getNormalF;

        if (!instr.f3.n and instr.f3.i) {
            getFn = &Self.getImmidiate;
            getFnB = &Self.getImmidiateB;
            getFnF = &Self.getImmidiateF;
        } else if (instr.f3.n and !instr.f3.i) {
            getFn = &Self.getIndirect;
            getFnB = &Self.getIndirectB;
            getFnF = &Self.getIndirectF;
        }

        const sic = !instr.f3.n and !instr.f3.i;

        const n = self.getAddr(instr, instr_size, sic, u24, getFn);

        switch (opcode) {
            .LDA => self.regs.gpr.A = n,
            .LDB => self.regs.gpr.B = n,
            .LDCH => {
                self.regs.gpr.A &= ~@as(u24, 0xFF);
                self.regs.gpr.A |= self.getAddr(instr, instr_size, sic, u8, getFnB);
            },
            .LDF => self.regs.F = self.getAddrF(instr, instr_size, sic, getFnF),
            .LDL => self.regs.gpr.L = n,
            .LDS => self.regs.gpr.S = n,
            .LDT => self.regs.gpr.T = n,
            .LDX => self.regs.gpr.X = n,
            .ADD => self.regs.gpr.A += n,
            .ADDF => {
                self.regs.F += self.getAddrF(instr, instr_size, sic, getFnF);
                self.regs.F = hlp.chopFloat(self.regs.F);
            },
            .ADDR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r2 + r1);
            },
            .AND => self.regs.gpr.A &= n,
            .CLEAR => self.regs.set(@enumFromInt(instr.f2.r1), @as(u24, 0)),
            .COMP => self.regs.SW.s.cc = comp(self.regs.gpr.A, n),
            .COMPF => {
                const f = self.getAddrF(instr, instr_size, sic, getFnF);
                self.regs.SW.s.cc = comp(self.regs.F, f);
            },
            .COMPR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.SW.s.cc = comp(r1, r2);
            },
            .DIV => self.regs.gpr.A /= n,
            .DIVF => {
                self.regs.F /= self.getAddrF(instr, instr_size, sic, getFnF);
                self.regs.F = hlp.chopFloat(self.regs.F);
            },
            .DIVR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r2 / r1);
            },
            .FIX => self.regs.gpr.A = @intFromFloat(self.regs.F),
            .FLOAT => {
                self.regs.F = @floatFromInt(self.regs.gpr.A);
                self.regs.F = hlp.chopFloat(self.regs.F);
            },
            // .HIO => {},
            .J => {
                if (self.regs.PC == n) self.stop();
                self.regs.PC = n;
            },
            .JEQ => if (self.regs.SW.s.cc == .Equal) {
                self.regs.PC = n;
            },
            .LGT => if (self.regs.SW.s.cc == .Greater) {
                self.regs.PC = n;
            },
            .JLT => if (self.regs.SW.s.cc == .Less) {
                self.regs.PC = n;
            },
            .JSUB => {
                self.regs.gpr.L = self.regs.PC;
                self.regs.PC = n;
            },
            // .LPS => {},
            .MUL => self.regs.gpr.A *= n,
            .MULF => {
                self.regs.F *= self.getAddrF(instr, instr_size, sic, getFnF);
                self.regs.F = hlp.chopFloat(self.regs.F);
            },
            .MULR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r2 * r1);
            },
            // .NORM => {}, ???
            .OR => self.regs.gpr.A |= n,
            .RD => {
                const dev_ = self.getAddr(instr, instr_size, sic, u8, getFnB);
                self.regs.gpr.A = self.devs.getDevice(dev_).read();
            },
            .RMO => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r1);
            },
            .RSUB => self.regs.PC = self.regs.gpr.L,
            .SHIFTL => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r1 << instr.f2.r2);
            },
            .SHIFTR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r1 >> instr.f2.r2);
            },
            // .SIO => {},
            // .SSK => {},
            .STA => self.mem.set(n, self.regs.gpr.A),
            .STB => self.mem.set(n, self.regs.gpr.B),
            .STCH => self.mem.set(n, @as(u8, @truncate(self.regs.gpr.A & 0xFF))),
            .STF => self.mem.setF(n, self.regs.F),
            // .STI => {},
            .STL => self.mem.set(n, self.regs.gpr.L),
            .STS => self.mem.set(n, self.regs.gpr.S),
            .STSW => self.mem.set(n, self.regs.SW),
            .STT => self.mem.set(n, self.regs.gpr.T),
            .STX => self.mem.set(n, self.regs.gpr.X),
            .SUB => self.regs.gpr.A -= n,
            .SUBF => {
                self.regs.F -= self.getAddrF(instr, instr_size, sic, getFnF);
                self.regs.F = hlp.chopFloat(self.regs.F);
            },
            .SUBR => {
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                const r2 = self.regs.get(@enumFromInt(instr.f2.r2), u24);
                self.regs.set(@enumFromInt(instr.f2.r2), r2 - r1);
            },
            // .SVC => {},
            .TD => {
                const dev_ = self.getAddr(instr, instr_size, sic, u8, getFnB);
                const t = self.devs.getDevice(dev_).@"test"();
                if (!t) {
                    self.regs.SW.s.cc = .Greater;
                }
            },
            // .TIO => {},
            .TIX => {
                self.regs.gpr.X += 1;
                self.regs.SW.s.cc = comp(self.regs.gpr.X, n);
            },
            .TIXR => {
                self.regs.gpr.X += 1;
                const r1 = self.regs.get(@enumFromInt(instr.f2.r1), u24);
                self.regs.SW.s.cc = comp(self.regs.gpr.X, r1);
            },
            .WD => {
                const dev_ = self.getAddr(instr, instr_size, sic, u8, getFnB);
                self.devs.getDevice(dev_).write(@truncate(self.regs.gpr.A & 0xFF));
            },
            else => @panic("unhandeled instruction"),
        }

        self.regs.PC += instr_size;
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

    fn getAddr(self: *Self, instr: Is.Fmt, instr_size: u3, sic: bool, comptime T: type, getFn: *const fn (*Self, u24) T) T {
        if (instr_size > 2) {
            var plus = self.regs.gpr.X * @intFromBool(instr.fs.x);

            if (sic) {
                return getFn(self, instr.fs.addr + plus);
            }

            if (instr.f3.b) {
                plus += self.regs.gpr.B * @intFromBool(instr.f3.b);
            }

            if (instr.f3.p) {
                plus += self.regs.PC * @intFromBool(instr.f3.p);
            }

            if (instr.f3.e) {
                if (instr.f4.p) {
                    return getFn(self, @truncate(hlp.as(hlp.as(instr.f4.addr, i20) + @as(i25, plus), u25)));
                }
                return getFn(self, instr.f4.addr + plus);
            }

            if (instr.f3.p) {
                return getFn(self, @truncate(hlp.as(hlp.as(instr.f3.addr, i12) + @as(i25, plus), u25)));
            }
            return getFn(self, instr.f3.addr + plus);
        }
        return 0;
    }

    fn getAddrF(self: *Self, instr: Is.Fmt, instr_size: u3, sic: bool, getFn: *const fn (*Self, u24) f64) f64 {
        if (instr_size > 2) {
            var plus = self.regs.gpr.X * @intFromBool(instr.fs.x);

            if (sic) {
                self.notSicErr();
                return 0;
            }

            if (instr.f3.b) {
                plus += self.regs.gpr.B * @intFromBool(instr.f3.b);
            }

            if (instr.f3.p) {
                plus += self.regs.PC * @intFromBool(instr.f3.p);
            }

            if (instr.f3.e) {
                if (instr.f4.p) {
                    const a: u24 = @truncate(hlp.as(hlp.as(instr.f4.addr, i20) + @as(i25, plus), u25));
                    return getFn(self, if (getFn == Self.getImmidiateF) a << 4 else a);
                }
                return getFn(self, instr.f4.addr + plus);
            }

            if (instr.f3.p) {
                const a: u24 = @truncate(hlp.as(hlp.as(instr.f3.addr, i12) + @as(i25, plus), u25));
                return getFn(self, if (getFn == Self.getImmidiateF) a << 12 else a);
            }

            const a: u24 = instr.f3.addr + plus;
            return getFn(self, if (getFn == Self.getImmidiateF) a << 12 else a);
        }
        return 0;
    }

    fn getImmidiate(self: *Self, val: u24) u24 {
        _ = self;
        return val;
    }

    fn getNormal(self: *Self, addr: u24) u24 {
        return self.mem.get(addr, u24);
    }

    fn getIndirect(self: *Self, addr: u24) u24 {
        return self.mem.get(self.mem.get(addr, u24), u24);
    }

    fn getImmidiateF(self: *Self, val: u24) f64 {
        _ = self;
        // unsupported ?
        return @bitCast(@as(u64, val) << 40);
    }

    fn getNormalF(self: *Self, addr: u24) f64 {
        return self.mem.getF(addr);
    }

    fn getIndirectF(self: *Self, addr: u24) f64 {
        return self.mem.getF(self.mem.get(addr, u24));
    }

    fn getImmidiateB(self: *Self, val: u24) u8 {
        _ = self;
        return @truncate(val & 0xFF);
    }

    fn getNormalB(self: *Self, addr: u24) u8 {
        return self.mem.get(addr, u8);
    }

    fn getIndirectB(self: *Self, addr: u24) u8 {
        return self.mem.get(self.mem.get(addr, u24), u8);
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

    const expected = std.mem.toBytes(std.mem.nativeToBig(u48, @truncate(@as(u64, @bitCast(@as(f64, 1.0))) >> 16)))[0..hlp.sizeOf(u48)];
    try std.testing.expectEqualSlices(u8, expected, buf[0..hlp.sizeOf(u48)]);
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
