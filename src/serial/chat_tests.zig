const std = @import("std");
const assembler = @import("../assembler/assembler.zig");
const Harness = @import("loader_harness.zig").Harness;
const wire = @import("chat_protocol.zig");

const Terminal = struct {
    h: Harness,
    image: assembler.Result,
    cursor: usize = 0,
    parser: wire.Parser = .{},

    fn init(self: *Terminal, mode: u8) !void {
        self.cursor = 0;
        self.parser = .{};
        var failure: assembler.FailureLocation = .{};
        self.image = try assembler.assembleFile(std.testing.io, std.testing.allocator, "examples/pc8001/chat.asm", &failure);
        errdefer self.image.deinit();
        try std.testing.expect(self.image.bytes.items.len <= 0x680);
        try self.h.init(std.testing.io, std.testing.allocator, false, false);
        self.h.bus.memory[0xea66] = 0x28 | mode;
        @memcpy(self.h.bus.memory[0xd000..][0..self.image.bytes.items.len], self.image.bytes.items);
        self.h.cpu.registers.pc = 0xd000;
        self.h.cpu.registers.sp = 0xe7f0;
        self.h.bus.write16(0xe7f0, 0xbeef);
        self.h.command = 0x37;
        self.h.port30 = 0x20;
    }
    fn deinit(self: *Terminal) void {
        self.image.deinit();
    }
    fn addr(self: *Terminal, name: []const u8) u16 {
        return self.image.symbols.address(name).?;
    }
    fn get(self: *Terminal, name: []const u8) u8 {
        return self.h.bus.memory[self.addr(name)];
    }
    fn set(self: *Terminal, name: []const u8, value: u8) void {
        self.h.bus.memory[self.addr(name)] = value;
    }
    fn until(self: *Terminal, name: []const u8) !void {
        for (0..500000) |_| {
            if (self.h.cpu.registers.pc == self.addr(name)) return;
            try self.h.steps(1);
        }
        return error.TerminalCheckpointTimeout;
    }
    fn next(self: *Terminal) !wire.Frame {
        for (0..500000) |_| {
            while (self.cursor < self.h.tx_len) {
                const byte = self.h.tx[self.cursor];
                self.cursor += 1;
                if (try self.parser.feed(byte)) |frame| return frame;
            }
            try self.h.steps(1);
        }
        return error.TerminalFrameTimeout;
    }
    fn feed(self: *Terminal, kind: wire.Kind, seq: u8, payload: []const u8) !void {
        var buffer: [wire.max_frame]u8 = undefined;
        try self.h.feed(try wire.encode(&buffer, kind, seq, payload));
    }
    fn connect(self: *Terminal) !void {
        const hello = try self.next();
        try std.testing.expectEqual(wire.Kind.hello, hello.kind);
        try std.testing.expectEqualStrings("C1", hello.payload[0..hello.len]);
        try self.feed(.ack, 0, "");
        try self.feed(.ready, 0, "C1");
        try std.testing.expectEqual(wire.Kind.ack, (try self.next()).kind);
        try self.until("chat_loop");
        try std.testing.expectEqual(@as(u8, 1), self.get("STATE"));
    }
    fn key(self: *Terminal, row: usize, mask: u8) !void {
        self.h.keys[row] = ~mask;
        try self.h.steps(1);
        try self.until("chat_loop");
        self.h.keys[row] = 255;
        try self.h.steps(1);
        try self.until("chat_loop");
    }
    fn presentation(self: *Terminal) !void {
        try self.h.steps(1);
        try self.until("keyboard");
        try std.testing.expectEqual(self.get("COL") * self.get("STRIDE"), self.h.cursor_x);
        try std.testing.expectEqual(self.get("ROW"), self.h.cursor_y);
        try std.testing.expect(self.h.cursor_enabled);
        try std.testing.expect(!self.h.invalid_crtc_command);
        try self.h.steps(1);
        try self.until("chat_loop");
    }
};

