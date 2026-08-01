const std = @import("std");
const Cell = @import("cell.zig").Cell;
const Style = @import("style.zig").Style;

pub const Frame = struct {
    width: usize,
    height: usize,
    cells: []Cell,
    allocator: std.mem.Allocator,
    unicode: bool = true,

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
        for (x + 1..@min(x + width - 1, self.width)) |column| {
            self.addBorder(column, y, 0b0011, style);
            self.addBorder(column, y + height - 1, 0b0011, style);
        }
        for (y + 1..@min(y + height - 1, self.height)) |row| {
            self.addBorder(x, row, 0b1100, style);
            self.addBorder(x + width - 1, row, 0b1100, style);
        }
        self.addBorder(x, y, 0b1010, style);
        self.addBorder(x + width - 1, y, 0b1001, style);
        self.addBorder(x, y + height - 1, 0b0110, style);
        self.addBorder(x + width - 1, y + height - 1, 0b0101, style);
        if (title.len > 0 and width > 4) self.writeText(x + 2, y, title, style);
    }

    /// Adds line directions to an existing border cell, producing junctions
    /// when adjacent panes share an edge. Bits are left/right/up/down.
    fn addBorder(self: *Frame, x: usize, y: usize, directions: u4, style: Style) void {
        if (x >= self.width or y >= self.height) return;
        const combined = borderMask(self.get(x, y).codepoint) | directions;
        self.set(x, y, if (self.unicode) unicodeBorder(combined) else asciiBorder(combined), style);
    }
};

fn borderMask(codepoint: u21) u4 {
    return switch (codepoint) {
        '─', '-' => 0b0011,
        '│', '|' => 0b1100,
        '┌' => 0b1010,
        '┐' => 0b1001,
        '└' => 0b0110,
        '┘' => 0b0101,
        '┬' => 0b1011,
        '┴' => 0b0111,
        '├' => 0b1110,
        '┤' => 0b1101,
        '┼', '+' => 0b1111,
        else => 0,
    };
}

fn unicodeBorder(mask: u4) u21 {
    return switch (mask) {
        0b0011 => '─',
        0b1100 => '│',
        0b1010 => '┌',
        0b1001 => '┐',
        0b0110 => '└',
        0b0101 => '┘',
        0b1011 => '┬',
        0b0111 => '┴',
        0b1110 => '├',
        0b1101 => '┤',
        0b1111 => '┼',
        else => ' ',
    };
}

fn asciiBorder(mask: u4) u21 {
    if (mask == 0b0011) return '-';
    if (mask == 0b1100) return '|';
    return '+';
}
