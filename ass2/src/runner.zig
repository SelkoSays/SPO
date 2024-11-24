const std = @import("std");
const Allocator = std.mem.Allocator;

const mach = @import("machine.zig");
const Machine = mach.Machine;

const device = @import("device.zig");
const Device = device.Device;
const Devices = device.Devices;

const Is = @import("instruction_set");
const Opcode = Is.Opcode;

const tui = @import("tui.zig");

const Runner = struct {
    M: Machine = undefined,
    m: std.Thread.Mutex = .{},
    c: std.Thread.Condition = .{},
    end: bool = false,
    action: Action = .Noop,
    n_instr: u32 = 0,
    mem_buf: []u8 = undefined,
    dev_buf: *Machine.OSDevices = undefined,

    const Action = enum {
        Step,
        NStep,
        Start,
        Noop,
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
    const in = std.io.getStdIn();
    var r = in.reader();

    const out = std.io.getStdOut();
    var w = out.writer();

    const prompt = "sic> ";
    try w.writeAll(prompt);

    var line = try r.readUntilDelimiterAlloc(alloc, '\n', 100);
    while (true) {
        var args = tui.parseArgs(line, alloc) catch tui.Args{};

        switch (args.action) {
            .Noop => {},
            .Quit => break,
            else => {},
        }

        args.deinit();
        alloc.free(line);
        try w.writeAll(prompt);
        line = try r.readUntilDelimiterAlloc(alloc, '\n', 100);
    }
    alloc.free(line);
}

fn execute_machine() void {
    while (!runner.end) {
        runner.m.lock();
        runner.c.wait(&runner.m);
        runner.m.unlock();

        switch (runner.action) {
            .Step => runner.M.step(),
            .NStep => runner.M.nStep(runner.n_instr),
            .Start => runner.M.start(),
            .Noop => {},
        }
    }
}
