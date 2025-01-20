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
    _ = prog2;

    const f1 = try std.fs.cwd().openFile("../ass1/cat.asm", .{ .mode = .read_only });
    // f1.readToEndAlloc(allocator: Allocator, max_bytes: usize)
    const prog3 = try f1.reader().readAllAlloc(alloc, 1_000_000_000);
    defer alloc.free(prog3);

    const l = lex.init(prog3, alloc);
    var p = try par.Parser.init(l);
    defer p.deinit();

    for (p.lines.lines) |ln| {
        ln.display();
        std.debug.print("\n", .{});
    }

    const ast = try p.parse();

    const f: std.fs.File = try (std.fs.cwd().createFile("neki.lst", .{}) catch std.fs.cwd().openFile("neki.lst", .{ .mode = .write_only }));
    const w = f.writer().any();

    for (ast) |i| {
        // i.display();
        // std.debug.print("\n", .{});

        i.lst_str(w) catch |e| {
            std.log.err("{}", .{e});
        };
        w.writeByte('\n') catch |e| {
            std.log.err("{}", .{e});
        };
    }

    alloc.free(ast);
    // const lines = (try l.lines()).unwrap();
    // defer lines.deinit(alloc);

    // for (lines.lines) |ln| {
    //     ln.display();
    //     std.debug.print("\n", .{});
    // }
}
