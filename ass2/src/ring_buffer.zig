const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn ForgetfulRingBuffer(comptime T: type, comptime free_item: ?*const fn (*T, ?Allocator) void) type {
    return struct {
        items: []T,
        leftIdx: usize,
        rightIdx: usize,
        len: usize,

        const Self = @This();

        pub fn init(alloc: Allocator, capacity: usize) !Self {
            return Self{
                .items = try alloc.alloc(T, capacity),
                .leftIdx = 0,
                .rightIdx = 0,
                .len = 0,
            };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            if (free_item != null) {
                var i = self.leftIdx;
                while (i != self.rightIdx) {
                    defer i = (i + 1) % self.items.len;
                    free_item.?(&self.items[i], alloc);
                }
            }
            alloc.free(self.items);
            self.items = undefined;
        }

        pub fn last(self: *Self) ?*T {
            if (self.len == 0) return null;
            return &self.items[(self.items.len + self.rightIdx - 1) % self.items.len];
        }

        pub fn resize(self: *Self, size: usize, alloc: Allocator) !void {
            if (size == 0) return error.CannotResizeToZero;

            var new_mem = try alloc.alloc(T, size);

            var i: usize = self.leftIdx;

            if (size < self.len) {
                i = (self.leftIdx + (self.len - size)) % self.items.len;

                if (free_item != null) {
                    var j = self.leftIdx;
                    while (j != i) {
                        defer j = (j + 1) % self.items.len;

                        free_item.?(&self.items[j], alloc);
                    }
                }
            }

            var len: usize = 0;
            if (i > self.rightIdx) {
                @memcpy(new_mem, self.items[i..]);
                len = self.items.len - i;
                i = 0;
            }

            @memcpy(new_mem[len..], self.items[i..self.rightIdx]);

            alloc.free(self.items);
            self.items = new_mem;

            self.leftIdx = 0;
            if (size < self.len) {
                self.rightIdx = size;
            } else {
                self.rightIdx = self.len;
            }
        }

        pub fn add(self: *Self, item: T, alloc: ?Allocator) void {
            if (self.len == self.items.len) {
                if (free_item) |free| {
                    free(&self.items[self.leftIdx], alloc);
                }
                self.leftIdx = (self.leftIdx + 1) % self.items.len;
                self.len -|= 1;
            }

            self.items[self.rightIdx] = item;
            self.rightIdx = (self.rightIdx + 1) % self.items.len;
            self.len += 1;
        }

        pub fn popFront(self: *Self) ?T {
            if (self.len == 0) return null;

            const item = self.items[self.leftIdx];
            self.leftIdx = (self.leftIdx + 1) % self.items.len;
            self.len -= 1;
            return item;
        }

        pub fn popBack(self: *Self) ?T {
            if (self.len == 0) return null;

            self.rightIdx = (self.rightIdx + self.items.len - 1) % self.items.len;

            const item = self.items[self.rightIdx];
            self.len -= 1;
            return item;
        }

        pub fn at(self: *Self, idx: usize) ?*T {
            if (idx >= self.len) return null;

            const i = (self.leftIdx + idx) % self.items.len;
            return &self.items[i];
        }

        pub fn atC(self: *const Self, idx: usize) ?*const T {
            if (idx >= self.len) return null;

            const i = (self.leftIdx + idx) % self.items.len;
            return &self.items[i];
        }
    };
}
