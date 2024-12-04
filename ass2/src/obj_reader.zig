const std = @import("std");
const Allocator = std.mem.Allocator;

const result = @import("result");

fn Result(comptime O: type) type {
    return result.Result(O, ObjReadErr);
}

pub const Code = struct {
    header: Header,
    start_addr: u24,
    records: []const Record,

    pub const Header = struct {
        name: [6]u8 = [_]u8{' '} ** 6,
        addr: u24,
        len: u24,
    };

    pub const Record = union(enum) {
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

        pub fn deinit(self: *Record, alloc: Allocator) void {
            switch (self.*) {
                .T => |t| {
                    alloc.free(t.code);
                },
                else => {},
            }
        }
    };

    const Self = @This();

    pub fn deinit(self: *const Self, alloc: Allocator) void {
        for (self.records) |*r| {
            switch (r.*) {
                .T => |t| {
                    alloc.free(t.code);
                },
                else => {},
            }
        }

        alloc.free(self.records);
    }

    pub fn display(self: *const Self, writer: std.io.AnyWriter) !void {
        try writer.print("H{s}{X:0>6}{X:0>6}\n", .{ self.header.name, self.header.addr, self.header.len });
        for (self.records) |*r| {
            switch (r.*) {
                .T => |t| {
                    try writer.print("T{X:0>6}{X:0>2}", .{ t.addr, t.len });
                    for (t.code) |c| {
                        try writer.print("{X:0>2}", .{c});
                    }
                    try writer.print("\n", .{});
                },
                .M => |m| {
                    try writer.print("M{X:0>6}{X:0>2}", .{ m.addr, m.size });
                    if (m.sign != null) {
                        try writer.print("{c}{X:0>6}", .{ m.sign.?, m.sym_name });
                    }
                    try writer.print("\n", .{});
                },
                else => {},
            }
        }

        try writer.print("E{X:0>6}", .{self.start_addr});
    }
};

pub const ObjReadErr = struct {
    type: anyerror,
    line: u32,
    col: u32 = 0,
    msg: ?[]const u8 = null,

    const Self = @This();
    pub fn any(self: Self) anyerror {
        return self.type;
    }

    pub fn display(self: Self) void {
        std.debug.print("{d}:{d}: Error {s}\n", .{ self.line, self.col, self.msg orelse "" });
    }
};

pub fn from_str(str: []const u8, alloc: Allocator) !Result(Code) {
    const R = Result(Code);

    var it = std.mem.tokenizeScalar(u8, str, '\n');

    if (it.peek() == null) {
        return R.err(.{
            .type = error.EmptyFile,
            .line = 0,
        });
    }

    var line_num: u32 = 0;

    const r_header = read_header(it.next().?, line_num);
    if (r_header.is_err()) {
        return r_header.map_ok(Code, null);
    }

    line_num += 1;

    const header = r_header.unwrap();

    var records = std.ArrayList(Code.Record).init(alloc);
    defer {
        for (records.items) |*r| {
            r.deinit(alloc);
        }
        records.deinit();
    }

    while (it.peek() != null) {
        const t = try read_T_record(it.peek().?, line_num, alloc);
        if (t.is_err()) {
            if (t.Err.type == error.ExpectedTRecord) {
                break;
            }

            return t.map_ok(Code, null);
        }

        const tt = t.unwrap();
        try records.append(tt);

        _ = it.next();

        line_num += 1;
    }

    if (it.peek() != null and it.peek().?[0] == 'M') {
        return R.err(.{
            .type = error.MRecordsNotSupported,
            .line = line_num,
        });
    }
    // TODO: parse M records
    // while (it.peek() != null) {
    //     if (it.peek().?[0] != 'M') {
    //         break;
    //     }
    //     line_num += 1;
    //     _ = it.next();
    // }

    var code = Code{
        .header = header,
        .start_addr = header.addr,
        .records = try records.toOwnedSlice(),
    };

    // parse Entry
    if (it.next()) |entry| {
        if (entry[0] != 'E') {
            return R.err(.{
                .type = error.ExpectedERecord,
                .line = line_num,
            });
        }

        const addr = read_int(u24, entry[1..7]) catch return parse_err(R, 1, line_num);
        code.start_addr = addr;
    }

    return R.ok(code);
}

