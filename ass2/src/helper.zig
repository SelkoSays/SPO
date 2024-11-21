/// minimal size in bytes
pub inline fn sizeOf(comptime T: type) usize {
    return (@bitSizeOf(T) + 7) / 8;
}

pub inline fn as(val: anytype, comptime T: type) T {
    return @bitCast(val);
}
