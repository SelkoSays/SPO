const std = @import("std");
const Machine = @import("machine.zig").Machine;

pub fn main() !void {
    var m = Machine.init();
    m.regs.set(.A, 1);
    m.regs.set(.B, 2);
    m.regs.set(.F, @as(f64, 1.1));
    std.debug.print("{d} {X:0>3}\n", .{ m.regs.get(.F, f64), m.regs.get(.A, u24) });
}
