const std = @import("std");
const Allocator = std.mem.Allocator;

const Lexer = @import("lexer.zig");
const token = @import("token.zig");
const tk = token.TokenType;

const res = @import("../../tools/result.zig");

const ISet = @import("../../tools/instruction_set.zig");
const RegSet = @import("../machine/machine.zig").RegIdx;

const I = @import("instruction.zig");
const Inst = I.Instruction;
const Expr = I.Expression;

fn Result(comptime O: type) type {
    return res.Result(O, ParseError);
}

const ParseError = struct {
    err: anyerror,
    msg: []const u8,

    pub fn any(self: *const ParseError) anyerror {
        return self.err;
    }
};

const PFn = fn (*Parser, *Inst) anyerror!void;

pub const Parser = struct {
    lines: Lexer.Lines = undefined,
    cur_line: Lexer.Line = undefined,
    cur_idx: u32 = 0,
    alloc: Allocator,

    ls: u32 = 0, // Lokacijski števec
    sym_tab: std.StringHashMap(?u32) = undefined,

    base: bool = false,

    reserved: std.StaticStringMap(?PFn),

    const Self = @This();

    pub fn init(lex: Lexer) !Self {
        var l = lex;
        const lines = try (try l.lines()).try_unwrap();

        const reserved = std.StaticStringMap(?PFn).initComptime(.{
            .{ "START", null },
            .{ "END", parse_end },
            .{ "ORG", parse_org },
            .{ "EQU", parse_equ },
            .{ "BASE", parse_base },
            .{ "NOBASE", parse_nobase },
            .{ "BYTE", parse_byte },
            .{ "WORD", parse_word },
            .{ "RESB", parse_resb },
            .{ "RESW", parse_resw },
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

    fn first_pass(self: *Self) !Result([]Inst) {
        const R = Result([]Inst);

        if (!self.is_reserved(self.cur_line.instruction.lexeme) or !std.mem.eql(u8, self.cur_line.instruction.lexeme, "START")) {
            return R.err(.{
                .err = error.NoStartError,
                .msg = "Program should start with a 'START' directive",
            });
        }

        if (self.cur_line.label != null and self.cur_line.label.?.lexeme.len > 6) {
            return R.err(.{
                .err = error.TooLongProgramNameError,
                .msg = "Program name should be at most 6 characters long",
            });
        }

        var code = std.ArrayList(Inst).init(self.alloc);
        defer code.deinit();

        const start_ls = try ex_get_num_from_args(self.cur_line, 0);
        if (start_ls) |ls| {
            self.ls = ls.num;
        }

        try code.append(Inst{
            .kind = .Start,
            .arg1 = ex_get_sym_from_label(self.cur_line),
            .arg2 = start_ls,
        });

        while (self.advance() and self.cur_line.instruction.type != .Eof) {
            const cl = self.cur_line;

            if (cl.label) |l| {
                const e = try self.sym_tab.getOrPut(l.lexeme);

                if (e.found_existing and e.value_ptr != null) {
                    return R.err(.{ .err = error.DuplicateLabelError, .msg = "Program should not have duplicate labels" });
                }

                e.value_ptr.* = self.ls;
            }

            var inst = Inst{ .loc = self.ls, .base = self.base };

            if (self.reserved.get(cl.instruction.lexeme)) |pfn| {
                if (pfn != null) {
                    try pfn.?(self, &inst);
                }
            } else {
                inst.opcode = std.meta.stringToEnum(ISet.Opcode, cl.instruction.lexeme) orelse return R.err(.{
                    .err = error.InvalidInstructionError,
                    .msg = "Instruction does not exist",
                });

                const i_len = ISet.opTable.get(inst.opcode).?;
                self.ls += i_len;
            }

            self.parse_args(&inst);

            try code.append(inst);
        }
    }

    fn is_reserved(self: *const Self, str: []const u8) bool {
        return self.reserved.has(str);
    }

    fn advance(self: *Self) bool {
        self.cur_idx += 1;
        if (self.cur_idx >= self.lines.lines.len) return false;
        self.cur_line = self.lines.lines[self.cur_idx];
        return true;
    }

    fn ex_get_num_from_args(line: *const Lexer.Line, idx: usize) !?Expr {
        if (line.args != null and line.args.?.len > idx) {
            return Expr{
                .num = try std.fmt.parseInt(u24, line.args.?[idx].lexeme, 0),
            };
        }
        return null;
    }

    fn ex_get_sym_from_args(line: *const Lexer.Line, idx: usize) ?Expr {
        if (line.args != null and line.args.?.len > idx) {
            return Expr{
                .sym = line.args.?[idx].lexeme,
            };
        }
        return null;
    }

    fn ex_get_sym_from_label(line: *const Lexer.Line) ?Expr {
        if (line.label) |l| {
            return Expr{
                .sym = l.lexeme,
            };
        }
        return null;
    }

    fn match_tk(comptime expected: []const tk, actual: tk) bool {
        for (expected) |t| {
            if (t == actual) return true;
        }

        return false;
    }

    fn try_parse_addr_mode(@"type": tk, inst: *Inst, i: *usize) bool {
        switch (@"type") {
            .At => {
                inst.addr_mode = .Indirect;
                i.* += 1;
                return true;
            },
            .Hash => {
                inst.addr_mode = .Immediate;
                i.* += 1;
                return true;
            },
            else => {},
        }

        return false;
    }

    fn parse_first_arg(self: *Self, args: []const token, inst: *Inst, i: *usize) !void {
        switch (args[i.*].type) {
            .Id => {
                const reg = std.meta.stringToEnum(RegSet, args[i.*].lexeme);

                if (reg) |r| {
                    inst.arg1 = Expr{ .reg = r };
                } else {
                    self.new_sym(args[i.*].lexeme, inst);
                }

                i += 1;
            },
            .Num => {
                inst.arg1 = try ex_get_num_from_args(self.cur_line, i);
                i += 1;
            },
            else => {
                return error.UnexpectedArgumentError;
            },
        }
    }

    fn parse_args(self: *Self, inst: *Inst) !void {
        const args = self.cur_line.args orelse return;

        var i: usize = 0;
        if (args.len == 0) return;

        const am = try_parse_addr_mode(args[i].type, inst, &i);

        if (am and args.len <= i) {
            return error.InsufficientArgumentsError;
        }

        try self.parse_first_arg(args, inst, &i);

        if (args.len >= i) {
            if (args[i].type != .Comma) {
                return error.ArgumentsNotSeparatedByComma;
            }

            i += 1;

            if (args[i].type != .Id) {
                return error.SecondArgumentNotIdentifierError;
            }

            const reg = std.meta.stringToEnum(RegSet, args[i].lexeme) orelse return error.SecondArgumentNotRegisterError;

            inst.arg2 = Expr{ .reg = reg };
        }
    }

    fn new_sym(self: *Self, sym: []const u8, inst: *Inst) void {
        const e = try self.sym_tab.getOrPut(sym);

        if (e.found_existing and e.value_ptr.* != null) {
            inst.arg1 = e.value_ptr.*.?;
        } else {
            e.value_ptr.* = null;
        }
    }

    fn parse_end(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.EndExpectsAnArgument;
        if (args.len == 0) return error.EndExpectsAnArgument;

        inst.kind = .End;

        var num = try ex_get_num_from_args(self.cur_line, 0);

        if (num == null) {
            num = try ex_get_sym_from_args(self.cur_line, 0);
        }

        if (num == null) {
            return error.EndDidNotGetNumOrIdError;
        }

        if (num.? == .sym) {
            self.new_sym(num.?.sym, inst);
        }
    }

    fn parse_equ(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.EquExpectsAnArgument;
        if (args.len == 0) return error.EquExpectsAnArgument;

        inst.kind = .Equ;

        var num = try ex_get_num_from_args(self.cur_line, 0);

        if (num == null) {
            num = try ex_get_sym_from_args(self.cur_line, 0);
        }

        if (num == null) {
            return error.EquDidNotGetNumOrIdError;
        }

        if (num.? == .sym) {
            self.new_sym(num.?.sym, inst);
        }
    }

    fn parse_org(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.OrgExpectsAnArgument;
        if (args.len == 0) return error.OrgExpectsAnArgument;

        _ = inst;

        const num = try ex_get_num_from_args(self.cur_line, 0) orelse return error.OrgExpectsANumberArgument;

        self.ls = num.num;
    }

    fn parse_base(self: *Self, inst: *Inst) anyerror!void {
        _ = self;
        _ = inst;
    }

    fn parse_nobase(self: *Self, inst: *Inst) anyerror!void {
        _ = self;
        _ = inst;
    }

    fn parse_byte(self: *Self, inst: *Inst) anyerror!void {
        _ = self;
        _ = inst;
    }

    fn parse_word(self: *Self, inst: *Inst) anyerror!void {
        _ = self;
        _ = inst;
    }

    fn parse_resb(self: *Self, inst: *Inst) anyerror!void {
        _ = self;
        _ = inst;
    }

    fn parse_resw(self: *Self, inst: *Inst) anyerror!void {
        _ = self;
        _ = inst;
    }
};
