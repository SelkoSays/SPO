const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = @import("token.zig");

const result = @import("result");

fn Result(comptime O: type) type {
    return result.Result(O, LexErr);
}

const LexErr = struct {
    pos: Token.Pos,
    msg: []const u8,

    pub fn any(self: *const LexErr) anyerror {
        _ = self;
        return error.LexerError;
    }
};

const Line = struct {
    label: ?Token = null,
    instruction: Token,
    args: []const Token,

    pub fn deinit(self: Line, alloc: Allocator) void {
        alloc.free(self);
    }
};

str: []const u8,
line: u32 = 0, // current line
col: u32 = 0,
start: u32 = 0,
cur: u32 = 0, // current index in str
ch: u8 = 0, // current char
new_line: bool = true,

const Self = @This();

pub fn init(str: []const u8) Self {
    var self = Self{
        .str = str,
    };

    _ = self.advance();
    self.cur -|= 1;

    return self;
}

pub fn next(self: *Self) Result(Line) {
    const R = Result(Line);

    while (self.is_nl()) {
        self.line += 1;
        self.col = 0;
        self.new_line = true;
        _ = self.advance();
    }

    const ch = self.ch;
    self.start = self.cur;

    if (ch == 0) return R.ok(self.tEof());

    if (self.new_line and !std.ascii.isWhitespace(ch)) {
        const id = self.identifier();
        if (id.is_err()) {
            return id.map_ok(Line, null);
        }
        self.new_line = false;
    }

    self.skipWhitespace();

    // Check comment
    // Lex instruction
    // Check comment
    // Lex args
}

fn identifier(self: *Self) Result([]const u8) {
    const R = Result([]const u8);
    const ascii = std.ascii;

    var ch = self.ch;

    if (!ascii.isAlphabetic(ch)) {
        return R.err(.{ .pos = self.curPos(null, null), .msg = "Label should start with a alphabetic character" });
    }

    while (ascii.isAlphanumeric(ch)) {
        ch = self.advance();
    }

    return R.ok(self.str[self.start..self.cur]);
}

fn skipWhitespace(self: *Self) void {
    var ch = self.ch;
    while (std.ascii.isWhitespace(ch)) {
        if (self.is_nl()) {
            self.line += 1;
        }
        ch = self.advance();
    }
}

fn advance(self: *Self) u8 {
    if (self.cur + 1 >= self.str.len) return 0;
    self.cur += 1;
    self.ch = self.str[self.cur];
    self.col += 1;

    return self.ch;
}

fn is_nl(self: *const Self) bool {
    return self.ch == '\n';
}
fn tEof(self: *const Self) Token {
    return Token{ .lexeme = "EOF", .pos = self.curPos(self.cur, 0) };
}

fn curPos(self: *const Self, start: ?u32, len: ?u32) Token.Pos {
    return Token.Pos{
        .line = self.line,
        .col = self.col,
        .start = start orelse self.cur,
        .len = len orelse 1,
    };
}