test "Z80 chat handshake input edit wrap scrolling duplicates and attributes in all video modes" {
    for (0..4) |mode| {
        var t: Terminal = undefined;
        try t.init(@intCast(mode));
        defer t.deinit();
        var attributes: [1000]u8 = undefined;
        const before = t.h.bus.memory;
        for (0..25) |row| @memcpy(attributes[row * 40 ..][0..40], t.h.bus.memory[0xf300 + row * 120 + 80 ..][0..40]);
        try t.connect();
        try t.presentation();
        const cursor_writes = t.h.cursor_writes;
        try t.presentation();
        try std.testing.expectEqual(cursor_writes, t.h.cursor_writes);
        try t.key(2, 2); // A
        try t.key(2, 4); // B
        try t.presentation();
        try t.key(8, 8); // Backspace
        try t.presentation();
        try std.testing.expectEqual(@as(u8, 1), t.get("LENGTH"));
        try std.testing.expectEqual(@as(u8, 'A'), t.h.bus.memory[t.addr("PROMPT")]);
        // Hold C for several scans: exactly one character.
        t.h.keys[2] = ~@as(u8, 8);
        for (0..4) |_| {
            try t.h.steps(1);
            try t.until("chat_loop");
            try t.presentation();
        }
        t.h.keys[2] = 255;
        try t.h.steps(1);
        try t.until("chat_loop");
        try std.testing.expectEqual(@as(u8, 2), t.get("LENGTH"));
        t.h.keys[1] = 0x7f;
        const prompt = try t.next();
        try std.testing.expectEqual(wire.Kind.prompt, prompt.kind);
        try std.testing.expectEqualSlices(u8, &.{ 1, 'A', 'C' }, prompt.payload[0..prompt.len]);
        t.h.keys[1] = 255;
        try t.feed(.ack, prompt.seq, "");
        try t.until("chat_loop");
        for (1..32) |seq| {
            try t.feed(.text, @intCast(seq), "HELLO WORLD.\n");
            const ack = try t.next();
            try std.testing.expectEqual(wire.Kind.ack, ack.kind);
            try t.until("chat_loop");
        }
        const row_before = t.get("ROW");
        const col_before = t.get("COL");
        try t.feed(.text, 31, "HELLO WORLD.\n");
        _ = try t.next();
        try t.until("chat_loop");
        try std.testing.expectEqual(row_before, t.get("ROW"));
        try std.testing.expectEqual(col_before, t.get("COL"));
        try t.feed(.done, 32, "");
        _ = try t.next();
        try t.until("chat_loop");
        try std.testing.expectEqual(@as(u8, 1), t.get("STATE"));
        for (0..25) |row| try std.testing.expectEqualSlices(u8, attributes[row * 40 ..][0..40], t.h.bus.memory[0xf300 + row * 120 + 80 ..][0..40]);
        try t.feed(.cancel, 33, "");
        _ = try t.next();
        try t.h.steps(1000);
        try std.testing.expectEqual(@as(u16, 0xbeef), t.h.cpu.registers.pc);
        try std.testing.expectEqual(@as(u8, 0x43), t.h.cpu.registers.a);
        try std.testing.expectEqual(@as(u16, 0xe7f2), t.h.cpu.registers.sp);
        for (before, t.h.bus.memory, 0..) |old, actual, address| {
            if (address >= 0xd000 and address < 0xd800) continue;
            if (address >= 0xe700 and address < 0xe800) continue;
            if (address >= 0xf300 and address < 0xfeb8) continue;
            try std.testing.expectEqual(old, actual);
        }
    }
}

test "Z80 chat loading spinner follows VRTC while preserving cursor text and attributes" {
    for (0..4) |mode| {
        var t: Terminal = undefined;
        try t.init(@intCast(mode));
        defer t.deinit();
        try t.connect();
        t.set("STATE", 2);
        const before = t.h.bus.memory;
        const row = t.get("ROW");
        const col = t.get("COL");
        const spinner_cell = @as(usize, 0xf378) + 10 * t.get("STRIDE");
        const frames = [_]u8{ '|', '/', '-', 92 };
        for (frames) |expected| {
            for (0..8) |_| {
                t.h.vrtc = false;
                try t.presentation();
                t.h.vrtc = true;
                try t.presentation();
            }
            try std.testing.expectEqual(expected, t.h.bus.memory[spinner_cell]);
        }
        try std.testing.expectEqual(row, t.get("ROW"));
        try std.testing.expectEqual(col, t.get("COL"));
        for (0..25) |r| try std.testing.expectEqualSlices(u8, before[0xf300 + r * 120 + 80 ..][0..40], t.h.bus.memory[0xf300 + r * 120 + 80 ..][0..40]);
        try t.feed(.done, 1, "");
        _ = try t.next();
        try t.until("chat_loop");
        try t.presentation();
        try std.testing.expectEqual(@as(u8, ' '), t.h.bus.memory[spinner_cell]);
    }
}

test "Z80 chat prompt bounds 64 bytes and sends three acknowledged segments with Shift punctuation" {
    var t: Terminal = undefined;
    try t.init(0);
    defer t.deinit();
    try t.connect();
    t.h.keys[8] = 0xbf; // SHIFT
    try t.key(7, 64); // ?
    t.h.keys[8] = 255;
    for (0..65) |_| try t.key(2, 2);
    try std.testing.expectEqual(@as(u8, 64), t.get("LENGTH"));
    try std.testing.expectEqual(@as(u8, '?'), t.h.bus.memory[t.addr("PROMPT")]);
    t.h.keys[1] = 0x7f;
    var total: usize = 0;
    for (0..3) |i| {
        const prompt = try t.next();
        try std.testing.expectEqual(wire.Kind.prompt, prompt.kind);
        try std.testing.expectEqual(@as(u8, if (i == 2) 1 else 0), prompt.payload[0]);
        total += prompt.len - 1;
        try t.feed(.ack, prompt.seq, "");
    }
    t.h.keys[1] = 255;
    try t.until("chat_loop");
    try std.testing.expectEqual(@as(usize, 64), total);
    try std.testing.expectEqual(@as(u8, 2), t.get("STATE"));
}

test "Z80 chat corrupt oversized and non-ASCII frames never draw or advance sequence" {
    var t: Terminal = undefined;
    try t.init(0);
    defer t.deinit();
    try t.connect();
    t.set("STATE", 2);
    const row = t.get("ROW");
    const col = t.get("COL");
    var buffer: [wire.max_frame]u8 = undefined;
    const bad = try wire.encode(&buffer, .text, 1, "CORRUPT");
    buffer[bad.len - 1] ^= 1;
    try t.h.feed(bad);
    try t.h.steps(30000);
    try t.h.feed(&.{ 0xa5, 0x5a, 4, 1, 255 });
    try t.h.steps(30000);
    try t.feed(.text, 1, &.{255});
    try t.h.steps(30000);
    try std.testing.expectEqual(@as(u8, 1), t.get("RXSEQ"));
    try std.testing.expectEqual(row, t.get("ROW"));
    try std.testing.expectEqual(col, t.get("COL"));
    try t.feed(.text, 1, "VALID");
    try std.testing.expectEqual(wire.Kind.ack, (try t.next()).kind);
    try t.until("chat_loop");
    try std.testing.expectEqual(@as(u8, 2), t.get("RXSEQ"));
}
