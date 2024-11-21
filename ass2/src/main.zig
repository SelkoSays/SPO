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

    m.mem.set(0, @as(u24, 0x210019));
    // buf[0] = 0x21;
    // buf[1] = 0x00;
    // buf[2] = 0x19;

    // const fmt: Fmt = @bitCast(m.mem.getE(0, u32, .little));
    // std.debug.print("fmt = {any}\n", .{fmt.f3});

    m.devs.setDevice(0, Device{ .file = std.io.getStdIn(), .closable = false });
    m.devs.setDevice(1, Device{ .file = std.io.getStdOut(), .closable = false });
    m.devs.setDevice(2, Device{ .file = std.io.getStdErr(), .closable = false });

    // m.devs.getDevice(1).write(48);
    // m.devs.getDevice(1).write(10);

    // var d = m.devs.getDevice(3);
    // for ("Hello World!\n") |c| {
    //     d.write(c);
    // }
    //
}
