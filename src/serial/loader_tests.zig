const std = @import("std");
const wire = @import("loader_protocol.zig");
const Harness = @import("loader_harness.zig").Harness;
const allocator = std.testing.allocator;

fn expectStatus(frame: wire.Frame, code: u8) !void {
    try std.testing.expectEqual(if (code == 0) wire.ack else wire.nak, frame.kind);
    try std.testing.expectEqual(code, frame.bytes[0]);
}
fn beginBytes(address: u16, size: u16, entry: u16, crc: u16, existing: bool) [9]u8 {
    var bytes: [9]u8 = undefined;
    wire.put16(&bytes, address);
    wire.put16(bytes[2..], size);
    wire.put16(bytes[4..], entry);
    wire.put16(bytes[6..], crc);
    bytes[8] = @intFromBool(existing);
    return bytes;
}
test "Stage0 READY fixed image CRC16 handoff and non-overlapping reserved regions" {
    var cold = try Harness.assemble(std.testing.io, allocator, "stage0", false);
    defer cold.deinit();
    var resident = try Harness.assemble(std.testing.io, allocator, "stage1", false);
    defer resident.deinit();
    try std.testing.expect(wire.stage1_address + wire.stage1_size <= wire.stage0_address);
    try std.testing.expect(cold.bytes.items.len <= 512);
    try std.testing.expect(resident.bytes.items.len <= wire.stage1_size);
    var image: [wire.stage1_size]u8 = @splat(0);
    @memcpy(image[0..resident.bytes.items.len], resident.bytes.items);
    var h: Harness = undefined;
    try h.init(std.testing.io, allocator, true, false);
    for (0..10000) |_| {
        try h.steps(1);
        if (h.tx_len == 5) break;
    }
    try std.testing.expectEqualSlices(u8, &.{ 0x5a, 0x30, 1, 0, 5 }, h.tx[0..h.tx_len]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0x40, 0x4e, 0x37 }, h.controls[0..6]);
    try h.feed("G");
    try h.feed(&image);
    var trailer: [2]u8 = undefined;
    wire.put16(&trailer, wire.crc(&image));
    try h.feed(&trailer);
    var entered = false;
    for (0..2_000_000) |_| {
        try h.steps(1);
        if (h.cpu.registers.pc == wire.stage1_address) {
            entered = true;
            break;
        }
    }
    try std.testing.expect(entered);
    try std.testing.expectEqual(@as(u8, 'O'), h.tx[h.tx_len - 1]);
    try std.testing.expectEqualSlices(u8, &image, h.bus.memory[wire.stage1_address..][0..wire.stage1_size]);
    try std.testing.expectEqual(@as(u8, 0xa5), h.bus.memory[wire.stage1_address - 1]);
    try std.testing.expectEqual(@as(u8, 0xa5), h.bus.memory[wire.stage1_address + wire.stage1_size]);
}
test "Stage0 incomplete corrupt or absent image never jumps and restores BASIC stack" {
    for (0..3) |fault| {
        var h: Harness = undefined;
        try h.init(std.testing.io, allocator, true, true);
        for (0..10000) |_| {
            try h.steps(1);
            if (h.tx_len == 5) break;
        }
        if (fault != 0) {
            try h.feed("G");
            const image: [wire.stage1_size + 2]u8 = @splat(0);
            try h.feed(image[0..if (fault == 1) 11 else image.len]);
        }
        try h.steps(2_000_000);
        try std.testing.expectEqual(@as(u16, 0xbeef), h.cpu.registers.pc);
        try std.testing.expectEqual(@as(u16, 0xcf02), h.cpu.registers.sp);
        try std.testing.expectEqual(@as(u16, 0x1234), h.cpu.registers.af());
        try std.testing.expectEqual(@as(u8, 1), h.bus.memory[0xe806]);
    }
}
test "Stage0 binary preflight returns all 256 values without executing the test data" {
    var h: Harness = undefined;
    try h.init(std.testing.io, allocator, true, false);
    for (0..10000) |_| {
        try h.steps(1);
        if (h.tx_len == 5) break;
    }
    var bytes: [256]u8 = undefined;
    for (&bytes, 0..) |*byte, i| byte.* = @intCast(i);
    var crc: [2]u8 = undefined;
    wire.put16(&crc, wire.crc(&bytes));
    try h.feed("T");
    try h.feed(&bytes);
    try h.feed(&crc);
    for (0..1_000_000) |_| {
        try h.steps(1);
        try std.testing.expect(h.cpu.registers.pc < wire.stage1_address or h.cpu.registers.pc >= wire.stage1_address + wire.stage1_size);
        if (h.cpu.registers.pc == 0xbeef) break;
    }
    try std.testing.expectEqual(@as(u16, 0xbeef), h.cpu.registers.pc);
    try std.testing.expectEqualSlices(u8, &bytes, h.tx[5..261]);
    try std.testing.expectEqual(@as(u8, 'O'), h.tx[261]);
    try std.testing.expectEqual(@as(u8, 0), h.bus.memory[0xe806]);
}
test "resident CRC data retransmission VERIFY EXEC return and repeat deployment" {
    var h: Harness = undefined;
    try h.init(std.testing.io, allocator, false, false);
    const hello = try h.transact(wire.hello, 0, "");
    try expectStatus(hello, 0);
    try std.testing.expectEqual(wire.crc(h.bus.memory[wire.stage1_address..][0..wire.stage1_size]), wire.read16(hello.bytes[6..]));
    const image = [_]u8{ 0x3e, 0x42, 0x32, 0x00, 0xd7, 0xc9 }; // LD A,42; LD (D700),A; RET
    const metadata = beginBytes(0xd000, image.len, 0xd000, wire.crc(&image), false);
    try expectStatus(try h.transact(wire.begin, 1, &metadata), 0);
    try expectStatus(try h.transact(wire.exec, 2, ""), 6);
    try expectStatus(try h.transact(wire.data, 2, &image), 0);
    const duplicate = try h.transact(wire.data, 2, &image);
    try expectStatus(duplicate, 0);
    try std.testing.expectEqual(@as(u16, image.len), wire.read16(duplicate.bytes[6..]));
    try expectStatus(try h.transact(wire.verify, 3, ""), 0);
    try expectStatus(try h.transact(wire.exec, 4, ""), 0);
    try h.steps(3000);
    try std.testing.expectEqual(@as(u8, 0x42), h.bus.memory[0xd700]);
    try std.testing.expectEqual(@as(usize, 1), h.application_entries);
    try expectStatus(try h.transact(wire.exec, 4, ""), 0);
    try h.steps(3000);
    try std.testing.expectEqual(@as(usize, 1), h.application_entries);
    try expectStatus(try h.transact(wire.hello, 0, ""), 0);
    try expectStatus(try h.transact(wire.begin, 1, &metadata), 0);
    try expectStatus(try h.transact(wire.data, 2, &image), 0);
    try expectStatus(try h.transact(wire.verify, 3, ""), 0);
    try expectStatus(try h.transact(wire.exec, 4, ""), 0);
    try h.steps(3000);
    try std.testing.expectEqual(@as(usize, 2), h.application_entries);
}
test "resident rejects invalid ranges entries CRC missing out of order and conflicting duplicates" {
    var h: Harness = undefined;
    try h.init(std.testing.io, allocator, false, true);
    try expectStatus(try h.transact(wire.hello, 0, ""), 0);
    for ([_]u16{ 0, 0x6000, 0xcfff, 0xd800, 0xe400, 0xe600, 0xe800, 0xea66, 0xf300, 0xffff }) |address| {
        const bad = beginBytes(address, 2, address, 0, false);
        try expectStatus(try h.transact(wire.begin, 1, &bad), 4);
    }
    for ([_][3]u16{ .{ 0xd000, 0, 0xd000 }, .{ 0xd000, 2049, 0xd000 }, .{ 0xd000, 1, 0xd001 }, .{ 0xd7ff, 2, 0xd7ff } }) |bad| {
        try expectStatus(try h.transact(wire.begin, 1, &beginBytes(bad[0], bad[1], bad[2], 0, false)), 4);
    }
    const image = [_]u8{ 0xc9, 0, 0, 0 };
    try expectStatus(try h.transact(wire.begin, 1, &beginBytes(0xd000, 4, 0xd000, wire.crc(&image), false)), 0);
    try expectStatus(try h.transact(wire.data, 3, &image), 5);
    try expectStatus(try h.transact(wire.verify, 2, ""), 6);
    var buffer: [wire.max_frame]u8 = undefined;
    const encoded = try wire.encode(&buffer, wire.data, 2, &image);
    buffer[6] ^= 1;
    try expectStatus(try h.exchange(encoded), 1);
    try std.testing.expectEqual(@as(u8, 0xa5), h.bus.memory[0xd000]);
    try expectStatus(try h.transact(wire.data, 2, &image), 0);
    try expectStatus(try h.transact(wire.data, 2, &.{ 0, 0, 0, 0 }), 5);
    h.bus.memory[0xd001] = 1;
    try expectStatus(try h.transact(wire.verify, 3, ""), 1);
    try expectStatus(try h.transact(wire.exec, 3, ""), 6);
    try expectStatus(try h.transact(wire.abort, 3, ""), 0);
    try expectStatus(try h.transact(wire.data, 4, &image), 6);
    try std.testing.expectEqual(@as(usize, 0), h.application_entries);
    for (h.bus.memory[0..0xcec0]) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
    for (h.bus.memory[0xe900..], 0xe900..) |byte, address| if (address != 0xea66 and !(address >= 0xfbe8 and address < 0xfc38 and (address - 0xfbe8) % 2 == 0)) {
        try std.testing.expectEqual(@as(u8, 0xa5), byte);
    };
}
test "resident echoes every binary byte and recovers a partial frame timeout and USART errors" {
    var h: Harness = undefined;
    try h.init(std.testing.io, allocator, false, true);
    try expectStatus(try h.transact(wire.hello, 0, ""), 0);
    for (0..4) |block| {
        var bytes: [64]u8 = undefined;
        for (&bytes, 0..) |*byte, i| byte.* = @intCast(block * 64 + i);
        const response = try h.transact(wire.echo, @intCast(block + 1), &bytes);
        try std.testing.expectEqual(wire.echo_reply, response.kind);
        try std.testing.expectEqualSlices(u8, &bytes, response.payload());
    }
    try h.feed(&.{ 0xa5, 0x5a, 1, wire.echo, 5 });
    try h.steps(20000);
    for ([_]u8{ 8, 16, 32 }) |flags| {
        h.errors = flags;
        try h.steps(1000);
        try std.testing.expectEqual(@as(u8, 0), h.errors);
    }
    const status = try h.transact(wire.info, 5, "");
    try expectStatus(status, 0);
    try std.testing.expect(wire.read16(status.bytes[10..]) >= 3);
    try std.testing.expect(wire.read16(status.bytes[12..]) >= 1);
}
test "deployed samples write VRAM RAM and restore the resident stack through RET or D803" {
    for ([_][]const u8{ "hello", "memory_test", "return_to_loader" }) |name| {
        var path: [128]u8 = undefined;
        const filename = try std.fmt.bufPrint(&path, "examples/pc8001/{s}.asm", .{name});
        var failure: @import("../assembler/assembler.zig").FailureLocation = .{};
        var image = try @import("../assembler/assembler.zig").assembleFile(std.testing.io, allocator, filename, &failure);
        defer image.deinit();
        var h: Harness = undefined;
        try h.init(std.testing.io, allocator, false, false);
        if (std.mem.eql(u8, name, "hello")) h.bus.memory[0xea66] |= 1; // Explicit WIDTH 80 precondition for contiguous cells.
        try expectStatus(try h.transact(wire.hello, 0, ""), 0);
        try expectStatus(try h.transact(wire.begin, 1, &beginBytes(wire.app_min, @intCast(image.bytes.items.len), wire.app_min, wire.crc(image.bytes.items), false)), 0);
        var sequence: u8 = 2;
        var offset: usize = 0;
        while (offset < image.bytes.items.len) {
            const count = @min(64, image.bytes.items.len - offset);
            try expectStatus(try h.transact(wire.data, sequence, image.bytes.items[offset..][0..count]), 0);
            offset += count;
            sequence += 1;
        }
        try expectStatus(try h.transact(wire.verify, sequence, ""), 0);
        try expectStatus(try h.transact(wire.exec, sequence + 1, ""), 0);
        try h.steps(20000);
        try std.testing.expectEqual(@as(usize, 1), h.application_entries);
        try std.testing.expect(h.cpu.registers.sp >= 0xe700 and h.cpu.registers.sp <= 0xe800);
        try std.testing.expectEqual(@as(u8, 0x37), h.command);
        if (std.mem.eql(u8, name, "hello")) try std.testing.expectEqualStrings("HELLO FROM ZIG_80", h.bus.memory[0xf300..][0..17]);
        if (std.mem.eql(u8, name, "memory_test")) {
            for (h.bus.memory[0xd700..0xd710], 0..) |byte, i| try std.testing.expectEqual(@as(u8, @intCast(i)), byte);
            try std.testing.expectEqual(@as(u8, 0), h.bus.memory[0xd710]);
        }
        if (std.mem.eql(u8, name, "return_to_loader")) try std.testing.expectEqual(@as(u8, 0x52), h.bus.memory[0xd710]);
    }
}

