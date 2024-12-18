const std = @import("std");
const run = @import("runner/runner.zig");
const lex = @import("compiler/lexer.zig");

pub const std_options: std.Options = .{ .log_level = .warn };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    try run.init(alloc);
    defer run.deinit(alloc);

    const action = try run.parseArgs(alloc);
    try run.run(alloc, action);

    var l = lex.init("abc");
    _ = try l.next();
}
