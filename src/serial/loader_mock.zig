//! Native integration fixture: real host USB frames -> exact portable C bridge
//! -> existing Z80 CPU/Bus -> assembled loaders. No physical device operations.
const std = @import("std");
const Harness = @import("loader_harness.zig").Harness;
const wire = @import("loader_protocol.zig");
const c = struct {
    extern fn loader_bridge_init() void;
    extern fn loader_bridge_connected(bool) void;
    extern fn loader_bridge_feed(u8, u64) void;
    extern fn loader_bridge_tick(u64) void;
    extern fn loader_bridge_pop(*u8) bool;
    extern fn loader_bridge_complete() void;
    extern fn loader_bridge_rx(u8, u64) void;
    extern fn loader_bridge_fault(u8, u64) void;
    extern fn loader_bridge_flush() void;
};
var active: *Context = undefined;
export fn loader_mock_emit(bytes: [*]const u8, len: usize) bool {
    return Context.writeAll(1, bytes[0..len]);
}
export fn loader_mock_safety(tx: bool) void {
    active.safety(tx);
}
var stopped = std.atomic.Value(bool).init(false);
fn stop(_: std.posix.SIG) callconv(.c) void {
    stopped.store(true, .monotonic);
}
const Context = struct {
    h: Harness = undefined,
    io: std.Io,
    mode: []const u8,
    fault: []const u8,
    used_fault: bool = false,
    started: bool = false,
    start_at: u64 = 0,
    resident: bool = false,
    log: ?std.posix.fd_t = null,
    output: [wire.max_frame]u8 = undefined,
    output_len: usize = 0,
    incoming: wire.Parser = .{},
    tx_cursor: usize = 0,
    fn now(self: *Context) u64 {
        return @import("transport.zig").nowUs(self.io);
    }
    fn writeAll(fd: std.posix.fd_t, bytes: []const u8) bool {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const n = std.posix.system.write(fd, bytes[offset..].ptr, bytes.len - offset);
            switch (std.posix.errno(n)) {
                .SUCCESS => {
                    if (n == 0) return false;
                    offset += @intCast(n);
                },
                .INTR => continue,
                else => return false,
            }
        }
        return true;
    }
    fn safety(self: *Context, tx: bool) void {
        if (self.log) |fd| _ = writeAll(fd, if (tx) "tx=1\n" else "tx=0\n");
        if (tx and !self.started) {
            self.started = true;
            self.start_at = self.now() + 250_000;
        }
    }
    fn receive(self: *Context, byte: u8) !void {
        var actual = byte;
        const app = self.h.cpu.registers.pc >= wire.app_min and self.h.cpu.registers.pc < wire.app_end;
        if (self.resident and !app) if (try self.incoming.feed(byte)) |frame| {
            if (frame.kind == wire.data and !self.used_fault) {
                if (std.mem.eql(u8, self.fault, "corrupt-data")) {
                    actual ^= 1;
                    self.used_fault = true;
                }
                if (std.mem.eql(u8, self.fault, "disconnect")) {
                    stopped.store(true, .monotonic);
                    self.used_fault = true;
                }
                if (std.mem.eql(u8, self.fault, "expire")) {
                    c.loader_bridge_tick(self.now() + 2_000_000);
                    self.used_fault = true;
                }
                if (std.mem.eql(u8, self.fault, "reconnect")) {
                    c.loader_bridge_connected(false);
                    c.loader_bridge_connected(true);
                    self.used_fault = true;
                }
            }
        };
        try self.h.feed(&.{actual});
    }
    fn targetByte(self: *Context, byte: u8) void {
        // Stage0 notification and application-owned UART are opaque raw bytes.
        const app = self.h.cpu.registers.pc >= wire.app_min and self.h.cpu.registers.pc < wire.app_end;
        if (!self.resident or app) {
            c.loader_bridge_rx(byte, self.now());
            return;
        }
        if (self.output_len == 0 and byte != 0xa5) return;
        if (self.output_len == 1 and byte != 0x5a) {
            self.output_len = 0;
            return;
        }
        self.output[self.output_len] = byte;
        self.output_len += 1;
        if (self.output_len < 6) return;
        const length: usize = self.output[5] + 8;
        if (length > self.output.len) {
            self.output_len = 0;
            return;
        }
        if (self.output_len != length) return;
        self.output_len = 0;
        if (!self.used_fault and self.output[3] == wire.ack) {
            if (std.mem.eql(u8, self.fault, "uart-framing") and self.h.bus.memory[0xe601] == wire.data) {
                c.loader_bridge_fault(0, self.now());
                self.used_fault = true;
            }
            if (std.mem.eql(u8, self.fault, "stale-return") and self.h.bus.memory[0xe601] == wire.begin) {
                var old: [wire.max_frame]u8 = undefined;
                const payload: [16]u8 = @splat(0);
                const bytes = wire.encode(&old, 0x82, 4, &payload) catch unreachable;
                for (bytes) |value| c.loader_bridge_rx(value, self.now());
                self.used_fault = true;
            }
            if ((std.mem.eql(u8, self.fault, "drop-data-ack") and self.h.bus.memory[0xe601] == wire.data) or (std.mem.eql(u8, self.fault, "drop-exec-ack") and self.h.bus.memory[0xe601] == wire.exec)) {
                self.used_fault = true;
                return;
            }
            if (std.mem.eql(u8, self.fault, "wrong-version")) {
                self.output[2] = 2;
                wire.put16(self.output[length - 2 ..], wire.crc(self.output[2 .. length - 2]));
                self.used_fault = true;
            }
        }
        for (self.output[0..length]) |value| c.loader_bridge_rx(value, self.now());
    }
};
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const mode = if (args.len > 1) args[1] else "stage1";
    const ctx = try init.arena.allocator().create(Context);
    ctx.* = .{ .io = init.io, .mode = mode, .fault = if (args.len > 2) args[2] else "" };
    try ctx.h.init(init.io, init.arena.allocator(), std.mem.eql(u8, mode, "stage0"), false);
    ctx.resident = !std.mem.eql(u8, mode, "stage0");
    if (std.mem.eql(u8, mode, "preflight")) {
        var failure: @import("../assembler/assembler.zig").FailureLocation = .{};
        var image = try @import("../assembler/assembler.zig").assembleFile(init.io, init.arena.allocator(), "examples/pc8001/serial/binary_ready_test.asm", &failure);
        defer image.deinit();
        @memcpy(ctx.h.bus.memory[wire.app_min..][0..image.bytes.items.len], image.bytes.items);
        ctx.h.cpu.registers.pc = wire.app_min;
        ctx.resident = false;
    }
    if (init.environ_map.get("MOCK_STATE_LOG")) |path| ctx.log = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }, 0o600);
    defer if (ctx.log) |fd| {
        var text: [128]u8 = undefined;
        const line = std.fmt.bufPrint(&text, "exec_entries={d}\n", .{ctx.h.application_entries}) catch unreachable;
        _ = Context.writeAll(fd, line);
        _ = std.posix.system.close(fd);
    };
    const action: std.posix.Sigaction = .{ .handler = .{ .handler = stop }, .mask = std.posix.sigemptyset(), .flags = 0 };
    std.posix.sigaction(.TERM, &action, null);
    std.posix.sigaction(.INT, &action, null);
    active = ctx;
    c.loader_bridge_init();
    c.loader_bridge_connected(true);
    defer c.loader_bridge_connected(false);
    while (!stopped.load(.monotonic)) {
        var fds = [_]std.posix.pollfd{.{ .fd = 0, .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = try std.posix.poll(&fds, 1);
        if (fds[0].revents & (std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) break;
        if (ready > 0) {
            var bytes: [512]u8 = undefined;
            const count = try std.posix.read(0, &bytes);
            if (count == 0) break;
            for (bytes[0..count]) |byte| c.loader_bridge_feed(byte, ctx.now());
        }
        c.loader_bridge_tick(ctx.now());
        if (ctx.started and ctx.now() >= ctx.start_at and !std.mem.eql(u8, mode, "silent")) {
            var byte: u8 = 0;
            while (c.loader_bridge_pop(&byte)) {
                try ctx.receive(byte);
                c.loader_bridge_complete();
            }
            for (0..5000) |_| {
                try ctx.h.steps(1);
                while (ctx.tx_cursor < ctx.h.tx_len) {
                    ctx.targetByte(ctx.h.tx[ctx.tx_cursor]);
                    ctx.tx_cursor += 1;
                }
                if (ctx.h.cpu.registers.pc == wire.stage1_address) ctx.resident = true;
            }
        }
        c.loader_bridge_flush();
    }
}
