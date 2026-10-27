//! Native integration fixture: real host USB frames -> exact portable C bridge
//! -> existing Z80 CPU/Bus -> assembled loaders. No physical device operations.
const std = @import("std");
const Harness = @import("loader_harness.zig").Harness;
const wire = @import("loader_protocol.zig");
const chat = @import("chat_protocol.zig");
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
    chat_input: chat.Parser = .{},
    chat_output: chat.Parser = .{},
    chat_key: usize = 0,
    chat_down: bool = false,
    chat_at: u64 = 0,
    chat_waited: bool = false,
    chat_turns: usize = 0,
    chat_limit: usize = 2,
    chat_idle: bool = false,
    chat_visible: bool = false,
    chat_watch: ?u8 = null,
    chat_returned: bool = false,
    chat_max_row: u8 = 0,
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
        if (app and std.mem.startsWith(u8, self.fault, "chat")) {
            if (try self.chat_input.feed(byte)) |frame| {
                if (!self.chat_visible and frame.kind == .text and frame.len > 0) self.chat_watch = frame.seq +% 1;
                if (!self.used_fault and std.mem.eql(u8, self.fault, "chat-corrupt") and frame.kind == .text) {
                    actual ^= 1;
                    self.used_fault = true;
                }
            }
        }
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
            if (app and std.mem.startsWith(u8, self.fault, "chat")) {
                const frame = self.chat_output.feed(byte) catch return;
                if (frame) |f| {
                    if (!self.used_fault and std.mem.eql(u8, self.fault, "chat-drop-ack") and f.kind == .ack and f.seq == 1) {
                        self.used_fault = true;
                        return;
                    }
                    var bytes: [chat.max_frame]u8 = undefined;
                    const encoded = chat.encode(&bytes, f.kind, f.seq, f.payload[0..f.len]) catch unreachable;
                    for (encoded) |value| c.loader_bridge_rx(value, self.now());
                }
                return;
            }
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
        if (std.mem.startsWith(u8, self.fault, "chat") and self.output[3] == 0x82) self.chat_returned = true;
    }

    fn chatScript(self: *Context) void {
        if (!std.mem.startsWith(u8, self.fault, "chat")) return;
        const app = self.h.cpu.registers.pc >= wire.app_min and self.h.cpu.registers.pc < wire.app_end;
        if (!app) return;
        const state = self.h.bus.memory[0xd77a];
        const row = self.h.bus.memory[0xd775];
        if ((state == 1 or state == 2) and row > self.chat_max_row) {
            self.chat_max_row = row;
            if (self.log) |fd| {
                var buffer: [64]u8 = undefined;
                const line = std.fmt.bufPrint(&buffer, "chat_max_row={d}\n", .{row}) catch unreachable;
                _ = writeAll(fd, line);
            }
        }
        if (state == 2) self.chat_waited = true;
        if (state == 1 and self.chat_waited) {
            self.chat_waited = false;
            self.chat_turns += 1;
            self.chat_key = 0;
        }
        if (!self.chat_visible) {
            if (self.chat_watch) |sequence| {
                if (self.h.bus.memory[0xd778] == sequence) {
                    self.chat_visible = true;
                    if (self.log) |fd| {
                        var buffer: [96]u8 = undefined;
                        const line = std.fmt.bufPrint(&buffer, "chat_text_visible_us={d}\n", .{self.now()}) catch unreachable;
                        _ = writeAll(fd, line);
                    }
                }
            }
        }
        if (self.now() < self.chat_at) return;
        if (self.chat_down) {
            @memset(&self.h.keys, 255);
            self.chat_down = false;
            self.chat_key += 1;
            self.chat_at = self.now() + 20_000;
            return;
        }
        if (state != 1) return;
        if (self.chat_turns >= self.chat_limit) {
            if (self.chat_idle) return;
            self.h.keys[9] = 0x7f;
            return;
        }
        const rows = [_]usize{ 3, 2, 3, 3, 3, 1 };
        const masks = [_]u8{ 1, 32, 16, 16, 128, 128 };
        if (self.chat_key < rows.len) {
            self.h.keys[rows[self.chat_key]] = ~masks[self.chat_key];
            self.chat_down = true;
            self.chat_at = self.now() + 20_000;
        }
    }
};
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const mode = if (args.len > 1) args[1] else "stage1";
    const ctx = try init.arena.allocator().create(Context);
    ctx.* = .{ .io = init.io, .mode = mode, .fault = if (args.len > 2) args[2] else "" };
    if (init.environ_map.get("CHAT_TURNS")) |count| ctx.chat_limit = try std.fmt.parseInt(usize, count, 10);
    ctx.chat_idle = init.environ_map.get("CHAT_IDLE_AFTER_TURNS") != null;
    try ctx.h.init(init.io, init.arena.allocator(), std.mem.eql(u8, mode, "stage0"), false);
    ctx.resident = !std.mem.eql(u8, mode, "stage0") and !std.mem.eql(u8, mode, "mini");
    if (std.mem.eql(u8, mode, "mini")) try ctx.h.initMini(init.io, init.arena.allocator());
    if (std.mem.eql(u8, ctx.fault, "auto-escape")) ctx.h.escape_after_polls = 12;
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
        const line = std.fmt.bufPrint(&text, "exec_entries={d}\nchat_turns={d}\nchat_returned={d}\n", .{ ctx.h.application_entries, ctx.chat_turns, @intFromBool(ctx.chat_returned) }) catch unreachable;
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
            ctx.h.vrtc = ctx.now() % 16_667 < 2_000;
            ctx.chatScript();
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
            if (ctx.tx_cursor == ctx.h.tx_len) {
                ctx.h.tx_len = 0;
                ctx.tx_cursor = 0;
            }
        }
        c.loader_bridge_flush();
    }
}
