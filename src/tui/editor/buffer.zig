const std = @import("std");

pub const SourceBuffer = struct {
    const HistoryEntry = struct { text: []u8, cursor: usize };
    const history_limit = 64;

    bytes: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,
    cursor: usize = 0,
    scroll_x: usize = 0,
    scroll_y: usize = 0,
    dirty: bool = false,
    revision: u64 = 0,
    selection_anchor: ?usize = null,
    undo_stack: std.ArrayList(HistoryEntry) = .empty,
    redo_stack: std.ArrayList(HistoryEntry) = .empty,

    pub fn init(allocator: std.mem.Allocator, initial_text: []const u8) !SourceBuffer {
        if (!std.unicode.utf8ValidateSlice(initial_text)) return error.InvalidUtf8;
        var self = SourceBuffer{ .allocator = allocator };
        try self.bytes.appendSlice(allocator, initial_text);
        return self;
    }

    pub fn deinit(self: *SourceBuffer) void {
        self.clearHistory(&self.undo_stack);
        self.clearHistory(&self.redo_stack);
        self.undo_stack.deinit(self.allocator);
        self.redo_stack.deinit(self.allocator);
        self.bytes.deinit(self.allocator);
    }

    pub fn text(self: *const SourceBuffer) []const u8 {
        return self.bytes.items;
    }

    pub fn insert(self: *SourceBuffer, codepoint: u21) !void {
        try self.checkpoint();
        self.deleteSelectionRaw();
        var encoded: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(codepoint, &encoded);
        try self.bytes.insertSlice(self.allocator, self.cursor, encoded[0..len]);
        self.cursor += len;
        self.changed();
    }

    pub fn newline(self: *SourceBuffer) !void {
        try self.checkpoint();
        self.deleteSelectionRaw();
        const start = lineStart(self.bytes.items, self.cursor);
        var indent_end = start;
        while (indent_end < self.bytes.items.len and (self.bytes.items[indent_end] == ' ' or self.bytes.items[indent_end] == '\t')) : (indent_end += 1) {}
        var indentation: []const u8 = self.bytes.items[start..@min(indent_end, self.cursor)];
        const before = std.mem.trimEnd(u8, self.bytes.items[start..self.cursor], " \t");
        const label_indent = before.len > 0 and before[before.len - 1] == ':' and indentation.len == 0;
        try self.bytes.insert(self.allocator, self.cursor, '\n');
        self.cursor += 1;
        if (label_indent) indentation = "    ";
        try self.bytes.insertSlice(self.allocator, self.cursor, indentation);
        self.cursor += indentation.len;
        self.changed();
    }

    pub fn backspace(self: *SourceBuffer) void {
        if (self.hasSelection()) {
            self.checkpoint() catch return;
            self.deleteSelectionRaw();
            self.changed();
            return;
        }
        if (self.cursor == 0) return;
        self.checkpoint() catch return;
        const start = previousBoundary(self.bytes.items, self.cursor);
        self.bytes.replaceRangeAssumeCapacity(start, self.cursor - start, "");
        self.cursor = start;
        self.changed();
    }

    pub fn delete(self: *SourceBuffer) void {
        if (self.hasSelection()) {
            self.checkpoint() catch return;
            self.deleteSelectionRaw();
            self.changed();
            return;
        }
        if (self.cursor >= self.bytes.items.len) return;
        self.checkpoint() catch return;
        const end = nextBoundary(self.bytes.items, self.cursor);
        self.bytes.replaceRangeAssumeCapacity(self.cursor, end - self.cursor, "");
        self.changed();
    }

    pub fn moveLeft(self: *SourceBuffer) void {
        if (self.cursor > 0) self.cursor = previousBoundary(self.bytes.items, self.cursor);
    }

    pub fn move(self: *SourceBuffer, direction: enum { up, down, left, right, home, end }, selecting: bool) void {
        if (selecting) {
            if (self.selection_anchor == null) self.selection_anchor = self.cursor;
        } else self.selection_anchor = null;
        switch (direction) {
            .up => self.moveUp(),
            .down => self.moveDown(),
            .left => self.moveLeft(),
            .right => self.moveRight(),
            .home => self.moveHome(),
            .end => self.moveEnd(),
        }
    }

    pub fn selectionRange(self: *const SourceBuffer) ?struct { start: usize, end: usize } {
        const anchor = self.selection_anchor orelse return null;
        if (anchor == self.cursor) return null;
        return .{ .start = @min(anchor, self.cursor), .end = @max(anchor, self.cursor) };
    }

    pub fn indent(self: *SourceBuffer, remove: bool) !void {
        try self.checkpoint();
        const range = self.selectionRange();
        const first = lineStart(self.bytes.items, if (range) |r| r.start else self.cursor);
        const last_position = if (range) |r| r.end else self.cursor;
        var position = first;
        var cursor_delta: isize = 0;
        while (position <= self.bytes.items.len) {
            if (remove) {
                var count: usize = 0;
                while (count < 4 and position + count < self.bytes.items.len and self.bytes.items[position + count] == ' ') : (count += 1) {}
                if (count == 0 and position < self.bytes.items.len and self.bytes.items[position] == '\t') count = 1;
                if (count > 0) {
                    self.bytes.replaceRangeAssumeCapacity(position, count, "");
                    if (position < self.cursor) cursor_delta -= @intCast(@min(count, self.cursor - position));
                }
            } else {
                try self.bytes.insertSlice(self.allocator, position, "    ");
                if (position <= self.cursor) cursor_delta += 4;
                position += 4;
            }
            const end = lineEnd(self.bytes.items, position);
            if (end >= last_position + @as(usize, @intCast(@max(cursor_delta, 0)))) break;
            if (end >= self.bytes.items.len) break;
            position = end + 1;
        }
        self.cursor = @intCast(@as(isize, @intCast(self.cursor)) + cursor_delta);
        self.selection_anchor = null;
        self.changed();
    }

    pub fn replaceRange(self: *SourceBuffer, start: usize, end: usize, replacement: []const u8) !void {
        try self.checkpoint();
        try self.bytes.replaceRange(self.allocator, start, end - start, replacement);
        self.cursor = start + replacement.len;
        self.selection_anchor = null;
        self.changed();
    }

    pub fn replaceAllIdentifier(self: *SourceBuffer, old: []const u8, new: []const u8) !usize {
        try self.checkpoint();
        var index: usize = 0;
        var count: usize = 0;
        while (index < self.bytes.items.len) {
            if (self.bytes.items[index] == ';') {
                index = (std.mem.indexOfScalarPos(u8, self.bytes.items, index, '\n') orelse self.bytes.items.len);
                continue;
            }
            if (self.bytes.items[index] == '"' or self.bytes.items[index] == '\'') {
                const quote = self.bytes.items[index];
                index += 1;
                while (index < self.bytes.items.len and self.bytes.items[index] != quote) : (index += 1) {
                    if (self.bytes.items[index] == '\\' and index + 1 < self.bytes.items.len) index += 1;
                }
                if (index < self.bytes.items.len) index += 1;
                continue;
            }
            if (index + old.len > self.bytes.items.len or !std.ascii.eqlIgnoreCase(self.bytes.items[index..][0..old.len], old)) {
                index += 1;
                continue;
            }
            const found = index;
            const left_ok = found == 0 or !isIdentifier(self.bytes.items[found - 1]);
            const right = found + old.len;
            const right_ok = right == self.bytes.items.len or !isIdentifier(self.bytes.items[right]);
            if (left_ok and right_ok) {
                try self.bytes.replaceRange(self.allocator, found, old.len, new);
                if (found < self.cursor) {
                    const adjusted = @as(isize, @intCast(self.cursor)) + @as(isize, @intCast(new.len)) - @as(isize, @intCast(old.len));
                    self.cursor = @intCast(@max(adjusted, 0));
                }
                index = found + new.len;
                count += 1;
            } else index += 1;
        }
        if (count == 0) {
            self.discardLastUndo();
            return 0;
        }
        self.selection_anchor = null;
        self.changed();
        return count;
    }

    pub fn undo(self: *SourceBuffer) !bool {
        return self.restore(&self.undo_stack, &self.redo_stack);
    }
    pub fn redo(self: *SourceBuffer) !bool {
        return self.restore(&self.redo_stack, &self.undo_stack);
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
        self.selection_anchor = null;
        return true;
    }

    pub fn ensureVisible(self: *SourceBuffer, width: usize, height: usize) void {
        const position = self.lineAndColumn();
        if (position.line < self.scroll_y) self.scroll_y = position.line;
        if (height > 0 and position.line >= self.scroll_y + height) self.scroll_y = position.line - height + 1;
        if (position.column < self.scroll_x) self.scroll_x = position.column;
        if (width > 0 and position.column >= self.scroll_x + width) self.scroll_x = position.column - width + 1;
    }

    pub fn absoluteLineStart(self: *const SourceBuffer, line: usize) ?usize {
        var wanted = line;
        var position: usize = 0;
        while (wanted > 0 and position < self.bytes.items.len) : (position += 1) {
            if (self.bytes.items[position] == '\n') wanted -= 1;
        }
        return if (wanted == 0) position else null;
    }

    fn checkpoint(self: *SourceBuffer) !void {
        if (self.undo_stack.items.len >= history_limit) {
            self.allocator.free(self.undo_stack.items[0].text);
            _ = self.undo_stack.orderedRemove(0);
        }
        try self.undo_stack.append(self.allocator, .{ .text = try self.allocator.dupe(u8, self.bytes.items), .cursor = self.cursor });
        self.clearHistory(&self.redo_stack);
    }

    fn restore(self: *SourceBuffer, from: *std.ArrayList(HistoryEntry), to: *std.ArrayList(HistoryEntry)) !bool {
        if (from.items.len == 0) return false;
        try to.append(self.allocator, .{ .text = try self.allocator.dupe(u8, self.bytes.items), .cursor = self.cursor });
        const entry = from.pop().?;
        self.bytes.clearRetainingCapacity();
        try self.bytes.appendSlice(self.allocator, entry.text);
        self.cursor = @min(entry.cursor, self.bytes.items.len);
        self.allocator.free(entry.text);
        self.selection_anchor = null;
        self.changed();
        return true;
    }

    fn clearHistory(self: *SourceBuffer, stack: *std.ArrayList(HistoryEntry)) void {
        for (stack.items) |entry| self.allocator.free(entry.text);
        stack.clearRetainingCapacity();
    }

    fn discardLastUndo(self: *SourceBuffer) void {
        if (self.undo_stack.pop()) |entry| self.allocator.free(entry.text);
    }

    fn hasSelection(self: *const SourceBuffer) bool {
        return self.selectionRange() != null;
    }
    fn deleteSelectionRaw(self: *SourceBuffer) void {
        const range = self.selectionRange() orelse return;
        self.bytes.replaceRangeAssumeCapacity(range.start, range.end - range.start, "");
        self.cursor = range.start;
        self.selection_anchor = null;
    }
    fn changed(self: *SourceBuffer) void {
        self.dirty = true;
        self.revision +%= 1;
    }
};

fn isIdentifier(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

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
