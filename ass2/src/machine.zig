const std = @import("std");
const helper = @import("helper.zig");
const dev = @import("device.zig");
const Device = dev.Device;
const Devices = dev.Devices;

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

            const Ord = enum(u2) {
                Less = 0b00,
                Equal = 0b01,
                Greater = 0b10,
            };
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

    pub const MAX_ADDR = std.math.maxInt(u24);

    const Self = @This();

    pub fn get(self: *const Self, addr: u24, comptime T: type) T {
        const size = helper.sizeOf(T);
        // TODO: check address
        var ret = std.mem.bytesToValue(T, self.buf[addr .. addr + size]);

        if (@typeInfo(T) == .Int) {
            ret = std.mem.bigToNative(T, ret);
        }

        return ret;
    }

    pub fn set(self: *Self, addr: u24, val: anytype) void {
        const T: type = @TypeOf(val);
        const size = helper.sizeOf(T);

        // std.debug.print("addr = {X}\n", .{addr});

        var v = val;

        if (@typeInfo(T) == .Int) {
            v = std.mem.nativeToBig(T, v);
        }

        const ptr = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]);
        ptr.* = v;
    }

    pub fn getE(self: *const Self, addr: u24, comptime T: type, comptime enidan: std.builtin.Endian) T {
        const size = helper.sizeOf(T);
        // TODO: check address
        var ret = std.mem.bytesToValue(T, self.buf[addr .. addr + size]);

        if (@typeInfo(T) == .Int) {
            ret = std.mem.bigToNative(T, ret);
            ret = std.mem.nativeTo(T, ret, enidan);
        }

        return ret;
    }

    pub fn setE(self: *Self, addr: u24, val: anytype, comptime enidan: std.builtin.Endian) void {
        const T: type = @TypeOf(val);
        const size = helper.sizeOf(T);

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
    devs: *Devices(256),

    const Self = @This();

    pub fn init(buf: [*]u8, devs: *Devices(256)) Self {
        return .{
            .mem = .{ .buf = buf },
            .devs = devs,
        };
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

    const expected = std.mem.toBytes(std.mem.nativeToBig(u48, @truncate(@as(u64, @bitCast(@as(f64, 1.0))) >> 16)))[0..helper.sizeOf(u48)];
    try std.testing.expectEqualSlices(u8, expected, buf[0..helper.sizeOf(u48)]);
}
