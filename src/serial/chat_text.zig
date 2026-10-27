//! Bounded incremental ASCII conversion for the experimental chat bridge.
const std = @import("std");

pub const Normalizer = struct {
    pending: [4]u8 = undefined,
    used: u8 = 0,
    needed: u8 = 0,
    remaining: usize = 160,

    /// Returns at most one display character per input byte. Non-ASCII UTF-8
    /// code points are replaced by '?'; malformed continuations fail closed.
    /// Input may be split at arbitrary byte boundaries.
    pub fn feed(self: *Normalizer, byte: u8) !?u8 {
        if (self.remaining == 0) return null;
        if (self.needed != 0) {
            if (byte & 0xc0 == 0x80) {
                self.pending[self.used] = byte;
                self.used += 1;
                if (self.used == self.needed) {
                    _ = std.unicode.utf8Decode(self.pending[0..self.used]) catch {
                        self.needed = 0;
                        self.used = 0;
                        return error.InvalidUtf8;
                    };
                    self.needed = 0;
                    self.used = 0;
                    return self.emit('?');
                }
                return null;
            }
            self.needed = 0;
            self.used = 0;
            return error.InvalidUtf8;
        }
        if (byte < 0x80) {
            return self.emit(if (byte == '\n' or (byte >= 0x20 and byte <= 0x7e)) byte else ' ');
        }
        self.needed = if (byte >= 0xc2 and byte <= 0xdf) 2 else if (byte >= 0xe0 and byte <= 0xef) 3 else if (byte >= 0xf0 and byte <= 0xf4) 4 else return self.emit('?');
        self.pending[0] = byte;
        self.used = 1;
        return null;
    }
    fn emit(self: *Normalizer, c: u8) u8 {
        self.remaining -= 1;
        return std.ascii.toUpper(c);
    }
    pub fn finish(self: *Normalizer) ?u8 {
        if (self.needed == 0 or self.remaining == 0) return null;
        self.needed = 0;
        self.used = 0;
        return self.emit('?');
    }
};

test "incremental text normalizes UTF-8 fragments and bounds output" {
    var n: Normalizer = .{ .remaining = 4 };
    try std.testing.expectEqual(@as(?u8, 'A'), try n.feed('A'));
    try std.testing.expectEqual(@as(?u8, null), try n.feed(0xe3));
    try std.testing.expectEqual(@as(?u8, null), try n.feed(0x81));
    try std.testing.expectEqual(@as(?u8, '?'), try n.feed(0x82));
    try std.testing.expectEqual(@as(?u8, ' '), try n.feed(0));
    try std.testing.expectEqual(@as(?u8, '\n'), try n.feed('\n'));
    try std.testing.expectEqual(@as(?u8, null), try n.feed('Z'));
}

test "invalid and truncated UTF-8 are handled without exceeding the limit" {
    var n: Normalizer = .{};
    _ = try n.feed(0xe0);
    _ = try n.feed(0x80);
    try std.testing.expectError(error.InvalidUtf8, n.feed(0x80));
    _ = try n.feed(0xe3);
    try std.testing.expectError(error.InvalidUtf8, n.feed('A'));
    _ = try n.feed(0xe3);
    try std.testing.expectEqual(@as(?u8, '?'), n.finish());
    try std.testing.expectEqual(@as(?u8, null), n.finish());
}
