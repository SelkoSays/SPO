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
                .leftIdx = capacity,
                .rightIdx = 0,
                .len = 0,
            };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            alloc.free(self.items);
            self.items = undefined;
        }

        pub fn add(self: *Self, item: T, alloc: ?Allocator) void {
            if (self.rightIdx == self.leftIdx) {
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
            return item;
        }

        pub fn popBack(self: *Self) ?T {
            if (self.len == 0) return null;

            const item = self.items[self.rightIdx];

            self.rightIdx = (self.rightIdx + self.items.len - 1) % self.items.len;

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
