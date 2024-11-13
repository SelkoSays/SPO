const std = @import("std");
const sr = @import("machine.zig").StatReg;

pub fn main() !void {
    var a: sr = sr.fromInt(0);
    a.mode = 1;
    a.idle = 1;

    std.debug.print("{X:0>3}\n", .{a.asInt()});
}