test "hello respects 40 and 80 column character stride without changing attributes or serial mode" {
    var failure: @import("../assembler/assembler.zig").FailureLocation = .{};
    var image = try @import("../assembler/assembler.zig").assembleFile(std.testing.io, allocator, "examples/pc8001/hello.asm", &failure);
    defer image.deinit();
    const message = "HELLO FROM ZIG_80";
    for ([_]u8{ 0, 1 }) |width80| {
        var h: Harness = undefined;
        try h.init(std.testing.io, allocator, false, false);
        h.bus.memory[0xea66] = 0x0a | width80;
        try expectStatus(try h.transact(wire.hello, 0, ""), 0);
        try expectStatus(try h.transact(wire.begin, 1, &beginBytes(wire.app_min, @intCast(image.bytes.items.len), wire.app_min, wire.crc(image.bytes.items), false)), 0);
        try expectStatus(try h.transact(wire.data, 2, image.bytes.items), 0);
        try expectStatus(try h.transact(wire.verify, 3, ""), 0);
        const screen_before = h.bus.memory[0xf300..0xfeb8].*;
        try expectStatus(try h.transact(wire.exec, 4, ""), 0);
        try h.steps(20000);
        const stride: usize = if (width80 == 1) 1 else 2;
        for (h.bus.memory[0xf300..0xfeb8], 0..) |byte, i| {
            const expected: u8 = if (i % stride == 0 and i / stride < message.len) message[i / stride] else screen_before[i];
            try std.testing.expectEqual(expected, byte);
        }
        try std.testing.expectEqual(@as(u8, 0x2a | width80), h.port30);
        try std.testing.expectEqual(@as(usize, 1), h.application_entries);
        try std.testing.expect(h.cpu.registers.sp >= 0xe700 and h.cpu.registers.sp <= 0xe800);
        var parser: wire.Parser = .{};
        var returned_mode: ?u8 = null;
        for (h.tx[0..h.tx_len]) |byte| if (try parser.feed(byte)) |frame| {
            if (frame.kind == 0x82) returned_mode = frame.bytes[6];
        };
        try std.testing.expectEqual(width80, returned_mode.?);
    }
}

