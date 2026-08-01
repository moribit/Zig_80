const Bus = @import("bus.zig").Bus;
const memory = @import("memory.zig");

pub const width = 128;
pub const height = 64;

pub fn pixel(bus: *const Bus, x: u8, y: u8) bool {
    if (x >= width or y >= height) return false;
    const address = memory.vram_start + @as(u16, y / 8) * width + x;
    return bus.read8(address) & (@as(u8, 1) << @intCast(y % 8)) != 0;
}

pub fn render(bus: *const Bus, writer: anytype) !void {
    var y: u8 = 0;
    while (y < height) : (y += 2) {
        var x: u8 = 0;
        while (x < width) : (x += 1) {
            const top = pixel(bus, x, y);
            const bottom = pixel(bus, x, y + 1);
            try writer.writeAll(if (top and bottom) "█" else if (top) "▀" else if (bottom) "▄" else " ");
        }
        try writer.writeByte('\n');
    }
}
