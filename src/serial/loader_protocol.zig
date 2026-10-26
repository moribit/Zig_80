//! PC-8001 UART protocol. Independent of the Pico USB framing.
const std = @import("std");
const usb = @import("protocol.zig");
pub const app_min: u16 = 0xd000;
pub const app_end: u16 = 0xd800;
pub const stage1_address: u16 = 0xd800;
pub const stage1_size = 1280;
pub const stage0_address: u16 = 0xe400;
pub const max_data = 64;
pub const max_frame = max_data + 8;
pub const hello: u8 = 1;
pub const begin: u8 = 2;
pub const data: u8 = 3;
pub const verify: u8 = 4;
pub const exec: u8 = 5;
pub const abort: u8 = 6;
pub const echo: u8 = 8;
pub const info: u8 = 9;
pub const ack: u8 = 0x80;
pub const nak: u8 = 0x81;
pub const echo_reply: u8 = 0x88;
pub const crc = usb.crc;
pub const read16 = usb.read16;
pub fn put16(out: []u8, value: u16) void {
    out[0] = @truncate(value);
    out[1] = @truncate(value >> 8);
}
pub fn validRange(address: u16, size: usize, entry: u16) bool {
    const end = @as(u32, address) + size;
    return size > 0 and address >= app_min and end <= app_end and entry >= address and entry < end;
}
pub fn encode(out: *[max_frame]u8, kind: u8, sequence: u8, payload: []const u8) ![]const u8 {
    if (payload.len > max_data) return error.LoaderFrameTooLarge;
    out[0..6].* = .{ 0xa5, 0x5a, 1, kind, sequence, @intCast(payload.len) };
    @memcpy(out[6..][0..payload.len], payload);
    put16(out[6 + payload.len ..], crc(out[2 .. 6 + payload.len]));
    return out[0 .. payload.len + 8];
}
pub const Frame = struct {
    version: u8,
    kind: u8,
    sequence: u8,
    len: u8,
    bytes: [max_data]u8 = @splat(0),
    pub fn payload(self: *const Frame) []const u8 {
        return self.bytes[0..self.len];
    }
};
pub const Parser = struct {
    bytes: [max_frame]u8 = undefined,
    used: usize = 0,
    pub fn feed(self: *Parser, byte: u8) !?Frame {
        if (self.used == 0 and byte != 0xa5) return null;
        if (self.used == 1 and byte != 0x5a) {
            self.used = if (byte == 0xa5) 1 else 0;
            return null;
        }
        self.bytes[self.used] = byte;
        self.used += 1;
        if (self.used < 6) return null;
        const len = self.bytes[5];
        if (len > max_data) {
            self.used = 0;
            return error.LoaderFrameTooLarge;
        }
        if (self.used != len + 8) return null;
        self.used = 0;
        if (read16(self.bytes[6 + len ..]) != crc(self.bytes[2 .. 6 + len])) return error.LoaderCrcMismatch;
        var result: Frame = .{ .version = self.bytes[2], .kind = self.bytes[3], .sequence = self.bytes[4], .len = len };
        @memcpy(result.bytes[0..len], self.bytes[6..][0..len]);
        return result;
    }
};
test "loader CRC vector framing and conservative RAM bounds" {
    try std.testing.expectEqual(@as(u16, 0x29b1), crc("123456789"));
    var data_bytes: [64]u8 = undefined;
    for (&data_bytes, 0..) |*byte, i| byte.* = @intCast(i);
    var out: [max_frame]u8 = undefined;
    var parser: Parser = .{};
    const encoded = try encode(&out, data, 255, &data_bytes);
    for (encoded, 0..) |byte, i| {
        const decoded = try parser.feed(byte);
        if (i + 1 == encoded.len) try std.testing.expectEqualSlices(u8, &data_bytes, decoded.?.payload());
    }
    try std.testing.expect(validRange(0xd000, 2048, 0xd7ff));
    for ([_]u16{ 0, 0x8000, 0xcfff, 0xd800, 0xe400, 0xe600, 0xe800, 0xea66, 0xf300, 0xffff }) |address| try std.testing.expect(!validRange(address, 1, address));
    try std.testing.expect(!validRange(0xd000, 0, 0xd000));
    try std.testing.expect(!validRange(0xd000, 2049, 0xd000));
    try std.testing.expect(!validRange(0xd000, 1, 0xd001));
}
