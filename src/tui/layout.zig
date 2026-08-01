pub const Rect = struct { x: usize, y: usize, width: usize, height: usize };
pub const Layout = struct {
    compact: bool,
    header: Rect,
    source: Rect,
    cpu: Rect,
    lower: Rect,
    status: Rect,

    pub fn calculate(width: usize, height: usize) Layout {
        if (width < 80 or height < 24) return .{
            .compact = true,
            .header = .{ .x = 0, .y = 0, .width = width, .height = @min(2, height) },
            .source = .{ .x = 0, .y = @min(2, height), .width = width, .height = height -| @min(3, height) },
            .cpu = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .lower = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .status = .{ .x = 0, .y = height -| 1, .width = width, .height = @min(1, height) },
        };
        const body_y: usize = 2;
        const status_height: usize = 1;
        const available = height - body_y - status_height;
        const upper_height = available * 2 / 3;
        const source_width = width * 7 / 10;
        return .{
            .compact = false,
            .header = .{ .x = 0, .y = 0, .width = width, .height = 2 },
            .source = .{ .x = 0, .y = body_y, .width = source_width, .height = upper_height },
            .cpu = .{ .x = source_width, .y = body_y, .width = width - source_width, .height = upper_height },
            .lower = .{ .x = 0, .y = body_y + upper_height, .width = width, .height = available - upper_height },
            .status = .{ .x = 0, .y = height - 1, .width = width, .height = status_height },
        };
    }
};
