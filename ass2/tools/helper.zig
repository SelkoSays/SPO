const std = @import("std");

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

/// expect 'bytes' in BigEndian order, expect 'val' in Native endianess
pub fn add_to_bytes(bytes: []u8, val: u24, nibbles: u8) void {
    const byte_num = (nibbles + 1) / 2;

    if (bytes.len < byte_num) @panic("Wrong byte len");
    if (bytes.len == 0) return;

    const v_bytes = std.mem.toBytes(std.mem.nativeToBig(u24, val))[0..3];
    var i = bytes.len - 1;
    var j: usize = 2;
    var carry: u1 = 0;

    while (i > 0 and j > 0) {
        defer {
            i -= 1;
            j -= 1;
        }

        const a: u9 = bytes[i];
        const b: u9 = v_bytes[j];
        const c = a + b + carry;
        carry = @truncate(c >> 8);
        bytes[i] = @truncate(c);
    }

    const pow: u4 = @truncate((((@as(u9, nibbles) + 1) % 2) + 1) * 4);
    const mask: u8 = @truncate((@as(u9, 1) << pow) -% 1);
    // 0000 0001
    // 7654 3210
    const a: u9 = bytes[i];
    const b: u9 = v_bytes[j];
    const c = a + b + carry;
    bytes[i] = (bytes[i] & (~mask)) | (@as(u8, @truncate(c)) & mask);
}

test add_to_bytes {
    const a: u32 = 0;
    const b: u24 = 1;

    var s = std.mem.toBytes(std.mem.nativeToBig(u32, a));
    for (1..9) |i| {
        const nibbles: u8 = @truncate(i);
        const byte_num = (nibbles + 1) / 2;

        const ss = &s[(4 -| byte_num)..];
        add_to_bytes(@constCast(ss).*, b, nibbles);
        const c = std.mem.bigToNative(u32, std.mem.bytesToValue(u32, &s));
        try std.testing.expectEqual(i, c);
    }
}
