const std = @import("std");

pub const Rect = struct { x: u16, y: u16, width: u16, height: u16 };

/// Page layout: byte=(y/8)*width+x, bit=y%8. No controller or terminal dependency.
pub fn Framebuffer(comptime width_value: usize, comptime height_value: usize) type {
    if (height_value % 8 != 0) @compileError("display height must be a multiple of eight");
    return struct {
        pub const width = width_value;
        pub const height = height_value;
        pub const byte_count = width * height / 8;
        const Self = @This();
        bytes: [byte_count]u8 = @splat(0),
        dirty: ?Rect = null,
        update_count: u64 = 0,

        pub fn pixel(self: *const Self, x: usize, y: usize) bool {
            if (x >= width or y >= height) return false;
            return self.bytes[(y / 8) * width + x] & (@as(u8, 1) << @as(u3, @intCast(y % 8))) != 0;
        }
        pub fn setPixel(self: *Self, x: usize, y: usize, value: bool) void {
            if (x >= width or y >= height) return;
            const index = (y / 8) * width + x;
            const mask = @as(u8, 1) << @as(u3, @intCast(y % 8));
            const old = self.bytes[index];
            const changed = if (value) old | mask else old & ~mask;
            if (old == changed) return;
            self.bytes[index] = changed;
            self.mark(x, y, 1, 1);
            self.update_count +%= 1;
        }
        pub fn writeByte(self: *Self, address: usize, value: u8) void {
            if (address >= byte_count or self.bytes[address] == value) return;
            self.bytes[address] = value;
            self.mark(address % width, (address / width) * 8, 1, 8);
            self.update_count +%= 1;
        }
        pub fn clear(self: *Self) void {
            for (0..byte_count) |i| self.writeByte(i, 0);
        }
        pub fn takeDirty(self: *Self) ?Rect {
            const result = self.dirty;
            self.dirty = null;
            return result;
        }
        pub fn snapshot(self: *const Self) [byte_count]u8 {
            return self.bytes;
        }

        fn mark(self: *Self, x: usize, y: usize, w: usize, h: usize) void {
            var rect: Rect = .{ .x = @intCast(x), .y = @intCast(y), .width = @intCast(w), .height = @intCast(h) };
            if (self.dirty) |old| {
                const right = @max(old.x + old.width, rect.x + rect.width);
                const bottom = @max(old.y + old.height, rect.y + rect.height);
                rect.x = @min(rect.x, old.x);
                rect.y = @min(rect.y, old.y);
                rect.width = right - rect.x;
                rect.height = bottom - rect.y;
            }
            self.dirty = rect;
        }

        /// Portable text PBM, row-major export independent of internal page layout.
        pub fn writePbm(self: *const Self, writer: *std.Io.Writer) !void {
            try writer.print("P1\n{d} {d}\n", .{ width, height });
            for (0..height) |y| {
                for (0..width) |x| try writer.writeAll(if (self.pixel(x, y)) "1 " else "0 ");
                try writer.writeAll("\n");
            }
        }
    };
}

pub const Vfd = Framebuffer(256, 64);
pub const Classic = Framebuffer(128, 64);

/// Abstract controller, deliberately not a Noritake command implementation.
pub const Controller = struct {
    frame: Vfd = .{},
    address: u11 = 0,
    pub fn read(self: *Controller) u8 {
        const value = self.frame.bytes[self.address];
        self.address +%= 1;
        return value;
    }
    pub fn write(self: *Controller, value: u8) void {
        self.frame.writeByte(self.address, value);
        self.address +%= 1;
    }
};
