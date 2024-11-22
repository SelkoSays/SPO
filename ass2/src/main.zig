const std = @import("std");

const mach = @import("machine.zig");
const Machine = mach.Machine;

const device = @import("device.zig");
const Device = device.Device;
const Devices = device.Devices;

const Is = @import("instruction_set");
const Opcode = Is.Opcode;

pub fn main() !void {
    var buf = [_]u8{0} ** 100;

    var m = Machine.init(&buf, undefined);

    var b = [_]u8{ 0, 1, 0, 0 };
    const fmt = std.mem.bytesToValue(Is.Fmt, &b);
    _ = fmt;

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
    try std.testing.expectEqual(21, m.regs.gpr.A);
    try std.testing.expectEqual(21, m.mem.get(10, u24));
}