pub fn from_reader(r: std.io.AnyReader, alloc: Allocator) !Result(Code) {
    var str = std.ArrayList(u8).init(alloc);
    defer str.deinit();
    const w = str.writer();
    try r.streamUntilDelimiter(w, 0, null);

    return from_str(str.items, alloc);
}

fn read_header(line: []const u8, line_num: u32) Result(Code.Header) {
    const R = Result(Code.Header);

    if (line[0] != 'H') {
        return R.err(.{
            .type = error.ExpectedHeader,
            .line = line_num,
        });
    }

    if (line.len != 19) {
        return R.err(.{
            .type = error.WrongHeaderLength,
            .line = line_num,
        });
    }

    const h_name = line[1..7];
    const addr = read_int(u24, line[7..13]) catch return parse_err(R, 7, line_num);
    const len = read_int(u24, line[13..19]) catch return parse_err(R, 13, line_num);

    return R.ok(.{
        .name = h_name.*,
        .addr = addr,
        .len = len,
    });
}

fn read_T_record(line: []const u8, line_num: u32, alloc: Allocator) !Result(Code.Record) {
    const R = Result(Code.Record);

    if (line[0] != 'T') {
        return R.err(.{
            .type = error.ExpectedTRecord,
            .line = line_num,
        });
    }

    if (line.len < 9) {
        return R.err(.{
            .type = error.WrongTRecordLength,
            .line = line_num,
        });
    }

    const addr = read_int(u24, line[1..7]) catch return parse_err(R, 1, line_num);
    const len: u8 = read_int(u8, line[7..9]) catch return parse_err(R, 1, line_num);

    if (len > 0x1E) {
        return R.err(.{
            .type = error.TRecordCodeLengthTooBig,
            .line = line_num,
            .col = 9,
        });
    }

    if (line[9..].len != (len * 2)) {
        return R.err(.{
            .type = error.WrongTRecordCodeLength,
            .line = line_num,
            .col = 9,
        });
    }

    var rest = len;
    var code = std.ArrayList(u8).init(alloc);
    defer code.deinit();

    var i: usize = 9;
    while (rest >= 1) {
        defer rest -= 1;
        defer i += 2;

        const byte = read_int(u8, line[i..(i + 2)]) catch return parse_err(R, @truncate(i), line_num);
        try code.append(byte);
    }

    return R.ok(.{ .T = .{
        .addr = addr,
        .len = len,
        .code = try code.toOwnedSlice(),
    } });
}

fn parse_err(comptime R: type, col: u32, line_num: u32) R {
    return R.err(.{
        .type = error.UnexpectedCharacter,
        .col = col,
        .line = line_num,
    });
}

fn read_int(comptime T: type, buf: []const u8) !T {
    return std.fmt.parseInt(T, buf, 16);
}

test from_str {
    const str =
        \\Hprg   000000000011
        \\T00000011B400510000510001510002510003510004
        \\E000000
    ;

    const r_code = try from_str(str, std.testing.allocator);
    if (r_code.is_err()) {
        _ = r_code.try_unwrap() catch |err| {
            std.log.err("Error: {}", .{err});
            return err;
        };
    }
    var code = r_code.unwrap();
    defer code.deinit(std.testing.allocator);

    try std.testing.expectEqualDeep(Code{
        .header = Code.Header{
            .name = "prg   ".*,
            .addr = 0,
            .len = 0x11,
        },
        .start_addr = 0,
        .records = &.{Code.Record{
            .T = .{
                .addr = 0,
                .len = 0x11,
                .code = &.{
                    0xB4, 0x00, 0x51, 0x00, 0x00, 0x51, 0x00, 0x01,
                    0x51, 0x00, 0x02, 0x51, 0x00, 0x03, 0x51, 0x00,
                    0x04,
                },
            },
        }},
    }, code);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try code.display(out.writer().any());

    try std.testing.expectEqualStrings(str, out.items);
}
