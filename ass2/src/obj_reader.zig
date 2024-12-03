const std = @import("std");
const Allocator = std.mem.Allocator;

const result = @import("result");

fn Result(comptime O: type) type {
    return result.Result(O, ObjReadErr);
}

pub const Code = struct {
    header: Header,
    start_addr: u24,
    records: []Record,

    const Header = struct {
        name: [6]u8 = [_]u8{' '} ** 6,
        addr: u24,
        len: u24,
    };

    const Record = union(enum) {
        T: struct {
            addr: u24,
            len: u8,
            code: []const u8,
        },
        M: struct {
            addr: u24,
            size: u8,
            sign: ?u8 = null, // + or -
            sym_name: [6]u8 = [_]u8{' '} ** 6,
        },
        D: void, // not supported at the moment
        R: void, // not supported at the moment
    };
};

pub const ObjReadErr = struct {
    type: anyerror,
    line: u32,
    col: u32,
    msg: ?[]const u8 = null,

    const Self = @This();
    pub fn any(self: Self) anyerror {
        return self.type;
    }

    pub fn display(self: Self) void {
        std.debug.print("{d}:{d}: Error {s}", .{ self.line, self.col, self.msg orelse "" });
    }
};

pub fn read(r: std.io.AnyReader, alloc: Allocator) !Result(Code) {
    const R = Result(Code);

    var line_num: u32 = 0;
    var line = std.ArrayList(u8).init(alloc);
    const line_writer = line.writer();

    try r.streamUntilDelimiter(line_writer, '\n', null);
    const r_header = read_header(line.items, line_num);
    if (r_header.is_err()) {
        return r_header.map_ok(Code, null);
    }

    const header = r_header.unwrap() catch unreachable; // never error
    line_num += 1;

    return R.Ok(.{
        .header = header,
        .records = undefined,
        .start_addr = undefined,
    });
}

fn read_header(line: []const u8, line_num: u32) Result(Code.Header) {
    const R = Result(Code.Header);

    if (line.len != 19) {
        return R.Err(.{
            .type = error.WrongHeaderLength,
            .line = line_num,
            .col = 0,
        });
    }

    if (line[0] != 'H') {
        return R.Err(.{
            .type = error.ExpectedHeader,
            .line = line_num,
            .col = 0,
        });
    }

    const h_name = line[1..7];
    const addr = std.fmt.parseInt(u24, line[7..13], 16) catch {
        return R.Err(.{
            .type = error.UnexpectedCharacter,
            .col = 7,
            .line = line_num,
        });
    };
    const len = std.fmt.parseInt(u24, line[13..19], 16) catch {
        return R.Err(.{
            .type = error.UnexpectedCharacter,
            .col = 13,
            .line = line_num,
        });
    };

    return R.Ok(.{
        .name = h_name.*,
        .addr = addr,
        .len = len,
    });
}

fn read_T_records(r: std.io.AnyReader, line: *std.ArrayList(u8), line_num: *u32) @TypeOf(.{ Result([]Code.Record), []const u8 }) {
    line.clearRetainingCapacity();
    _ = r;
    _ = line_num;
}
