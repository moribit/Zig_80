const std = @import("std");

pub const Size = struct { width: usize, height: usize };

pub fn get(io: std.Io) !Size {
    if (@import("builtin").os.tag == .windows) return error.UnsupportedPlatform;
    var window: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    const result = (try io.operate(.{ .device_io_control = .{
        .file = std.Io.File.stdout(),
        .code = std.posix.T.IOCGWINSZ,
        .arg = &window,
    } })).device_io_control;
    if (result < 0 or window.col == 0 or window.row == 0) return error.TerminalSizeUnavailable;
    return .{ .width = window.col, .height = window.row };
}
