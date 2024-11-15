/// minimal size in bytes
pub inline fn sizeOf(comptime T: type) usize {
    return (@bitSizeOf(T) + 7) / 8;
}
