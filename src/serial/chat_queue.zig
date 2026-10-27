//! Bounded response chunking. The caller owns the clock and ACK/retry I/O.
const std = @import("std");
const max_payload = @import("chat_protocol.zig").max_payload;

pub const Queue = struct {
    bytes: [160]u8 = undefined,
    head: usize = 0,
    len: usize = 0,
    first_us: ?u64 = null,
    flush_us: u64 = 200_000,
    chunk_size: u8 = max_payload,

    /// The producer must stop reading HTTP when this returns Full. Never
    /// overwrite bytes that have not been sent and acknowledged.
    pub fn push(self: *Queue, byte: u8, now: u64) !void {
        if (self.len == self.bytes.len) return error.Full;
        self.bytes[(self.head + self.len) % self.bytes.len] = byte;
        self.len += 1;
        if (self.first_us == null) self.first_us = now;
    }

    /// A frame becomes ready when full, on a newline, after the flush delay,
    /// or when the producer has finished. Peek does not consume: consume only
    /// after ACK, so an identical frame can be resent after an ACK loss.
    pub fn peek(self: *const Queue, now: u64, done: bool, out: *[max_payload]u8) ?[]const u8 {
        std.debug.assert(self.chunk_size >= 1 and self.chunk_size <= max_payload);
        if (self.len == 0) return null;
        const count = @min(self.len, self.chunk_size);
        var boundary: usize = count;
        var newline = false;
        for (0..count) |i| {
            out[i] = self.bytes[(self.head + i) % self.bytes.len];
            if (out[i] == '\n') {
                boundary = i + 1;
                newline = true;
                break;
            }
        }
        if (!done and !newline and count < self.chunk_size and now -| self.first_us.? < self.flush_us) return null;
        return out[0..boundary];
    }

    pub fn consume(self: *Queue, count: usize, now: u64) !void {
        if (count == 0 or count > self.len or count > max_payload) return error.InvalidConsume;
        self.head = (self.head + count) % self.bytes.len;
        self.len -= count;
        // Conservatively flush remaining data immediately: some of it may
        // have waited since before the acknowledged frame was sent.
        self.first_us = if (self.len == 0) null else now -| self.flush_us;
    }
};

test "flush timer sends generated text before done, retaining bytes until ACK" {
    var q: Queue = .{};
    for ("HELLO") |b| try q.push(b, 1_000);
    var buffer: [max_payload]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), q.peek(100_000, false, &buffer));
    try std.testing.expectEqualStrings("HELLO", q.peek(201_000, false, &buffer).?);
    try std.testing.expectEqualStrings("HELLO", q.peek(300_000, false, &buffer).?);
    try q.consume(5, 300_000);
    try std.testing.expectEqual(@as(usize, 0), q.len);
    for ("ONE\nTWO") |b| try q.push(b, 400_000);
    try std.testing.expectEqualStrings("ONE\n", q.peek(400_000, false, &buffer).?);
    try q.consume(4, 400_000);
    try std.testing.expectEqualStrings("TWO", q.peek(400_000, false, &buffer).?);
}

test "small text chunks flush at their own limit and preserve order until ACK" {
    var q: Queue = .{ .chunk_size = 8, .flush_us = 100_000 };
    for ("ABCDEFGHIJKLMNOPQRST") |b| try q.push(b, 1_000);
    var buffer: [max_payload]u8 = undefined;
    try std.testing.expectEqualStrings("ABCDEFGH", q.peek(1_000, false, &buffer).?);
    try q.consume(8, 200_000);
    try std.testing.expectEqualStrings("IJKLMNOP", q.peek(200_000, false, &buffer).?);
    try q.consume(8, 300_000);
    try std.testing.expectEqualStrings("QRST", q.peek(300_000, false, &buffer).?);
}

test "queue applies bounded backpressure and preserves wraparound order" {
    var q: Queue = .{};
    for (0..160) |i| try q.push(@intCast(i + 32), 0);
    try std.testing.expectError(error.Full, q.push(1, 0));
    var buffer: [max_payload]u8 = undefined;
    try std.testing.expectEqualSlices(u8, q.bytes[0..32], q.peek(0, false, &buffer).?);
    try q.consume(32, 0);
    for (0..32) |i| try q.push(@intCast(i), 1);
    try std.testing.expectEqual(@as(usize, 160), q.len);
    try std.testing.expectError(error.InvalidConsume, q.consume(33, 1));
}

test "mock model stream reaches receiver before model done and lost ACK is deduplicated" {
    const wire = @import("chat_protocol.zig");
    const ollama = @import("chat_ollama.zig");
    const text = @import("chat_text.zig");
    var decoder: ollama.Decoder = .{};
    var normalizer: text.Normalizer = .{};
    var queue: Queue = .{};
    var sender: wire.Sender = .{};
    var receiver: wire.Receiver = .{};
    var output: [32]u8 = undefined;
    var received: [32]u8 = undefined;
    var received_len: usize = 0;
    const first = "{\"message\":{\"content\":\"HELLO!\"},\"done\":false}\n";
    for (first) |b| {
        if (try decoder.feed(std.testing.allocator, b)) |parsed| {
            defer parsed.deinit();
            const event = try ollama.getEvent(parsed.value);
            for (event.text) |c| if (try normalizer.feed(c)) |ascii| try queue.push(ascii, 1_000);
        }
    }
    const payload = queue.peek(201_000, decoder.finished, &output).?;
    const frame = try sender.begin(.text, payload, 1);
    try std.testing.expectEqual(wire.Receiver.Result.accepted, receiver.accept(frame));
    @memcpy(received[0..frame.len], frame.payload[0..frame.len]);
    received_len += frame.len;
    try std.testing.expect(!decoder.finished);
    const retry = try sender.timeout();
    try std.testing.expectEqual(wire.Receiver.Result.duplicate, receiver.accept(retry));
    try std.testing.expect(sender.acknowledge(wire.ack(retry.seq)));
    try queue.consume(frame.len, 202_000);
    const last = "{\"message\":{\"content\":\"\"},\"done\":true}\n";
    for (last) |b| if (try decoder.feed(std.testing.allocator, b)) |parsed| parsed.deinit();
    try decoder.finish();
    try std.testing.expectEqualStrings("HELLO!", received[0..received_len]);
}
