const std = @import("std");
const wire = @import("loader_protocol.zig");
const transport = @import("transport.zig");
const Transport = transport.Transport;
const assets = @import("loader_assets.zig");

/// Upload and execute using an already leased transport. Ownership stays with
/// the caller, allowing the application protocol to continue without a Hi-Z
/// transition, DTR toggle, RX reset, or second USB session.
pub fn uploadApplication(channel: *Transport, payload: []const u8, out: *std.Io.Writer) !u8 {
    if (!wire.validRange(wire.app_min, payload.len, wire.app_min)) return error.UnsafeDeployRange;
    var client: Client = .{ .io = channel, .timeout = 3_000_000, .retries = 2, .out = out };
    try out.writeAll("Waiting for resident loader (ACK timeout 3s; up to 2 retries)...\n");
    try out.flush();
    _ = try client.hello();
    try out.writeAll("Loader detected; application RAM range validated.\n");
    try out.flush();
    var metadata: [9]u8 = @splat(0);
    wire.put16(&metadata, wire.app_min);
    wire.put16(metadata[2..], @intCast(payload.len));
    wire.put16(metadata[4..], wire.app_min);
    const checksum = wire.crc(payload);
    wire.put16(metadata[6..], checksum);
    try out.print("Starting upload: {d} bytes at D000h, 300bps. Payload alone needs at least {d}s; protocol overhead adds time.\n", .{ payload.len, (payload.len * 10 + 299) / 300 });
    try out.flush();
    _ = try client.exchange(wire.begin, &metadata);
    const started = channel.now();
    try out.print("Uploading: 0/{d} bytes (0%)\n", .{payload.len});
    try out.flush();
    var offset: usize = 0;
    while (offset < payload.len) {
        const count = @min(wire.max_data, payload.len - offset);
        const reply = try client.exchange(wire.data, payload[offset..][0..count]);
        offset += count;
        if (wire.read16(reply.bytes[6..]) != offset) return error.UnexpectedLoaderOffset;
        const elapsed = channel.now() - started;
        const remaining = elapsed * (payload.len - offset) / offset;
        try out.print("Uploading: {d}/{d} bytes ({d}%) elapsed={d}s ETA~{d}s\n", .{ offset, payload.len, offset * 100 / payload.len, elapsed / 1_000_000, (remaining + 999_999) / 1_000_000 });
        try out.flush();
    }
    try out.writeAll("Verifying uploaded RAM CRC16...\n");
    try out.flush();
    const verified = try client.exchange(wire.verify, "");
    if (wire.read16(verified.bytes[6..]) != checksum or verified.bytes[8] & 2 == 0) return error.ImageVerificationFailed;
    try out.print("RAM CRC16 verified: {X:0>4}. Requesting EXEC at D000h...\n", .{checksum});
    try out.flush();
    const sequence = client.sequence;
    _ = try client.exchange(wire.exec, "");
    try out.print("Chat application verified and EXEC acknowledged: {d} bytes CRC16={X:0>4}\n", .{ payload.len, checksum });
    try out.flush();
    return sequence;
}

pub const usage =
    \\zig80 deploy FILE --target pc8001 --port PATH --enable-tx --voltage-confirmed
    \\  [--load-address 0xD000] [--entry ADDRESS] [--loader mini|stage1|stage0]
    \\  [--no-exec] [--verify-only] [--timeout MS] [--retries N] [--log FILE]
    \\  [--ready-timeout MS] [--wait-return] [--app-echo]
    \\zig80 deploy bootstrap --target pc8001 [--bootstrap mini|legacy] [--format files|monitor|basic|cmt|wav] [--out-dir DIR]
    \\zig80 deploy resident --target pc8001 --loader mini --port PATH --enable-tx --voltage-confirmed
    \\zig80 deploy stage1 --target pc8001 --loader stage0 --port PATH --enable-tx --voltage-confirmed
    \\zig80 deploy test --target pc8001 --loader mini|stage0|stage1|preflight --port PATH --enable-tx --voltage-confirmed
    \\zig80 deploy abort --target pc8001 --port PATH --enable-tx --voltage-confirmed
    \\bootstrap is offline. Start the host BEFORE invoking Stage 0/preflight USR.
    \\Only D000-D7FF is deployable. Startup/exit remain Hi-Z. No automatic re-arm.
    \\
