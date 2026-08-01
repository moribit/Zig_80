const std = @import("std");
const key = @import("key.zig");

pub const DecodedInput = struct { event: key.KeyEvent, consumed: usize };

pub fn decodeOne(bytes: []const u8) ?DecodedInput {
    if (bytes.len == 0) return null;
    if (bytes[0] != 0x1b) {
        const consumed: usize = if (bytes[0] < 0x80) 1 else std.unicode.utf8ByteSequenceLength(bytes[0]) catch return null;
        if (bytes.len < consumed) return null;
        return .{ .event = decode(bytes[0..consumed]) orelse return null, .consumed = consumed };
    }
    if (bytes.len == 1) return .{ .event = .{ .code = .escape }, .consumed = 1 };
    if (bytes[1] != '[' and bytes[1] != 'O') {
        const nested = decodeOne(bytes[1..]) orelse return null;
        var event = nested.event;
        event.alt = true;
        return .{ .event = event, .consumed = nested.consumed + 1 };
    }
    var end: usize = 2;
    while (end < bytes.len) : (end += 1) {
        const byte = bytes[end];
        if ((byte >= 'A' and byte <= 'Z') or byte == '~') {
            const consumed = end + 1;
            return .{ .event = decode(bytes[0..consumed]) orelse return null, .consumed = consumed };
        }
    }
    return null;
}

pub fn decode(bytes: []const u8) ?key.KeyEvent {
    if (bytes.len == 0) return null;
    if (bytes[0] == 0x1b) {
        if (bytes.len == 1) return .{ .code = .escape };
        if (bytes[1] != '[' and bytes[1] != 'O') {
            const nested = decode(bytes[1..]) orelse return .{ .code = .escape };
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
