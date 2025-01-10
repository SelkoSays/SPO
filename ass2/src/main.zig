const std = @import("std");
const run = @import("runner/runner.zig");
const lex = @import("compiler/lexer.zig");
const par = @import("compiler/parser.zig");

pub const std_options: std.Options = .{ .log_level = .warn };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // try run.init(alloc);
    // defer run.deinit(alloc);

    // const action = try run.parseArgs(alloc);
    // try run.run(alloc, action);

    const prog =
        \\abc lda x    ,  l   .hello
        \\aa . Jojojojoj
        \\  lda  @x,y, 123 . ok
        \\  rsub
        \\. Konec
        \\ . Konec
    ;
    const l = lex.init(prog, alloc);
    const p = try par.Parser.init(l);
    p.deinit();
    // const lines = (try l.lines()).unwrap();
    // defer lines.deinit(alloc);

    // for (lines.lines) |ln| {
    //     ln.display();
    //     std.debug.print("\n", .{});
    // }
}
