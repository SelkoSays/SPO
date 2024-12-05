const std = @import("std");
const run = @import("runner.zig");
const obj_r = @import("obj_reader.zig");
// const Machine = @import("machine.zig").Machine;

pub const std_options: std.Options = .{ .log_level = .warn };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    try run.init(alloc);
    defer run.deinit(alloc);

    const action = try run.parseArgs(alloc);
    try run.run(alloc, action);
}
