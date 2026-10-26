const std = @import("std");
const assembler = @import("../assembler/assembler.zig");
const wire = @import("loader_protocol.zig");
const Harness = @import("loader_harness.zig").Harness;
const allocator = std.testing.allocator;
fn ack(reply: wire.Frame) !void {
    try std.testing.expectEqual(wire.ack, reply.kind);
    try std.testing.expectEqual(@as(u8, 0), reply.bytes[0]);
}
const Game = struct {
    h: Harness,
    image: assembler.Result,
    fn init(self: *Game, mode: u8) !void {
        var failure: assembler.FailureLocation = .{};
        self.image = try assembler.assembleFile(std.testing.io, allocator, "examples/pc8001/invaders.asm", &failure);
        errdefer self.image.deinit();
        try std.testing.expect(self.image.bytes.items.len <= 0x700);
        try self.h.init(std.testing.io, allocator, false, false);
        self.h.bus.memory[0xea66] = 0x28 | mode;
        try ack(try self.h.transact(wire.hello, 0, ""));
        var metadata: [9]u8 = @splat(0);
        wire.put16(&metadata, wire.app_min);
        wire.put16(metadata[2..], @intCast(self.image.bytes.items.len));
        wire.put16(metadata[4..], wire.app_min);
        wire.put16(metadata[6..], wire.crc(self.image.bytes.items));
        try ack(try self.h.transact(wire.begin, 1, &metadata));
        var sequence: u8 = 2;
        var offset: usize = 0;
        while (offset < self.image.bytes.items.len) {
            const count = @min(64, self.image.bytes.items.len - offset);
            try ack(try self.h.transact(wire.data, sequence, self.image.bytes.items[offset..][0..count]));
            offset += count;
            sequence += 1;
        }
        try ack(try self.h.transact(wire.verify, sequence, ""));
        try ack(try self.h.transact(wire.exec, sequence + 1, ""));
    }
    fn deinit(self: *Game) void {
        self.image.deinit();
    }
    fn address(self: *const Game, name: []const u8) u16 {
        return self.image.symbols.address(name).?;
    }
    fn get(self: *const Game, name: []const u8) u8 {
        return self.h.bus.memory[self.address(name)];
    }
    fn set(self: *Game, name: []const u8, value: u8) void {
        self.h.bus.memory[self.address(name)] = value;
    }
    fn until(self: *Game, name: []const u8) !void {
        const pc = self.address(name);
        for (0..300000) |_| {
            if (self.h.cpu.registers.pc == pc) return;
            try self.h.steps(1);
        }
        return error.GameDidNotReachCheckpoint;
    }
    fn frame(self: *Game, keypad: u8, cursor: u8, action: u8) !void {
        try std.testing.expectEqual(self.address("frame_loop"), self.h.cpu.registers.pc);
        self.h.keys[0] = keypad;
        self.h.keys[8] = cursor;
        self.h.keys[9] = action;
        try self.h.steps(1);
        try self.until("frame_loop");
    }
    fn quit(self: *Game, key: u8) !void {
        self.h.keys[9] = key;
        var returned = false;
        for (0..300000) |_| {
            try self.h.steps(1);
            if (self.h.cpu.registers.pc >= wire.stage1_address and self.h.cpu.registers.pc < wire.stage1_address + wire.stage1_size) {
                returned = true;
                break;
            }
        }
        try std.testing.expect(returned);
        try self.h.steps(10000);
        var parser: wire.Parser = .{};
        var notification = false;
        for (self.h.tx[0..self.h.tx_len]) |byte| if (try parser.feed(byte)) |reply| {
            if (reply.kind == 0x82) {
                try std.testing.expectEqual(@as(u8, 0x49), reply.bytes[6]);
                notification = true;
            }
        };
        try std.testing.expect(notification);
        try std.testing.expect(self.h.cpu.registers.sp >= 0xe700 and self.h.cpu.registers.sp <= 0xe800);
    }
};
fn textAt(game: *const Game, row: usize, stride: usize, expected: []const u8) !void {
    for (expected, 0..) |byte, column| try std.testing.expectEqual(byte, game.h.bus.memory[0xf300 + row * 120 + column * stride]);
}
fn referenceSprite(canvas: *[640]u8, x: usize, y: usize, bytes: []const u8) void {
    for (bytes, 0..) |bits, row| for (0..7) |column| {
        if (bits & (@as(u8, 0x40) >> @as(u3, @intCast(column))) != 0) referencePixel(canvas, x + column, y + row);
    };
}
fn referencePixel(canvas: *[640]u8, x: usize, y: usize) void {
    canvas[(y / 4) * 40 + x / 2] |= @as(u8, 1) << @as(u3, @intCast(y % 4 + x % 2 * 4));
}
test "invaders clears every old character and attribute then renders sprites and exits cleanly in all modes" {
    for ([_]u8{ 0, 1, 2, 3 }) |mode| {
        var game: Game = undefined;
        try game.init(mode);
        defer game.deinit();
        const before = game.h.bus.memory;
        try game.until("screen_cleared");
        const normal: u8 = if (mode & 2 != 0) 0 else 0xe8;
        for (0..25) |row| {
            for (0..80) |column| try std.testing.expectEqual(@as(u8, 32), game.h.bus.memory[0xf300 + row * 120 + column]);
            for (0..20) |pair| {
                try std.testing.expectEqual(@as(u8, if (pair == 0) 0 else 80), game.h.bus.memory[0xf350 + row * 120 + pair * 2]);
                try std.testing.expectEqual(normal, game.h.bus.memory[0xf351 + row * 120 + pair * 2]);
            }
        }
        try game.until("frame_loop");
        try game.frame(0xff, 0xff, 0xff);
        const stride: usize = if (mode & 1 != 0) 1 else 2;
        var expected: [640]u8 = @splat(0);
        for (0..10) |i| referenceSprite(&expected, 5 + i % 5 * 12, 4 + i / 5 * 10, &.{ 28, 62, 107, 127, 34 });
        referenceSprite(&expected, 36, 57, &.{ 8, 28, 62, 127, 99 });
        referencePixel(&expected, 8, 9);
        referencePixel(&expected, 8, 10);
        for (0..16) |row| {
            for (0..40) |column| try std.testing.expectEqual(expected[row * 40 + column], game.h.bus.memory[0xf3f0 + row * 120 + column * stride]);
            try std.testing.expectEqual(@as(u8, if (mode & 2 != 0) 0x80 else 0xf8), game.h.bus.memory[0xf441 + row * 120]);
            try std.testing.expectEqual(@as(u8, @intCast(40 * stride)), game.h.bus.memory[0xf442 + row * 120]);
        }
        try textAt(&game, 0, stride, "INVADERS  SCORE 00  LIVES 3");
        try game.quit(0x7f); // ESC.
        const exit = "LOADER READY - INVADERS CLOSED";
        for (0..25) |row| {
            for (0..80) |column| {
                const value: u8 = if (row == 0 and column % stride == 0 and column / stride < exit.len) exit[column / stride] else 32;
                try std.testing.expectEqual(value, game.h.bus.memory[0xf300 + row * 120 + column]);
            }
            for (0..20) |pair| {
                try std.testing.expectEqual(@as(u8, if (pair == 0) 0 else 80), game.h.bus.memory[0xf350 + row * 120 + pair * 2]);
                try std.testing.expectEqual(normal, game.h.bus.memory[0xf351 + row * 120 + pair * 2]);
            }
        }
        for (before, 0..) |byte, address| {
            const allowed = (address >= 0xd700 and address < 0xd72a) or (address >= 0xd7e0 and address < 0xd7e5) or
                (address >= 0xe600 and address < 0xe900) or (address >= 0xf300 and address < 0xfeb8);
            if (!allowed) try std.testing.expectEqual(byte, game.h.bus.memory[address]);
        }
        try std.testing.expectEqual(@as(u8, 0x28 | mode), game.h.port30);
        try std.testing.expectEqual(@as(usize, 1), game.h.application_entries);
    }
}
test "invaders active-low cursor shift keypad bounds and simultaneous movement plus space" {
    var game: Game = undefined;
    try game.init(2);
    defer game.deinit();
    try game.until("frame_loop");
    try game.frame(0xff, 0xfb, 0xff);
    try std.testing.expectEqual(@as(u8, 38), game.get("PLAYER_X"));
    try game.frame(0xff, 0xbb, 0xff);
    try std.testing.expectEqual(@as(u8, 36), game.get("PLAYER_X"));
    try game.frame(0xef, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 34), game.get("PLAYER_X"));
    try game.frame(0xbf, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 36), game.get("PLAYER_X"));
    try game.frame(0xaf, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 36), game.get("PLAYER_X"));
    game.set("PLAYER_X", 1);
    try game.frame(0xff, 0xbb, 0xff);
    try game.frame(0xff, 0xbb, 0xff);
    try std.testing.expectEqual(@as(u8, 0), game.get("PLAYER_X"));
    game.set("PLAYER_X", 72);
    try game.frame(0xff, 0xfb, 0xff);
    try game.frame(0xff, 0xfb, 0xff);
    try std.testing.expectEqual(@as(u8, 73), game.get("PLAYER_X"));
    game.set("PLAYER_X", 10);
    try game.frame(0xff, 0xfb, 0xbf);
    try std.testing.expectEqual(@as(u8, 12), game.get("PLAYER_X"));
    try std.testing.expectEqual(@as(u8, 1), game.get("SHOT_ACTIVE"));
    try std.testing.expectEqual(@as(u8, 15), game.get("SHOT_X"));
    try std.testing.expectEqual(@as(u8, 53), game.get("SHOT_Y"));
    try game.frame(0xff, 0xfb, 0xbf);
    try std.testing.expectEqual(@as(u8, 15), game.get("SHOT_X"));
    try std.testing.expectEqual(@as(u8, 51), game.get("SHOT_Y"));
    try game.quit(0xfe); // STOP also returns safely.
}
test "invaders hits scoring victory release-before-restart lives and invulnerability" {
    var game: Game = undefined;
    try game.init(2);
    defer game.deinit();
    try game.until("frame_loop");
    game.set("TICK", 1);
    game.set("SHOT_ACTIVE", 1);
    game.set("SHOT_X", 7);
    game.set("SHOT_Y", 8);
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 0), game.h.bus.memory[game.address("ALIVE")]);
    try std.testing.expectEqual(@as(u8, 9), game.get("REMAINING"));
    try textAt(&game, 0, 2, "INVADERS  SCORE 01  LIVES 3");
    game.set("SHOT_ACTIVE", 1);
    game.set("SHOT_X", 79);
    game.set("SHOT_Y", 8);
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 9), game.get("REMAINING"));
    game.set("SHOT_Y", 1);
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 0), game.get("SHOT_ACTIVE"));
    @memset(game.h.bus.memory[game.address("ALIVE")..][0..10], 0);
    game.h.bus.memory[game.address("ALIVE") + 9] = 1;
    game.set("REMAINING", 1);
    game.set("SHOT_ACTIVE", 1);
    game.set("SHOT_X", 55);
    game.set("SHOT_Y", 18);
    try game.frame(0xff, 0xff, 0xbf);
    try std.testing.expectEqual(@as(u8, 0), game.get("REMAINING"));
    try std.testing.expectEqual(@as(u8, 1), game.get("GAME_MODE"));
    try game.frame(0xff, 0xff, 0xbf);
    try std.testing.expectEqual(@as(u8, 1), game.get("GAME_MODE"));
    try game.frame(0xff, 0xff, 0xff);
    try game.frame(0xff, 0xff, 0xbf);
    try std.testing.expectEqual(@as(u8, 0), game.get("GAME_MODE"));
    try std.testing.expectEqual(@as(u8, 10), game.get("REMAINING"));
    try std.testing.expectEqual(@as(u8, 3), game.get("LIVES"));
    for (0..2) |hit| {
        game.set("TICK", 1);
        game.set("ENEMY_SHOT", 1);
        game.set("ENEMY_X", game.get("PLAYER_X") + 3);
        game.set("ENEMY_Y", 55);
        try game.frame(0xff, 0xff, 0xff);
        try std.testing.expectEqual(@as(u8, 2), game.get("LIVES"));
        if (hit == 0) try std.testing.expectEqual(@as(u8, 24), game.get("HIT_TIMER"));
    }
    game.set("HIT_TIMER", 0);
    game.set("ENEMY_SHOT", 1);
    game.set("ENEMY_X", game.get("PLAYER_X") + 3);
    game.set("ENEMY_Y", 61);
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 2), game.get("LIVES")); // A bullet below the ship is not a hit.
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 0), game.get("ENEMY_SHOT"));
    game.set("LIVES", 1);
    game.set("ENEMY_SHOT", 1);
    game.set("ENEMY_X", game.get("PLAYER_X") + 3);
    game.set("ENEMY_Y", 55);
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 0), game.get("LIVES"));
    try std.testing.expectEqual(@as(u8, 2), game.get("GAME_MODE"));
    try game.quit(0x7f);
}
test "invaders fleet reverses descends and ends round before leaving the playfield" {
    var game: Game = undefined;
    try game.init(2);
    defer game.deinit();
    try game.until("frame_loop");
    game.set("FLEET_X", 24);
    game.set("TICK", 0);
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 0), game.get("FLEET_DIR"));
    try std.testing.expectEqual(@as(u8, 6), game.get("FLEET_Y"));
    game.set("FLEET_X", 2);
    game.set("TICK", 8);
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 1), game.get("FLEET_DIR"));
    try std.testing.expectEqual(@as(u8, 8), game.get("FLEET_Y"));
    game.set("FLEET_X", 24);
    game.set("FLEET_Y", 40);
    game.set("TICK", 0);
    try game.frame(0xff, 0xff, 0xff);
    try std.testing.expectEqual(@as(u8, 2), game.get("GAME_MODE"));
    try game.quit(0x7f);
}
