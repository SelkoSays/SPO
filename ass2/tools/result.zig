const std = @import("std");

pub fn Result(comptime O: type, comptime E: type) type {
    return union(enum) {
        Ok: O,
        Err: E,

        const Self = @This();

        pub fn unwrap(self: *Self) !O {
            return switch (self.*) {
                .Ok => |ok| ok,
                .Err => |err| blk: {
                    if (@hasDecl(E, "display")) {
                        _ = err.display();
                    }

                    if (@hasDecl(E, "any")) {
                        return err.any();
                    }

                    if (E == anyerror) {
                        break :blk err;
                    }

                    @compileError("Type E should be of type anyerror or has to have a method 'any' that returns anyerror");
                },
            };
        }

        pub fn map_ok(self: Self, comptime T: type, mapFn: *const fn (ok: O) T) Result(T, E) {
            return switch (self) {
                .Ok => |ok| .{ .Ok = mapFn(ok) },
                .Err => |err| .{ .Err = err },
            };
        }
    };
}
