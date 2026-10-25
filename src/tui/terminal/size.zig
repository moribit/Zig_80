const std = @import("std");

pub const Size = struct { width: usize, height: usize };

pub fn get(io: std.Io) !Size {
    if (@import("builtin").os.tag == .windows) return error.UnsupportedPlatform;
    var window: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const result = if (@import("builtin").os.tag == .macos)
        // Keep the output pointer visible at Darwin's variadic libc boundary;
        // the Io integer-argument route failed the optimized PTY regression.
        std.c.ioctl(std.Io.File.stdout().handle, @as(c_int, @intCast(std.posix.T.IOCGWINSZ)), &window)
    else
        (try io.operate(.{ .device_io_control = .{
            .file = std.Io.File.stdout(),
            .code = std.posix.T.IOCGWINSZ,
            .arg = &window,
        } })).device_io_control;
    if (result < 0 or window.col == 0 or window.row == 0) return error.TerminalSizeUnavailable;
    return .{ .width = window.col, .height = window.row };
}
