const std = @import("std");
const Allocator = std.mem.Allocator;

const Result = @import("result").Result;

pub const Code = struct {
    header: Header,
    start_addr: u24,
    records: []Record,

    const Header = struct {
        name: [6]u8 = [_]u8{0} ** 6,
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
            sym_name: ?[6]u8 = null,
        },
        D: void, // not supported at the moment
        R: void, // not supported at the moment
    };
};

pub const ObjReadErr = struct {
    type: anyerror,
    line: u32,
    col: u32,

    const Self = @This();
    pub fn any(self: Self) anyerror {
        return self.type;
    }
};

pub fn read(r: std.io.AnyReader, alloc: Allocator) !Result(Code, ObjReadErr) {
    var col: u32 = 0;
    var line_num: u32 = 0;
    var line = std.ArrayList(u8).init(alloc);
    const line_writer = line.writer();

    try r.streamUntilDelimiter(line_writer, '\n', null);
    _ = try read_header(line.items, &col);

    line_num += 1;

    return undefined;
}

fn read_header(line: []const u8, col: *u32) !Result(Code.Header, ObjReadErr) {
    _ = line;
    _ = col;

    return undefined;
}
