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
    _ = prog;

    const prog2 =
        \\PRG START 0
        \\    LDA   #1
        \\A   RESB  3
        \\B   RESW  3
        \\C   EQU   4
        \\D   BYTE  1
        \\E   WORD  2
        \\    END   PRG
    ;
    const l = lex.init(prog2, alloc);
    var p = try par.Parser.init(l);
    defer p.deinit();

    for (p.lines.lines) |ln| {
        ln.display();
        std.debug.print("\n", .{});
    }

    const ast = try p.parse();

    for (ast) |i| {
        i.display();
        std.debug.print("\n", .{});
    }

    alloc.free(ast);
    // const lines = (try l.lines()).unwrap();
    // defer lines.deinit(alloc);

    // for (lines.lines) |ln| {
    //     ln.display();
    //     std.debug.print("\n", .{});
    // }
}
