/// Does not own literal
const std = @import("std");

type: TokenType = .Eof,
lexeme: []const u8,
pos: Pos,

pub const TokenType = enum {
    Id,
    Num,
    Str,
    Comma, // ,
    Hash, // #
    At, // @,
    Eof,
};

pub const Pos = struct {
    line: u32,
    start: u32, // position in string
    len: u32,
};

const Self = @This();

/// Does not own string literal
pub fn init(
    @"type": TokenType,
    lexeme: []const u8,
    pos: Pos,
) Self {
    return Self{
        .type = @"type",
        .lexeme = lexeme,
        .pos = pos,
    };
}

// ./src/compiler/compiler.zig:1:0