fn expectLoadBar(h: *Harness, filled: usize, stride: usize) !void {
    const label = "LOAD [";
    for (0..80 / stride) |col| {
        const expected: u8 = if (col < label.len) label[col] else if (col < label.len + 16) (if (col - label.len < filled) '#' else '.') else if (col == label.len + 16) ']' else ' ';
        try std.testing.expectEqual(expected, h.bus.memory[0xfbe8 + col * stride]);
    }
}

test "resident receiver progress counts only accepted bytes in every width and color mode" {
    for (0..4) |mode| {
        var h: Harness = undefined;
        try h.init(std.testing.io, allocator, false, false);
        h.bus.memory[0xea66] = 0x28 | @as(u8, @intCast(mode));
        const stride: usize = if (mode & 1 == 0) 2 else 1;
        const screen = h.bus.memory[0xf300..0xfeb8].*;
        const resident = h.bus.memory[wire.stage1_address..][0..wire.stage1_size].*;
        var image: [128]u8 = @splat(0);
        image[0] = 0xc9;
        try expectStatus(try h.transact(wire.hello, 0, ""), 0);
        try expectStatus(try h.transact(wire.begin, 1, &beginBytes(0xd000, image.len, 0xd000, wire.crc(&image), false)), 0);
        try expectLoadBar(&h, 0, stride);
        try expectStatus(try h.transact(wire.data, 2, image[0..64]), 0);
        try expectLoadBar(&h, 8, stride);
        try expectStatus(try h.transact(wire.data, 2, image[0..64]), 0);
        try expectLoadBar(&h, 8, stride);
        var buffer: [wire.max_frame]u8 = undefined;
        const bad = try wire.encode(&buffer, wire.data, 3, image[64..]);
        buffer[bad.len - 1] ^= 1;
        try expectStatus(try h.exchange(bad), 1);
        try expectLoadBar(&h, 8, stride);
        try expectStatus(try h.transact(wire.data, 4, image[64..]), 5);
        try expectLoadBar(&h, 8, stride);
        try expectStatus(try h.transact(wire.data, 3, image[64..]), 0);
        try expectLoadBar(&h, 16, stride);
        try expectStatus(try h.transact(wire.verify, 4, ""), 0);
        try expectStatus(try h.transact(wire.exec, 5, ""), 0);
        try h.steps(10000);
        try std.testing.expectEqual(@as(usize, 1), h.application_entries);
        try expectStatus(try h.transact(wire.hello, 0, ""), 0);
        try std.testing.expectEqualSlices(u8, &resident, h.bus.memory[wire.stage1_address..][0..wire.stage1_size]);
        for (screen, 0..) |old, i| {
            const row = i / 120;
            const col = i % 120;
            if (row == 19 and col < 80 and col % stride == 0) continue;
            try std.testing.expectEqual(old, h.bus.memory[0xf300 + i]);
        }
        try std.testing.expectEqual(@as(u8, 0x28 | @as(u8, @intCast(mode))), h.port30);
        try std.testing.expect(!h.invalid_crtc_command);
        try std.testing.expect(h.cpu.registers.sp >= 0xe700 and h.cpu.registers.sp <= 0xe800);
    }
}

