const std = @import("std");
pub const max_payload = 256;
pub const max_frame = 266;
pub const info: u8 = 1;
pub const config: u8 = 2;
pub const rx_start: u8 = 3;
pub const rx_stop: u8 = 4;
pub const arm: u8 = 5;
pub const disarm: u8 = 6;
pub const send: u8 = 7;
pub const stats: u8 = 8;
pub const keepalive: u8 = 9;
pub const invert: u8 = 10;
pub const event: u8 = 0x40;
pub const confirmation = "VOLTAGES_CHECKED";

pub fn read16(p: []const u8) u16 {
    return @as(u16, p[0]) | (@as(u16, p[1]) << 8);
}
pub fn read32(p: []const u8) u32 {
    var value: u32 = 0;
    for (0..4) |i| value |= @as(u32, p[i]) << @as(u5, @intCast(i * 8));
    return value;
}
pub fn read64(p: []const u8) u64 {
    var value: u64 = 0;
    for (0..8) |i| value |= @as(u64, p[i]) << @as(u6, @intCast(i * 8));
    return value;
}
pub fn crc(data: []const u8) u16 {
    var value: u16 = 0xffff;
    for (data) |byte| {
        value ^= @as(u16, byte) << 8;
        for (0..8) |_| value = if (value & 0x8000 != 0) (value << 1) ^ 0x1021 else value << 1;
    }
    return value;
}
pub fn encode(out: *[max_frame]u8, kind: u8, sequence: u16, data: []const u8) ![]const u8 {
    if (data.len > max_payload) return error.PacketTooLarge;
    out[0] = 0x5a;
    out[1] = 0x38;
    out[2] = 1;
    out[3] = kind;
    out[4] = @truncate(sequence);
    out[5] = @truncate(sequence >> 8);
    out[6] = @truncate(data.len);
    out[7] = @truncate(data.len >> 8);
    @memcpy(out[8..][0..data.len], data);
    const checksum = crc(out[2 .. 8 + data.len]);
    out[8 + data.len] = @truncate(checksum);
    out[9 + data.len] = @truncate(checksum >> 8);
    return out[0 .. data.len + 10];
}
pub const Frame = struct {
    kind: u8,
    sequence: u16,
    len: usize,
    data: [max_payload]u8 = @splat(0),
    pub fn payload(self: *const Frame) []const u8 {
        return self.data[0..self.len];
    }
};
pub const Parser = struct {
    bytes: [max_frame]u8 = undefined,
    used: usize = 0,
    pub fn feed(self: *Parser, byte: u8) !?Frame {
        if (self.used == 0 and byte != 0x5a) return null;
        if (self.used == 1 and byte != 0x38) {
            self.used = if (byte == 0x5a) 1 else 0;
            return null;
        }
        self.bytes[self.used] = byte;
        self.used += 1;
        if (self.used == 3 and byte != 1) {
            self.used = 0;
            return error.ProtocolVersion;
        }
        if (self.used < 8) return null;
        const len = read16(self.bytes[6..]);
        if (len > max_payload) {
            self.used = 0;
            return error.PacketTooLarge;
        }
        if (self.used != len + 10) return null;
        self.used = 0;
        if (read16(self.bytes[8 + len ..]) != crc(self.bytes[2 .. 8 + len])) return error.ChecksumMismatch;
        var result: Frame = .{ .kind = self.bytes[3], .sequence = read16(self.bytes[4..]), .len = len };
        @memcpy(result.data[0..len], self.bytes[8..][0..len]);
        return result;
    }
};

test "serial frame codec covers all byte values boundaries split input and corruption" {
    var data: [256]u8 = undefined;
    for (&data, 0..) |*byte, i| byte.* = @intCast(i);
    var buffer: [max_frame]u8 = undefined;
    const bytes = try encode(&buffer, send, 0x1234, &data);
    var parser: Parser = .{};
    var decoded: ?Frame = null;
    _ = try parser.feed(0xff);
    for (bytes) |byte| if (try parser.feed(byte)) |frame| {
        decoded = frame;
    };
    try std.testing.expectEqual(@as(u16, 0x1234), decoded.?.sequence);
    try std.testing.expectEqualSlices(u8, &data, decoded.?.payload());
    buffer[20] ^= 1;
    var failed = false;
    for (buffer) |byte| {
        _ = parser.feed(byte) catch |err| {
            try std.testing.expectEqual(error.ChecksumMismatch, err);
            failed = true;
            continue;
        };
    }
    try std.testing.expect(failed);
    const large: [257]u8 = @splat(0);
    try std.testing.expectError(error.PacketTooLarge, encode(&buffer, send, 0, &large));
    for ([_]u8{ 0x5a, 0x38, 1, 7, 0, 0, 1 }) |byte| _ = try parser.feed(byte);
    try std.testing.expectError(error.PacketTooLarge, parser.feed(1));
}
