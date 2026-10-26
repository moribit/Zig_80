//! One explicit leased UART session; never re-arms automatically after a fault.
const std = @import("std");
const wire = @import("protocol.zig");
const cli = @import("cli.zig");
pub const nowUs = @import("port.zig").nowUs;
pub const Transport = struct {
    session: cli.Session,
    heartbeat: u64 = 0,
    baseline: [11]u64 = @splat(0),
    identity: [128]u8 = undefined,
    identity_len: usize = 0,
    pub fn open(io: std.Io, path: []const u8, out: *std.Io.Writer, log: ?*std.Io.Writer, _: u64) !Transport {
        var self: Transport = .{ .session = .{
            .port = try @import("port.zig").Port.open(io, path),
            .out = out,
            .log = log,
            .quiet = true,
            .queue_uart = true,
            .timeout_us = 500_000,
        } };
        errdefer self.session.close();
        const id = try self.session.request(wire.info, "");
        const name = id.data[1..id.len];
        if (!std.mem.startsWith(u8, name, "pico2-pc8001/") or name.len > self.identity.len) return error.WrongSerialDevice;
        @memcpy(self.identity[0..name.len], name);
        self.identity_len = name.len;
        _ = try self.session.request(wire.disarm, "");
        _ = try self.session.request(wire.rx_stop, "");
        _ = try self.session.request(wire.invert, &.{1});
        const config = try self.session.request(wire.config, "");
        if (config.len != 21 or wire.read32(config.data[1..]) != 300 or config.data[5] != 8 or config.data[6] != 0 or config.data[7] != 1 or config.data[8] != 1) return error.UnsupportedUartConfiguration;
        _ = try self.session.request(wire.rx_start, "");
        _ = try self.session.request(wire.arm, wire.confirmation);
        self.session.armed = true;
        self.heartbeat = self.now();
        // Establish inverted idle LOW for > six bytes before looking for READY.
        // No UART payload is emitted in this interval. RX startup faults discarded.
        try self.wait(200_000);
        self.session.uart_len = 0;
        self.session.uart_head = 0;
        const counters = try self.stats();
        for (&self.baseline, 0..) |*value, i| value.* = wire.read64(counters.data[1 + i * 8 ..]);
        self.session.strict_uart = true;
        return self;
    }
    pub fn now(self: *const Transport) u64 {
        return nowUs(self.session.port.io);
    }
    pub fn close(self: *Transport) void {
        self.session.close();
    }
    pub fn stats(self: *Transport) !wire.Frame {
        const result = try self.session.request(wire.stats, "");
        if (result.len != 93) return error.InvalidStatisticsReply;
        return result;
    }
    fn maintain(self: *Transport) !void {
        if (self.now() >= self.heartbeat) {
            _ = try self.session.request(wire.keepalive, "");
            self.heartbeat = self.now() + 150_000;
        }
    }
    pub fn poll(self: *Transport, deadline: u64) !void {
        try self.maintain();
        self.session.pump(@min(deadline, self.now() + 20_000)) catch |err| switch (err) {
            error.Timeout => {},
            else => return err,
        };
    }
    pub fn wait(self: *Transport, duration_us: u64) !void {
        const deadline = self.now() + duration_us;
        while (self.now() < deadline) try self.poll(deadline);
    }
    pub fn readByte(self: *Transport, deadline: u64) !u8 {
        while (true) {
            try self.maintain();
            const s = &self.session;
            if (s.uart_len > 0) {
                const byte = s.uart[s.uart_head];
                s.uart_head = (s.uart_head + 1) % s.uart.len;
                s.uart_len -= 1;
                return byte;
            }
            if (self.now() >= deadline) return error.LoaderTimeout;
            try self.poll(deadline);
        }
    }
    pub fn send(self: *Transport, bytes: []const u8, deadline: u64) !void {
        var offset: usize = 0;
        while (offset < bytes.len) {
            try self.maintain();
            if (self.now() >= deadline) return error.LoaderTimeout;
            const counters = try self.stats();
            if (wire.read16(counters.data[89..]) > 128) {
                try self.poll(deadline);
                continue;
            }
            const count = @min(128, bytes.len - offset);
            _ = try self.session.request(wire.send, bytes[offset..][0..count]);
            offset += count;
        }
    }
    pub fn drain(self: *Transport, deadline: u64) !void {
        while (true) {
            try self.maintain();
            if (self.now() >= deadline) return error.LoaderTimeout;
            const counters = try self.stats();
            if (wire.read16(counters.data[89..]) == 0) return;
            try self.poll(deadline);
        }
    }
    pub fn finish(self: *Transport, deadline: u64) !void {
        try self.drain(deadline);
        try self.wait(100_000);
        const counters = try self.stats();
        for ([_]usize{ 2, 3, 4, 5, 6, 7, 8, 9, 10 }) |i| {
            if (wire.read64(counters.data[1 + i * 8 ..]) != self.baseline[i]) return error.TransportCounterChanged;
        }
        _ = try self.session.request(wire.disarm, "");
        self.session.armed = false;
        _ = try self.session.request(wire.rx_stop, "");
    }
};
