//! Bounded HTTP/1.1 streaming for the loopback Ollama service. All reads and
//! writes and connection start are nonblocking; USB owns the loop.
const std = @import("std");

pub const Body = struct {
    header: [8192]u8 = undefined,
    used: usize = 0,
    state: enum { headers, raw, size, chunk, cr, lf, ended } = .headers,
    remaining: usize = 0,
    size_line: [32]u8 = undefined,
    size_len: usize = 0,
    total: usize = 0,

    pub fn feed(self: *Body, byte: u8) !?u8 {
        switch (self.state) {
            .headers => {
                if (self.used == self.header.len) return error.HttpHeadersTooLarge;
                self.header[self.used] = byte;
                self.used += 1;
                if (self.used < 4 or !std.mem.eql(u8, self.header[self.used - 4 .. self.used], "\r\n\r\n")) return null;
                var lines = std.mem.splitSequence(u8, self.header[0..self.used], "\r\n");
                const status = lines.next().?;
                if (!std.mem.startsWith(u8, status, "HTTP/1.1 200 ") and !std.mem.startsWith(u8, status, "HTTP/1.0 200 ")) return error.OllamaHttpStatus;
                var chunked = false;
                var length: ?usize = null;
                while (lines.next()) |line| {
                    const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
                    const name = line[0..colon];
                    const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
                    if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                        if (!std.ascii.eqlIgnoreCase(value, "chunked")) return error.UnsupportedHttpEncoding;
                        chunked = true;
                    }
                    if (std.ascii.eqlIgnoreCase(name, "content-encoding") and !std.ascii.eqlIgnoreCase(value, "identity")) return error.UnsupportedHttpEncoding;
                    if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                        if (length != null) return error.InvalidHttpHeaders;
                        length = try std.fmt.parseInt(usize, value, 10);
                        if (length.? > 262144) return error.HttpBodyTooLarge;
                    }
                }
                if (chunked and length != null) return error.InvalidHttpHeaders;
                self.remaining = length orelse 262144;
                self.state = if (chunked) .size else if (self.remaining == 0) .ended else .raw;
                return null;
            },
            .size => {
                if (byte == '\n') {
                    if (self.size_len < 2 or self.size_line[self.size_len - 1] != '\r') return error.InvalidHttpChunk;
                    self.remaining = try std.fmt.parseInt(usize, self.size_line[0 .. self.size_len - 1], 16);
                    if (self.remaining > 262144) return error.HttpBodyTooLarge;
                    self.size_len = 0;
                    self.state = if (self.remaining == 0) .ended else .chunk;
                } else {
                    if (self.size_len == self.size_line.len) return error.InvalidHttpChunk;
                    self.size_line[self.size_len] = byte;
                    self.size_len += 1;
                }
                return null;
            },
            .raw, .chunk => {
                self.total += 1;
                if (self.total > 262144) return error.HttpBodyTooLarge;
                self.remaining -= 1;
                if (self.remaining == 0) self.state = if (self.state == .chunk) .cr else .ended;
                return byte;
            },
            .cr => {
                if (byte != '\r') return error.InvalidHttpChunk;
                self.state = .lf;
                return null;
            },
            .lf => {
                if (byte != '\n') return error.InvalidHttpChunk;
                self.state = .size;
                return null;
            },
            .ended => return null,
        }
    }
};

