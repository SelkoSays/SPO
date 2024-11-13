const std = @import("std");
const m = @import("machine.zig");
const sr = m.StatReg;

pub fn main() !void {
    var a: sr = sr.fromInt(0);
    a.mode = 1;
    a.idle = 1;

    std.debug.print("{X:0>3}\n", .{m.Regs.A.asInt()});
}
