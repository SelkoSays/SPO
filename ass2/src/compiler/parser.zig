const std = @import("std");
const Allocator = std.mem.Allocator;

const Lexer = @import("lexer.zig");
const res = @import("../../tools/result.zig");
const ISet = @import("instruction_set");
const RegSet = @import("../machine/machine.zig").RegIdx;

pub const Parser = struct {
    lines: Lexer.Lines = undefined,
    cur_line: u32,
    alloc: Allocator,

    ls: u32 = 0, // Lokacijski števec
    sym_tab: std.StringHashMap(?u32) = undefined,

    can_use_start: bool = true,
    reserved: std.StaticStringMap(void),

    const Self = @This();

    pub fn init(lex: Lexer) !Self {
        var l = lex;
        const lines = try (try l.lines()).try_unwrap();

        const reserved = std.StaticStringMap(void).initComptime(.{
            .{ "START", {} },
            .{ "END", {} },
            .{ "ORG", {} },
            .{ "EQU", {} },
            .{ "BASE", {} },
            .{ "NOBASE", {} },
            .{ "BYTE", {} },
            .{ "WORD", {} },
            .{ "RESB", {} },
            .{ "RESW", {} },
        });

        return Self{
            .lines = lines,
            .cur_line = 0,
            .alloc = lex.alloc,
            .sym_tab = std.StringHashMap(?u32).init(lex.alloc),
            .reserved = reserved,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.lines.deinit(self.lex.alloc);
    }

    pub fn parse(self: *Self) void {
        _ = self;
    }

    fn first_pass(self: *Self) void {
        _ = self;
    }
};
