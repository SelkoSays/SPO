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

    pub fn display(self: *const LexErr) void {
        std.debug.print("Error({d}): {s}\n", .{ self.pos.line, self.msg });
    }
};

pub const Line = struct {
    label: ?Token = null,
    instruction: Token = undefined,
    args: ?[]const Token = null,

    pub fn deinit(self: *const Line, alloc: Allocator) void {
        if (self.args != null) {
            alloc.free(self.args.?);
        }
    }

    pub fn display(self: *const Line) void {
        if (self.instruction.type == .Eof) {
            std.debug.print(">EOF<\n", .{});
            return;
        }

        if (self.label) |l| {
            std.debug.print("Label: {{ .lexeme = '{s}', .type = {s}, .pos = {{ .line = {d}, .start = {d} }} }}\n", .{ l.lexeme, @tagName(l.type), l.pos.line, l.pos.start });
        }

        std.debug.print("Instrunction: '{s}'\n", .{self.instruction.lexeme});

        if (self.args) |args| {
            std.debug.print("Arguments: [", .{});
            for (args) |a| {
                std.debug.print(" '{s}'", .{a.lexeme});
            }
            std.debug.print(" ]\n", .{});
        }
    }
};

pub const Lines = struct {
    lines: []Line,

    pub fn deinit(self: *const Lines, alloc: Allocator) void {
        for (self.lines) |*l| {
            l.deinit(alloc);
        }

        alloc.free(self.lines);
    }
};

str: []const u8,
line: u32 = 0, // current line
start: u32 = 0,
cur: u32 = 0, // current index in str
ch: u8 = 0, // current char
alloc: Allocator,

const Self = @This();

pub fn init(str: []const u8, alloc: Allocator) Self {
    var self = Self{
        .str = str,
        .alloc = alloc,
    };

    _ = self.advance();
    self.cur -|= 1;

    return self;
}

pub fn lines(self: *Self) !Result(Lines) {
    var liness = std.ArrayList(Line).init(self.alloc);
    defer {
        for (liness.items) |*l| {
            l.deinit(self.alloc);
        }
        liness.deinit();
    }

    var cur_line = try self.next();

    while (cur_line.is_ok() and cur_line.unwrap().instruction.type != .Eof) {
        try liness.append(cur_line.unwrap());
        cur_line = try self.next();
    }

    if (cur_line.is_err()) {
        return cur_line.map_ok(Lines, null) catch unreachable;
    }

    try liness.append(cur_line.unwrap());

    return Result(Lines).ok(.{ .lines = try liness.toOwnedSlice() });
}

pub fn next(self: *Self) !Result(Line) {
    const R = Result(Line);

    var skipped_comment = false;
    while (self.ch == '.') {
        self.skipComment();
        self.skipWhitespace();
        skipped_comment = true;
    }

    var c = self.str[self.cur -| 1];
    if (skipped_comment and std.ascii.isWhitespace(c) and c != '\n') {
        self.cur -|= 1;
        self.ch = c;
        skipped_comment = false;
    }

    while (self.is_nl()) {
        self.line += 1;
        _ = self.advance();
    }

    while (self.ch == '.') {
        self.skipComment();
        self.skipWhitespace();
        skipped_comment = true;
    }

    if (self.ch == 0) return R.ok(Line{ .instruction = self.tEof() });

    c = self.str[self.cur -| 1];
    if (skipped_comment and std.ascii.isWhitespace(c) and c != '\n') {
        self.cur -|= 1;
        self.ch = c;
    }

    const ch = self.ch;
    self.start = self.cur;

    var line = Line{};

    if (!std.ascii.isWhitespace(ch)) {
        const id = self.identifier();
        if (id.is_err()) {
            return id.map_ok(Line, null) catch unreachable;
        }
        const lexeme = id.unwrap();
        line.label = Token.init(
            .Id,
            lexeme,
            self.curPos(self.start, @truncate(lexeme.len)),
        );
    }

    self.skipWhitespace();

    while (self.ch == '.') {
        self.skipComment();
        self.skipWhitespace();
    }

    // Lex instruction
    const instr = self.identifier();
    if (instr.is_err()) {
        return instr.map_ok(Line, null) catch unreachable;
    }

    const lexeme = instr.unwrap();
    line.instruction = Token.init(
        .Id,
        lexeme,
        self.curPos(self.start, @truncate(lexeme.len)),
    );

    _ = self.skipWhitespaceUntilEOL();

    if (self.ch == '.') {
        self.skipComment();
        return R.ok(line);
    }

    // Lex args
    const args = try self.arguments();
    if (args.is_err()) {
        return args.map_ok(Line, null) catch unreachable;
    }

    line.args = args.unwrap();

    return R.ok(line);
}

fn skipComment(self: *Self) void {
    while ((self.ch != 0) and !self.is_nl()) {
        _ = self.advance();
    }

    if (self.is_nl()) {
        self.line += 1;
    }
    _ = self.advance();
    return;
}

