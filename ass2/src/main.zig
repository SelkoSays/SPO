const std = @import("std");
const run = @import("runner.zig");
const obj_r = @import("obj_reader.zig");
const Machine = @import("machine.zig").Machine;

pub const std_options: std.Options = .{ .log_level = .warn };

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const alloc = gpa.allocator();

    // // try run.init(alloc);
    // // defer run.deinit(alloc);

    // // const action = try run.parseArgs(alloc);
    // // try run.run(alloc, action);

    // var buf = [_]u8{0} ** 300;
    // var m = Machine.init(&buf, undefined);

    // const str =
    //     \\HHORNER000000000059
    //     \\T0000001E0000010000020000030000040000050000020000000500000100051D0001
    //     \\T00001E1EAC05692FDDB400A01533201F37201C6D0003984190311B8000232FD59431
    //     \\T00003C1D6D00039C416D000190413F2FDC6D0003984190311B80000F2FBC3F2FFD
    //     \\E000015
    // ;

    // try m.load(str, true, alloc);

    // m.start();

    // try std.testing.expectEqual(57, m.mem.get(0x12, u24));
}