pub const Connection = struct {
    stream: std.Io.net.Stream,
    io: std.Io,
    request: [12288]u8 = undefined,
    length: usize = 0,
    sent: usize = 0,
    connecting: bool = true,
    input: [1024]u8 = undefined,
    available: usize = 0,
    cursor: usize = 0,
    body: Body = .{},

    pub fn open(io: std.Io, url: []const u8, json: []const u8) !Connection {
        if (!std.mem.startsWith(u8, url, "http://")) return error.LocalHttpUrlRequired;
        const authority = std.mem.trimEnd(u8, url[7..], "/");
        const colon = std.mem.indexOfScalar(u8, authority, ':');
        const host = authority[0 .. colon orelse authority.len];
        if (!std.mem.eql(u8, host, "127.0.0.1") and !std.mem.eql(u8, host, "localhost")) return error.LoopbackOllamaRequired;
        const port = if (colon) |index| try std.fmt.parseInt(u16, authority[index + 1 ..], 10) else 11434;
        const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(port) };
        const socket_rc = std.posix.system.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
        if (std.posix.errno(socket_rc) != .SUCCESS) return error.SocketCreateFailed;
        const stream: std.Io.net.Stream = .{ .socket = .{ .handle = @intCast(socket_rc), .address = address } };
        errdefer stream.close(io);
        const fd = stream.socket.handle;
        const current = std.posix.system.fcntl(fd, std.posix.F.GETFL, @as(usize, 0));
        if (std.posix.errno(current) != .SUCCESS) return error.SocketFlagsFailed;
        const nonblock: u32 = @bitCast(std.posix.O{ .NONBLOCK = true });
        if (std.posix.errno(std.posix.system.fcntl(fd, std.posix.F.SETFL, @as(usize, @intCast(current)) | nonblock)) != .SUCCESS) return error.SocketFlagsFailed;
        if (std.posix.errno(std.posix.system.fcntl(fd, std.posix.F.SETFD, @as(usize, std.posix.FD_CLOEXEC))) != .SUCCESS) return error.SocketFlagsFailed;
        const sockaddr: std.posix.sockaddr.in = .{ .port = std.mem.nativeToBig(u16, port), .addr = std.mem.nativeToBig(u32, 0x7f000001) };
        const connected = std.posix.system.connect(fd, @ptrCast(&sockaddr), @sizeOf(@TypeOf(sockaddr)));
        switch (std.posix.errno(connected)) {
            .SUCCESS, .INPROGRESS, .AGAIN, .INTR => {},
            else => return error.OllamaConnectFailed,
        }
        var self: Connection = .{ .io = io, .stream = stream };
        const request = try std.fmt.bufPrint(&self.request, "POST /api/chat HTTP/1.1\r\nHost: {s}\r\nContent-Type: application/json\r\nAccept: application/x-ndjson\r\nAccept-Encoding: identity\r\nConnection: close\r\nContent-Length: {d}\r\n\r\n{s}", .{ authority, json.len, json });
        self.length = request.len;
        return self;
    }
    pub fn close(self: *Connection) void {
        self.stream.close(self.io);
    }

    /// No byte means "not ready". Never waits for network data.
    pub fn next(self: *Connection) !?u8 {
        const fd = self.stream.socket.handle;
        if (self.connecting) {
            var fds = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.OUT, .revents = 0 }};
            if (try std.posix.poll(&fds, 0) == 0) return null;
            var socket_error: u32 = 0;
            var length: std.posix.socklen_t = @sizeOf(u32);
            if (std.posix.errno(std.posix.system.getsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.ERROR, @ptrCast(&socket_error), &length)) != .SUCCESS or socket_error != 0) return error.OllamaConnectFailed;
            self.connecting = false;
        }
        if (self.sent < self.length) {
            const bytes = self.request[self.sent..self.length];
            const rc = std.posix.system.sendto(fd, bytes.ptr, bytes.len, std.posix.MSG.NOSIGNAL, null, 0);
            switch (std.posix.errno(rc)) {
                .SUCCESS => self.sent += @intCast(rc),
                .AGAIN, .INTR => return null,
                else => return error.OllamaWriteFailed,
            }
            return null;
        }
        // Bound CPU work per event-loop iteration, even for large headers.
        for (0..256) |_| {
            if (self.cursor == self.available) {
                self.available = std.posix.read(fd, &self.input) catch |err| switch (err) {
                    error.WouldBlock => return null,
                    else => return err,
                };
                self.cursor = 0;
                if (self.available == 0) return error.OllamaStreamClosed;
            }
            const byte = self.input[self.cursor];
            self.cursor += 1;
            if (try self.body.feed(byte)) |value| return value;
            if (self.body.state == .ended) return error.OllamaStreamClosed;
        }
        return null;
    }
};

test "HTTP streaming body survives every chunk boundary and rejects status and encoding errors" {
    const source = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nABC\r\n2\r\nDE\r\n0\r\n\r\n";
    var body: Body = .{};
    var result: [5]u8 = undefined;
    var used: usize = 0;
    for (source) |b| if (try body.feed(b)) |c| {
        result[used] = c;
        used += 1;
    };
    try std.testing.expectEqualStrings("ABCDE", result[0..used]);
    try std.testing.expectEqual(@TypeOf(body.state).ended, body.state);
    var bad: Body = .{};
    for ("HTTP/1.1 500 ERROR\r\n\r\n"[0..21]) |b| _ = try bad.feed(b);
    try std.testing.expectError(error.OllamaHttpStatus, bad.feed('\n'));
}
