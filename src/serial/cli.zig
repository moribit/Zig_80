const std = @import("std");
const wire = @import("protocol.zig");
const serial_port = @import("port.zig");
const Port = serial_port.Port;
var interrupted = std.atomic.Value(bool).init(false);
fn onSignal(_: std.posix.SIG) callconv(.c) void {
    interrupted.store(true, .monotonic);
}

const Options = struct {
    port: ?[]const u8 = null,
    text: ?[]const u8 = null,
    file: ?[]const u8 = null,
    log: ?[]const u8 = null,
    duration_us: u64 = 5_000_000,
    timeout_us: u64 = 2_000_000,
    raw: bool = false,
    normal: bool = false,
    enable_tx: bool = false,
    voltage_confirmed: bool = false,
};
const Session = struct {
    port: Port,
    parser: wire.Parser = .{},
    sequence: u16 = 0,
    buffer: [512]u8 = undefined,
    available: usize = 0,
    offset: usize = 0,
    out: *std.Io.Writer,
    log: ?*std.Io.Writer = null,
    raw: bool = false,
    quiet: bool = false,
    received: [512]u8 = undefined,
    captured: usize = 0,
    rx_count: u64 = 0,
    framing: u64 = 0,
    gaps: u64 = 0,
    armed: bool = false,
    timeout_us: u64,

    fn close(self: *Session) void {
        var buffer: [wire.max_frame]u8 = undefined;
        const data = wire.encode(&buffer, wire.disarm, self.sequence +% 1, "") catch unreachable;
        _ = self.port.writeSome(data) catch 0;
        self.port.close();
    }
    fn events(self: *Session, frame: *const wire.Frame) !void {
        if (frame.len % 10 != 0) return error.InvalidEventLength;
        var i: usize = 0;
        while (i < frame.len) : (i += 10) {
            const timestamp = wire.read64(frame.data[i..]);
            const flags = frame.data[i + 8];
            const byte = frame.data[i + 9];
            if (flags & 2 != 0) self.gaps += 1 else {
                self.rx_count += 1;
                if (self.captured < self.received.len) {
                    self.received[self.captured] = byte;
                    self.captured += 1;
                }
                if (flags & 1 != 0) self.framing += 1;
                if (self.raw) try self.out.writeByte(byte);
            }
            if (!self.raw and !self.quiet) try self.out.print("pico_us={d} RX {X:0>2} '{c}' flags={d}\n", .{ timestamp, byte, if (std.ascii.isPrint(byte)) byte else @as(u8, '.'), flags });
            if (self.log) |log| try log.print("{{\"pico_us\":{d},\"byte\":{d},\"flags\":{d}}}\n", .{ timestamp, byte, flags });
        }
        try self.out.flush();
    }
    fn next(self: *Session, deadline: u64) !wire.Frame {
        while (true) {
            if (interrupted.load(.monotonic)) return error.Interrupted;
            while (self.offset < self.available) {
                const byte = self.buffer[self.offset];
                self.offset += 1;
                if (try self.parser.feed(byte)) |frame| return frame;
            }
            if (serial_port.nowUs(self.port.io) >= deadline) return error.Timeout;
            self.available = try self.port.read(&self.buffer, 20);
            self.offset = 0;
        }
    }
    fn request(self: *Session, command: u8, payload: []const u8) !wire.Frame {
        self.sequence +%= 1;
        var encoded: [wire.max_frame]u8 = undefined;
        const frame = try wire.encode(&encoded, command, self.sequence, payload);
        const deadline = serial_port.nowUs(self.port.io) + self.timeout_us;
        try self.port.write(frame, deadline);
        while (true) {
            const answer = try self.next(deadline);
            if (answer.kind == wire.event) {
                try self.events(&answer);
                continue;
            }
            if (answer.sequence != self.sequence or answer.kind != command | 0x80 or answer.len < 1) return error.UnexpectedReply;
            if (answer.data[0] != 0) {
                if (command == wire.arm) return error.TransmitPermissionRejected;
                return error.DeviceCommandRejected;
            }
            return answer;
        }
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: []const []const u8, out: *std.Io.Writer, errout: *std.Io.Writer) !void {
    if (args.len > 0 and std.mem.eql(u8, args[0], "build-examples")) {
        if (args.len != 1 and (args.len != 3 or !std.mem.eql(u8, args[1], "--out-dir"))) return error.InvalidArguments;
        try @import("artifacts.zig").build(io, allocator, if (args.len == 3) args[2] else "zig-out/pc8001", out);
        return;
    }
    if (args.len == 0 or std.mem.eql(u8, args[0], "--help")) {
        try out.writeAll("zig80 serial list\nzig80 serial build-examples [--out-dir DIR]\nzig80 serial info|monitor|send|test --port PATH [TEXT] [--file FILE] [--raw] [--log FILE] [--duration-ms N] [--timeout-ms N] [--normal]\nSending requires BOTH --enable-tx --voltage-confirmed; never enables itself after a test.\nAll USB traffic is framed; --raw extracts UART bytes only. No deploy/loader is implemented.\n");
        return;
    }
    if (std.mem.eql(u8, args[0], "list")) {
        if (args.len != 1) return error.InvalidArguments;
        try listPorts(io, allocator, out);
        return;
    }
    const is_info = std.mem.eql(u8, args[0], "info");
    const is_monitor = std.mem.eql(u8, args[0], "monitor");
    const is_send = std.mem.eql(u8, args[0], "send");
    const is_test = std.mem.eql(u8, args[0], "test");
    if (!is_info and !is_monitor and !is_send and !is_test) return error.InvalidSerialCommand;
    var options: Options = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--enable-tx")) options.enable_tx = true else if (std.mem.eql(u8, arg, "--voltage-confirmed")) options.voltage_confirmed = true else if (std.mem.eql(u8, arg, "--raw")) options.raw = true else if (std.mem.eql(u8, arg, "--normal")) options.normal = true else if (std.mem.startsWith(u8, arg, "--")) {
            if (index + 1 >= args.len) return error.InvalidArguments;
            index += 1;
            const value = args[index];
            if (std.mem.eql(u8, arg, "--port")) options.port = value else if (std.mem.eql(u8, arg, "--file")) options.file = value else if (std.mem.eql(u8, arg, "--log")) options.log = value else if (std.mem.eql(u8, arg, "--duration-ms")) options.duration_us = try parseMilliseconds(value) else if (std.mem.eql(u8, arg, "--timeout-ms")) options.timeout_us = try parseMilliseconds(value) else return error.InvalidArguments;
        } else if (options.text == null) options.text = arg else return error.InvalidArguments;
    }
    if ((is_send or is_test) and (!options.enable_tx or !options.voltage_confirmed)) {
        try errout.writeAll("TX remains disabled. Confirm measured wiring/voltage/power sequencing, then explicitly supply --enable-tx --voltage-confirmed.\n");
        return error.TransmitConfirmationRequired;
    }
    if (options.enable_tx and !is_send and !is_test) return error.InvalidArguments;
    const path = options.port orelse return error.ExplicitPortRequired;
    var pattern: [256]u8 = undefined;
    for (&pattern, 0..) |*byte, i| byte.* = @intCast(i);
    const payload: []const u8 = if (is_test) &pattern else if (options.file) |file| try std.Io.Dir.cwd().readFileAlloc(io, file, allocator, .limited(257)) else options.text orelse "";
    if (is_send and (payload.len == 0 or payload.len > 256)) return error.InvalidPayloadLength;
    if (options.file != null and options.text != null) return error.InvalidArguments;
    var log_file: ?std.Io.File = null;
    var log_buffer: [4096]u8 = undefined;
    var log_writer: std.Io.File.Writer = undefined;
    if (options.log) |file| {
        log_file = try std.Io.Dir.cwd().createFile(io, file, .{});
        log_writer = log_file.?.writer(io, &log_buffer);
    }
    defer if (log_file) |file| {
        log_writer.interface.flush() catch {};
        file.close(io);
    };

    interrupted.store(false, .monotonic);
    var old_int: std.posix.Sigaction = undefined;
    var old_term: std.posix.Sigaction = undefined;
    const action: std.posix.Sigaction = .{ .handler = .{ .handler = onSignal }, .mask = std.posix.sigemptyset(), .flags = 0 };
    std.posix.sigaction(.INT, &action, &old_int);
    std.posix.sigaction(.TERM, &action, &old_term);
    defer {
        std.posix.sigaction(.INT, &old_int, null);
        std.posix.sigaction(.TERM, &old_term, null);
    }
    var session: Session = .{ .port = try Port.open(io, path), .out = out, .raw = options.raw, .quiet = is_test, .timeout_us = options.timeout_us, .log = if (log_file != null) &log_writer.interface else null };
    defer session.close();
    const identity = try session.request(wire.info, "");
    if (!std.mem.startsWith(u8, identity.data[1..identity.len], "pico2-pc8001/")) return error.WrongSerialDevice;
    _ = try session.request(wire.disarm, "");
    _ = try session.request(wire.rx_stop, "");
    const inversion = [_]u8{if (options.normal) 0 else 1};
    _ = try session.request(wire.invert, &inversion);
    const configuration = try session.request(wire.config, "");
    if (configuration.len != 21) return error.InvalidConfigurationReply;
    const data = configuration.data[1..configuration.len];
    if (is_info) {
        try out.print("firmware={s} port={s}\nUART={d} {d}N{d} inverted={d} RX=GP{d} TX=GP{d} tx_enabled={d}\nclock_hz={d} divider_q8={d} (actual baud=clock_hz*256/(divider_q8*8))\n", .{ identity.data[1..identity.len], path, wire.read32(data), data[4], data[6], data[7], data[8], data[9], (data[10] >> 1) & 1, wire.read32(data[12..]), wire.read32(data[16..]) });
        return;
    }
    _ = try session.request(wire.rx_start, "");
    if (is_send or is_test) {
        _ = try session.request(wire.arm, wire.confirmation);
        session.armed = true;
        _ = try session.request(wire.send, payload);
    }
    const start = serial_port.nowUs(io);
    const duration = if (is_send or is_test) @max(options.duration_us, @as(u64, @intCast(payload.len)) * 40_000 + options.timeout_us) else options.duration_us;
    const deadline = start + duration;
    var heartbeat = start;
    var transmit_done = false;
    var transmit_settled: ?u64 = null;
    while (serial_port.nowUs(io) < deadline) {
        const now = serial_port.nowUs(io);
        if (session.armed and now >= heartbeat) {
            _ = try session.request(wire.keepalive, "");
            heartbeat = now + 200_000;
            const counters = try session.request(wire.stats, "");
            if (counters.len != 93) return error.InvalidStatisticsReply;
            transmit_done = wire.read16(counters.data[89..]) == 0;
            if (transmit_done) {
                // Allow six 300-baud byte times for the last prompt echo to arrive.
                if (transmit_settled == null) transmit_settled = now;
                if ((is_send and now - transmit_settled.? >= 200_000 and wire.read16(counters.data[91..]) == 0) or (is_test and session.rx_count >= payload.len)) break;
            }
        }
        const incoming = session.next(@min(deadline, now + 50_000)) catch |err| switch (err) {
            error.Timeout => continue,
            else => return err,
        };
        if (incoming.kind != wire.event) return error.UnexpectedReply;
        try session.events(&incoming);
    }
    _ = try session.request(wire.disarm, "");
    session.armed = false;
    _ = try session.request(wire.rx_stop, "");
    const counters = try session.request(wire.stats, "");
    if (counters.len != 93) return error.InvalidStatisticsReply;
    const report = if (options.raw) errout else out;
    const elapsed = serial_port.nowUs(io) - start;
    const names = [_][]const u8{ "rx_bytes", "tx_completed", "framing_errors", "rx_overflows", "pio_overrun_events", "tx_timeouts", "protocol_errors", "usb_dropped_events", "lease_expirations", "tx_aborted", "rx_timeouts" };
    try report.print("transport={s} elapsed_us={d} host_rx={d} gaps={d}\n", .{ identity.data[1..identity.len], elapsed, session.rx_count, session.gaps });
    for (names, 0..) |name, i| try report.print("{s}={d}\n", .{ name, wire.read64(counters.data[1 + i * 8 ..]) });
    if (is_test) {
        var mismatch: u64 = if (session.rx_count > 256) session.rx_count - 256 else 256 - session.rx_count;
        for (session.received[0..@min(session.captured, 256)], 0..) |byte, i| if (byte != pattern[i]) {
            mismatch += 1;
        };
        try report.print("mismatches={d} payload_rx_bytes_per_second={d} (host elapsed; topology NOT verified)\n", .{ mismatch, if (elapsed == 0) 0 else session.rx_count * 1_000_000 / elapsed });
        if (mismatch != 0 or session.framing != 0 or session.gaps != 0) return error.SerialTestFailed;
    }
    if ((is_send or is_test) and !transmit_done) return error.TransmitTimeout;
}
fn parseMilliseconds(text: []const u8) !u64 {
    const value = try std.fmt.parseInt(u64, text, 10);
    if (value == 0 or value > 3_600_000) return error.InvalidTimeout;
    return value * 1000;
}
fn listPorts(io: std.Io, allocator: std.mem.Allocator, out: *std.Io.Writer) !void {
    var directory = try std.Io.Dir.cwd().openDir(io, "/dev", .{ .iterate = true });
    defer directory.close(io);
    var iterator = directory.iterate();
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);
    while (try iterator.next(io)) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "cu.usbmodem") and !std.mem.startsWith(u8, entry.name, "ttyACM")) continue;
        try paths.append(allocator, try std.fmt.allocPrint(allocator, "/dev/{s}", .{entry.name}));
    }
    defer for (paths.items) |path| allocator.free(path);
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    for (paths.items) |path| try out.print("{s}\n", .{path});
    try out.writeAll("Candidates only; firmware identity/VID is not inferred from a pathname. Use info --port PATH. No port is automatically selected.\n");
}
