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
        try std.testing.expect(self.image.bytes.items.len <= 0x715);
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
        try std.testing.expectEqual((self.get("COL") + self.get("ANIM_ACTIVE")) * self.get("STRIDE"), self.h.cursor_x);
        try std.testing.expectEqual(self.get("ROW"), self.h.cursor_y);
        try std.testing.expect(self.h.cursor_enabled);
        try std.testing.expect(!self.h.invalid_crtc_command);
        try self.h.steps(1);
        try self.until("chat_loop");
    }
    fn rowText(self: *Terminal, row: usize, text: []const u8) !void {
        for (text, 0..) |char, col| try std.testing.expectEqual(char, self.h.bus.memory[0xf300 + row * 120 + col * self.get("STRIDE")]);
    }
    fn fixed(self: *Terminal, state: []const u8) !void {
        try self.rowText(0, "ZIG_80 CHAT");
        for ([_]usize{ 1, 17 }) |row| {
            for (0..self.get("WIDTH")) |col| try std.testing.expectEqual(@as(u8, '-'), self.h.bus.memory[0xf300 + row * 120 + col * self.get("STRIDE")]);
        }
        try self.rowText(18, "> ");
        try self.rowText(19, state);
        const start = self.get("WIDTH") - 8;
        for ("ESC:EXIT", 0..) |char, col| try std.testing.expectEqual(char, self.h.bus.memory[0xf300 + 19 * 120 + (start + col) * self.get("STRIDE")]);
    }
    fn ask(self: *Terminal) !void {
        try self.key(2, 2);
        self.h.keys[1] = 0x7f;
        const prompt = try self.next();
        try std.testing.expectEqual(wire.Kind.prompt, prompt.kind);
        self.h.keys[1] = 255;
        try self.feed(.ack, prompt.seq, "");
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
            try t.presentation();
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
        try t.h.steps(10000);
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

test "Z80 chat spinner sits after AI and is replaced safely by text empty DONE and cancellation" {
    for (0..4) |mode| {
        var t: Terminal = undefined;
        try t.init(@intCast(mode));
        defer t.deinit();
        try t.connect();
        try t.ask();
        const before = t.h.bus.memory;
        const row = t.get("ROW");
        const col = t.get("COL");
        const spinner_cell = @as(usize, 0xf300) + row * @as(usize, 120) + col * t.get("STRIDE");
        for ("  ", 0..) |char, i| try std.testing.expectEqual(char, t.h.bus.memory[0xf300 + @as(usize, row) * 120 + i * t.get("STRIDE")]);
        try std.testing.expectEqual(@as(u8, '.'), t.h.bus.memory[spinner_cell]);
        const frames = [_]u8{ '+', '*', '+', '.' };
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
        try t.feed(.text, 1, "FIRST");
        _ = try t.next();
        try t.until("chat_loop");
        try t.presentation();
        try std.testing.expectEqual(@as(u8, 0), t.get("ANIM_ACTIVE"));
        for (0..8) |_| {
            t.h.vrtc = false;
            try t.presentation();
            t.h.vrtc = true;
            try t.presentation();
        }
        for ("FIRST", 0..) |char, i| try std.testing.expectEqual(char, t.h.bus.memory[spinner_cell + i * t.get("STRIDE")]);
        try t.feed(.done, 2, "");
        _ = try t.next();
        try t.until("chat_loop");
        try t.ask();
        const empty_cell = 0xf300 + @as(usize, t.get("ROW")) * 120 + @as(usize, t.get("COL")) * t.get("STRIDE");
        try t.feed(.done, 3, "");
        _ = try t.next();
        try t.until("chat_loop");
        try std.testing.expectEqual(@as(u8, ' '), t.h.bus.memory[empty_cell]);
        try t.ask();
        const cancel_cell = 0xf300 + @as(usize, t.get("ROW")) * 120 + @as(usize, t.get("COL")) * t.get("STRIDE");
        try t.feed(.cancel, 4, "");
        _ = try t.next();
        try t.h.steps(10000);
        try std.testing.expectEqual(@as(u16, 0xbeef), t.h.cpu.registers.pc);
        try std.testing.expectEqual(@as(u8, ' '), t.h.bus.memory[cancel_cell]);
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
    try t.presentation();
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

test "Z80 chat keeps new prompts visible through repeated full screens in 20-row mode" {
    for (0..8) |mode| {
        var t: Terminal = undefined;
        try t.init(@intCast(mode % 4));
        t.h.visible_rows = if (mode < 4) 20 else 25;
        defer t.deinit();
        try t.connect();
        try t.fixed("READY");
        const header = t.h.bus.memory[0xf300..0xf3f0].*;
        const attributes = t.h.bus.memory;
        var seq: u8 = 1;
        for (0..15) |_| {
            try t.ask();
            try t.fixed("THINKING");
            for (0..20) |_| {
                try t.feed(.text, seq, "ABCDEFG\n");
                _ = try t.next();
                try t.until("chat_loop");
                try std.testing.expect(t.get("ROW") <= 16);
                try t.fixed("RECEIVING");
                try std.testing.expectEqualSlices(u8, &header, t.h.bus.memory[0xf300..0xf3f0]);
                try t.presentation();
                seq +%= 1;
            }
            try t.feed(.done, seq, "");
            _ = try t.next();
            try t.until("chat_loop");
            seq +%= 1;
            try t.fixed("READY");
            for (0..25) |r| try std.testing.expectEqualSlices(u8, attributes[0xf300 + r * 120 + 80 ..][0..40], t.h.bus.memory[0xf300 + r * 120 + 80 ..][0..40]);
            try std.testing.expectEqual(@as(u8, 1), t.get("STATE"));
            try std.testing.expectEqual(@as(u8, 18), t.get("ROW"));
            try t.presentation();
            for ("> ", 0..) |c, col| try std.testing.expectEqual(c, t.h.bus.memory[0xf300 + @as(usize, t.get("ROW")) * 120 + col * t.get("STRIDE")]);
        }
        try t.feed(.cancel, seq, "");
        _ = try t.next();
        try t.h.steps(10000);
        try std.testing.expectEqual(@as(u16, 0xbeef), t.h.cpu.registers.pc);
    }
}

test "Z80 classic fixed input viewport follows 64 bytes and Backspace without changing history" {
    for (0..4) |mode| {
        var t: Terminal = undefined;
        try t.init(@intCast(mode));
        defer t.deinit();
        try t.connect();
        const body = t.h.bus.memory[0xf3f0..0xfaf8].*;
        for (0..65) |i| {
            try t.key(2, if (i % 2 == 0) 2 else 4);
            const length: u8 = @intCast(@min(i + 1, 64));
            const capacity = t.get("WIDTH") - 2;
            const start = length -| capacity;
            try std.testing.expectEqual(length, t.get("LENGTH"));
            try std.testing.expectEqual(start, t.get("INPUT_START"));
            try std.testing.expectEqual(@as(u8, 18), t.get("ROW"));
            try std.testing.expect(t.get("COL") < t.get("WIDTH"));
            for (start..length) |j| try std.testing.expectEqual(t.h.bus.memory[t.addr("PROMPT") + j], t.h.bus.memory[0xfb70 + (2 + j - start) * t.get("STRIDE")]);
            try std.testing.expectEqualSlices(u8, &body, t.h.bus.memory[0xf3f0..0xfaf8]);
            try t.presentation();
        }
        for (0..30) |_| try t.key(8, 8);
        try std.testing.expectEqual(@as(u8, 34), t.get("LENGTH"));
        try std.testing.expectEqual(@as(u8, 0), t.get("INPUT_START"));
        const expected = t.h.bus.memory[t.addr("PROMPT")..][0..34].*;
        t.h.keys[1] = 0x7f;
        var offset: usize = 0;
        for (0..2) |_| {
            const frame = try t.next();
            const count = frame.len - 1;
            try std.testing.expectEqualSlices(u8, expected[offset..][0..count], frame.payload[1..frame.len]);
            offset += count;
            try t.feed(.ack, frame.seq, "");
        }
        t.h.keys[1] = 255;
        try t.until("chat_loop");
        try std.testing.expectEqual(@as(usize, 34), offset);
        try t.fixed("THINKING");
        for (2..t.get("WIDTH")) |col| try std.testing.expectEqual(@as(u8, ' '), t.h.bus.memory[0xfb70 + col * t.get("STRIDE")]);
        try t.rowText(2, "> ABABAB");
    }
}

test "Z80 classic empty TEXT DONE ERROR and 1 8 32 byte streams preserve fixed regions" {
    for ([_]usize{ 1, 8, 32 }) |chunk| {
        var t: Terminal = undefined;
        try t.init(0);
        defer t.deinit();
        try t.connect();
        try t.ask();
        try t.feed(.text, 1, "");
        _ = try t.next();
        try t.until("chat_loop");
        try t.fixed("THINKING");
        try std.testing.expectEqual(@as(u8, 1), t.get("ANIM_ACTIVE"));
        var seq: u8 = 2;
        const text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ ABCDEFGHIJKLMNOPQRSTUVWXYZ\nNEW LINE";
        var offset: usize = 0;
        while (offset < text.len) {
            const end = @min(offset + chunk, text.len);
            try t.feed(.text, seq, text[offset..end]);
            _ = try t.next();
            try t.until("chat_loop");
            try t.fixed("RECEIVING");
            try std.testing.expectEqual(@as(u8, 0), t.get("ANIM_ACTIVE"));
            offset = end;
            seq +%= 1;
        }
        try t.rowText(4, "  ABCDEFGHIJKLMNOPQRSTUVWXYZ ABCDEFGHIJK");
        try t.rowText(5, "  LMNOPQRSTUVWXYZ");
        try t.rowText(6, "  NEW LINE");
        try t.feed(.done, seq, "");
        _ = try t.next();
        try t.until("chat_loop");
        try t.fixed("READY");
        seq +%= 1;
        try t.ask();
        try t.feed(.err, seq, "FAILED");
        _ = try t.next();
        try t.until("chat_loop");
        try t.fixed("ERROR");
        try std.testing.expectEqual(@as(u8, 18), t.get("ROW"));
    }
}

test "Z80 classic header model alignment alphabet space and static RAM boundaries" {
    for (0..4) |mode| {
        var t: Terminal = undefined;
        try t.init(@intCast(mode));
        defer t.deinit();
        const ranges = [_][2]u16{
            .{ 0xd000, t.addr("chat_end") },                  .{ t.addr("TX"), t.addr("TX") + 35 },
            .{ t.addr("PREVIOUS"), t.addr("PREVIOUS") + 37 }, .{ t.addr("KEYS"), t.addr("KEYS") + 10 },
            .{ t.addr("ENTRY_SP"), t.addr("HAVE_CHAT") + 1 }, .{ t.addr("PROMPT"), t.addr("PROMPT") + 64 },
            .{ t.addr("RX"), t.addr("RX") + 37 },
        };
        for (ranges, 0..) |range, i| {
            try std.testing.expect(range[0] >= 0xd000 and range[1] <= 0xd800);
            if (i != 0) try std.testing.expect(ranges[i - 1][1] <= range[0]);
        }
        _ = try t.next();
        try t.feed(.ack, 0, "");
        const model = "LONG-MODEL-NAME-1234";
        try t.feed(.ready, 0, "C1" ++ model);
        _ = try t.next();
        try t.until("chat_loop");
        try t.fixed("READY");
        for (model, 0..) |c, i| try std.testing.expectEqual(c, t.h.bus.memory[0xf300 + (t.get("WIDTH") - model.len + i) * t.get("STRIDE")]);
        for (1..27) |i| try t.key(2 + i / 8, @as(u8, 1) << @as(u3, @intCast(i % 8)));
        try t.key(9, 64);
        try std.testing.expectEqualStrings("ABCDEFGHIJKLMNOPQRSTUVWXYZ ", t.h.bus.memory[t.addr("PROMPT")..][0..27]);
        const immutable = t.addr("ack_buffer") - 0xd000;
        try std.testing.expectEqualSlices(u8, t.image.bytes.items[0..immutable], t.h.bus.memory[0xd000..][0..immutable]);
    }
}
