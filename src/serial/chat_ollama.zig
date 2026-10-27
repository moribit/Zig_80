//! Incremental, bounded Ollama NDJSON decoding; no HTTP or serial I/O here.
const std = @import("std");

pub const max_line = 8192;
pub const Event = struct {
    text: []const u8,
    done: bool,
};

pub const Decoder = struct {
    line: [max_line]u8 = undefined,
    used: usize = 0,
    finished: bool = false,

    /// Returned event text belongs to `parsed` and is valid until deinit.
    pub fn feed(self: *Decoder, allocator: std.mem.Allocator, byte: u8) !?std.json.Parsed(std.json.Value) {
        if (self.finished) return error.DataAfterDone;
        if (byte != '\n') {
            if (self.used == self.line.len) return error.OllamaLineTooLong;
            self.line[self.used] = byte;
            self.used += 1;
            return null;
        }
        const line = std.mem.trim(u8, self.line[0..self.used], "\r \t");
        self.used = 0;
        if (line.len == 0) return null;
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
        errdefer parsed.deinit();
        const event = try getEvent(parsed.value);
        self.finished = event.done;
        return parsed;
    }

    pub fn finish(self: *const Decoder) !void {
        if (self.used != 0 or !self.finished) return error.IncompleteOllamaStream;
    }
};

pub fn getEvent(value: std.json.Value) !Event {
    if (value != .object) return error.InvalidOllamaEvent;
    if (value.object.get("error") != null) return error.OllamaError;
    const done = value.object.get("done") orelse return error.InvalidOllamaEvent;
    if (done != .bool) return error.InvalidOllamaEvent;
    const message = value.object.get("message") orelse return error.InvalidOllamaEvent;
    if (message != .object) return error.InvalidOllamaEvent;
    const content = message.object.get("content") orelse return error.InvalidOllamaEvent;
    if (content != .string) return error.InvalidOllamaEvent;
    return .{ .text = content.string, .done = done.bool };
}

test "Ollama text is available incrementally before done and split UTF-8 survives" {
    const stream = "{\"message\":{\"content\":\"HELLO あ\"},\"done\":false}\n{\"message\":{\"content\":\"!\"},\"done\":true}\n";
    var decoder: Decoder = .{};
    var events: usize = 0;
    for (stream) |byte| {
        if (try decoder.feed(std.testing.allocator, byte)) |parsed| {
            defer parsed.deinit();
            const event = try getEvent(parsed.value);
            if (events == 0) {
                try std.testing.expect(!event.done);
                try std.testing.expectEqualStrings("HELLO あ", event.text);
                try std.testing.expect(!decoder.finished);
            } else try std.testing.expect(event.done);
            events += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), events);
    try decoder.finish();
}

test "Ollama decoder rejects incomplete, unbounded and error streams" {
    var decoder: Decoder = .{};
    for ("{\"error\":\"model not found\"}") |b| _ = try decoder.feed(std.testing.allocator, b);
    try std.testing.expectError(error.OllamaError, decoder.feed(std.testing.allocator, '\n'));
    try std.testing.expectError(error.IncompleteOllamaStream, decoder.finish());
    for (0..max_line) |_| _ = try decoder.feed(std.testing.allocator, 'x');
    try std.testing.expectError(error.OllamaLineTooLong, decoder.feed(std.testing.allocator, 'x'));
}