fn arguments(self: *Self) !Result([]Token) {
    const R = Result([]Token);

    var args = std.ArrayList(Token).init(self.alloc);
    defer args.deinit();

    var ch = self.ch;

    while (ch != 0 and ch != '\n') {
        self.start = self.cur;

        var any_skipped = false;
        switch (ch) {
            ',' => {
                try args.append(Token.init(.Comma, ",", self.curPos(null, null)));
                ch = self.advance();
                any_skipped = self.skipWhitespaceUntilEOL();
                if (!any_skipped) self.cur -|= 1;
            },
            '#' => {
                try args.append(Token.init(.Hash, "#", self.curPos(null, null)));
            },
            '@' => {
                try args.append(Token.init(.At, "@", self.curPos(null, null)));
            },
            'a'...'z', 'A'...'Z' => {
                const id = self.identifier();
                if (id.is_err()) {
                    return id.map_ok([]Token, null) catch unreachable;
                }
                const name = id.unwrap();
                try args.append(Token.init(.Id, name, self.curPos(self.start, @truncate(name.len))));
                any_skipped = self.skipWhitespaceUntilEOL();
                if (!any_skipped) {
                    self.cur -|= 1;
                }
            },
            '0'...'9' => {
                const num = self.number();
                if (num.is_err()) {
                    return num.map_ok([]Token, null) catch unreachable;
                }
                const name = num.unwrap();
                try args.append(Token.init(.Num, name, self.curPos(self.start, @truncate(name.len))));
                any_skipped = self.skipWhitespaceUntilEOL();
                if (!any_skipped) {
                    self.cur -|= 1;
                }
            },
            '.' => {
                break;
            },
            else => {
                return R.err(.{ .pos = self.curPos(null, null), .msg = "Unknown symbol for argument" });
            },
        }

        if (!any_skipped) {
            ch = self.advance();
        } else {
            ch = self.ch;
        }
    }

    return R.ok(try args.toOwnedSlice());
}

fn identifier(self: *Self) Result([]const u8) {
    const R = Result([]const u8);
    const ascii = std.ascii;

    self.start = self.cur;

    var ch = self.ch;

    if (!ascii.isAlphabetic(ch)) {
        return R.err(.{ .pos = self.curPos(null, null), .msg = "Label should start with an alphabetic character" });
    }

    while (ascii.isAlphanumeric(ch)) {
        ch = self.advance();
    }

    if (ch == 0) {
        self.cur += 1;
    }

    return R.ok(self.str[self.start..self.cur]);
}

fn number(self: *Self) Result([]const u8) {
    const R = Result([]const u8);
    const ascii = std.ascii;

    self.start = self.cur;

    var ch = self.ch;

    if (!ascii.isDigit(ch)) {
        return R.err(.{ .pos = self.curPos(null, null), .msg = "Number should start with a digit" });
    }

    var base: u8 = 10;

    if (ch == '0') {
        ch = self.advance();
        if (ch == 'x') {
            base = 16;
            ch = self.advance();
        } else if (ch == 'b') {
            base = 2;
            ch = self.advance();
        } else if (ascii.isDigit(ch)) {
            return R.err(.{ .pos = self.curPos(null, null), .msg = "Number not equal to 0 should not start with zero" });
        }
    }

    while (digitInBase(ch, base)) {
        ch = self.advance();
    }

    if (ch == 0) {
        self.cur += 1;
    }

    return R.ok(self.str[self.start..self.cur]);
}

fn digitInBase(digit: u8, base: u8) bool {
    if (std.ascii.isDigit(digit)) {
        return (digit - '0') < base;
    } else if (std.ascii.isAlphabetic(digit)) {
        const d = std.ascii.toUpper(digit);
        return (d - 'A' + 10) < base;
    }

    return false;
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

fn skipWhitespaceUntilEOL(self: *Self) bool {
    var ch = self.ch;
    var any_skip = false;
    while (std.ascii.isWhitespace(ch) and !self.is_nl()) {
        ch = self.advance();
        any_skip = true;
    }
    return any_skip;
}

fn advance(self: *Self) u8 {
    if (self.cur + 1 >= self.str.len) {
        self.ch = 0;
        return 0;
    }
    self.cur += 1;
    self.ch = self.str[self.cur];

    return self.ch;
}

fn is_nl(self: *const Self) bool {
    return self.ch == '\n';
}
fn tEof(self: *const Self) Token {
    return Token{ .lexeme = "EOF", .pos = self.curPos(null, 0) };
}

fn curPos(self: *const Self, start: ?u32, len: ?u32) Token.Pos {
    return Token.Pos{
        .line = self.line,
        .start = start orelse self.cur,
        .len = len orelse 1,
    };
}

test "test_lexer" {
    const prog =
        \\abc lda x    ,  l   .hello
        \\aa . Jojojojoj
        \\  lda  @x,y, 123 . ok
        \\  rsub
        \\. Konec
        \\ . Konec
    ;
    var l = init(prog, std.testing.allocator);

    const lines_ = (try l.lines()).unwrap();
    defer lines_.deinit(std.testing.allocator);

    // lines_.lines[0].display();

    try std.testing.expectEqualDeep(Line{
        .label = Token{
            .type = .Id,
            .lexeme = "abc",
            .pos = Token.Pos{
                .line = 0,
                .len = 3,
                .start = 0,
            },
        },
        .instruction = Token{
            .type = .Id,
            .lexeme = "lda",
            .pos = Token.Pos{
                .line = 0,
                .len = 3,
                .start = 4,
            },
        },
        .args = &.{
            Token.init(.Id, "x", Token.Pos{ .line = 0, .len = 1, .start = 8 }),
            Token.init(.Comma, ",", Token.Pos{ .line = 0, .len = 1, .start = 13 }),
            Token.init(.Id, "l", Token.Pos{ .line = 0, .len = 1, .start = 16 }),
        },
    }, lines_.lines[0]);
}
