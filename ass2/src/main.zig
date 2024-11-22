const std = @import("std");

const mach = @import("machine.zig");
const Machine = mach.Machine;

const device = @import("device.zig");
const Device = device.Device;
const Devices = device.Devices;

const Is = @import("instruction_set");
const Opcode = Is.Opcode;

const Runner = struct {
    M: Machine = undefined,
    m: std.Thread.Mutex = .{},
    c: std.Thread.Condition = .{},
    end: bool = false,
    action: Action = .Noop,
    n_instr: u32 = 0,

    const Action = enum {
        Step,
        NStep,
        Start,
        Noop,
    };
};

var runner: Runner = .{};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    var buf = try alloc.alloc(u8, 1 << 24);

    runner.M = Machine.init(&buf, undefined);
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
