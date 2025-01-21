const std = @import("std");
const Allocator = std.mem.Allocator;

const Lexer = @import("lexer.zig");
const token = @import("token.zig");
const tk = token.TokenType;

const res = @import("result");

const ISet = @import("instruction_set");
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

const PFn = *const fn (*Parser, *Inst) anyerror!void;

pub const Parser = struct {
    lines: Lexer.Lines = undefined,
    cur_line: Lexer.Line = undefined,
    cur_idx: u32 = 0,
    alloc: Allocator,

    ls: u32 = 0, // Lokacijski števec
    sym_tab: std.StringHashMap(?u32) = undefined,

    base: bool = false,
    parsed_end: bool = false,

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

        var p = Self{
            .lines = lines,
            .cur_idx = @bitCast(@as(i32, -1)),
            .alloc = lex.alloc,
            .sym_tab = std.StringHashMap(?u32).init(lex.alloc),
            .reserved = reserved,
        };

        _ = p.advance();
        return p;
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit(self.alloc);
        self.sym_tab.deinit();
    }

    pub fn parse(self: *Self) ![]Inst {
        const astr = try self.first_pass();
        if (astr.is_err()) {
            _ = try astr.try_unwrap();
            unreachable;
        }

        const ast = astr.unwrap();
        errdefer self.alloc.free(ast);

        try self.second_pass(ast);

        return ast;
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

        const start_ls = try ex_get_num_from_args(&self.cur_line, 0);
        if (start_ls) |ls| {
            self.ls = ls.num;
        }

        if (self.cur_line.label) |l| {
            try self.sym_tab.put(l.lexeme, self.ls);
        }

        var inst = Inst{
            .kind = .Start,
            .label = if (self.cur_line.label) |l| l.lexeme else null,
            .arg1 = start_ls,
        };

        try code.append(inst);

        while (self.advance() and self.cur_line.instruction.type != .Eof) {
            const cl = self.cur_line;

            if (cl.label) |l| {
                const e = try self.sym_tab.getOrPut(l.lexeme);

                if (e.found_existing and e.value_ptr.* != null) {
                    return R.err(.{ .err = error.DuplicateLabelError, .msg = "Program should not have duplicate labels" });
                }

                e.value_ptr.* = self.ls;
            }

            inst = Inst{
                .label = if (self.cur_line.label) |l| l.lexeme else null,
                .loc = self.ls,
                .base = self.base,
            };

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

                try self.parse_args(&inst);
            }

            try code.append(inst);
        }

        return R.ok(try code.toOwnedSlice());
    }

    fn second_pass(self: *Self, ast: []Inst) !void {
        self.ls = 0;

        for (ast) |*inst| {
            switch (inst.kind) {
                .Start => {
                    if (inst.arg1) |n| {
                        self.ls = n.num;
                    }
                },
                .End => {
                    if (inst.arg1.? == .sym) {
                        inst.res_arg1 = try self.get_sym_from_symtab(inst.arg1.?.sym);
                    }
                },
                .Byte,
                => {
                    if (inst.arg1.? == .sym) {
                        inst.res_arg1 = try self.get_sym_from_symtab(inst.arg1.?.sym);
                    }

                    self.ls += 1;
                },
                .Word,
                => {
                    if (inst.arg1.? == .sym) {
                        inst.res_arg1 = try self.get_sym_from_symtab(inst.arg1.?.sym);
                    }

                    self.ls += 3;
                },
                .Equ => {
                    if (inst.arg1.? == .sym) {
                        inst.res_arg1 = try self.get_sym_from_symtab(inst.arg1.?.sym);
                    }

                    const e = self.sym_tab.getEntry(inst.label.?).?;
                    e.value_ptr.*.? = inst.arg1.?.num;
                },
                .Org => {
                    if (inst.arg1.? == .sym) {
                        inst.res_arg1 = try self.get_sym_from_symtab(inst.arg1.?.sym);
                    }

                    self.ls = inst.arg1.?.num;
                },
                .Base,
                .NoBase,
                => {},
                .Resb => {
                    self.ls += inst.arg1.?.num;
                },
                .Resw => {
                    self.ls += inst.arg1.?.num * 3;
                },
                .Normal,
                => {
                    if (inst.label) |l| {
                        const e = self.sym_tab.getEntry(l).?;
                        e.value_ptr.* = self.ls;
                    }
                    inst.loc = self.ls;

                    const i_len = ISet.opTable.get(inst.opcode).?;
                    self.ls += i_len;

                    if (inst.arg1 != null and inst.arg1.? == .sym) {
                        var e = try self.get_sym_from_symtab(inst.arg1.?.sym);
                        if (inst.addr_mode == .Normal and !inst.sic and !inst.base) {
                            e.num = @bitCast(@as(i24, @bitCast(e.num)) - @as(i24, @bitCast(@as(u24, @truncate(self.ls)))));
                        }
                        inst.res_arg1 = e;
                    }
                },
            }
        }
    }

    fn get_sym_from_symtab(self: *const Self, sym: []const u8) !Expr {
        return Expr{ .num = @truncate((self.sym_tab.get(sym) orelse return error.SymbolMissingError) orelse return error.SymbolMissingError) };
    }

    fn is_reserved(self: *const Self, str: []const u8) bool {
        return self.reserved.has(str);
    }

    fn advance(self: *Self) bool {
        self.cur_idx +%= 1;
        if (self.cur_idx >= self.lines.lines.len) return false;
        self.cur_line = self.lines.lines[self.cur_idx];
        return true;
    }

    fn ex_get_num_from_args(line: *const Lexer.Line, idx: usize) !?Expr {
        if (line.args != null and line.args.?.len > idx) {
            if (line.args.?[idx].type != .Num) return null;
            return Expr{
                .num = try std.fmt.parseInt(u24, line.args.?[idx].lexeme, 0),
            };
        }
        return null;
    }

    fn ex_get_sym_from_args(line: *const Lexer.Line, idx: usize) ?Expr {
        if (line.args != null and line.args.?.len > idx) {
            if (line.args.?[idx].type != .Id) return null;
            return Expr{
                .sym = line.args.?[idx].lexeme,
            };
        }
        return null;
    }

    fn ex_get_sym_from_label(line: *const Lexer.Line) ?Expr {
        if (line.label) |l| {
            if (l.type != .Id) return null;
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
            else => {
                inst.addr_mode = .Normal;
            },
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
                    try self.new_sym(args[i.*].lexeme, inst);
                }

                i.* += 1;
            },
            .Num => {
                inst.arg1 = try ex_get_num_from_args(&self.cur_line, i.*);
                i.* += 1;
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

        // if (args.len == 0) {
        //     inst.addr_mode = .None;
        // }

        try self.parse_first_arg(args, inst, &i);

        if (args.len > i) {
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

    fn new_sym(self: *Self, sym: []const u8, inst: *Inst) !void {
        const e = try self.sym_tab.getOrPut(sym);

        if (e.found_existing and e.value_ptr.* != null) {
            inst.arg1 = Expr{ .sym = sym };
            inst.res_arg1 = Expr{ .num = @truncate(e.value_ptr.*.?) };
        } else {
            inst.arg1 = Expr{ .sym = sym };
            e.value_ptr.* = null;
        }
    }

    fn parse_end(self: *Self, inst: *Inst) anyerror!void {
        if (self.parsed_end) {
            return error.EndDirectiveDuplicateError;
        }

        self.parsed_end = true;

        const args = self.cur_line.args orelse return error.EndExpectsAnArgument;
        if (args.len == 0) return error.EndExpectsAnArgument;

        inst.kind = .End;

        var num = try ex_get_num_from_args(&self.cur_line, 0);

        if (num == null) {
            num = ex_get_sym_from_args(&self.cur_line, 0);
        }

        if (num == null) {
            return error.EndDidNotGetNumOrIdError;
        }

        if (num.? == .sym) {
            try self.new_sym(num.?.sym, inst);
        } else {
            inst.arg1 = num;
        }
    }

    fn parse_equ(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.EquExpectsAnArgument;
        if (args.len == 0) return error.EquExpectsAnArgument;

        inst.kind = .Equ;

        var num = try ex_get_num_from_args(&self.cur_line, 0);

        if (num == null) {
            num = ex_get_sym_from_args(&self.cur_line, 0);
        }

        if (num == null) {
            return error.EquDidNotGetNumOrIdError;
        }

        if (num.? == .sym) {
            try self.new_sym(num.?.sym, inst);
        } else {
            inst.arg1 = num;
        }

        const e = self.sym_tab.getEntry(inst.label.?).?;
        if (inst.arg1.? == .num) {
            e.value_ptr.* = inst.arg1.?.num;
        } else {
            e.value_ptr.* = null;
        }
    }

    fn parse_org(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.OrgExpectsAnArgument;
        if (args.len == 0) return error.OrgExpectsAnArgument;

        const num = try ex_get_num_from_args(&self.cur_line, 0) orelse return error.OrgExpectsANumberArgument;

        self.ls = num.num;
        inst.kind = .Org;
        inst.arg1 = num;
    }

    fn parse_base(self: *Self, inst: *Inst) anyerror!void {
        // TODO: fix, base has one argument
        inst.kind = .Base;
        self.base = true;
    }

    fn parse_nobase(self: *Self, inst: *Inst) anyerror!void {
        inst.kind = .NoBase;
        self.base = false;
    }

    fn parse_byte(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.ByteExpectsAnArgument;
        if (args.len == 0) return error.ByteExpectsAnArgument;

        inst.kind = .Byte;

        var num = try ex_get_num_from_args(&self.cur_line, 0);

        if (num == null) {
            num = ex_get_sym_from_args(&self.cur_line, 0);
        }

        if (num == null) {
            return error.ByteDidNotGetNumOrIdError;
        }

        if (num.? == .sym) {
            try self.new_sym(num.?.sym, inst);
        } else {
            inst.arg1 = num;
        }

        self.ls += 1;
    }

    fn parse_word(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.WordExpectsAnArgument;
        if (args.len == 0) return error.WordExpectsAnArgument;

        inst.kind = .Word;

        var num = try ex_get_num_from_args(&self.cur_line, 0);

        if (num == null) {
            num = ex_get_sym_from_args(&self.cur_line, 0);
        }

        if (num == null) {
            return error.WordDidNotGetNumOrIdError;
        }

        if (num.? == .sym) {
            try self.new_sym(num.?.sym, inst);
        } else {
            inst.arg1 = num;
        }

        self.ls += 3;
    }

    fn parse_resb(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.ResbExpectsAnArgument;
        if (args.len == 0) return error.ResbExpectsAnArgument;

        inst.kind = .Resb;

        const num = try ex_get_num_from_args(&self.cur_line, 0);

        if (num == null) {
            return error.ResbDidNotGetNumError;
        }

        inst.arg1 = num;
        self.ls += num.?.num;
    }

    fn parse_resw(self: *Self, inst: *Inst) anyerror!void {
        const args = self.cur_line.args orelse return error.ReswExpectsAnArgument;
        if (args.len == 0) return error.ReswExpectsAnArgument;

        inst.kind = .Resw;

        const num = try ex_get_num_from_args(&self.cur_line, 0);

        if (num == null) {
            return error.ReswDidNotGetNumError;
        }

        inst.arg1 = num;
        self.ls += num.?.num * 3;
    }
};
