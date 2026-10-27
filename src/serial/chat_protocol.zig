//! Building blocks for the experimental PC-8001 chat protocol.
//! This module does not enable a UART or constitute a complete chat bridge.
const std = @import("std");
const crc16 = @import("protocol.zig").crc;

pub const max_payload = 32;
pub const max_frame = max_payload + 7;
pub const Kind = enum(u8) { hello = 1, ready, prompt, text, done, err, ack, cancel };

pub const Frame = struct {
    kind: Kind,
    seq: u8,
    len: u8,
    payload: [max_payload]u8 = @splat(0),
};

/// CRC-16/CCITT-FALSE, little-endian; covers type through payload.
pub fn encode(out: *[max_frame]u8, kind: Kind, seq: u8, payload: []const u8) ![]const u8 {
    if (payload.len > max_payload) return error.FrameTooLarge;
    out[0..2].* = .{ 0xa5, 0x5a };
    out[2] = switch (kind) {
        .hello => 1,
        .ready => 2,
        .prompt => 3,
        .text => 4,
        .done => 5,
        .err => 6,
        .ack => 7,
        .cancel => 8,
    };
    out[3] = seq;
    out[4] = @intCast(payload.len);
    @memcpy(out[5..][0..payload.len], payload);
    const checksum = crc16(out[2 .. 5 + payload.len]);
    out[5 + payload.len] = @truncate(checksum);
    out[6 + payload.len] = @truncate(checksum >> 8);
    return out[0 .. 7 + payload.len];
}

pub const Parser = struct {
    bytes: [max_frame]u8 = undefined,
    used: usize = 0,

    /// Call on an inter-byte timeout before accepting a new frame.
    pub fn reset(self: *Parser) void {
        self.used = 0;
    }

    pub fn feed(self: *Parser, byte: u8) !?Frame {
        if (self.used == 0 and byte != 0xa5) return null;
        if (self.used == 1 and byte != 0x5a) {
            self.used = if (byte == 0xa5) 1 else 0;
            return null;
        }
        self.bytes[self.used] = byte;
        self.used += 1;
        if (self.used < 5) return null;
        const len = self.bytes[4];
        if (len > max_payload) {
            self.reset();
            return error.FrameTooLarge;
        }
        if (self.used < len + 7) return null;
        self.reset();
        const expected = @as(u16, self.bytes[5 + len]) | (@as(u16, self.bytes[6 + len]) << 8);
        if (crc16(self.bytes[2 .. 5 + len]) != expected) return error.CrcMismatch;
        const kind = std.enums.fromInt(Kind, self.bytes[2]) orelse return error.UnknownFrameType;
        var frame: Frame = .{ .kind = kind, .seq = self.bytes[3], .len = len };
        @memcpy(frame.payload[0..len], self.bytes[5..][0..len]);
        return frame;
    }
};

/// Deduplicates only an identical retransmission of the last accepted frame.
/// Out-of-order and same-sequence/different-content frames must not be applied.
pub const Receiver = struct {
    expected: u8 = 0,
    previous: ?Frame = null,
    pub const Result = enum { accepted, duplicate, rejected };
    pub fn accept(self: *Receiver, frame: Frame) Result {
        if (self.previous) |prev| {
            if (frame.seq == prev.seq) {
                if (frame.kind == prev.kind and frame.len == prev.len and std.mem.eql(u8, frame.payload[0..frame.len], prev.payload[0..prev.len])) return .duplicate;
                return .rejected;
            }
        }
        if (frame.seq != self.expected) return .rejected;
        self.previous = frame;
        self.expected +%= 1;
        return .accepted;
    }
};

