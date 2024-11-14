const std = @import("std");
const mach = @import("machine.zig");
const Machine = mach.Machine;
const Device = @import("device.zig").Device;

pub fn main() !void {
    var buf = [_]u8{0} ** 20;
    var devs = [_]?Device{null} ** 256;
    var m = Machine.init(&buf, &devs);

    m.devs.setDevice(0, Device{ .file = std.io.getStdIn() });

    m.mem.set(0, @as(u24, 1));

    std.debug.print("{X:0>2} {X:0>2} {X:0>2}\n", .{ m.mem.get(0, u8), m.mem.get(1, u8), m.mem.get(2, u8) });
    std.debug.print("{X:0>6}\n", .{m.mem.get(0, u24)});

    m.regs.set(.A, 1);
    m.regs.set(.B, 2);
    m.regs.set(.F, @as(f64, 1.1));
    std.debug.print("{d} {X:0>3}\n", .{ m.regs.get(.F, f64), m.regs.get(.A, u24) });
}
