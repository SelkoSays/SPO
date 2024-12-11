const std = @import("std");
const Allocator = std.mem.Allocator;

const rl = @cImport({
    @cInclude("readline/readline.h");
    @cInclude("readline/history.h");
});
const mach = @import("machine.zig");
const Machine = mach.Machine;

const device = @import("device.zig");
const Device = device.Device;
const Devices = device.Devices;

const Is = @import("instruction_set");
const Opcode = Is.Opcode;

const tui = @import("tui.zig");

const undo = @import("undo.zig");

const WatchList = std.AutoArrayHashMap(u24, u24); // K = address, V = size
pub const Breakpoints = std.AutoArrayHashMap(u24, u8); // K = address, V = byte

const Runner = struct {
    M: Machine = undefined,
    m: std.Thread.Mutex = .{},
    c: std.Thread.Condition = .{},
    end: bool = false,
    action: Action = .Wait,
    n_instr: u32 = 0,
    mem_buf: []u8 = undefined,
    dev_buf: *Machine.OSDevices = undefined,
    undo_buf: *undo.UndoBuf = undefined,
    watch_list: WatchList = undefined,
    breakpoints: Breakpoints = undefined,

    const Action = enum {
        Step,
        NStep,
        Start,
        Noop,
        Wait,
    };
};

var runner: Runner = .{};

pub fn init(alloc: Allocator) !void {
    const buf = try alloc.alloc(u8, 1 << 20);
    @memset(buf, 0);
    errdefer alloc.free(buf);
    runner.mem_buf = buf;

    const devs = try alloc.create(Machine.OSDevices);
    errdefer alloc.destroy(devs);
    devs.* = Machine.OSDevices{};
    runner.dev_buf = devs;

    const u_buf = try alloc.create(undo.UndoBuf);
    errdefer alloc.destroy(u_buf);
    u_buf.* = try undo.UndoBuf.init(alloc, 50);
    runner.undo_buf = u_buf;

    const w_list = WatchList.init(alloc);
    errdefer w_list.deinit();
    runner.watch_list = w_list;

    const bps = Breakpoints.init(alloc);
    errdefer bps.deinit();
    runner.breakpoints = bps;

    runner.M = Machine.init(@ptrCast(buf), devs, u_buf, &runner.breakpoints, alloc);

    runner.M.devs.setDevice(0, Device.init(std.io.getStdIn(), "", false));
    runner.M.devs.setDevice(1, Device.init(std.io.getStdOut(), "", false));
    runner.M.devs.setDevice(2, Device.init(std.io.getStdErr(), "", false));
}

pub fn deinit(alloc: Allocator) void {
    alloc.free(runner.mem_buf);

    runner.dev_buf.deinit();
    alloc.destroy(runner.dev_buf);

    runner.undo_buf.deinit(alloc);
    alloc.destroy(runner.undo_buf);

    runner.watch_list.deinit();
    runner.breakpoints.deinit();

    if (runner.M.code) |c| {
        c.deinit(alloc);
    }
}

const RunAction = union(enum) {
    Noop,
    Tui,
    Gui,
    Compile,
};

pub fn parseArgs(alloc: Allocator) !RunAction {
    var args = try std.process.argsWithAllocator(alloc);

    _ = args.next(); // skip program name

    // tui      [file]
    // compile  file[,...]
    // gui      [file]
    // help

    const cmd = args.next();

    if (cmd == null or std.mem.eql(u8, cmd.?, "help")) {
        // print usage
        return .Noop;
    } else if (std.mem.eql(u8, cmd.?, "tui")) {
        // tui action
        return .Tui;
    } else if (std.mem.eql(u8, cmd.?, "gui")) {
        // gui action
        return .Gui;
    } else if (std.mem.eql(u8, cmd.?, "compile")) {
        return .Compile;
    }
    // unknown command
    return .Noop;
}

pub fn run(alloc: Allocator, action: RunAction) !void {
    var thread = try std.Thread.spawn(.{}, execute_machine, .{});

    try switch (action) {
        .Tui => runTui(alloc),
        else => {},
    };

    runner.M.stopped = true;
    runner.end = true;
    if (runner.m.tryLock()) { // if thread waits
        runner.action = .Noop;
        runner.c.signal();
        runner.m.unlock();
    }

    thread.join();
}

