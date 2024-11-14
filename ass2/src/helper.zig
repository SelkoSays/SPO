/// minimal size in bytes
pub fn sizeOf(comptime T: type) usize {
    return (@bitSizeOf(T) + 7) / 8;
}
