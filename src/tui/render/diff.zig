const std = @import("std");
const Frame = @import("frame.zig").Frame;
const Style = @import("style.zig").Style;
const ansi = @import("../terminal/ansi.zig");

pub fn render(allocator: std.mem.Allocator, output: *std.ArrayList(u8), previous: ?*const Frame, next: *const Frame, color: bool) !void {
    output.clearRetainingCapacity();
    var current_style: ?Style = null;
    var emitted = false;
    for (0..next.height) |y| for (0..next.width) |x| {
        const cell = next.get(x, y);
        if (previous) |old| if (old.width == next.width and old.height == next.height and std.meta.eql(old.get(x, y), cell)) continue;
        try appendFmt(allocator, output, "\x1b[{d};{d}H", .{ y + 1, x + 1 });
        emitted = true;
        if (current_style == null or !std.meta.eql(current_style.?, cell.style)) {
            try appendStyle(allocator, output, cell.style, color);
            current_style = cell.style;
        }
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cell.codepoint, &encoded) catch 1;
        if (len == 1 and cell.codepoint > 0x7f) encoded[0] = '?';
        try output.appendSlice(allocator, encoded[0..len]);
    };
    if (emitted) try output.appendSlice(allocator, ansi.reset);
}

fn appendStyle(allocator: std.mem.Allocator, output: *std.ArrayList(u8), style: Style, color: bool) !void {
    try output.appendSlice(allocator, ansi.reset);
    if (style.bold) try output.appendSlice(allocator, "\x1b[1m");
    if (style.reverse) try output.appendSlice(allocator, "\x1b[7m");
    if (color and style.fg != .default) try appendFmt(allocator, output, "\x1b[{d}m", .{30 + @intFromEnum(style.fg)});
    if (color and style.bg != .default) try appendFmt(allocator, output, "\x1b[{d}m", .{40 + @intFromEnum(style.bg)});
}

fn appendFmt(allocator: std.mem.Allocator, output: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    var buffer: [64]u8 = undefined;
    const text = try std.fmt.bufPrint(&buffer, fmt, args);
    try output.appendSlice(allocator, text);
}
