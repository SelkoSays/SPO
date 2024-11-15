const std = @import("std");
const mach = @import("machine.zig");
const Machine = mach.Machine;
const Device = @import("device.zig").Device;

pub fn main() !void {
    var buf = [_]u8{0} ** 20;
    var devs = [_]?Device{null} ** 256;
    var m = Machine.init(&buf, &devs);

    m.devs.setDevice(0, Device.init(std.io.getStdIn(), ""));
    m.devs.setDevice(1, Device.init(std.io.getStdOut(), ""));
    m.devs.setDevice(2, Device.init(std.io.getStdErr(), ""));

    m.devs.getDevice(1).write(48);
    m.devs.getDevice(1).write(10);
    // const b = m.devs.getDevice(0).read();
    // std.log.debug("Byte: {X}", .{b});

    var d = m.devs.getDevice(3);
    d.write(72);
    d.write(101);
    d.write(108);
    d.write(108);
    d.write(111);

    d.file.?.close(); // just for testing purposes
    // m.mem.set(0, @as(u24, 1));

    // std.debug.print("{X:0>2} {X:0>2} {X:0>2}\n", .{ m.mem.get(0, u8), m.mem.get(1, u8), m.mem.get(2, u8) });
    // std.debug.print("{X:0>6}\n", .{m.mem.get(0, u24)});

    // m.regs.set(.A, 1);
    // m.regs.set(.B, 2);
    // m.regs.set(.F, @as(f64, 1.1));
    // std.debug.print("{d} {X:0>3}\n", .{ m.regs.get(.F, f64), m.regs.get(.A, u24) });
}
