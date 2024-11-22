/// minimal size in bytes
pub inline fn sizeOf(comptime T: type) usize {
    return (@bitSizeOf(T) + 7) / 8;
}

pub inline fn as(val: anytype, comptime T: type) T {
    return @bitCast(val);
}

pub fn chopFloat(f: f64) f64 {
    return as(@as(u64, as(f, u64) & ~@as(u64, 0xFFFF)), f64);
}