;
const Options = struct {
    target: bool = false,
    port: ?[]const u8 = null,
    address: u16 = wire.app_min,
    entry: ?u16 = null,
    mode: enum { mini, stage0, stage1, preflight } = .stage1,
    bootstrap: enum { mini, legacy } = .mini,
    timeout_us: u64 = 3_000_000,
    ready_us: u64 = 60_000_000,
    retries: u8 = 2,
    no_exec: bool = false,
    verify_only: bool = false,
    wait_return: bool = false,
    app_echo: bool = false,
    tx: bool = false,
    voltage: bool = false,
    log: ?[]const u8 = null,
    format: []const u8 = "files",
    directory: []const u8 = "zig-out/pc8001/loader",
};
fn milliseconds(text: []const u8) !u64 {
    const n = try std.fmt.parseInt(u64, text, 10);
    if (n < 100 or n > 3_600_000) return error.InvalidTimeout;
    return n * 1000;
}
fn parse(args: []const []const u8) !Options {
    var options: Options = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const flag = args[index];
        if (std.mem.eql(u8, flag, "--enable-tx")) options.tx = true else if (std.mem.eql(u8, flag, "--voltage-confirmed")) options.voltage = true else if (std.mem.eql(u8, flag, "--no-exec")) options.no_exec = true else if (std.mem.eql(u8, flag, "--verify-only")) options.verify_only = true else if (std.mem.eql(u8, flag, "--wait-return")) options.wait_return = true else if (std.mem.eql(u8, flag, "--app-echo")) options.app_echo = true else {
            if (index + 1 == args.len) return error.InvalidArguments;
            index += 1;
            const value = args[index];
            if (std.mem.eql(u8, flag, "--target")) {
                if (!std.mem.eql(u8, value, "pc8001")) return error.UnsupportedDeployTarget;
                options.target = true;
            } else if (std.mem.eql(u8, flag, "--port")) options.port = value else if (std.mem.eql(u8, flag, "--load-address")) options.address = try std.fmt.parseInt(u16, value, 0) else if (std.mem.eql(u8, flag, "--entry")) options.entry = try std.fmt.parseInt(u16, value, 0) else if (std.mem.eql(u8, flag, "--loader")) options.mode = std.meta.stringToEnum(@TypeOf(options.mode), value) orelse return error.InvalidLoaderMode else if (std.mem.eql(u8, flag, "--bootstrap")) options.bootstrap = std.meta.stringToEnum(@TypeOf(options.bootstrap), value) orelse return error.InvalidBootstrapMode else if (std.mem.eql(u8, flag, "--timeout")) options.timeout_us = try milliseconds(value) else if (std.mem.eql(u8, flag, "--ready-timeout")) options.ready_us = try milliseconds(value) else if (std.mem.eql(u8, flag, "--retries")) {
                options.retries = try std.fmt.parseInt(u8, value, 10);
                if (options.retries > 10) return error.InvalidRetryLimit;
            } else if (std.mem.eql(u8, flag, "--log")) options.log = value else if (std.mem.eql(u8, flag, "--format")) options.format = value else if (std.mem.eql(u8, flag, "--out-dir")) options.directory = value else return error.InvalidArguments;
        }
    }
    if (!options.target) return error.ExplicitTargetRequired;
    if (options.mode == .preflight and !std.mem.eql(u8, args[0], "test")) return error.InvalidLoaderMode;
    if ((options.no_exec or options.verify_only) and (options.wait_return or options.app_echo)) return error.InvalidArguments;
    return options;
}
const Client = struct {
    io: *Transport,
    sequence: u8 = 0,
    timeout: u64,
    retries: u8,
    retries_used: usize = 0,
    returned_sequence: ?u8 = null,
    exec_sequence: ?u8 = null,
    returned_value: u8 = 0,
    noise_bytes: usize = 0,
    extra_frames: usize = 0,
    out: *std.Io.Writer,
    fn exchange(self: *Client, kind: u8, payload: []const u8) !wire.Frame {
        if (kind == wire.exec) {
            self.exec_sequence = self.sequence;
            self.returned_sequence = null;
        }
        var encoded: [wire.max_frame]u8 = undefined;
        const frame = try wire.encode(&encoded, kind, self.sequence, payload);
        var attempt: usize = 0;
        attempts: while (attempt <= self.retries) : (attempt += 1) {
            if (attempt > 0) {
                self.retries_used += 1;
                try self.out.print("Retry sequence={d} attempt={d}\n", .{ self.sequence, attempt });
                try self.out.flush();
            }
            const deadline = self.io.now() + self.timeout + (frame.len + wire.max_frame) * 40_000;
            try self.io.send(frame, deadline);
            try self.io.drain(deadline);
            var parser: wire.Parser = .{};
            while (self.io.now() < deadline) {
                const byte = self.io.readByte(deadline) catch |err| switch (err) {
                    error.LoaderTimeout => continue :attempts,
                    else => return err,
                };
                if (parser.used == 0 and byte != 0xa5) self.noise_bytes += 1;
                if (parser.used == 1 and byte != 0x5a) self.noise_bytes += 1;
                const maybe = parser.feed(byte) catch |err| switch (err) {
                    error.LoaderCrcMismatch, error.LoaderFrameTooLarge => continue :attempts,
                };
                if (maybe) |response| {
                    if (response.version != 1) return error.LoaderVersionMismatch;
                    if (response.kind == 0x82 and response.len == 16 and response.bytes[0] == 0) {
                        if (self.exec_sequence == response.sequence) {
                            self.returned_sequence = response.sequence;
                            self.returned_value = response.bytes[6];
                        } else self.extra_frames += 1;
                        continue;
                    }
                    if (response.sequence != self.sequence) {
                        self.extra_frames += 1;
                        continue;
                    }
                    if (response.kind == wire.nak) {
                        if (response.len != 16) return error.InvalidLoaderReply;
                        if (response.bytes[0] == 1) continue :attempts;
                        try self.out.print("Loader rejected request: status={d}\n", .{response.bytes[0]});
                        try self.out.flush();
                        return error.LoaderRejectedRequest;
                    }
                    if (kind == wire.echo) {
                        if (response.kind != wire.echo_reply or !std.mem.eql(u8, payload, response.payload())) return error.BinaryMismatch;
                    } else if (response.kind != wire.ack or response.len != 16 or response.bytes[0] != 0) return error.InvalidLoaderReply;
                    self.sequence +%= 1;
                    if (self.io.session.log) |log| {
                        try log.print("{{\"deploy\":\"ack\",\"type\":{d},\"sequence\":{d},\"attempt\":{d}}}\n", .{ kind, response.sequence, attempt });
                        try log.flush();
                    }
                    return response;
                }
            }
        }
        return error.LoaderRetryLimit;
    }
    fn hello(self: *Client) !wire.Frame {
        self.sequence = 0;
        const response = try self.exchange(wire.hello, "");
        if (response.bytes[1] != 1 or wire.read16(response.bytes[2..]) != wire.app_min or wire.read16(response.bytes[4..]) != wire.app_end or response.bytes[9] != wire.max_data) return error.UnsupportedLoaderLayout;
        return response;
    }
    fn waitReturn(self: *Client, sequence: u8) !void {
        if (self.returned_sequence == sequence) {
            try self.out.print("Application returned to loader; A={X:0>2}\n", .{self.returned_value});
            return;
        }
        var parser: wire.Parser = .{};
        const deadline = self.io.now() + self.timeout + wire.max_frame * 40_000;
        while (true) {
            if (try parser.feed(try self.io.readByte(deadline))) |reply| {
                if (reply.version == 1 and reply.kind == 0x82 and reply.sequence == sequence and reply.len == 16 and reply.bytes[0] == 0) {
                    try self.out.print("Application returned to loader; A={X:0>2}\n", .{reply.bytes[6]});
                    return;
                }
            }
        }
    }
};
fn stage0(io: *Transport, images: *const assets.Images, ready_us: u64, timeout: u64, out: *std.Io.Writer, ready_received: bool) !u16 {
    if (!ready_received) try waitStage0(io, ready_us, out);
    const started = io.now();
    const deadline = started + timeout + (wire.stage1_size + 3) * 40_000;
    try io.send("G", deadline);
    try io.send(&images.stage1, deadline);
    var checksum: [2]u8 = undefined;
    const crc = wire.crc(&images.stage1);
    wire.put16(&checksum, crc);
    try io.send(&checksum, deadline);
    try io.drain(deadline);
    // No Stage 0 retry: an interrupted fixed-length image must be restarted.
    if (try io.readByte(deadline) != 'O') return error.Stage0RejectedImage;
    try out.print("Stage 0 accepted CRC16; Stage 1 transfer bytes={d} elapsed_us={d}\n", .{ wire.stage1_size, io.now() - started });
    return crc;
}
fn waitStage0(io: *Transport, ready_us: u64, out: *std.Io.Writer) !void {
    try out.writeAll("TX idle established. Waiting for Stage 0 READY; invoke R=USR0(0) now.\n");
    try out.flush();
    try readStage0Ready(io, io.now() + ready_us);
}
fn readStage0Ready(io: *Transport, ready_deadline: u64) !void {
    const expected = [_]u8{ 0x5a, 0x30, 1, @truncate(wire.stage1_size), @truncate(wire.stage1_size >> 8) };
    var matched: usize = 0;
    while (matched < expected.len) {
        const byte = try io.readByte(ready_deadline);
        if (byte == expected[matched]) matched += 1 else matched = if (byte == expected[0]) 1 else 0;
    }
}
fn miniBoot(io: *Transport, images: *const assets.Images, ready_us: u64, timeout: u64, out: *std.Io.Writer) !void {
    try out.writeAll("TX idle established. Waiting for Mini Stage 0 READY; invoke USR0 at E300 now.\n");
    try out.flush();
    const ready_deadline = io.now() + ready_us;
    while (try io.readByte(ready_deadline) != wire.mini_ready) {}
    const start = io.now();
    const deadline = start + timeout + (wire.relay_size + 6) * 40_000;
    try io.send(images.stage0, deadline);
    var sum: u8 = 0;
    for (images.stage0) |byte| sum +%= byte;
    try io.send(&.{0 -% sum}, deadline);
    try io.drain(deadline);
    try readStage0Ready(io, deadline);
    try out.print("Relay Stage 1 READY after {d} bytes + SUM8; elapsed_us={d}\n", .{ images.stage0.len, io.now() - start });
}
fn stage0Test(io: *Transport, ready_us: u64, timeout: u64, out: *std.Io.Writer, ready_received: bool) !void {
    if (!ready_received) try waitStage0(io, ready_us, out);
    var pattern: [258]u8 = undefined;
    for (pattern[0..256], 0..) |*byte, i| byte.* = @intCast(i);
    wire.put16(pattern[256..], wire.crc(pattern[0..256]));
    const start = io.now();
    const deadline = start + 2 * 259 * 40_000 + timeout;
    try io.send("T", deadline);
    try io.send(&pattern, deadline);
    for (pattern[0..256]) |byte| if (try io.readByte(deadline) != byte) return error.BinaryMismatch;
    if (try io.readByte(deadline) != 'O') return error.Stage0RejectedImage;
    try io.drain(deadline);
    try io.wait(200_000);
    if (io.session.uart_len != 0) return error.ExtraUartBytes;
    try out.print("Stage 0 binary roundtrip: 256/256 missing=0 extra=0 mismatch=0 CRC16=OK elapsed_us={d}; no jump\n", .{io.now() - start});
}
fn binaryTest(client: *Client, ready_us: u64, preflight: bool) !void {
    var pattern: [256]u8 = undefined;
    for (&pattern, 0..) |*byte, i| byte.* = @intCast(i);
    if (preflight) {
        try client.out.writeAll("TX idle established. Waiting for BP; start binary_ready_test USR now.\n");
        try client.out.flush();
        const deadline = client.io.now() + ready_us;
        var b = false;
        while (true) {
            const byte = try client.io.readByte(deadline);
            if (b and byte == 'P') break;
            b = byte == 'B';
        }
        const end = client.io.now() + client.timeout + 256 * 80_000;
        try client.io.send(&pattern, end);
        for (pattern) |expected| if (try client.io.readByte(end) != expected) return error.BinaryMismatch;
        if (try client.io.readByte(end) != 'O' or try client.io.readByte(end) != 'K') return error.TargetUartFault;
        try client.io.drain(end);
        try client.io.wait(200_000);
        if (client.io.session.uart_len != 0) return error.ExtraUartBytes;
    } else {
        const before = try client.hello();
        for (0..4) |block| _ = try client.exchange(wire.echo, pattern[block * 64 ..][0..64]);
        const after = try client.exchange(wire.info, "");
        if (wire.read16(before.bytes[10..]) != wire.read16(after.bytes[10..]) or wire.read16(before.bytes[12..]) != wire.read16(after.bytes[12..])) return error.TargetUartFault;
        try client.io.wait(200_000);
        if (client.io.session.uart_len != 0 or client.noise_bytes != 0 or client.extra_frames != 0 or client.retries_used != 0) return error.BinaryTestNotClean;
    }
    try client.out.writeAll("Binary roundtrip: 256/256, missing=0 extra=0 mismatch=0; target failures would reject/time out.\n");
}
pub fn run(io: std.Io, allocator: std.mem.Allocator, args: []const []const u8, out: *std.Io.Writer, errout: *std.Io.Writer) !void {
    if (args.len == 0 or std.mem.eql(u8, args[0], "--help")) {
        try out.writeAll(usage);
        return;
    }
    const options = try parse(args);
    const name = args[0];
    if (std.mem.eql(u8, name, "bootstrap")) {
        try assets.generate(io, allocator, options.directory, out);
        if (!std.mem.eql(u8, options.format, "files")) {
            const audio = std.mem.eql(u8, options.format, "cmt") or std.mem.eql(u8, options.format, "wav");
            const extension = if (std.mem.eql(u8, options.format, "monitor")) "-monitor.txt" else if (std.mem.eql(u8, options.format, "basic")) ".bas" else if (std.mem.eql(u8, options.format, "wav")) ".wav" else if (std.mem.eql(u8, options.format, "cmt")) ".cmt" else return error.InvalidFormat;
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ options.directory, if (options.bootstrap == .mini) "mini-stage0" else "relay-stage1", extension });
            defer allocator.free(path);
            if (audio) try out.print("Generated cassette file: {s}; playback is manual, never automatic.\n", .{path}) else {
                const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(65536));
                defer allocator.free(text);
                try out.writeAll(text);
            }
        }
        try out.print("Next: start deploy resident --loader {s} --target pc8001 --port PATH --enable-tx --voltage-confirmed, wait for READY prompt, then invoke USR on PC.\n", .{if (options.bootstrap == .mini) "mini" else "stage0"});
        return;
    }
    if (!options.tx or !options.voltage) {
        try errout.writeAll("TX remains disabled. Deploy requires --enable-tx --voltage-confirmed after physical checks.\n");
        return error.TransmitConfirmationRequired;
    }
    const port = options.port orelse return error.ExplicitPortRequired;
    const is_test = std.mem.eql(u8, name, "test");
    const install_only = std.mem.eql(u8, name, "stage1") or std.mem.eql(u8, name, "resident");
    const abort_only = std.mem.eql(u8, name, "abort");
    if (abort_only and options.mode != .stage1) return error.InvalidLoaderMode;
    if (install_only and options.mode != .stage0 and options.mode != .mini) return error.Stage0ModeRequired;
    const file_bytes: ?[]u8 = if (!is_test and !install_only and !abort_only) try std.Io.Dir.cwd().readFileAlloc(io, name, allocator, .limited(2049)) else null;
    defer if (file_bytes) |bytes| allocator.free(bytes);
    const payload = file_bytes orelse "";
    const entry = options.entry orelse options.address;
    if (file_bytes != null and !wire.validRange(options.address, payload.len, entry)) return error.UnsafeDeployRange;
    if (options.log) |path| if (std.mem.eql(u8, path, name)) return error.LogWouldOverwriteProgram;
    // Assembly/file I/O happens before ARM; it must not starve the 1 s lease.
    var boot_images: ?assets.Images = if ((options.mode == .stage0 and !is_test) or options.mode == .mini) try assets.Images.load(io, allocator) else null;
    defer if (boot_images) |*images| images.deinit(allocator);
    var log_file: ?std.Io.File = null;
    var log_buffer: [4096]u8 = undefined;
    var log_writer: std.Io.File.Writer = undefined;
    if (options.log) |path| {
        log_file = try std.Io.Dir.cwd().createFile(io, path, .{});
        log_writer = log_file.?.writer(io, &log_buffer);
    }
    defer if (log_file) |file| {
        log_writer.interface.flush() catch {};
        file.close(io);
    };
    var signals = @import("cli.zig").Signals.init();
    defer signals.deinit();
    var channel = try Transport.open(io, port, out, if (log_file != null) &log_writer.interface else null, options.timeout_us);
    defer channel.close();
    try out.print("Zig_80 Serial Deploy\nTarget=PC-8001 transport={s} baud=300\n", .{channel.identity[0..channel.identity_len]});
    try out.flush();
    const start = channel.now();
    var client: Client = .{ .io = &channel, .timeout = options.timeout_us, .retries = options.retries, .out = out };
    // On failure: GPIO/DTR cleanup always runs. Never send an unsequenced EXEC.
    if (options.mode == .mini) try miniBoot(&channel, &boot_images.?, options.ready_us, options.timeout_us, out);
    const expected_loader_crc: ?u16 = if (!is_test and boot_images != null) try stage0(&channel, &boot_images.?, options.ready_us, options.timeout_us, out, options.mode == .mini) else null;
    if (is_test) {
        if (options.mode == .stage0 or options.mode == .mini) try stage0Test(&channel, options.ready_us, options.timeout_us, out, options.mode == .mini) else try binaryTest(&client, options.ready_us, options.mode == .preflight);
    } else {
        const loader = try client.hello();
        const actual = wire.read16(loader.bytes[6..]);
        if (expected_loader_crc) |expected| if (actual != expected) return error.ResidentLoaderCrcMismatch;
        try out.print("Loader detected: protocol=1 RAM=D000-D7FF resident_crc={X:0>4}\n", .{actual});
        if (abort_only) {
            _ = try client.exchange(wire.abort, "");
            try out.writeAll("Transfer aborted; loader remains resident\n");
        } else if (!install_only) {
            const crc = wire.crc(payload);
            var metadata: [9]u8 = undefined;
            wire.put16(&metadata, options.address);
            wire.put16(metadata[2..], @intCast(payload.len));
            wire.put16(metadata[4..], entry);
            wire.put16(metadata[6..], crc);
            metadata[8] = @intFromBool(options.verify_only);
            _ = try client.exchange(wire.begin, &metadata);
            try out.print("Memory range validated; load={X:0>4} entry={X:0>4} size={d}\n", .{ options.address, entry, payload.len });
            var offset: usize = 0;
            if (!options.verify_only) while (offset < payload.len) {
                const count = @min(wire.max_data, payload.len - offset);
                const response = try client.exchange(wire.data, payload[offset..][0..count]);
                offset += count;
                if (wire.read16(response.bytes[6..]) != offset) return error.UnexpectedLoaderOffset;
                try out.print("Uploading {d}/{d}\n", .{ offset, payload.len });
                try out.flush();
            };
            const verified = try client.exchange(wire.verify, "");
            if (wire.read16(verified.bytes[6..]) != crc or verified.bytes[8] & 2 == 0) return error.ImageVerificationFailed;
            try out.print("RAM CRC16 verified: {X:0>4}\n", .{crc});
            if (!options.no_exec and !options.verify_only) {
                const sequence = client.sequence;
                _ = try client.exchange(wire.exec, "");
                try out.print("EXEC acknowledged at {X:0>4}\n", .{entry});
                if (options.app_echo) {
                    const text = "HELLO FROM PICO 2";
                    const end = channel.now() + options.timeout_us + 2_000_000;
                    try channel.send(text, end);
                    for (text) |byte| if (try channel.readByte(end) != byte) return error.ApplicationEchoMismatch;
                    try out.writeAll("Application echo: 17 bytes matched\n");
                }
                if (options.wait_return or options.app_echo) try client.waitReturn(sequence);
            }
        }
    }
    try channel.finish(channel.now() + options.timeout_us + 2_000_000);
    try out.print("Completed; elapsed_us={d} loader_retries={d}; TX released\n", .{ channel.now() - start, client.retries_used });
    if (channel.session.log) |log| {
        try log.print("{{\"deploy\":\"complete\",\"elapsed_us\":{d},\"retries\":{d}}}\n", .{ channel.now() - start, client.retries_used });
        try log.flush();
    }
}
