const std = @import("std");

pub const Device = struct {
    file: ?std.fs.File,

    const Self = @This();

    pub fn init(file: ?std.fs.File, name: []const u8) Self {
        _ = file;
        _ = name;
        return .{ .file = null };
    }

    pub fn @"test"(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn read(self: *Self) u8 {
        _ = self;
        return 0;
    }

    pub fn write(self: *Self, val: u8) void {
        _ = self;
        _ = val;
    }
};
