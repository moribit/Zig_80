const std = @import("std");
const Harness = @import("loader_harness.zig").Harness;
const wire = @import("loader_protocol.zig");
const assets = @import("loader_assets.zig");
const allocator = std.testing.allocator;
fn ready(h: *Harness) !void {
    for (0..10000) |_| {
        try h.steps(1);
        if (h.tx_len != 0) break;
    }
    try std.testing.expectEqualSlices(u8, &.{wire.mini_ready}, h.tx[0..h.tx_len]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0x40, 0x4e, 0x37 }, h.controls[0..6]);
    try std.testing.expectEqual(@as(u8, 0x2a), h.port30);
}
fn checksum(bytes: []const u8) u8 {
    var sum: u8 = 0;
    for (bytes) |byte| sum +%= byte;
    return 0 -% sum;
}
test "100-byte mini fits reserved RAM and preserves the exact 333-byte relay" {
    var images = try assets.Images.load(std.testing.io, allocator);
    defer images.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 100), images.mini.len);
    try std.testing.expect(wire.mini_address + images.mini.len <= wire.stage0_address);
    try std.testing.expectEqual(@as(usize, 333), images.stage0.len);
    var hash: [32]u8 = undefined;
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(images.stage0, &hash, .{});
    _ = try std.fmt.hexToBytes(&expected, "914b95198822e10778dbc96a3af25ee9dd5f3c606140f58da79c7db071285258");
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}
test "mini full receipt plus checksum hands off with original BASIC registers and stack" {
    var images = try assets.Images.load(std.testing.io, allocator);
    defer images.deinit(allocator);
    var h: Harness = undefined;
    try h.initMini(std.testing.io, allocator);
    try ready(&h);
    try h.feed(images.stage0);
    try h.feed(&.{checksum(images.stage0)});
    var handed_off = false;
    for (0..100000) |_| {
        try h.steps(1);
        if (h.cpu.registers.pc == wire.stage0_address) {
            handed_off = true;
            break;
        }
    }
    try std.testing.expect(handed_off);
    try std.testing.expectEqualSlices(u8, images.stage0, h.bus.memory[wire.stage0_address..][0..images.stage0.len]);
    try std.testing.expectEqual(@as(u16, 0xcf00), h.cpu.registers.sp);
    try std.testing.expectEqual(@as(u16, 0x1234), h.cpu.registers.af());
    try std.testing.expectEqual(@as(u16, 0x5678), h.cpu.registers.bc());
    try std.testing.expectEqual(@as(u16, 0x9abc), h.cpu.registers.de());
    try std.testing.expectEqual(@as(u16, 0xdef0), h.cpu.registers.hl());
    try std.testing.expectEqual(@as(u8, 0xa5), h.bus.memory[wire.stage0_address - 1]);
    try std.testing.expectEqual(@as(u8, 0xa5), h.bus.memory[wire.stage0_address + images.stage0.len]);
    for (0..10000) |_| {
        try h.steps(1);
        if (h.tx_len == 6) break;
    }
    try std.testing.expectEqualSlices(u8, &.{ 0x5a, 0x30, 1, 0, 5 }, h.tx[1..6]);
}
test "mini rejects partial absent corrupt checksum FE OE PE without executing relay" {
    var images = try assets.Images.load(std.testing.io, allocator);
    defer images.deinit(allocator);
    for (0..6) |fault| {
        var h: Harness = undefined;
        try h.initMini(std.testing.io, allocator);
        try ready(&h);
        if (fault < 2) {
            try h.feed(images.stage0[0..if (fault == 0) 7 else images.stage0.len]);
            if (fault != 0) try h.feed(&.{checksum(images.stage0) ^ 1});
        } else if (fault >= 3) {
            h.errors = ([_]u8{ 8, 16, 32 })[fault - 3];
        }
        for (0..800000) |_| {
            try h.steps(1);
            try std.testing.expect(h.cpu.registers.pc != wire.stage0_address);
        }
        try std.testing.expect(h.cpu.registers.pc >= wire.mini_address and h.cpu.registers.pc < wire.mini_address + 100);
        try std.testing.expectEqual(@as(usize, 0), h.application_entries);
        try std.testing.expectEqual(@as(u8, 0xa5), h.bus.memory[wire.stage0_address + images.stage0.len]);
    }
}
