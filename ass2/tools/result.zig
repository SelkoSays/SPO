const std = @import("std");

pub fn Result(comptime O: type, comptime E: type) type {
    return union(enum) {
        Ok: O,
        Err: E,

        const Self = @This();

        pub fn err(@"error": E) Self {
            return Self{
                .Err = @"error",
            };
        }

        pub fn ok(ok_: O) Self {
            return Self{
                .Ok = ok_,
            };
        }

        pub fn is_err(self: *const Self) bool {
            return self.* == .Err;
        }

        pub fn is_ok(self: *const Self) bool {
            return self.* == .Ok;
        }

        pub fn try_unwrap(self: *const Self) !O {
            return switch (self.*) {
                .Ok => |ok_| ok_,
                .Err => |err_| blk: {
                    if (@hasDecl(E, "display")) {
                        _ = err_.display();
                    }

                    if (@hasDecl(E, "any")) {
                        return err_.any();
                    }

                    if (E == anyerror) {
                        break :blk err_;
                    }

                    @compileError("Type E should be of type anyerror or has to have a method 'any' that returns anyerror");
                },
            };
        }

        pub fn unwrap(self: *const Self) O {
            return switch (self.*) {
                .Ok => |ok_| ok_,
                .Err => |err_| {
                    if (@hasDecl(E, "display")) {
                        _ = err_.display();
                    }

                    if (@hasDecl(E, "any")) {
                        std.debug.panic("{}", .{err_.any()});
                    }

                    if (E == anyerror) {
                        std.debug.panic("{}", .{err_});
                    }

                    @compileError("Type E should be of type anyerror or has to have a method 'any' that returns anyerror");
                },
            };
        }

        pub fn map_ok(self: Self, comptime T: type, comptime mapFn: ?*const fn (ok: O) T) !Result(T, E) {
            if (mapFn == null) {
                return switch (self) {
                    .Ok => error.CannotMapOkType,
                    .Err => |err_| .{ .Err = err_ },
                };
            }

            return switch (self) {
                .Ok => |ok_| .{ .Ok = mapFn(ok_) },
                .Err => |err_| .{ .Err = err_ },
            };
        }
    };
}