fn runTui(alloc: Allocator) !void {
    const out = std.io.getStdOut();
    const w = out.writer().any();

    _ = try w.write("Any command ran like '.cmd' or '.menu cmd' ... is executed in 'sync' mode.\nIf you want to run a program that requires standard IO access, you should run it in 'sync' mode, otherwise it might not work.\n");

    const prompt = "sic> ";

    while (true) {
        const line: [*c]u8 = rl.readline(prompt);
        defer std.c.free(line);

        if (line == null) {
            continue;
        }

        const l = std.mem.sliceTo(line, 0);
        const sync = (l[0] == '.');

        if (l.len > 0) {
            rl.add_history(line);
        }

        var args = tui.parseArgs(if (sync) l[1..] else l, alloc) catch tui.Args{};
        defer args.deinit();

        switch (args.action) {
            .Noop => {},
            .Quit => {
                break;
            },

            // machine has to be stopped
            .Load,
            .Reload,
            .Start,
            .Step,
            .DisAsm,
            .Undo,
            .UndoClear,
            .UndoSet,
            .Speed,
            .RegPrint,
            .RegSet,
            .RegClear,
            .MemPrint,
            .MemClear,
            .WatchList,
            .BreakpointSet,
            .BreakpointRemove,
            // .MemSet
            => {
                if (!runner.m.tryLock()) {
                    printOut(w, "Cannot execute this action, while the machine is running.\n", .{});
                    continue;
                }
                runner.m.unlock();

                switch (args.action) {
                    .Load => {
                        const v = args.get("file").?; // should have this key
                        runner.M.load(v.Str, false) catch {
                            std.log.err("Cannot load file.", .{});
                        };
                    },
                    .Reload => {
                        runner.undo_buf.clear(alloc);

                        if (!sync) {
                            // Clear registers and memory
                            var regs = &runner.M.regs;
                            regs.F = 0.0;
                            regs.PC = 0;
                            regs.SW.i = 0;
                            @memset(regs.gpr.asArray()[0..6], 0);
                            @memset(runner.mem_buf, 0);
                        }

                        const file = args.get("file");
                        if (file) |f| {
                            runner.M.load(f.Str, false) catch {
                                std.log.err("Cannot load file.", .{});
                            };
                        } else {
                            runner.M.reload(); // if machine has code, it should be valid
                        }
                    },
                    .Start => {
                        if (!sync) {
                            runner.m.lock();
                            runner.action = .Start;
                            runner.m.unlock();

                            runner.c.signal();
                        } else {
                            runner.M.start();
                        }
                    },
                    .Step => {
                        const count = args.get("count");
                        if (count == null) {
                            const str = runner.M.instrStr(runner.M.regs.PC, null);
                            if (str) |s| {
                                printOut(w, "{s}\n", .{s});
                            }
                        }

                        if (!sync) {
                            runner.m.lock();
                            if (count) |c| {
                                runner.n_instr = @truncate(c.Int);
                                runner.action = .NStep;
                            } else {
                                runner.action = .Step;
                            }
                            runner.m.unlock();

                            runner.c.signal();
                        } else {
                            if (count) |c| {
                                runner.M.nStep(@truncate(c.Int));
                            } else {
                                runner.M.step() catch {};
                                if (runner.M.in_dbg_mode) {
                                    runner.M.step() catch {};
                                }
                            }
                        }
                    },
                    .DisAsm => {
                        var addr = if (args.get("addr")) |a| a.Int else runner.M.regs.PC;
                        const count = if (args.get("count")) |v| v.Int else 1;

                        var i_sz: usize = 0;
                        for (0..count) |_| {
                            defer addr += i_sz;
                            const str = runner.M.instrStr(@truncate(addr), &i_sz);
                            if (str) |s| {
                                printOut(w, "{s}\n", .{s});
                            } else {
                                std.log.err("InternalError: could not write instruction", .{});
                            }
                        }
                    },
                    .Undo => {
                        var n: usize = 1;
                        if (args.get("count")) |c| {
                            n = c.Int;
                        }
                        runner.M.undoN(n);
                    },
                    .UndoSet => {
                        const size = args.get("val").?;
                        runner.undo_buf.resize(size.Int, alloc) catch {
                            std.log.err("Could not resize undo buffer", .{});
                        };
                    },
                    .UndoClear => {
                        runner.undo_buf.clear(alloc);
                    },
                    .RegPrint => {
                        const o_reg_name = args.get("reg");
                        printOut(w, "REGISTER   HEX          UNSIGNED    SIGNED      SPECIAL\n", .{});

                        if (o_reg_name) |reg_name| {
                            const ri = std.meta.stringToEnum(mach.RegIdx, reg_name.Str).?;
                            printReg(w, ri, reg_name.Str);
                        } else {
                            inline for (@typeInfo(mach.RegIdx).Enum.fields) |f| {
                                printReg(w, @field(mach.RegIdx, f.name), f.name);
                            }
                        }
                    },
                    .Speed => {
                        const val = args.get("val");
                        if (val == null) {
                            printOut(w, "Simulation speed: {d} kHz\n", .{runner.M.clock_speed});
                        } else {
                            runner.M.setSpeed(val.?.Int);
                        }
                    },
                    .RegSet => {
                        const reg = args.get("reg").?;
                        const val = args.get("val").?;
                        const ri = std.meta.stringToEnum(mach.RegIdx, reg.Str).?;
                        if (ri == .F) {
                            runner.M.regs.set(ri, val.Flt);
                        } else {
                            runner.M.regs.set(ri, @as(u24, @truncate(val.Int)));
                        }
                    },
                    .RegClear => {
                        var regs = &runner.M.regs;
                        regs.F = 0.0;
                        regs.PC = 0;
                        regs.SW.i = 0;
                        @memset(regs.gpr.asArray()[0..6], 0);
                    },
                    .MemPrint => {
                        const addr = args.get("addr").?;
                        const count = args.get("count") orelse tui.Args.Val{ .Int = 1 };

                        runner.M.mem.print(w, @truncate(addr.Int), @truncate(count.Int), sync) catch {
                            std.log.err("InternalError: Unable to write to standard output.", .{});
                        };
                    },
                    .MemClear => {
                        @memset(runner.mem_buf, 0);
                    },
                    .WatchList => {
                        var it = runner.watch_list.iterator();
                        if (it.len == 0) {
                            printOut(w, "Nothing to watch\n", .{});
                            continue;
                        }
                        var i: u24 = 0;
                        while (it.next()) |e| {
                            defer i += 1;
                            printOut(w, "{d}:\n ", .{i});
                            runner.M.mem.print(w, e.key_ptr.*, e.value_ptr.*, sync) catch {
                                std.log.err("InternalError: Unable to write to standard output.", .{});
                            };
                        }
                    },
                    .BreakpointSet => {
                        const addr = args.get("addr").?.Int;

                        if (!runner.breakpoints.contains(@truncate(addr))) {
                            const rep = runner.M.mem.get(@truncate(addr), u8) orelse continue;
                            runner.breakpoints.put(@truncate(addr), rep) catch {
                                std.log.err("InternalError: Unable to add breakpoint.", .{});
                            };
                            runner.M.mem.set(@truncate(addr), Opcode.INT.int());
                        }
                    },
                    .BreakpointRemove => {
                        const idx = args.get("idx");

                        if (idx) |i| {
                            if (i.Int >= runner.breakpoints.count()) {
                                continue;
                            }

                            const it = runner.breakpoints.iterator();
                            const addr = it.keys[i.Int];
                            const v = it.values[i.Int];

                            runner.M.mem.set(addr, v);

                            runner.breakpoints.orderedRemoveAt(i.Int);
                        } else {
                            var it = runner.breakpoints.iterator();

                            while (it.next()) |e| {
                                runner.M.mem.set(e.key_ptr.*, e.value_ptr.*);
                            }
                            runner.breakpoints.clearAndFree();
                        }
                    },
                    else => {
                        std.log.err("Unhandled action '{s}'", .{@tagName(args.action)});
                    },
                }
            },
            .Stop => {
                runner.M.stopped = true;
            },
            .WatchSet => {
                const addr = args.get("addr").?.Int;
                const size_v = args.get("size").?;
                const size: u64 = switch (size_v) {
                    .Int => |i| i,
                    .Str => |s| blk: {
                        if (std.mem.eql(u8, s, "byte")) {
                            break :blk 1;
                        }
                        break :blk 3;
                    },
                    else => {
                        std.log.err("Argument size should not be a float.", .{});
                        continue;
                    },
                };

                runner.watch_list.put(@truncate(addr), @truncate(size)) catch {
                    std.log.err("InternalError: Could not add to watch list.", .{});
                };
            },
            .WatchRemove => {
                const idx = args.get("idx");
                if (idx) |i| {
                    runner.watch_list.orderedRemoveAt(i.Int);
                } else {
                    runner.watch_list.clearAndFree();
                }
            },
            .BreakpointList => {
                var it = runner.breakpoints.iterator();
                if (it.len == 0) {
                    printOut(w, "No breakpoints to show\n", .{});
                    continue;
                }

                var i: u24 = 0;
                while (it.next()) |e| {
                    defer i += 1;
                    printOut(w, "{d}:\n ", .{i});
                    const str = runner.M.instrStr(e.key_ptr.*, null);
                    if (str) |s| {
                        printOut(w, "{s}\n", .{s});
                    } else {
                        std.log.err("InternalError: could not write instruction", .{});
                    }
                }
            },
        }
    }
}

