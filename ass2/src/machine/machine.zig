const std = @import("std");
const Allocator = std.mem.Allocator;

const hl = @import("helper");
const dev = @import("device.zig");
const Device = dev.Device;
const Devices = dev.Devices;
const Is = @import("instruction_set");
const Opcode = Is.Opcode;
const Fmt = Is.Fmt;
const obj = @import("obj_reader.zig");
const undo = @import("undo.zig");
const Breakpoints = @import("../runner/runner.zig").Breakpoints;

pub const RegIdx = enum(u4) {
    A = 0x0,
    X = 0x1,
    L = 0x2,
    B = 0x3,
    S = 0x4,
    T = 0x5,
    F = 0x6,
    PC = 0x8,
    SW = 0x9,

    const Self = @This();

    pub fn asInt(self: Self) u4 {
        return @intFromEnum(self);
    }
};

pub const Ord = enum(u2) {
    Less = 0b00,
    Equal = 0b01,
    Greater = 0b10,
};

const Regs = struct {
    gpr: GPR = .{},
    F: f64 = 0.0,
    PC: u24 = 0, // program counter
    SW: SR = .{ .i = 0 }, // status register

    const GPR = struct { // General Purpose Registers
        A: u24 = 0,
        X: u24 = 0,
        L: u24 = 0,
        B: u24 = 0,
        S: u24 = 0,
        T: u24 = 0,

        pub fn asArray(self: *GPR) [*]u24 {
            return @ptrCast(self);
        }

        pub fn asConstArray(self: *const GPR) [*]const u24 {
            return @ptrCast(self);
        }
    };

    const SR = packed union {
        i: u24,
        s: packed struct(u24) {
            mode: u1,
            idle: u1,
            id: u4,
            cc: Ord,
            mask: u4,
            _unused: u4,
            icode: u8,
        },
    };

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Set register
    pub fn set(self: *Self, ri: RegIdx, val: anytype) void {
        // TODO: don't panic -> log error instead?
        if (@TypeOf(val) == f64) {
            if (ri != RegIdx.F) std.debug.panic("Register {} cannot be set with a floating point number.", .{ri});
            self.F = val;
        } else if (@TypeOf(val) == u8) {
            if (ri != RegIdx.A) std.debug.panic("Register {} cannot be set with an 8-bit number.", .{ri});
            self.gpr.rt.A &= ~@as(u24, 0xFF);
            self.gpr.rt.A |= val;
        } else {
            switch (ri) {
                .F => @panic("Register F cannot be set with a word."),
                .SW => self.SW.i = val,
                .PC => self.PC = val,
                else => self.gpr.asArray()[ri.asInt()] = val,
            }
        }
    }

    /// Get register
    pub fn get(self: *const Self, ri: RegIdx, comptime T: type) T {
        if (T == f64) {
            if (ri != RegIdx.F) std.debug.panic("Cannot read register {} as a floating point number.", .{ri});
            return self.F;
        } else if (T == u8) {
            if (ri != RegIdx.A) std.debug.panic("Cannot read register {} as an 8-bit number.", .{ri});
            return @intCast(self.gpr.rt.A & 0xFF);
        } else {
            return switch (ri) {
                .F => @panic("Cannot read register F as a word."),
                .SW => self.SW.i,
                .PC => self.PC,
                else => self.gpr.asConstArray()[ri.asInt()],
            };
        }
    }
};

