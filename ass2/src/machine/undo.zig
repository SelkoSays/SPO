const std = @import("std");

const RegIdx = @import("machine.zig").RegIdx;
const ring_buffer = @import("ring_buffer");

pub const State = union(enum) {
    MemByteState: struct { addr: u24, val: u8 },
    MemWordState: struct { addr: u24, val: u24 },
    MemFState: struct { addr: u24, val: f64 },
    RegState: struct { ri: RegIdx, val: packed union { i: u24, f: f64 } },
};

fn deinitStates(a: *std.ArrayListUnmanaged(State), alloc: ?std.mem.Allocator) void {
    a.deinit(alloc.?);
}

pub const UndoBuf = ring_buffer.ForgetfulRingBuffer(std.ArrayListUnmanaged(State), deinitStates);
