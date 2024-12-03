const std = @import("std");

pub fn Result(comptime O: type, comptime E: type) type {
    return union(enum) {
        Ok: O,
        Err: E,

        const Self = @This();

        pub fn Err(@"error": E) Self {
            return Self{
                .Err = @"error",
            };
        }

        pub fn Ok(ok: O) Self {
            return Self{
                .Ok = ok,
            };
        }

        pub fn is_err(self: *const Self) bool {
            return self.* == .Err;
        }

        pub fn is_ok(self: *const Self) bool {
            return self.* == .Ok;
        }

        pub fn unwrap(self: *const Self) !O {
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

        pub fn map_ok(self: Self, comptime T: type, comptime mapFn: ?*const fn (ok: O) T) !Result(T, E) {
            if (mapFn == null) {
                return switch (self) {
                    .Ok => error.CannotMapOkType,
                    .Err => |err| .{ .Err = err },
                };
            }

            return switch (self) {
                .Ok => |ok| .{ .Ok = mapFn(ok) },
                .Err => |err| .{ .Err = err },
            };
        }
    };
}