/// Does not own buf
const Mem = struct {
    buf: [*]u8,

    pub const MAX_ADDR = 1 << 20; // 1MB

    const Self = @This();

    pub fn get(self: *const Self, addr: u24, comptime T: type) ?T {
        if (addr > MAX_ADDR) {
            std.log.err("Invalid address {d}", .{addr});
            return null;
        }

        const size = hl.sizeOf(T);
        var ret = std.mem.bytesToValue(T, self.buf[addr .. addr + size]);

        if (@typeInfo(T) == .Int) {
            ret = std.mem.bigToNative(T, ret);
        }

        return ret;
    }

    pub fn peek(self: *const Self, addr: u24, comptime T: type) ?*T {
        if (addr > MAX_ADDR) {
            std.log.err("Invalid address {d}", .{addr});
            return null;
        }

        const size = hl.sizeOf(T);
        // TODO: check address
        const ret = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]);

        if (@typeInfo(T) == .Int) {
            ret.* = std.mem.bigToNative(T, ret.*);
        }

        return ret;
    }

    pub fn setSlice(self: *Self, addr: u24, slice: []const u8) void {
        if (addr > MAX_ADDR) {
            std.log.err("Invalid address {d}", .{addr});
            return;
        }

        @memcpy(self.buf[addr .. addr + slice.len], slice);
    }

    pub fn set(self: *Self, addr: u24, val: anytype) void {
        if (addr > MAX_ADDR) {
            std.log.err("Invalid address {d}", .{addr});
            return;
        }

        const T: type = @TypeOf(val);
        const size = hl.sizeOf(T);

        // std.debug.print("addr = {X}\n", .{addr});

        var v = val;

        if (@typeInfo(T) == .Int) {
            v = std.mem.nativeToBig(T, v);
        }

        const ptr = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]);
        ptr.* = v;
    }

    pub fn getE(self: *const Self, addr: u24, comptime T: type, comptime enidan: std.builtin.Endian) ?T {
        if (addr > MAX_ADDR) {
            std.log.err("Invalid address {d}", .{addr});
            return;
        }

        const size = hl.sizeOf(T);
        // TODO: check address
        var ret = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]).*;

        if (@typeInfo(T) == .Int) {
            ret = std.mem.bigToNative(T, ret);
            ret = std.mem.nativeTo(T, ret, enidan);
        }

        return ret;
    }

    pub fn setE(self: *Self, addr: u24, val: anytype, comptime enidan: std.builtin.Endian) void {
        if (addr > MAX_ADDR) {
            std.log.err("Invalid address {d}", .{addr});
            return;
        }

        const T: type = @TypeOf(val);
        const size = hl.sizeOf(T);

        // std.debug.print("addr = {X}\n", .{addr});

        var v = val;

        if (@typeInfo(T) == .Int) {
            // v = std.mem.nativeToBig(T, v);
            v = std.mem.nativeTo(T, v, enidan);
        }

        const ptr = std.mem.bytesAsValue(T, self.buf[addr .. addr + size]);
        ptr.* = v;
    }

    pub fn setF(self: *Self, addr: u24, val: f64) void {
        if (addr > MAX_ADDR) {
            std.log.err("Invalid address {d}", .{addr});
            return;
        }

        const v: u48 = @truncate(@as(u64, @bitCast(val)) >> (@bitSizeOf(u64) - @bitSizeOf(u48)));
        self.set(addr, v);
    }

    pub fn getF(self: *const Self, addr: u24) ?f64 {
        if (addr > MAX_ADDR) {
            std.log.err("Invalid address {d}", .{addr});
            return null;
        }
        return @bitCast(@as(u64, self.get(addr, u48) orelse return null) << (@bitSizeOf(u64) - @bitSizeOf(u48)));
    }

    fn writeChars(self: *const Self, w: std.io.AnyWriter, addr: u24, size: u24) !void {
        try w.writeByte('|');
        for (0..size) |j| {
            const byte = self.buf[addr + j];
            if (byte < 32 or byte >= 127) {
                try w.writeByte('.');
            } else {
                try w.writeByte(self.buf[addr + j]);
            }
        }
        try w.writeByte('|');
    }

    pub fn print(self: *const Self, w: std.io.AnyWriter, addr: u24, size: u24, includeChr: bool) !void {
        var i: u24 = 0;

        try w.print("{X:0>6}", .{addr});
        while ((i < size) and (addr + i) < MAX_ADDR) {
            defer i += 1;

            try w.print(" {X:0>2}", .{self.buf[addr + i]});
            const last_in_line = (((i + 1) % 16) == 0);

            if (last_in_line and (i < (size - 1))) {
                if (includeChr) {
                    try w.writeByte(' ');
                    try self.writeChars(w, addr + (i -| 16), 16);
                }

                try w.print("\n{X:0>6}", .{addr + i + 1});
            }
        }

        if (includeChr) {
            try w.writeByte(' ');
            if ((i % 16) != 0) {
                try self.writeChars(w, addr + (i -| (i % 16)), (i % 16));
            } else {
                try self.writeChars(w, addr + (i -| 16), 16);
            }
        }

        try w.writeByte('\n');
    }
};

