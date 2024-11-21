const std = @import("std");

const mach = @import("machine.zig");
const Machine = mach.Machine;

const device = @import("device.zig");
const Device = device.Device;
const Devices = device.Devices;

// const Fmt = @import("instructions.zig").Fmt;

pub fn main() !void {
    var buf = [_]u8{0} ** 20;
    var devs = Devices(256){};
    defer devs.deinit();

    var m = Machine.init(&buf, &devs);

    m.devs.setDevice(0, Device{ .file = std.io.getStdIn(), .closable = false });
    m.devs.setDevice(1, Device{ .file = std.io.getStdOut(), .closable = false });
    m.devs.setDevice(2, Device{ .file = std.io.getStdErr(), .closable = false });

    m.step();
}
