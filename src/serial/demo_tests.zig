const std = @import("std");
const wire = @import("loader_protocol.zig");
const Harness = @import("loader_harness.zig").Harness;
const allocator = std.testing.allocator;

fn ack(reply: wire.Frame) !void {
    try std.testing.expectEqual(wire.ack, reply.kind);
    try std.testing.expectEqual(@as(u8, 0), reply.bytes[0]);
}
fn sine(index: usize) u8 {
    return @intFromFloat(@round(32 + 30 * @sin(2 * std.math.pi * @as(f64, @floatFromInt(index % 64)) / 64)));
}
fn referenceFrame(frame: u8) [512]u8 {
    var expected: [512]u8 = @splat(0);
    for (0..64) |angle| {
        const coordinates = [_][2]u8{
            .{ sine(angle), sine(angle + frame + 16) / 2 + 16 },
            .{ sine(angle + frame + 16) / 2 + 16, sine(angle) },
        };
        for (coordinates) |point| {
            const x = point[0];
            const y = point[1];
            expected[@as(usize, y / 4) * 32 + x / 2] |= @as(u8, 1) << @as(u3, @intCast(y % 4 + (x % 2) * 4));
        }
    }
    expected[8 * 32 + 16] |= 1; // Center pixel (32,32).
    return expected;
}

test "orbital demo renders deterministic frames in all text modes and restores attributes stack and loader" {
    var failure: @import("../assembler/assembler.zig").FailureLocation = .{};
    var image = try @import("../assembler/assembler.zig").assembleFile(std.testing.io, allocator, "examples/pc8001/orbital_rings.asm", &failure);
    defer image.deinit();
    try std.testing.expect(wire.app_min + image.bytes.items.len <= 0xd4e0);
    try std.testing.expect(0xd500 + 640 <= wire.app_end);
    const delay_pc = image.symbols.address("frame_delay").?;
    const frame_address = image.symbols.address("FRAME_NO").?;
    for ([_]u8{ 0, 1, 2, 3 }) |display_bits| {
        var h: Harness = undefined;
        try h.init(std.testing.io, allocator, false, false);
        h.bus.memory[0xea66] = 0x28 | display_bits;
        // Make exact attribute restoration observable, rather than assuming zeros.
        for (0..16) |row| for (0..40) |i| {
            h.bus.memory[0xf440 + row * 120 + i] = @truncate(row * 29 + i * 7);
        };
        try ack(try h.transact(wire.hello, 0, ""));
        var metadata: [9]u8 = @splat(0);
        wire.put16(&metadata, wire.app_min);
        wire.put16(metadata[2..], @intCast(image.bytes.items.len));
        wire.put16(metadata[4..], wire.app_min);
        wire.put16(metadata[6..], wire.crc(image.bytes.items));
        try ack(try h.transact(wire.begin, 1, &metadata));
        var sequence: u8 = 2;
        var offset: usize = 0;
        while (offset < image.bytes.items.len) {
            const count = @min(64, image.bytes.items.len - offset);
            try ack(try h.transact(wire.data, sequence, image.bytes.items[offset..][0..count]));
            sequence += 1;
            offset += count;
        }
        try ack(try h.transact(wire.verify, sequence, ""));
        const before = h.bus.memory;
        const stride: usize = if (display_bits & 1 != 0) 1 else 2;
        try ack(try h.transact(wire.exec, sequence + 1, ""));
        var seen: [128]bool = @splat(false);
        var finished = false;
        for (0..20_000_000) |_| {
            try h.steps(1);
            const frame = h.bus.memory[frame_address];
            if (h.cpu.registers.pc == delay_pc and frame < 128 and !seen[frame]) {
                seen[frame] = true;
                if (frame == 0 or frame == 16) {
                    const expected = referenceFrame(frame);
                    for (0..16) |row| {
                        for (0..32) |column| try std.testing.expectEqual(expected[row * 32 + column], h.bus.memory[0xf3f0 + row * 120 + column * stride]);
                        const base = 0xf440 + row * 120;
                        try std.testing.expectEqual(@as(u8, 0), h.bus.memory[base]);
                        try std.testing.expectEqual(@as(u8, if (display_bits & 2 != 0) 0x80 else 0xf8), h.bus.memory[base + 1]);
                        try std.testing.expectEqual(@as(u8, @intCast(32 * stride)), h.bus.memory[base + 2]);
                    }
                }
            }
            if (frame == 128 and h.cpu.registers.pc >= wire.stage1_address and h.cpu.registers.pc < wire.stage1_address + wire.stage1_size) {
                finished = true;
                break;
            }
        }
        try std.testing.expect(finished);
        for (seen) |value| try std.testing.expect(value);
        try h.steps(10000);
        for (before, 0..) |byte, address| {
            const scratch = (address >= 0xd4e0 and address < 0xd4e6) or (address >= 0xd500 and address < 0xd780);
            const loader_work = address >= 0xe600 and address < 0xe900;
            const video = address >= 0xf300 and address < 0xfeb8;
            if (!scratch and !loader_work and !video) try std.testing.expectEqual(byte, h.bus.memory[address]);
        }
        const title = "ZIG_80  ORBITAL RINGS";
        const footer = "COMPLETE - LOADER READY    ";
        for (0..25) |row| for (0..120) |column| {
            const address = 0xf300 + row * 120 + column;
            var expected = before[address];
            if (column % stride == 0) {
                const cell = column / stride;
                if (row >= 2 and row < 18 and cell < 32) expected = 32;
                if (row == 0 and cell < title.len) expected = title[cell];
                if (row == 19 and cell < footer.len) expected = footer[cell];
            }
            try std.testing.expectEqual(expected, h.bus.memory[address]);
        };
        try std.testing.expectEqual(@as(u8, 0x28 | display_bits), h.port30);
        try std.testing.expectEqual(@as(usize, 1), h.application_entries);
        try std.testing.expect(h.cpu.registers.sp >= 0xe700 and h.cpu.registers.sp <= 0xe800);
        var parser: wire.Parser = .{};
        var returned = false;
        for (h.tx[0..h.tx_len]) |byte| if (try parser.feed(byte)) |reply| {
            if (reply.kind == 0x82) {
                try std.testing.expectEqual(@as(u8, 0x52), reply.bytes[6]);
                returned = true;
            }
        };
        try std.testing.expect(returned);
    }
}
