const std = @import("std");
const fs = std.fs;

var _buf: [6]u8 = [_]u8{ 0, 0, 0, 0, 0, 0 };

pub const Device = struct {
    file: ?std.fs.File = null,
    reader: ?std.io.AnyReader = null,
    writer: ?std.io.AnyWriter = null,
    closable: bool = true,

    const Self = @This();

    pub fn init(file: ?fs.File, name: []const u8, closable: bool) Self {
        if (file) |f| return .{ .file = f, .reader = f.reader().any(), .writer = f.writer().any(), .closable = closable };

        const f: ?std.fs.File = fs.cwd().createFile(name, .{ .read = true, .truncate = false }) catch |err| bl: {
            break :bl switch (err) {
                error.PathAlreadyExists => fs.cwd().openFile(name, .{ .mode = .read_write }) catch null,
                else => null,
            };
        };

        const r = if (f) |ff| ff.reader().any() else null;
        const w = if (f) |ff| ff.writer().any() else null;
        return .{ .file = f, .reader = r, .writer = w, .closable = closable };
    }

    pub fn from_rw(reader: ?std.io.AnyReader, writer: ?std.io.AnyWriter) Self {
        return .{
            .reader = reader,
            .writer = writer,
            .closable = false,
        };
    }

    pub fn @"test"(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn read(self: *Self) ?u8 {
        if (self.reader) |r| {
            return r.readByte() catch {
                std.log.info("Could not read from device.", .{});
                return null;
            };
        }
        return null;
    }

    pub fn write(self: *Self, val: u8) void {
        if (self.writer) |w| {
            w.writeByte(val) catch {
                std.log.info("Could not write to device.", .{});
            };
        }
    }

    pub fn close(self: *Self) void {
        if (self.file != null and self.closable) {
            self.file.?.close();
        }
    }
};

pub fn Devices(N: comptime_int) type {
    return struct {
        devs: [N]?Device = [_]?Device{null} ** N,

        const Self = @This();

        pub fn init(devs: [N]?Device) Self {
            return .{
                .devs = devs,
            };
        }

        pub fn setDevice(self: *Self, n: u8, dev: ?Device) void {
            if (dev != null) {
                self.devs[n] = dev;
            } else {
                self.devs[n] = Device.init(null, getName(n), true);
            }
        }

        pub fn getDevice(self: *Self, n: u8) *Device {
            if (self.devs[n] != null) return @constCast(&(self.devs[n].?));
            self.devs[n] = Device.init(null, getName(n), true);
            return &(self.devs[n].?);
        }

        fn getName(n: u8) []const u8 {
            const name = std.fmt.bytesToHex([_]u8{n}, .upper);
            return std.fmt.bufPrint(&_buf, "{s}.dev", .{name[0..2]}) catch unreachable;
        }

        pub fn deinit(self: *Self) void {
            for (&self.devs) |*dev| {
                if (dev.* != null) {
                    dev.*.?.close();
                    dev.* = null;
                }
            }
        }
    };
}
