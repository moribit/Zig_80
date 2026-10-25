const std = @import("std");
const builtin = @import("builtin");
pub fn nowUs(io: std.Io) u64 {
    return @intCast(@divTrunc(std.Io.Clock.awake.now(io).nanoseconds, 1000));
}
pub const Port = struct {
    file: std.Io.File,
    original: std.posix.termios,
    io: std.Io,

    pub fn open(io: std.Io, path: []const u8) !Port {
        if (builtin.os.tag != .macos and builtin.os.tag != .linux) return error.UnsupportedPlatform;
        const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDWR, .NOCTTY = true, .NONBLOCK = true, .CLOEXEC = true }, 0);
        const file: std.Io.File = .{ .handle = fd, .flags = .{ .nonblocking = true } };
        errdefer file.close(io);
        const original = try std.posix.tcgetattr(fd);
        var raw = original;
        raw.iflag.IGNBRK = false;
        raw.iflag.BRKINT = false;
        raw.iflag.PARMRK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.INLCR = false;
        raw.iflag.IGNCR = false;
        raw.iflag.ICRNL = false;
        raw.iflag.IXON = false;
        raw.iflag.IXOFF = false;
        raw.oflag.OPOST = false;
        raw.lflag.ECHO = false;
        raw.lflag.ECHONL = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;
        raw.cflag.CSIZE = .CS8;
        raw.cflag.PARENB = false;
        raw.cflag.CSTOPB = false;
        raw.cflag.CREAD = true;
        raw.cflag.CLOCAL = true;
        if (builtin.os.tag == .linux) raw.cflag.CRTSCTS = false;
        if (builtin.os.tag == .macos) {
            raw.cflag.CCTS_OFLOW = false;
            raw.cflag.CRTS_IFLOW = false;
        }
        raw.ispeed = .B115200;
        raw.ospeed = .B115200;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        try std.posix.tcsetattr(fd, .FLUSH, raw);
        var port: Port = .{ .file = file, .original = original, .io = io };
        port.dtr(true);
        return port;
    }
    pub fn dtr(self: *Port, asserted: bool) void {
        var bits: c_int = 2; // TIOCM_DTR, POSIX driver ABI on macOS/Linux.
        if (builtin.os.tag == .macos) {
            const request: c_int = @bitCast(@as(u32, if (asserted) 0x8004746c else 0x8004746b)); // TIOCMBIS/BIC
            _ = std.c.ioctl(self.file.handle, request, &bits);
        } else if (builtin.os.tag == .linux) {
            _ = std.os.linux.ioctl(self.file.handle, if (asserted) 0x5416 else 0x5417, @intFromPtr(&bits));
        }
        // PTYs may not implement modem bits. The firmware handshake still
        // establishes identity; physical CDC requires DTR to be observed.
    }
    pub fn close(self: *Port) void {
        self.dtr(false);
        std.posix.tcsetattr(self.file.handle, .NOW, self.original) catch {};
        self.file.close(self.io);
    }
    pub fn read(self: *Port, buffer: []u8, timeout_ms: i32) !usize {
        var descriptors = [_]std.posix.pollfd{.{ .fd = self.file.handle, .events = std.posix.POLL.IN, .revents = 0 }};
        if (try std.posix.poll(&descriptors, timeout_ms) == 0) return 0;
        if (descriptors[0].revents & (std.posix.POLL.HUP | std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0) return error.DeviceDisconnected;
        return std.posix.read(self.file.handle, buffer) catch |err| switch (err) {
            error.WouldBlock => 0,
            else => return err,
        };
    }
    pub fn writeSome(self: *Port, data: []const u8) !usize {
        const rc = std.posix.system.write(self.file.handle, data.ptr, data.len);
        return switch (std.posix.errno(rc)) {
            .SUCCESS => @intCast(rc),
            .AGAIN, .INTR => 0,
            else => error.SerialWriteFailed,
        };
    }
    pub fn write(self: *Port, data: []const u8, deadline: u64) !void {
        var offset: usize = 0;
        while (offset < data.len) {
            if (nowUs(self.io) >= deadline) return error.Timeout;
            var descriptors = [_]std.posix.pollfd{.{ .fd = self.file.handle, .events = std.posix.POLL.OUT, .revents = 0 }};
            _ = try std.posix.poll(&descriptors, 20);
            if (descriptors[0].revents & (std.posix.POLL.HUP | std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0) return error.DeviceDisconnected;
            if (descriptors[0].revents & std.posix.POLL.OUT != 0) offset += try self.writeSome(data[offset..]);
        }
    }
};