pub const Machine = struct {
    regs: Regs = .{},
    mem: Mem,
    devs: *OSDevices,
    clock_speed: u64 = 1, // [kHz]
    stopped: bool = true,
    code: ?obj.Code = null,
    undo_buf: *undo.UndoBuf,
    use_undo: bool = true,
    alloc: Allocator,
    in_dbg_mode: bool = false,
    bps: *Breakpoints,

    pub const OSDevices = Devices(256);

    pub const AddrMode = enum(u2) {
        None = 0b00,
        Immediate = 0b01,
        Normal = 0b10,
        Indirect = 0b11,
    };

    const Self = @This();

    pub fn init(buf: [*]u8, devs: *OSDevices, undo_buf: *undo.UndoBuf, bps: *Breakpoints, alloc: Allocator) Self {
        return .{
            .mem = .{ .buf = buf },
            .devs = devs,
            .undo_buf = undo_buf,
            .alloc = alloc,
            .bps = bps,
        };
    }

    var instruction_str_buf = [_]u8{0} ** 70;
    pub fn instrStr(self: *const Self, addr: u24, i_sz: ?*usize) ?[]const u8 {
        const bytes = self.mem.get(addr, [4]u8) orelse return null;
        var opcode_ni = bytes[0];
        var opcode: Opcode = std.meta.intToEnum(Opcode, (opcode_ni >> 2) << 2) catch return null;

        if (opcode == .INT) {
            if (self.bps.get(addr)) |i| {
                opcode_ni = i;
                opcode = std.meta.intToEnum(Opcode, (opcode_ni >> 2) << 2) catch return null;
            }
        }

        const xbpe_addr = bytes[1];
        const x = (xbpe_addr & 0x80) >> 7;
        const b = (xbpe_addr & 0x40) >> 6;
        const p = (xbpe_addr & 0x20) >> 5;
        const e = (xbpe_addr & 0x10) >> 4;

        var sic = false;
        const am = addressMode(opcode_ni, &sic);

        var ins_sz = Is.opTable.get(opcode) orelse return null;
        if (ins_sz > 2 and (e == 1)) {
            ins_sz += 1;
        }

        if (i_sz) |sz| {
            sz.* = ins_sz;
        }

        var buf = std.fmt.bufPrint(&instruction_str_buf, "{X:0>6}  {X:0>2} {X:0>2} ", .{ addr, opcode_ni, xbpe_addr }) catch return null;

        @memset(instruction_str_buf[buf.len .. buf.len + 5], ' ');
        if (ins_sz == 3) {
            const bb = std.fmt.bufPrint(instruction_str_buf[buf.len..], "{X:0>2}    ", .{bytes[2]}) catch return null;
            buf.len += bb.len;
        } else if (ins_sz == 4) {
            const bb = std.fmt.bufPrint(instruction_str_buf[buf.len..], "{X:0>2} {X:0>2} ", .{ bytes[2], bytes[3] }) catch return null;
            buf.len += bb.len;
        } else {
            buf.len += 5;
        }

        var bb = std.fmt.bufPrint(instruction_str_buf[buf.len..], " {s}{s:<5}    ", .{
            if (e > 0) "+" else " ",
            @tagName(opcode),
        }) catch return null;
        buf.len += bb.len;

        if (ins_sz == 1) {} else if (ins_sz == 2) {
            bb = std.fmt.bufPrint(instruction_str_buf[buf.len..], "{s}, {s}", .{
                @tagName(reg1(bytes[2])),
                @tagName(reg2(bytes[2])),
            }) catch return null;
            buf.len += bb.len;
        } else if (sic) {
            const addr_ = (@as(u15, bytes[1]) << 8) | bytes[2];
            bb = std.fmt.bufPrint(instruction_str_buf[buf.len..], "{d}{s}", .{
                addr_,
                if (x > 0) " + X" else "",
            }) catch return null;
            buf.len += bb.len;
        } else if (ins_sz == 3) {
            const addr_: i12 = @bitCast((@as(u12, xbpe_addr & 0xF) << 8) | bytes[2]);
            addrStr(addr_, &buf, x, b, p, am) orelse return null;
        } else if (ins_sz == 4) {
            const addr_: i20 = @bitCast(((@as(u20, xbpe_addr & 0xF) << 16) | (@as(u20, bytes[2]) << 8)) | bytes[3]);
            addrStr(addr_, &buf, x, b, p, am) orelse return null;
        }

        return buf;
    }

    fn addrStr(addr: anytype, buf: *[]u8, x: u8, b: u8, p: u8, am: AddrMode) ?void {
        switch (am) {
            .Immediate => {
                const bb = std.fmt.bufPrint(instruction_str_buf[buf.len..], "#{d}{s}{s}", .{
                    addr,
                    if (p > 0) " + PC" else "",
                    if (b > 0) " + B" else "",
                }) catch return null;
                buf.len += bb.len;
            },
            .Normal => {
                const bb = std.fmt.bufPrint(instruction_str_buf[buf.len..], "{d}{s}{s}{s}", .{
                    addr,
                    if (x > 0) " + X" else "",
                    if (p > 0) " + PC" else "",
                    if (b > 0) " + B" else "",
                }) catch return null;
                buf.len += bb.len;
            },
            .Indirect => {
                const bb = std.fmt.bufPrint(instruction_str_buf[buf.len..], "@[{d}{s}{s}]", .{
                    addr,
                    if (p > 0) " + PC" else "",
                    if (b > 0) " + B" else "",
                }) catch return null;
                buf.len += bb.len;
            },
            else => return null,
        }
    }

    fn addressMode(byte: u8, sic: *bool) AddrMode {
        var address_mode = AddrMode.Normal;
        const n = (byte & 0b10) > 0;
        const i = (byte & 0b01) > 0;

        if (!n and i) {
            address_mode = .Immediate;
        } else if (n and !i) {
            address_mode = .Indirect;
        }

        sic.* = !n and !i;

        return address_mode;
    }

    pub fn reload(self: *Self) void {
        if (self.code) |code| {
            self.load_code(code) catch unreachable;
        }
    }

    fn load_code(self: *Self, code: obj.Code) !void {
        const start_ = code.header.addr;
        for (code.records) |r| {
            switch (r) {
                .T => |t| {
                    self.mem.setSlice(t.addr, t.code);
                },
                .M => |m| {
                    const addr = m.addr + code.start_addr;
                    const nibble_len = m.len;
                    const byte_len = (nibble_len + 1) / 2;
                    const slice = &self.mem.buf[addr .. addr + byte_len];
                    hl.add_to_bytes(slice.*, start_, nibble_len);
                },
                else => return error.UnsupportedRecord,
            }
        }

        self.regs.PC = code.start_addr;
    }

    pub fn load(self: *Self, path: []const u8, comptime is_str: bool) !void {
        if (self.code) |c| {
            c.deinit(self.alloc);
        }

        const r_code = try if (is_str) blk: {
            break :blk obj.from_str(path, self.alloc);
        } else blk: {
            const cur_dir = std.fs.cwd();
            const f = cur_dir.openFile(path, .{ .mode = .read_only }) catch |err| {
                std.log.err("Cannot open file because: {}", .{err});
                return;
            };
            defer f.close();

            break :blk obj.from_reader(f.reader().any(), self.alloc);
        };

        if (r_code.is_err()) {
            _ = try r_code.try_unwrap();
        }

        const code = r_code.unwrap();
        errdefer code.deinit(self.alloc);

        self.code = code;

        try self.load_code(code);
    }

    pub fn setSpeed(self: *Self, speed_kHz: u64) void {
        self.clock_speed = speed_kHz;
        if (speed_kHz == 0) {
            self.clock_speed = 1;
        }
    }

    inline fn sleep_time(self: *const Self) u64 {
        return std.time.us_per_s / self.clock_speed;
    }

    pub fn start(self: *Self) void {
        self.stopped = false;
        while (!self.stopped) {
            const t_start = std.time.microTimestamp();
            self.step() catch {
                self.stopped = true;
            };
            const elapsed = std.time.microTimestamp() - t_start;
            const t = (self.sleep_time() -| @as(u64, @intCast(elapsed)));
            std.time.sleep(t);
        }
    }

    pub fn stop(self: *Self) void {
        self.stopped = true;
    }

    pub fn nStep(self: *Self, n: u32) void {
        var nn = n;
        self.stopped = true;
        while (!self.stopped and nn > 0) {
            self.step() catch {
                self.stopped = true;
            };

            if (self.in_dbg_mode) {
                self.step() catch {
                    self.stopped = true;
                };
            }

            nn -= 1;
        }
    }

    fn saveReg(self: *const Self, reg: RegIdx) !void {
        if (!self.use_undo) return;
        const states = self.undo_buf.last() orelse return;

        if (reg == .F) {
            try states.append(self.alloc, .{ .RegState = .{ .ri = reg, .val = .{ .f = self.regs.get(reg, f64) } } });
        } else {
            try states.append(self.alloc, .{ .RegState = .{ .ri = reg, .val = .{ .i = self.regs.get(reg, u24) } } });
        }
    }

    fn saveMem(self: *Self, addr: u24, val: type) !void {
        if (!self.use_undo) return;

        const states = self.undo_buf.last() orelse return;

        if (val == u8) {
            try states.append(self.alloc, .{ .MemByteState = .{ .addr = addr, .val = self.mem.get(addr, val) orelse return } });
        } else if (val == u24) {
            try states.append(self.alloc, .{ .MemWordState = .{ .addr = addr, .val = self.mem.get(addr, val) orelse return } });
        } else if (val == f64) {
            try states.append(self.alloc, .{ .MemFState = .{ .addr = addr, .val = self.mem.get(addr, val) orelse return } });
        } else {
            @compileError("Cannot save any other type rather than u8, u24, f64");
        }
    }

    pub fn undoN(self: *Self, count: usize) void {
        if (!self.use_undo) return;

        var i = count;
        while ((self.undo_buf.len > 0) and (i > 0)) {
            defer i -= 1;

            var states = self.undo_buf.popBack().?;
            defer states.deinit(self.alloc);

            for (states.items) |state| {
                switch (state) {
                    .MemByteState => |m| {
                        self.mem.set(m.addr, m.val);
                    },
                    .MemWordState => |m| {
                        self.mem.set(m.addr, m.val);
                    },
                    .MemFState => |m| {
                        self.mem.set(m.addr, m.val);
                    },
                    .RegState => |r| {
                        if (r.ri == .F) {
                            self.regs.set(r.ri, r.val.f);
                        } else {
                            self.regs.set(r.ri, r.val.i);
                        }
                    },
                }
            }
        }
    }

    pub fn step(self: *Self) !void {
        if (self.regs.PC > Mem.MAX_ADDR) {
            std.log.err("Invalid address {d}", .{self.regs.PC});
            return;
        }

        const dbg_addr: u24 = self.regs.PC;
        if (self.in_dbg_mode) {
            if (self.bps.get(self.regs.PC)) |a| {
                self.mem.set(self.regs.PC, a);
            } else {
                std.log.err("Invalid debug mode (breakpoint)", .{});
                self.stop();
                return;
            }
        }

        errdefer {
            if (self.in_dbg_mode) {
                self.mem.set(dbg_addr, Opcode.INT.int());
                self.in_dbg_mode = false;
            }
        }

        if (self.use_undo) {
            var states = try std.ArrayListUnmanaged(undo.State).initCapacity(self.alloc, 2);
            errdefer states.deinit(self.alloc);

            self.undo_buf.add(states, self.alloc);
            errdefer {
                var a = self.undo_buf.popBack().?;
                a.deinit(self.alloc);
            }

            try self.saveReg(.PC);
        }

        const opcode_ni = self.fetch();
        const opcode: Opcode = std.meta.intToEnum(Opcode, (opcode_ni >> 2) << 2) catch {
            self.stop();
            return;
        };

        var sic = false;
        const address_mode = addressMode(opcode_ni, &sic);

        var ins_sz = Is.opTable.get(opcode) orelse 0;
        if (ins_sz > 2) {
            const e = ((self.mem.get(self.regs.PC, u8).? >> 4) & 1);
            if (e == 1) ins_sz += 1;
        }

        const operand = switch (opcode) {
            .STA, .STX, .STL, .JSUB, .STCH, .STB, .STS, .STT, .STSW, .J, .JEQ, .JGT, .JLT => self.getAddr(u24, sic, true, address_mode) orelse return error.InvalidAddress,
            .LDCH, .ADDF, .SUBF, .MULF, .DIVF, .COMPF, .RD, .WD, .TD => 0,
            else => if (ins_sz > 2) self.getAddr(u24, sic, false, address_mode) orelse return error.InvalidAddress else 0,
        };

        const regs = if (ins_sz == 2) self.fetch() else 0;

        switch (opcode) {
            // load and store
            .LDA => {
                try self.saveReg(.A);
                self.regs.gpr.A = operand;
            },
            .LDX => {
                try self.saveReg(.X);
                self.regs.gpr.X = operand;
            },
            .LDL => {
                try self.saveReg(.L);
                self.regs.gpr.L = operand;
            },
            .STA => if (address_mode != .Immediate) {
                try self.saveMem(operand, u24);
                self.mem.set(
                    operand,
                    self.regs.gpr.A,
                );
            },
            .STX => if (address_mode != .Immediate) {
                try self.saveMem(operand, u24);
                self.mem.set(
                    operand,
                    self.regs.gpr.X,
                );
            },
            .STL => if (address_mode != .Immediate) {
                try self.saveMem(operand, u24);
                self.mem.set(
                    operand,
                    self.regs.gpr.L,
                );
            },
            // fixed point arithmetic
            .ADD => {
                try self.saveReg(.A);
                self.regs.gpr.A +%= operand;
            },
            .SUB => {
                try self.saveReg(.A);
                self.regs.gpr.A -%= operand;
            },
            .MUL => {
                try self.saveReg(.A);
                self.regs.gpr.A *%= operand;
            },
            .DIV => {
                try self.saveReg(.A);
                self.regs.gpr.A /= operand;
            },
            .COMP => {
                try self.saveReg(.SW);
                self.regs.SW.s.cc = comp(self.regs.gpr.A, operand);
            },
            .TIX => {
                try self.saveReg(.X);
                try self.saveReg(.SW);
                self.regs.gpr.X +%= 1;
                self.regs.SW.s.cc = comp(self.regs.gpr.X, operand);
            },
            // jumps
            .JEQ => if (self.regs.SW.s.cc == .Equal) {
                self.regs.PC = operand;
            },
            .JGT => if (self.regs.SW.s.cc == .Greater) {
                self.regs.PC = operand;
            },
            .JLT => if (self.regs.SW.s.cc == .Less) {
                self.regs.PC = operand;
            },
            .J => {
                if (self.regs.PC == (operand + ins_sz)) self.stop();
                self.regs.PC = operand;
            },
            // bit manipulation
            .AND => {
                try self.saveReg(.A);
                self.regs.gpr.A &= operand;
            },
            .OR => {
                try self.saveReg(.A);
                self.regs.gpr.A |= operand;
            },
            // jump to subroutine
            .JSUB => {
                try self.saveReg(.L);
                self.regs.gpr.L = self.regs.PC;
                self.regs.PC = operand;
            },
            .RSUB => {
                self.regs.PC = self.regs.gpr.L;
            },
            // load and store byte
            .LDCH => {
                try self.saveReg(.A);
                const a = self.regs.gpr.A & ~@as(u24, 0xFF);
                self.regs.gpr.A = a | (self.getAddr(u8, sic, false, address_mode) orelse return error.InvalidAddress);
            },
            .STCH => if (address_mode != .Immediate) {
                try self.saveMem(operand, u8);
                self.mem.set(
                    operand,
                    @as(u8, @truncate(self.regs.gpr.A & 0xFF)),
                );
            },
            // floating point arithmetic
            .ADDF => {
                try self.saveReg(.F);
                self.regs.F += self.getAddr(f64, sic, false, address_mode) orelse return error.InvalidAddress;
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .SUBF => {
                try self.saveReg(.F);
                self.regs.F -= self.getAddr(f64, sic, false, address_mode) orelse return error.InvalidAddress;
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .MULF => {
                try self.saveReg(.F);
                self.regs.F *= self.getAddr(f64, sic, false, address_mode) orelse return error.InvalidAddress;
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .DIVF => {
                try self.saveReg(.F);
                self.regs.F /= self.getAddr(f64, sic, false, address_mode) orelse return error.InvalidAddress;
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .COMPF => {
                try self.saveReg(.F);
                try self.saveReg(.SW);
                const f = self.getAddr(f64, sic, false, address_mode) orelse return error.InvalidAddress;
                self.regs.SW.s.cc = comp(self.regs.F, f);
            },

            // load and store
            .LDB => {
                try self.saveReg(.B);
                self.regs.gpr.B = operand;
            },
            .LDS => {
                try self.saveReg(.S);
                self.regs.gpr.S = operand;
            },
            .LDF => {
                try self.saveReg(.F);
                self.regs.F = self.getAddr(f64, sic, false, address_mode) orelse return error.InvalidAddress;
            },
            .LDT => {
                try self.saveReg(.T);
                self.regs.gpr.T = operand;
            },
            .STB => if (address_mode != .Immediate) {
                try self.saveMem(operand, u24);
                self.mem.set(
                    operand,
                    self.regs.gpr.B,
                );
            },
            .STS => if (address_mode != .Immediate) {
                try self.saveMem(operand, u24);
                self.mem.set(
                    operand,
                    self.regs.gpr.S,
                );
            },
            .STF => {
                try self.saveMem(operand, f64);
                self.mem.setF(operand, self.regs.F);
            },
            .STT => if (address_mode != .Immediate) {
                try self.saveMem(operand, u24);
                self.mem.set(
                    operand,
                    self.regs.gpr.T,
                );
            },
            // special load and store
            // .LPS => {},
            // .STI => {},
            .STSW => if (address_mode != .Immediate) {
                try self.saveMem(operand, u24);
                self.mem.set(
                    operand,
                    self.regs.SW,
                );
            },
            // devices
            .RD => {
                try self.saveReg(.A);
                const dev_ = self.getAddr(u8, sic, false, address_mode) orelse return error.InvalidAddress;
                const r = self.devs.getDevice(dev_).read();
                if (r) |rr| {
                    self.regs.gpr.A = rr;
                } else {
                    self.stop();
                    self.regs.gpr.A = 0;
                }
            },
            .WD => {
                const dev_ = self.getAddr(u8, sic, false, address_mode) orelse return error.InvalidAddress;
                self.devs.getDevice(dev_).write(@truncate(self.regs.gpr.A & 0xFF));
            },
            .TD => {
                try self.saveReg(.SW);
                const dev_ = self.getAddr(u8, sic, false, address_mode) orelse return error.InvalidAddress;
                const t = self.devs.getDevice(dev_).@"test"();
                if (!t) {
                    self.regs.SW.s.cc = .Greater;
                } else {
                    self.regs.SW.s.cc = .Equal; // ???
                }
            },
            // system
            // .SSK => {},

            // ***** SIC/XE Format 1 *****
            .FLOAT => {
                try self.saveReg(.F);
                self.regs.F = @floatFromInt(self.regs.gpr.A);
                self.regs.F = hl.chopFloat(self.regs.F);
            },
            .FIX => {
                try self.saveReg(.A);
                self.regs.gpr.A = @intFromFloat(self.regs.F);
            },
            // .NORM => {}, ???

            // ***** SIC/XE Format 2 *****
            .ADDR => {
                try self.saveReg(reg2(regs));
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.set(reg2(regs), r2 +% r1);
            },
            .SUBR => {
                try self.saveReg(reg2(regs));
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.set(reg2(regs), r2 -% r1);
            },
            .MULR => {
                try self.saveReg(reg2(regs));
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.set(reg2(regs), r2 *% r1);
            },
            .DIVR => {
                try self.saveReg(reg2(regs));
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.set(reg2(regs), r2 / r1);
            },
            .COMPR => {
                try self.saveReg(.SW);
                const r1 = self.regs.get(reg1(regs), u24);
                const r2 = self.regs.get(reg2(regs), u24);
                self.regs.SW.s.cc = comp(r1, r2);
            },
            .SHIFTL => {
                try self.saveReg(reg2(regs));
                const r1 = self.regs.get(reg1(regs), u24);
                self.regs.set(reg2(regs), r1 << @truncate(regs & 0xF));
            },
            .SHIFTR => {
                try self.saveReg(reg2(regs));
                const r1 = self.regs.get(reg1(regs), u24);
                self.regs.set(reg2(regs), r1 >> @truncate(regs & 0xF));
            },
            .RMO => {
                try self.saveReg(reg2(regs));
                const r1 = self.regs.get(reg1(regs), u24);
                self.regs.set(reg2(regs), r1);
            },
            // .SVC => {},
            .CLEAR => {
                try self.saveReg(reg1(regs));
                self.regs.set(reg1(regs), @as(u24, 0));
            },
            .TIXR => {
                try self.saveReg(.X);
                try self.saveReg(.SW);
                self.regs.gpr.X +%= 1;
                const r1 = self.regs.get(reg1(regs), u24);
                self.regs.SW.s.cc = comp(self.regs.gpr.X, r1);
            },

            // .HIO => {},
            // .SIO => {},
            // .TIO => {},
            .INT => {
                self.stop();
                self.in_dbg_mode = true;
                self.regs.PC -= ins_sz;
                if (self.undo_buf.popBack()) |e| {
                    var ee = e;
                    ee.deinit(self.alloc);
                } // remove last undo entry
                return;
            },

            else => std.log.warn("unhandeled instruction", .{}),
        }

        if (self.in_dbg_mode) {
            self.mem.set(dbg_addr, Opcode.INT.int());
            self.in_dbg_mode = false;
        }
    }

    inline fn mv_back(self: *Self, n: u24) void {
        self.regs.PC -%= n;
    }

    inline fn reg1(r: u8) RegIdx {
        return @enumFromInt(r >> 4);
    }

    inline fn reg2(r: u8) RegIdx {
        return @enumFromInt(r & 0xF);
    }

    fn comp(v1: anytype, v2: @TypeOf(v1)) Ord {
        if (v1 < v2) {
            return .Less;
        } else if (v1 > v2) {
            return .Greater;
        } else {
            return .Equal;
        }
    }

    fn get(self: *Self, comptime T: type, addr: u24, addr_mode: AddrMode, comptime addr_size: usize) ?T {
        if (T == f64) {
            const shift = @bitSizeOf(u48) - (@bitSizeOf(u24) - addr_size);

            return switch (addr_mode) {
                .Immediate => @bitCast(@as(u64, addr) << shift), // ????????
                .Normal => self.mem.getF(addr),
                .Indirect => self.mem.getF(self.mem.get(addr, u24) orelse return null),
                .None => unreachable,
            };
        }
        return switch (addr_mode) {
            .Immediate => @truncate(addr),
            .Normal => self.mem.get(addr, T) orelse return null,
            .Indirect => self.mem.get(self.mem.get(addr, u24) orelse return null, T) orelse return null,
            .None => unreachable, // Error
        };
    }

    fn getAddr(self: *Self, comptime T: type, sic: bool, comptime is_store: bool, addr_mode: AddrMode) ?T {
        const am: AddrMode = if (is_store) @enumFromInt(@intFromEnum(addr_mode) -| 1) else addr_mode;

        const xbpe_addr = self.fetch();
        const x = (xbpe_addr & 0x80) >> 7;
        const b = (xbpe_addr & 0x40) >> 6;
        const p = (xbpe_addr & 0x20) >> 5;
        const e = (xbpe_addr & 0x10) >> 4;

        const a = self.fetch();

        var plus = self.regs.gpr.X * x;

        if (sic) {
            const addr = (@as(u24, xbpe_addr & 0x7F) << 8) | a;
            return self.get(T, addr + plus, am, @bitSizeOf(u15));
        }

        plus += self.regs.gpr.B * b;

        if (e > 0) {
            const addr: i20 = @bitCast(((@as(u20, xbpe_addr & 0xF) << 16) | (@as(u20, a) << 8)) | self.fetch());
            plus += self.regs.PC * p;
            return self.get(T, @truncate(@as(u25, @bitCast(@as(i25, addr) + @as(i25, plus)))), am, @bitSizeOf(u20));
        }

        plus += self.regs.PC * p;

        const addr: i12 = @bitCast((@as(u12, xbpe_addr & 0xF) << 8) | a);
        return self.get(T, @truncate(@as(u25, @bitCast(@as(i25, addr) + @as(i25, plus)))), am, @bitSizeOf(u12));
    }

    fn fetch(self: *Self) u8 {
        const ret = self.mem.get(self.regs.PC, u8).?;
        self.regs.PC += 1;
        return ret;
    }
};

test "Regs.set, Regs.get" {
    var m = Machine.init(undefined, undefined, undefined, undefined, undefined);

    m.regs.set(.A, 1);
    try std.testing.expectEqual(1, m.regs.gpr.A);
    try std.testing.expectEqual(1, m.regs.get(.A, u24));

    m.regs.set(.B, 2);
    try std.testing.expectEqual(2, m.regs.gpr.B);
    try std.testing.expectEqual(2, m.regs.get(.B, u24));

    try std.testing.expectEqualSlices(u24, &.{ 1, 0, 0, 2, 0, 0 }, m.regs.gpr.asArray()[0..6]);

    m.regs.set(.F, @as(f64, 1.1));
    try std.testing.expectEqual(1.1, m.regs.F);
    try std.testing.expectEqual(1.1, m.regs.get(.F, f64));
}

test "Mem.set, Mem.get" {
    var buf = [_]u8{0} ** 20;
    var mem = Mem{ .buf = &buf };

    mem.set(0, @as(u24, 10));

    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 10 }, buf[0..3]);

    const v = mem.get(0, u24).?;

    try std.testing.expectEqual(10, v);

    mem.setF(0, 1.0);

    const f = mem.getF(0).?;
    try std.testing.expectEqual(1.0, f);

    const expected = std.mem.toBytes(std.mem.nativeToBig(u48, @truncate(@as(u64, @bitCast(@as(f64, 1.0))) >> 16)))[0..hl.sizeOf(u48)];
    try std.testing.expectEqualSlices(u8, expected, buf[0..hl.sizeOf(u48)]);
}

test "Machine.load with M record" {
    var buf = [_]u8{0} ** 100;
    const str =
        \\Hprg   000001000011
        \\T00000111B400510000510001510002510003510004
        \\M00000201
        \\E000001
    ;

    var m = Machine.init(&buf, undefined, undefined, undefined, std.testing.allocator);
    m.use_undo = false;

    try m.load(str, true);
    defer {
        if (m.code) |c| {
            c.deinit(std.testing.allocator);
        }
    }

    const prog = m.mem.get(1, [17]u8).?;
    try std.testing.expectEqualSlices(u8, &.{
        0xB4, 0x00, 0x52, 0x00, 0x00, 0x51, 0x00, 0x01,
        0x51, 0x00, 0x02, 0x51, 0x00, 0x03, 0x51, 0x00,
        0x04,
    }, &prog);

    try std.testing.expectEqual(1, m.regs.PC);
}

test "Machine.load" {
    var buf = [_]u8{0} ** 100;
    const str =
        \\Hprg   000001000011
        \\T00000111B400510000510001510002510003510004
        \\E000001
    ;

    var m = Machine.init(&buf, undefined, undefined, undefined, std.testing.allocator);
    m.use_undo = false;

    try m.load(str, true);
    defer {
        if (m.code) |c| {
            c.deinit(std.testing.allocator);
        }
    }

    const prog = m.mem.get(1, [17]u8).?;
    try std.testing.expectEqualSlices(u8, &.{
        0xB4, 0x00, 0x51, 0x00, 0x00, 0x51, 0x00, 0x01,
        0x51, 0x00, 0x02, 0x51, 0x00, 0x03, 0x51, 0x00,
        0x04,
    }, &prog);

    try std.testing.expectEqual(1, m.regs.PC);
}

test "test_arith" {
    var buf = [_]u8{0} ** 200;
    var m = Machine.init(&buf, undefined, undefined, undefined, std.testing.allocator);
    m.use_undo = false;

    const str =
        \\HARITH 00000000006F
        \\T00000006000007000004
        \\T0000151E4B200F4B20184B20214B202A4B20333F2FFD032FD61B2FD60F2FD64F0000
        \\T0000331E032FCA1F2FCA0F2FCD4F0000032FBE232FBE0F2FC44F0000032FB2272FB2
        \\T0000511E0F2FBB4F0000032FA6272FA6232FA30F2FAF032F9A1F2FA90F2FA64F0000
        \\E000015
    ;

    try m.load(str, true);
    defer {
        if (m.code) |c| {
            c.deinit(std.testing.allocator);
        }
    }

    m.start();

    const res = [_]u8{ 0, 0, 7, 0, 0, 4, 0, 0, 11, 0, 0, 3, 0, 0, 28, 0, 0, 1, 0, 0, 3 };
    try std.testing.expectEqualSlices(u8, &res, &m.mem.get(0, [7 * 3]u8).?);
}

test "test_horner" {
    var buf = [_]u8{0} ** 300;
    var m = Machine.init(&buf, undefined, undefined, undefined, std.testing.allocator);
    m.use_undo = false;

    const str =
        \\HHORNER000000000059
        \\T0000001E0000010000020000030000040000050000020000000500000100051D0001
        \\T00001E1EAC05692FDDB400A01533201F37201C6D0003984190311B8000232FD59431
        \\T00003C1D6D00039C416D000190413F2FDC6D0003984190311B80000F2FBC3F2FFD
        \\E000015
    ;

    try m.load(str, true);
    defer {
        if (m.code) |c| {
            c.deinit(std.testing.allocator);
        }
    }

    m.start();

    try std.testing.expectEqual(57, m.mem.get(0x12, u24).?);
}

test "fact" {
    var buf = [_]u8{0} ** 1000;
    var m = Machine.init(&buf, undefined, undefined, undefined, std.testing.allocator);
    m.use_undo = false;

    const PRG_FACT =
        \\Hfact  000000000C2D
        \\T0000001E4B20360100054B20033F2FFD1620604B2036290001332018290000332012
        \\T00001E1E0E204E4B20241D00014B2FE24B202D22203F4B20270A20394F00000F2036
        \\T00003C1E0120360F202D03202D4F00000F20270320211B201B0F201B03201B4F0000
        \\T00005A1B0F201503200F1F20090F20090320094F0000000003000000000000
        \\E000000
    ;

    try m.load(PRG_FACT, true);
    defer {
        if (m.code) |c| {
            c.deinit(std.testing.allocator);
        }
    }

    m.start();

    try std.testing.expectEqual(120, m.regs.gpr.A);
}

test "cat" {
    var buf = [_]u8{0} ** 1000;

    var devs = Machine.OSDevices{};

    var m = Machine.init(&buf, &devs, undefined, undefined, std.testing.allocator);
    m.use_undo = false;

    // ```asm
    //cat START 0
    //
    //loop RD #0 . stdin
    //WD #1 . stdout
    //J loop
    // ```
    const PRG_CAT =
        \\Hcat   000000000009
        \\T00000009D90000DD00013F2FF7
        \\E000000
    ;

    const in: []const u8 = "123";

    const out: []u8 = try std.testing.allocator.alloc(u8, 3);
    defer std.testing.allocator.free(out);

    var br = std.io.fixedBufferStream(in);
    var bw = std.io.fixedBufferStream(out);

    m.devs.setDevice(0, Device.from_rw(br.reader().any(), null));
    m.devs.setDevice(1, Device.from_rw(null, bw.writer().any()));

    try m.load(PRG_CAT, true);
    defer {
        if (m.code) |c| {
            c.deinit(std.testing.allocator);
        }
    }

    m.start();

    try std.testing.expectEqualSlices(u8, in, out[0..3]);
}
