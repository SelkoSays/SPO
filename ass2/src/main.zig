const std = @import("std");

const mach = @import("machine.zig");
const Machine = mach.Machine;

const device = @import("device.zig");
const Device = device.Device;
const Devices = device.Devices;

pub fn main() !void {
    var buf = [_]u8{0} ** 20;
    var devs = Devices(256){};
    defer devs.deinit();

    var m = Machine.init(&buf, &devs);

    m.devs.setDevice(0, Device{ .file = std.io.getStdIn(), .closable = false });
    m.devs.setDevice(1, Device{ .file = std.io.getStdOut(), .closable = false });
    m.devs.setDevice(2, Device{ .file = std.io.getStdErr(), .closable = false });

    m.devs.getDevice(1).write(48);
    m.devs.getDevice(1).write(10);
    // const b = m.devs.getDevice(0).read();
    // std.log.debug("Byte: {X}", .{b});

    var d = m.devs.getDevice(3);
    for ("Hello World!\n") |c| {
        d.write(c);
    }

    // m.mem.set(0, @as(u24, 1));

    // std.debug.print("{X:0>2} {X:0>2} {X:0>2}\n", .{ m.mem.get(0, u8), m.mem.get(1, u8), m.mem.get(2, u8) });
    // std.debug.print("{X:0>6}\n", .{m.mem.get(0, u24)});

}
