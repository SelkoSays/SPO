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
    const buf = try alloc.alloc(u8, 1 << 21);
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

    runner.M = Machine.init(@ptrCast(buf), devs, u_buf, alloc);
    runner.M.devs.setDevice(0, .{ .file = std.io.getStdIn(), .closable = false });
    runner.M.devs.setDevice(1, .{ .file = std.io.getStdOut(), .closable = false });
    runner.M.devs.setDevice(2, .{ .file = std.io.getStdErr(), .closable = false });
}

pub fn deinit(alloc: Allocator) void {
    alloc.free(runner.mem_buf);

    runner.dev_buf.deinit();
    alloc.destroy(runner.dev_buf);

    runner.undo_buf.deinit(alloc);
    alloc.destroy(runner.undo_buf);
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

    thread.join();
}

fn runTui(alloc: Allocator) !void {
    const out = std.io.getStdOut();
    const w = out.writer().any();

    const prompt = "sic> ";

    while (true) {
        const line: [*c]u8 = rl.readline(prompt);
        defer std.c.free(line);

        if (line == null) {
            continue;
        }

        const l = std.mem.sliceTo(line, 0);
        const sync = l[0] == '.';

        var args = tui.parseArgs(if (sync) l[1..] else l, alloc) catch tui.Args{};
        defer args.deinit();

        switch (args.action) {
            .Noop => {},
            .Quit => {
                runner.M.stopped = true;
                runner.end = true;
                if (runner.m.tryLock()) { // if thread waits
                    runner.action = .Noop;
                    runner.c.signal();
                    runner.m.unlock();
                }
                break;
            },

            // machine has to be stopped
            .Load, .Start, .Step, .Undo, .UndoSet, .Speed, .RegPrint, .RegSet, .RegClear, .MemPrint, .MemSet, .MemClear, .WatchList, .Breakpoint => {
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
                            const str = runner.M.curInstrStr();
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
                    .RegPrint => {
                        const reg_name = args.get("reg").?.Str;
                        const ri = std.meta.stringToEnum(mach.RegIdx, reg_name).?;
                        printOut(w, "REGISTER   HEX          UNSIGNED    SIGNED      SPECIAL\n", .{});
                        switch (ri) {
                            .F => {
                                const val = runner.M.regs.get(ri, f64);
                                printOut(w, "{s:<10} {s:<12} {s:<11} {s:<11} {d}\n", .{ reg_name, "", "", "", val });
                            },
                            else => {
                                const val = runner.M.regs.get(ri, u24);
                                printOut(w, "{s:<10} {X:0<6}       {d:<11} {d}\n", .{ reg_name, val, val, @as(i24, @bitCast(val)) });
                            },
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

                        runner.M.mem.print(w, @truncate(addr.Int), @truncate(count.Int)) catch {
                            std.log.err("InternalError: Unable to write to standard output.", .{});
                        };
                    },
                    // .MemSet => {},
                    .MemClear => {
                        @memset(runner.mem_buf, 0);
                    },
                    // .WatchList => {},
                    // .Breakpoint => {},
                    else => {},
                }
            },
            .Stop => {
                runner.M.stopped = true;
            },
            .Watch => {},
            .BreakpointList => {},
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
            .Step => runner.M.step() catch {},
            .NStep => runner.M.nStep(runner.n_instr),
            .Start => runner.M.start(),
            .Noop, .Wait => {},
        }

        runner.action = .Wait;
    }
}

fn printOut(w: std.io.AnyWriter, comptime format: []const u8, args: anytype) void {
    std.io.AnyWriter.print(w, format, args) catch {
        std.log.err("InternalError: Unable to write to standard output.", .{});
    };
}
