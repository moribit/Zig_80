const std = @import("std");
const Cell = @import("cell.zig").Cell;
const Style = @import("style.zig").Style;

pub const Frame = struct {
    width: usize,
    height: usize,
    cells: []Cell,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Frame {
        const cells = try allocator.alloc(Cell, width * height);
        @memset(cells, .{});
        return .{ .width = width, .height = height, .cells = cells, .allocator = allocator };
    }

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.cells);
        self.* = undefined;
    }

    pub fn clear(self: *Frame) void {
        @memset(self.cells, .{});
    }

    pub fn set(self: *Frame, x: usize, y: usize, codepoint: u21, style: Style) void {
        if (x >= self.width or y >= self.height) return;
        self.cells[y * self.width + x] = .{ .codepoint = codepoint, .style = style };
    }

    pub fn get(self: *const Frame, x: usize, y: usize) Cell {
        if (x >= self.width or y >= self.height) return .{};
        return self.cells[y * self.width + x];
    }

    pub fn writeText(self: *Frame, x_start: usize, y: usize, text: []const u8, style: Style) void {
        if (y >= self.height) return;
        var view = std.unicode.Utf8View.init(text) catch return;
        var iterator = view.iterator();
        var x = x_start;
        while (iterator.nextCodepoint()) |codepoint| : (x += 1) {
            if (x >= self.width) break;
            self.set(x, y, codepoint, style);
        }
    }

    pub fn print(self: *Frame, x: usize, y: usize, style: Style, comptime fmt: []const u8, args: anytype) void {
        var buffer: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, fmt, args) catch return;
        self.writeText(x, y, text, style);
    }

    pub fn fillRect(self: *Frame, x: usize, y: usize, width: usize, height: usize, codepoint: u21, style: Style) void {
        for (y..@min(y + height, self.height)) |row|
            for (x..@min(x + width, self.width)) |column| self.set(column, row, codepoint, style);
    }

    pub fn box(self: *Frame, x: usize, y: usize, width: usize, height: usize, title: []const u8, style: Style) void {
        if (width < 2 or height < 2) return;
        for (x..@min(x + width, self.width)) |column| {
            self.set(column, y, '-', style);
            self.set(column, y + height - 1, '-', style);
        }
        for (y..@min(y + height, self.height)) |row| {
            self.set(x, row, '|', style);
            self.set(x + width - 1, row, '|', style);
        }
        self.set(x, y, '+', style);
        self.set(x + width - 1, y, '+', style);
        self.set(x, y + height - 1, '+', style);
        self.set(x + width - 1, y + height - 1, '+', style);
        if (title.len > 0 and width > 4) self.writeText(x + 2, y, title, style);
    }
};