/// One outstanding data frame per direction. Callers transmit returned frames
/// through the leased transport and call `timeout` only after the *whole*
/// frame has left the UART and the ACK deadline has elapsed.
pub const Sender = struct {
    sequence: u8 = 0,
    pending: ?Frame = null,
    retries_left: u8 = 0,

    pub fn begin(self: *Sender, kind: Kind, payload: []const u8, retries: u8) !Frame {
        if (self.pending != null) return error.FrameInFlight;
        if (kind == .ack) return error.InvalidDataFrame;
        if (payload.len > max_payload) return error.FrameTooLarge;
        var frame: Frame = .{ .kind = kind, .seq = self.sequence, .len = @intCast(payload.len) };
        @memcpy(frame.payload[0..payload.len], payload);
        self.pending = frame;
        self.retries_left = retries;
        return frame;
    }

    /// ACKs are unsequenced control messages. Their sequence identifies the
    /// acknowledged data frame; they are never acknowledged themselves.
    pub fn acknowledge(self: *Sender, reply: Frame) bool {
        if (reply.kind != .ack or reply.len != 0) return false;
        const pending = self.pending orelse return false;
        if (reply.seq != pending.seq) return false;
        self.pending = null;
        self.sequence +%= 1;
        return true;
    }

    pub fn timeout(self: *Sender) !Frame {
        const frame = self.pending orelse return error.NoFrameInFlight;
        if (self.retries_left == 0) return error.RetryLimit;
        self.retries_left -= 1;
        return frame;
    }
};

pub fn ack(sequence: u8) Frame {
    return .{ .kind = .ack, .seq = sequence, .len = 0 };
}

test "chat frame supports embedded sync and rejects corruption, oversized length and timeout" {
    var buf: [max_frame]u8 = undefined;
    var p: Parser = .{};
    const payload = [_]u8{ 0xa5, 0x5a, 0, 255 };
    const encoded = try encode(&buf, .text, 7, &payload);
    for (encoded, 0..) |b, i| {
        const frame = try p.feed(b);
        if (i + 1 == encoded.len) try std.testing.expectEqualSlices(u8, &payload, frame.?.payload[0..frame.?.len]);
    }
    buf[5] ^= 1;
    for (buf[0 .. encoded.len - 1]) |b| _ = try p.feed(b);
    try std.testing.expectError(error.CrcMismatch, p.feed(buf[encoded.len - 1]));
    for (&[_]u8{ 0xa5, 0x5a, 4, 0 }) |b| _ = try p.feed(b);
    try std.testing.expectError(error.FrameTooLarge, p.feed(33));
    _ = try p.feed(0xa5);
    p.reset();
    try std.testing.expectEqual(@as(?Frame, null), try p.feed(0x5a));
}

test "chat receiver rejects out of order and changed duplicate including sequence wrap" {
    var r: Receiver = .{ .expected = 255 };
    var f: Frame = .{ .kind = .text, .seq = 255, .len = 1 };
    f.payload[0] = 'A';
    try std.testing.expectEqual(Receiver.Result.accepted, r.accept(f));
    try std.testing.expectEqual(Receiver.Result.duplicate, r.accept(f));
    f.payload[0] = 'B';
    try std.testing.expectEqual(Receiver.Result.rejected, r.accept(f));
    f.seq = 1;
    try std.testing.expectEqual(Receiver.Result.rejected, r.accept(f));
    f.seq = 0;
    try std.testing.expectEqual(Receiver.Result.accepted, r.accept(f));
}

test "lost ACK retransmits identical frame without displaying text twice" {
    var sender: Sender = .{};
    var receiver: Receiver = .{};
    const first = try sender.begin(.text, "HELLO", 2);
    try std.testing.expectEqual(Receiver.Result.accepted, receiver.accept(first));
    try std.testing.expectError(error.FrameInFlight, sender.begin(.text, "NEXT", 1));
    try std.testing.expect(!sender.acknowledge(ack(1)));
    const retry = try sender.timeout();
    try std.testing.expectEqualDeep(first, retry);
    try std.testing.expectEqual(Receiver.Result.duplicate, receiver.accept(retry));
    try std.testing.expect(sender.acknowledge(ack(retry.seq)));
    try std.testing.expect(!sender.acknowledge(ack(retry.seq)));
    try std.testing.expectEqual(@as(u8, 1), (try sender.begin(.done, "", 0)).seq);
    try std.testing.expectError(error.RetryLimit, sender.timeout());
}
