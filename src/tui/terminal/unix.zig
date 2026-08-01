const std = @import("std");

pub fn readInput(buffer: []u8, timeout_ms: i32) !usize {
    var descriptors = [_]std.posix.pollfd{.{
        .fd = std.Io.File.stdin().handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    if (try std.posix.poll(&descriptors, timeout_ms) == 0) return 0;
    if (descriptors[0].revents & std.posix.POLL.IN == 0) return 0;
    return std.posix.read(std.Io.File.stdin().handle, buffer);
}