fn execute_machine() void {
    while (!runner.end) {
        runner.m.lock();
        defer runner.m.unlock();
        while (runner.action == .Wait) {
            runner.c.wait(&runner.m);
        }

        switch (runner.action) {
            .Step => {
                runner.M.step() catch {};
                if (runner.M.in_dbg_mode) {
                    runner.M.step() catch {};
                }
            },
            .NStep => runner.M.nStep(runner.n_instr),
            .Start => runner.M.start(),
            .Noop, .Wait => {},
        }

        runner.action = .Wait;
    }
}

fn printOut(w: std.io.AnyWriter, comptime format: []const u8, args: anytype) void {
    w.print(format, args) catch {
        std.log.err("InternalError: Unable to write to standard output.", .{});
    };
}

fn printReg(w: std.io.AnyWriter, ri: mach.RegIdx, reg_name: []const u8) void {
    switch (ri) {
        .F => {
            const val = runner.M.regs.get(ri, f64);
            printOut(w, "{s:<10} {X:0>12} {s:<11} {s:<11} {d}\n", .{
                reg_name,
                @as(u48, @truncate(@as(u64, @bitCast(val)) >> 16)),
                "",
                "",
                val,
            });
        },
        else => {
            const val = runner.M.regs.get(ri, u24);
            printOut(w, "{s:<10} {X:0>6}       {d:<11} {d}\n", .{ reg_name, val, val, @as(i24, @bitCast(val)) });
        },
    }
}
