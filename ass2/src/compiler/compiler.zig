const std = @import("std");
const Allocator = std.mem.Allocator;

const Inst = @import("instruction.zig").Instruction;

const obj = @import("../machine/obj_reader.zig");
const Code = obj.Code;

pub const Compiler = struct {
    ast: []Inst,
    start: Inst = undefined,
    end: ?Inst = null,

    const Self = @This();

    pub fn init(ast: []Inst) !Self {
        if (ast[0].kind != .Start) return error.AstDoesNotStartWithStart;

        const start = ast[0];

        var end: ?Inst = null;
        for (ast) |*i| {
            if (i.kind == .End) {
                end = i.*;
                break;
            }
        }

        return Self{
            .ast = ast,
            .start = start,
            .end = end,
        };
    }

    pub fn emit_obj(self: *const Self, alloc: Allocator) !Code {
        var code = Code{
            .header = .{
                .addr = self.start.arg1.?.num,
            },
        };

        if (self.start.label != null) {
            _ = try std.fmt.bufPrint(&code.header.name, "{s}", .{self.start.label.?});
        }

        if (self.end) |e| {
            if (e.res_arg1 != null) {
                code.start_addr = e.res_arg1.?.num;
            } else if (e.arg1) |a1| {
                code.start_addr = a1.num;
            } else {
                code.start_addr = @truncate(self.start.loc);
            }
        }

        var recs = std.ArrayList(Code.Record).init(alloc);
        defer recs.deinit();

        var rec = Code.Record{
            .T = .{
                .addr = undefined,
                .len = 0,
                .code = undefined,
            },
        };

        var t_code = std.ArrayList(u8).init(alloc);
        defer t_code.deinit();

        var code_len: usize = 0;

        var new = true;
        for (self.ast[1..]) |*i| {
            if (new) {
                rec.T.addr = @truncate(i.loc);
                new = false;
            }

            var l: u3 = 0;
            switch (i.kind) {
                .Byte => {
                    code_len += 1;
                    if (t_code.items.len + 1 > 0x1E) {
                        rec.T.len = @as(u8, @truncate(t_code.items.len));
                        rec.T.code = try t_code.toOwnedSlice();

                        try recs.append(rec);

                        rec = Code.Record{
                            .T = .{
                                .addr = @truncate(i.loc),
                                .len = 0,
                                .code = undefined,
                            },
                        };

                        t_code = std.ArrayList(u8).init(alloc);
                    }

                    const b = if (i.res_arg1) |a| a.num else i.arg1.?.num;
                    try t_code.append(@truncate(b));
                },
                .Word => {
                    code_len += 3;
                    l = 3;

                    const b = if (i.res_arg1) |a| a.num else i.arg1.?.num;
                    if (t_code.items.len + l > 0x1E) {
                        const ll: u24 = @truncate(0x1E - t_code.items.len);
                        if (ll > 0) {
                            l -= 1;
                            try t_code.append(@truncate((b >> 16) & 0xFF));
                        }

                        if (ll > 1) {
                            l -= 1;
                            try t_code.append(@truncate((b >> 8) & 0xFF));
                        }

                        rec.T.len = @as(u8, @truncate(t_code.items.len));
                        rec.T.code = try t_code.toOwnedSlice();

                        try recs.append(rec);

                        rec = Code.Record{
                            .T = .{
                                .addr = @as(u24, @truncate(i.loc)) + ll,
                                .len = 0,
                                .code = undefined,
                            },
                        };

                        t_code = std.ArrayList(u8).init(alloc);
                    }

                    if (l > 2) {
                        try t_code.append(@truncate((b >> 16) & 0xFF));
                    }
                    if (l > 1) {
                        try t_code.append(@truncate((b >> 8) & 0xFF));
                    }
                    try t_code.append(@truncate(b & 0xFF));
                },
                .Resb,
                .Resw,
                => {
                    if (i.kind == .Resb) {
                        code_len += i.arg1.?.num;
                    } else {
                        code_len += i.arg1.?.num * 3;
                    }

                    if (t_code.items.len > 0) {
                        rec.T.len = @truncate(t_code.items.len);
                        rec.T.code = try t_code.toOwnedSlice();

                        try recs.append(rec);

                        rec = Code.Record{
                            .T = .{
                                .addr = undefined,
                                .len = 0,
                                .code = undefined,
                            },
                        };

                        t_code = std.ArrayList(u8).init(alloc);
                    }
                    new = true;
                },
                .Normal => {
                    const b = i.bytes(&l);
                    code_len += l;

                    var st_idx: u24 = 0;

                    if (t_code.items.len + l > 0x1E) {
                        const ll = 0x1E - t_code.items.len;
                        for (0..ll) |idx| {
                            try t_code.append(b[idx]);
                            st_idx += 1;
                        }

                        rec.T.len = @as(u8, @truncate(t_code.items.len));
                        rec.T.code = try t_code.toOwnedSlice();

                        try recs.append(rec);

                        rec = Code.Record{
                            .T = .{
                                .addr = @as(u24, @truncate(i.loc)) + st_idx,
                                .len = 0,
                                .code = undefined,
                            },
                        };

                        t_code = std.ArrayList(u8).init(alloc);
                    }

                    for (st_idx..l) |idx| {
                        try t_code.append(b[idx]);
                    }
                },
                .Org => {
                    if (i.res_arg1) |a| {
                        code_len = a.num;
                    } else {
                        code_len = i.arg1.?.num;
                    }
                },
                else => {},
            }
        }

        if (t_code.items.len > 0) {
            rec.T.len = @as(u8, @truncate(t_code.items.len));
            rec.T.code = try t_code.toOwnedSlice();

            try recs.append(rec);
        }

        for (self.ast[1..]) |*i| {
            if (!i.extended) continue;

            // addr: u24,
            // len: u8,
            // sign: ?u8 = null, // + or -
            // sym_name: [6]u8 = [_]u8{' '} ** 6,

            try recs.append(.{ .M = .{
                .addr = @as(u24, @truncate(i.loc)) + 1,
                .len = 5,
            } });
        }

        code.records = try recs.toOwnedSlice();
        code.header.len = @truncate(code_len);

        return code;
    }
};
