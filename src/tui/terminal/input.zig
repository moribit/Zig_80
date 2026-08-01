const std = @import("std");
const key = @import("key.zig");

pub const escape_timeout_ms: i64 = 30;
pub const DecodedInput = struct { event: key.KeyEvent, consumed: usize };

/// Allocation-free terminal input stream decoder. Incomplete UTF-8 and escape
/// sequences remain buffered across reads.
pub const InputDecoder = struct {
    buffer: [256]u8 = undefined,
    len: usize = 0,
    escape_pending_since: ?i64 = null,

    pub fn feed(self: *InputDecoder, bytes: []const u8) void {
        if (bytes.len > self.buffer.len) {
            // Drop the overlong prefix and retain a useful, bounded suffix.
            const tail = bytes[bytes.len - self.buffer.len ..];
            @memcpy(&self.buffer, tail);
            self.len = tail.len;
            self.escape_pending_since = null;
            return;
        }
        if (self.len + bytes.len > self.buffer.len) {
            // Existing input cannot be a valid bounded event. Recover at the
            // next feed boundary instead of overwriting memory.
            self.len = 0;
            self.escape_pending_since = null;
        }
        @memcpy(self.buffer[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }

    pub fn next(self: *InputDecoder, now_ms: i64) ?key.KeyEvent {
        while (self.len > 0) {
            if (self.buffer[0] == 0x1b and self.escape_pending_since != null and now_ms - self.escape_pending_since.? >= escape_timeout_ms) {
                self.consume(1);
                return .{ .code = .escape };
            }
            if (self.buffer[0] == 0x1b and self.len == 1) {
                if (self.escape_pending_since == null) self.escape_pending_since = now_ms;
                if (now_ms - self.escape_pending_since.? < escape_timeout_ms) return null;
                self.consume(1);
                return .{ .code = .escape };
            }
            const parsed = parseOne(self.buffer[0..self.len]);
            switch (parsed) {
                .incomplete => return null,
                .invalid => |consumed| {
                    self.consume(consumed);
                    continue;
                },
                .event => |decoded| {
                    self.consume(decoded.consumed);
                    return decoded.event;
                },
            }
        }
        return null;
    }

    fn consume(self: *InputDecoder, count: usize) void {
        const remaining = self.len - @min(count, self.len);
        std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[count..self.len]);
        self.len = remaining;
        self.escape_pending_since = null;
    }
};

const ParseResult = union(enum) { event: DecodedInput, incomplete, invalid: usize };

fn parseOne(bytes: []const u8) ParseResult {
    if (bytes.len == 0) return .incomplete;
    if (bytes[0] != 0x1b) return parsePlain(bytes);
    if (bytes.len == 1) return .incomplete;
    if (bytes[1] != '[' and bytes[1] != 'O') {
        const nested = parsePlain(bytes[1..]);
        return switch (nested) {
            .event => |decoded| blk: {
                var event = decoded.event;
                event.alt = true;
                break :blk .{ .event = .{ .event = event, .consumed = decoded.consumed + 1 } };
            },
            .incomplete => .incomplete,
            .invalid => |count| .{ .invalid = count + 1 },
        };
    }
    var end: usize = 2;
    while (end < bytes.len) : (end += 1) {
        const byte = bytes[end];
        if (byte >= 0x40 and byte <= 0x7e) {
            const consumed = end + 1;
            if (decode(bytes[0..consumed])) |event| return .{ .event = .{ .event = event, .consumed = consumed } };
            // A complete but unknown sequence is discarded; subsequent input
            // remains available to the caller.
            return .{ .invalid = consumed };
        }
    }
    return if (bytes.len == 256) .{ .invalid = 1 } else .incomplete;
}

fn parsePlain(bytes: []const u8) ParseResult {
    const length: usize = if (bytes[0] < 0x80) 1 else std.unicode.utf8ByteSequenceLength(bytes[0]) catch return .{ .invalid = 1 };
    if (bytes.len < length) return .incomplete;
    const event = decode(bytes[0..length]) orelse return .{ .invalid = 1 };
    return .{ .event = .{ .event = event, .consumed = length } };
}

pub fn decodeOne(bytes: []const u8) ?DecodedInput {
    return switch (parseOne(bytes)) {
        .event => |event| event,
        else => null,
    };
}

pub fn decode(bytes: []const u8) ?key.KeyEvent {
    if (bytes.len == 0) return null;
    if (bytes[0] == 0x1b) {
        if (bytes.len == 1) return .{ .code = .escape };
        if (bytes[1] != '[' and bytes[1] != 'O') {
            const nested = decode(bytes[1..]) orelse return null;
            return .{ .code = nested.code, .ctrl = nested.ctrl, .alt = true, .shift = nested.shift };
        }
        const sequence = bytes[1..];
        if (std.mem.eql(u8, sequence, "[A")) return .{ .code = .up };
        if (std.mem.eql(u8, sequence, "[B")) return .{ .code = .down };
        if (std.mem.eql(u8, sequence, "[C")) return .{ .code = .right };
        if (std.mem.eql(u8, sequence, "[D")) return .{ .code = .left };
        if (std.mem.eql(u8, sequence, "[H") or std.mem.eql(u8, sequence, "OH")) return .{ .code = .home };
        if (std.mem.eql(u8, sequence, "[F") or std.mem.eql(u8, sequence, "OF")) return .{ .code = .end };
        if (std.mem.eql(u8, sequence, "[3~")) return .{ .code = .delete };
        if (std.mem.eql(u8, sequence, "[5~")) return .{ .code = .page_up };
        if (std.mem.eql(u8, sequence, "[6~")) return .{ .code = .page_down };
        if (functionKey(sequence)) |number| return .{ .code = .{ .function = number } };
        return null;
    }
    const byte = bytes[0];
    if (byte == '\r' or byte == '\n') return .{ .code = .enter };
    if (byte == '\t') return .{ .code = .tab };
    if (byte == 0x7f or byte == 0x08) return .{ .code = .backspace };
    if (byte >= 1 and byte <= 26) return .{ .code = .{ .character = 'a' + byte - 1 }, .ctrl = true };
    if (byte < 0x80) return .{ .code = .{ .character = byte } };
    const length = std.unicode.utf8ByteSequenceLength(byte) catch return null;
    if (bytes.len < length) return null;
    const codepoint = std.unicode.utf8Decode(bytes[0..length]) catch return null;
    return .{ .code = .{ .character = codepoint } };
}

fn functionKey(sequence: []const u8) ?u8 {
    if (sequence.len == 2 and sequence[0] == 'O' and sequence[1] >= 'P' and sequence[1] <= 'S') return sequence[1] - 'P' + 1;
    const table = [_]struct { text: []const u8, number: u8 }{
        .{ .text = "[15~", .number = 5 }, .{ .text = "[17~", .number = 6 }, .{ .text = "[18~", .number = 7 },
        .{ .text = "[19~", .number = 8 }, .{ .text = "[20~", .number = 9 }, .{ .text = "[21~", .number = 10 },
    };
    for (table) |entry| if (std.mem.eql(u8, sequence, entry.text)) return entry.number;
    return null;
}
