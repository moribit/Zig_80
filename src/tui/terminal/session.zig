const std = @import("std");
const builtin = @import("builtin");
const ansi = @import("ansi.zig");

pub const TerminalSession = struct {
    io: std.Io,
    original: std.posix.termios,
    active: bool = false,

    pub fn begin(io: std.Io) !TerminalSession {
        if (builtin.os.tag != .macos and builtin.os.tag != .linux) return error.UnsupportedPlatform;
        if (!try std.Io.File.stdin().isTty(io) or !try std.Io.File.stdout().isTty(io)) return error.NotATerminal;
        const original = try std.posix.tcgetattr(std.Io.File.stdin().handle);
        var raw = original;
        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ISIG = false; // Ctrl+C is decoded by the application so defer can restore the terminal.
        raw.lflag.IEXTEN = false;
        raw.iflag.ICRNL = false;
        raw.iflag.IXON = false;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;
        try std.posix.tcsetattr(std.Io.File.stdin().handle, .FLUSH, raw);
        errdefer std.posix.tcsetattr(std.Io.File.stdin().handle, .FLUSH, original) catch {};
        try std.Io.File.stdout().writeStreamingAll(io, ansi.alternate_screen_enter ++ ansi.cursor_hide ++ ansi.clear ++ ansi.home);
        return .{ .io = io, .original = original, .active = true };
    }

    pub fn deinit(self: *TerminalSession) void {
        if (!self.active) return;
        std.Io.File.stdout().writeStreamingAll(self.io, ansi.reset ++ ansi.cursor_show ++ ansi.alternate_screen_leave) catch {};
        std.posix.tcsetattr(std.Io.File.stdin().handle, .FLUSH, self.original) catch {};
        self.active = false;
    }
};
