const std = @import("std");

const RegIdx = @import("machine.zig").RegIdx;
const ring_buffer = @import("ring_buffer.zig");

pub const State = union(enum) {
    MemState: struct { addr: u24, bytes: []const u8 },
    RegState: struct { ri: RegIdx, val: packed union { i: u24, f: f64 } },
    MultiState: []const State,

    pub fn deinit(self: *State, alloc: ?std.mem.Allocator) void {
        switch (self) {
            .MultiState => |s| if (alloc) |a| a.free(s),
            else => {},
        }
    }
};

pub const UndoBuf = ring_buffer.ForgetfulRingBuffer(State, State.deinit);