test "resident progress handles short partial maximum images and existing RAM verification" {
    for ([_]usize{ 1, 44, 65, 1743, 2048 }) |size| {
        var h: Harness = undefined;
        try h.init(std.testing.io, allocator, false, false);
        const image: [2048]u8 = @splat(0);
        const metadata = beginBytes(0xd000, @intCast(size), 0xd000, wire.crc(image[0..size]), false);
        try expectStatus(try h.transact(wire.hello, 0, ""), 0);
        try expectStatus(try h.transact(wire.begin, 1, &metadata), 0);
        var offset: usize = 0;
        var seq: u8 = 2;
        while (offset < size) {
            const end = @min(offset + 64, size);
            try expectStatus(try h.transact(wire.data, seq, image[offset..end]), 0);
            offset = end;
            try expectLoadBar(&h, offset * 16 / size, 2);
            seq += 1;
        }
        try expectStatus(try h.transact(wire.verify, seq, ""), 0);
        try expectStatus(try h.transact(wire.hello, 0, ""), 0);
        try expectStatus(try h.transact(wire.begin, 1, &beginBytes(0xd000, @intCast(size), 0xd000, wire.crc(image[0..size]), true)), 0);
        try expectLoadBar(&h, 16, 2);
        try expectStatus(try h.transact(wire.verify, 2, ""), 0);
    }
}
