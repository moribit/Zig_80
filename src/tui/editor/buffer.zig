const std = @import("std");

pub const SourceBuffer = struct {
    bytes: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,
    cursor: usize = 0,
    scroll_x: usize = 0,
    scroll_y: usize = 0,
    dirty: bool = false,

    pub fn init(allocator: std.mem.Allocator, initial_text: []const u8) !SourceBuffer {
        if (!std.unicode.utf8ValidateSlice(initial_text)) return error.InvalidUtf8;
        var self = SourceBuffer{ .allocator = allocator };
        try self.bytes.appendSlice(allocator, initial_text);
        return self;
    }

    pub fn deinit(self: *SourceBuffer) void {
        self.bytes.deinit(self.allocator);
    }

    pub fn text(self: *const SourceBuffer) []const u8 {
        return self.bytes.items;
    }

    pub fn insert(self: *SourceBuffer, codepoint: u21) !void {
        var encoded: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(codepoint, &encoded);
        try self.bytes.insertSlice(self.allocator, self.cursor, encoded[0..len]);
        self.cursor += len;
        self.dirty = true;
    }

    pub fn newline(self: *SourceBuffer) !void {
        try self.insert('\n');
    }

    pub fn backspace(self: *SourceBuffer) void {
        if (self.cursor == 0) return;
        const start = previousBoundary(self.bytes.items, self.cursor);
        self.bytes.replaceRangeAssumeCapacity(start, self.cursor - start, "");
        self.cursor = start;
        self.dirty = true;
    }

    pub fn delete(self: *SourceBuffer) void {
        if (self.cursor >= self.bytes.items.len) return;
        const end = nextBoundary(self.bytes.items, self.cursor);
        self.bytes.replaceRangeAssumeCapacity(self.cursor, end - self.cursor, "");
        self.dirty = true;
    }

    pub fn moveLeft(self: *SourceBuffer) void {
        if (self.cursor > 0) self.cursor = previousBoundary(self.bytes.items, self.cursor);
    }

    pub fn moveRight(self: *SourceBuffer) void {
        if (self.cursor < self.bytes.items.len) self.cursor = nextBoundary(self.bytes.items, self.cursor);
    }

    pub fn moveHome(self: *SourceBuffer) void {
        self.cursor = lineStart(self.bytes.items, self.cursor);
    }

    pub fn moveEnd(self: *SourceBuffer) void {
        self.cursor = lineEnd(self.bytes.items, self.cursor);
    }

    pub fn moveUp(self: *SourceBuffer) void {
        const start = lineStart(self.bytes.items, self.cursor);
        if (start == 0) return;
        const column = self.cursor - start;
        const previous_end = start - 1;
        const previous_start = lineStart(self.bytes.items, previous_end);
        self.cursor = validBoundaryAtOrBefore(self.bytes.items, previous_start + @min(column, previous_end - previous_start));
    }

    pub fn moveDown(self: *SourceBuffer) void {
        const start = lineStart(self.bytes.items, self.cursor);
        const end = lineEnd(self.bytes.items, self.cursor);
        if (end >= self.bytes.items.len) return;
        const column = self.cursor - start;
        const next_start = end + 1;
        const next_end = lineEnd(self.bytes.items, next_start);
        self.cursor = validBoundaryAtOrBefore(self.bytes.items, next_start + @min(column, next_end - next_start));
    }

    pub fn lineAndColumn(self: *const SourceBuffer) struct { line: usize, column: usize } {
        var line: usize = 0;
        var start: usize = 0;
        for (self.bytes.items[0..self.cursor], 0..) |byte, i| if (byte == '\n') {
            line += 1;
            start = i + 1;
        };
        return .{ .line = line, .column = self.cursor - start };
    }

    pub fn lineSlice(self: *const SourceBuffer, wanted: usize) ?[]const u8 {
        var iterator = std.mem.splitScalar(u8, self.bytes.items, '\n');
        var index: usize = 0;
        while (iterator.next()) |line| : (index += 1) if (index == wanted) return line;
        return null;
    }

    pub fn lineCount(self: *const SourceBuffer) usize {
        var count: usize = 1;
        for (self.bytes.items) |byte| if (byte == '\n') {
            count += 1;
        };
        return count;
    }

    pub fn goToLine(self: *SourceBuffer, wanted: usize) bool {
        var line: usize = 0;
        var position: usize = 0;
        while (line < wanted and position < self.bytes.items.len) : (position += 1) {
            if (self.bytes.items[position] == '\n') line += 1;
        }
        if (line != wanted) return false;
        self.cursor = position;
        return true;
    }

    pub fn ensureVisible(self: *SourceBuffer, width: usize, height: usize) void {
        const position = self.lineAndColumn();
        if (position.line < self.scroll_y) self.scroll_y = position.line;
        if (height > 0 and position.line >= self.scroll_y + height) self.scroll_y = position.line - height + 1;
        if (position.column < self.scroll_x) self.scroll_x = position.column;
        if (width > 0 and position.column >= self.scroll_x + width) self.scroll_x = position.column - width + 1;
    }
};

fn lineStart(text: []const u8, position: usize) usize {
    var i = @min(position, text.len);
    while (i > 0 and text[i - 1] != '\n') : (i -= 1) {}
    return i;
}
fn lineEnd(text: []const u8, position: usize) usize {
    var i = @min(position, text.len);
    while (i < text.len and text[i] != '\n') : (i += 1) {}
    return i;
}
fn previousBoundary(text: []const u8, position: usize) usize {
    var i = position - 1;
    while (i > 0 and text[i] & 0xc0 == 0x80) : (i -= 1) {}
    return i;
}
fn nextBoundary(text: []const u8, position: usize) usize {
    var i = position + 1;
    while (i < text.len and text[i] & 0xc0 == 0x80) : (i += 1) {}
    return i;
}
fn validBoundaryAtOrBefore(text: []const u8, position: usize) usize {
    var i = @min(position, text.len);
    while (i > 0 and i < text.len and text[i] & 0xc0 == 0x80) : (i -= 1) {}
    return i;
}
