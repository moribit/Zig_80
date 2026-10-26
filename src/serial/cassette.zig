//! Original PC-8001 machine-code CMT records and offline 600-baud FSK WAV.
//! Independent implementation of the documented format, no external runtime tool.
const std = @import("std");
pub const sample_rate = 48_000;
pub const samples_per_bit = 80;
pub const frame_bits = 12; // start, 8 data LSB first, three mark/stop bits.
pub fn writeCmt(out: *std.Io.Writer, address: u16, data: []const u8) !void {
    if (data.len == 0 or @as(usize, address) + data.len > 65536) return error.InvalidCassetteRange;
    const high: u8 = @truncate(address >> 8);
    const low: u8 = @truncate(address);
    try out.writeAll(&.{ 0x3a, high, low, 0 -% high -% low });
    var offset: usize = 0;
    while (offset < data.len) {
        const count = @min(255, data.len - offset);
        var sum: u8 = @intCast(count);
        try out.writeAll(&.{ 0x3a, @intCast(count) });
        for (data[offset..][0..count]) |byte| {
            try out.writeByte(byte);
            sum +%= byte;
        }
        try out.writeByte(0 -% sum);
        offset += count;
    }
    try out.writeAll(&.{ 0x3a, 0, 0 });
}
fn u32le(out: *std.Io.Writer, number: u32) !void {
    try out.writeAll(&.{ @truncate(number), @truncate(number >> 8), @truncate(number >> 16), @truncate(number >> 24) });
}
fn silence(out: *std.Io.Writer, samples: usize) !void {
    const zeros: [4096]u8 = @splat(0);
    var bytes = samples * 2;
    while (bytes > 0) {
        const count = @min(bytes, zeros.len);
        try out.writeAll(zeros[0..count]);
        bytes -= count;
    }
}
fn bit(out: *std.Io.Writer, high: bool) !void {
    var pcm: [samples_per_bit * 2]u8 = undefined;
    const period: usize = if (high) 20 else 40; // 2400/1200 Hz at 48000 Hz.
    for (0..samples_per_bit) |i| {
        const phase = 2 * std.math.pi * @as(f64, @floatFromInt(i % period)) / @as(f64, @floatFromInt(period));
        const value: i16 = @intFromFloat(@round(8192 * @sin(phase)));
        const raw: u16 = @bitCast(value);
        pcm[i * 2] = @truncate(raw);
        pcm[i * 2 + 1] = @truncate(raw >> 8);
    }
    try out.writeAll(&pcm);
}
pub fn wavSamples(cmt_len: usize) usize {
    return 295_200 + cmt_len * frame_bits * samples_per_bit;
}
pub fn writeWav(out: *std.Io.Writer, cmt: []const u8) !void {
    if (cmt.len > 70_000) return error.CassetteImageTooLarge;
    const data_bytes: u32 = @intCast(wavSamples(cmt.len) * 2);
    try out.writeAll("RIFF");
    try u32le(out, data_bytes + 36);
    try out.writeAll("WAVEfmt ");
    try u32le(out, 16);
    try out.writeAll(&.{ 1, 0, 1, 0 }); // PCM mono
    try u32le(out, sample_rate);
    try u32le(out, sample_rate * 2);
    try out.writeAll(&.{ 2, 0, 16, 0 });
    try out.writeAll("data");
    try u32le(out, data_bytes);
    try silence(out, 96_000); // 2 seconds blank, then 3.5 seconds mark leader.
    for (0..2100) |_| try bit(out, true);
    for (cmt) |byte| {
        try bit(out, false);
        for (0..8) |i| try bit(out, byte & (@as(u8, 1) << @as(u3, @intCast(i))) != 0);
        for (0..3) |_| try bit(out, true);
    }
    for (0..30) |_| try bit(out, true); // 50 ms tail carrier, 600 ms silence.
    try silence(out, 28_800);
}
test "CMT known-format header block checksums terminator and address wrap" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try writeCmt(&out.writer, 0xd000, &.{ 0xc3, 0x0c, 0xd0 });
    try std.testing.expectEqualSlices(u8, &.{ 0x3a, 0xd0, 0, 0x30, 0x3a, 3, 0xc3, 0x0c, 0xd0, 0x5e, 0x3a, 0, 0 }, out.written());
    try std.testing.expectError(error.InvalidCassetteRange, writeCmt(&out.writer, 0xffff, &.{ 1, 2 }));
    try std.testing.expectError(error.InvalidCassetteRange, writeCmt(&out.writer, 0xe300, ""));
}
