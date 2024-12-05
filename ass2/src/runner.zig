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
    undo_buf: undo.UndoBuf = undefined,

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
    runner.mem_buf = buf;

    const devs = try alloc.create(Machine.OSDevices);
    devs.* = Machine.OSDevices{};
    runner.dev_buf = devs;

    runner.M = Machine.init(@ptrCast(buf), devs);
    runner.M.devs.setDevice(0, .{ .file = std.io.getStdIn(), .closable = false });
    runner.M.devs.setDevice(1, .{ .file = std.io.getStdOut(), .closable = false });
    runner.M.devs.setDevice(2, .{ .file = std.io.getStdErr(), .closable = false });
}

pub fn deinit(alloc: Allocator) void {
    alloc.free(runner.mem_buf);
    runner.dev_buf.deinit();
    alloc.destroy(runner.dev_buf);
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
    try switch (action) {
        .Tui => runTui(alloc),
        else => {},
    };
}

fn runTui(alloc: Allocator) !void {
    const out = std.io.getStdOut();
    const w = out.writer();

    const prompt = "sic> ";

    while (true) {
        const line: [*c]u8 = rl.readline(prompt);
        defer std.c.free(line);

        if (line == null) {
            continue;
        }

        const l = std.mem.sliceTo(line, 0);
        var args = tui.parseArgs(l, alloc) catch tui.Args{};
        defer args.deinit();

        switch (args.action) {
            .Noop => {},
            .Quit => break,

            // machine has to be stopped
            .Load, .Start, .Step, .Undo, .UndoSet, .RegPrint, .RegSet, .RegClear, .MemPrint, .MemSet, .MemClear, .WatchList, .Breakpoint => {
                if (!runner.m.tryLock()) {
                    w.writeAll("Cannot execute this action, while the machine is running.\n") catch {
                        std.log.err("InternalError: Cannot write to stdout.", .{});
                    };
                    continue;
                }
                runner.m.unlock();

                switch (args.action) {
                    .Load => {
                        const v = args.get("file").?; // should have this key
                        runner.M.load(v.Str, false, alloc) catch {
                            std.log.err("Cannot load file.", .{});
                        };
                    },
                    .Start => {
                        runner.m.lock();
                        runner.action = .Start;
                        runner.m.unlock();

                        runner.c.signal();
                    },
                    .Step => {
                        const count = args.get("count");
                        if (count == null) {
                            const str = runner.M.curInstrStr();
                            if (str) |s| {
                                w.print("{s}\n", .{s}) catch {
                                    std.log.err("InternalError: Cannot write to stdout.", .{});
                                };
                            }
                        }
                    },
                    .Undo => {},
                    .UndoSet => {},
                    .RegPrint => {},
                    .RegSet => {},
                    .RegClear => {},
                    .MemPrint => {},
                    .MemSet => {},
                    .MemClear => {},
                    .WatchList => {},
                    .Breakpoint => {},
                    else => {},
                }
            },
            .Stop => {},
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
            .Step => runner.M.step(),
            .NStep => runner.M.nStep(runner.n_instr),
            .Start => runner.M.start(),
            .Noop, .Wait => {},
        }

        runner.action = .Wait;
    }
}
