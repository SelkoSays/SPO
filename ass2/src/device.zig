const std = @import("std");
const fs = std.fs;

var _buf: [6]u8 = [_]u8{ 0, 0, 0, 0, 0, 0 };

pub const Device = struct {
    file: ?fs.File,
    closable: bool = true,

    const Self = @This();

    pub fn init(file: ?fs.File, name: []const u8) Self {
        if (file) |f| return .{ .file = f };

        const f = fs.cwd().createFile(name, .{ .read = true, .truncate = false }) catch |err| switch (err) {
            error.PathAlreadyExists => fs.cwd().openFile(name, .{ .mode = .read_write }) catch null,
            else => null,
        };

        return .{ .file = f };
    }

    pub fn @"test"(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn read(self: *Self) u8 {
        var buf = [1]u8{0};
        _ = self.file.?.read(&buf) catch 0; // TODO: Maybe handle better
        return buf[0];
    }

    pub fn write(self: *Self, val: u8) void {
        _ = self.file.?.write(&.{val}) catch 0;
    }

    pub fn close(self: *Self) void {
        if (self.file != null and self.closable) {
            self.file.?.close();
        }
    }
};

pub const Devices = struct {
    devs: []?Device,

    const Self = @This();

    pub fn init(devs: []?Device) Self {
        return .{
            .devs = devs,
        };
    }

    pub fn setDevice(self: *Self, n: u8, dev: ?Device) void {
        if (dev != null) {
            self.devs[n] = dev;
        } else {
            self.devs[n] = Device.init(null, getName(n));
        }
    }

    pub fn getDevice(self: *Self, n: u8) *Device {
        if (self.devs[n] != null) return @constCast(&self.devs[n].?);
        self.devs[n] = Device.init(null, getName(n));
        return &self.devs[n].?;
    }

    fn getName(n: u8) []const u8 {
        const name = std.fmt.bytesToHex([_]u8{n}, .upper);
        return std.fmt.bufPrint(&_buf, "{s}.dev", .{name[0..2]}) catch unreachable;
    }

    pub fn deinit(self: *Self) void {
        for (self.devs) |*dev| {
            if (dev.* != null) {
                dev.*.?.close();
            }
        }
    }
};
