const std = @import("std");
const assembler = @import("../assembler/assembler.zig");

fn hex(writer: *std.Io.Writer, bytes: []const u8) !void {
    return writeHex(writer, bytes, 0xd000);
}
pub fn writeHex(writer: *std.Io.Writer, bytes: []const u8, base: u16) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = @min(16, bytes.len - offset);
        const address: u16 = @intCast(@as(usize, base) + offset);
        var sum: u8 = @as(u8, @intCast(count)) +% @as(u8, @truncate(address >> 8)) +% @as(u8, @truncate(address));
        try writer.print(":{X:0>2}{X:0>4}00", .{ count, address });
        for (bytes[offset..][0..count]) |byte| {
            sum +%= byte;
            try writer.print("{X:0>2}", .{byte});
        }
        try writer.print("{X:0>2}\r\n", .{0 -% sum});
        offset += count;
    }
    try writer.writeAll(":00000001FF\r\n");
}

fn basic(writer: *std.Io.Writer, bytes: []const u8) !void {
    try writer.print("10 CLEAR 300,&HCFFF\r\n20 FOR I=0 TO {d}:READ B:POKE &HD000+I,B:NEXT I\r\n30 DEFUSR0=&HD000\r\n40 PRINT \"LOADED. START MANUALLY: R=USR0(0)\"\r\n50 END\r\n", .{bytes.len - 1});
    var offset: usize = 0;
    var line: usize = 100;
    while (offset < bytes.len) {
        const count = @min(12, bytes.len - offset);
        try writer.print("{d} DATA ", .{line});
        for (bytes[offset..][0..count], 0..) |byte, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{d}", .{byte});
        }
        try writer.writeAll("\r\n");
        offset += count;
        line += 10;
    }
}

pub fn build(io: std.Io, allocator: std.mem.Allocator, directory: []const u8, out: *std.Io.Writer) !void {
    try std.Io.Dir.cwd().createDirPath(io, directory);
    for ([_][]const u8{ "tx_test", "rx_test", "echo_test", "pattern_test", "binary_ready_test" }) |name| {
        const source = try std.fmt.allocPrint(allocator, "examples/pc8001/serial/{s}.asm", .{name});
        defer allocator.free(source);
        var failure: assembler.FailureLocation = .{};
        var result = try assembler.assembleFile(io, allocator, source, &failure);
        defer result.deinit();
        const bytes = result.bytes.items;
        if (bytes.len == 0 or bytes.len > 0x400) return error.InvalidPc8001Image;
        for ([_][]const u8{ "bin", "hex", "bas" }) |extension| {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}.{s}", .{ directory, name, extension });
            defer allocator.free(path);
            const file = try std.Io.Dir.cwd().createFile(io, path, .{});
            defer file.close(io);
            var buffer: [4096]u8 = undefined;
            var writer = file.writer(io, &buffer);
            if (std.mem.eql(u8, extension, "bin")) try writer.interface.writeAll(bytes) else if (std.mem.eql(u8, extension, "hex")) try hex(&writer.interface, bytes) else try basic(&writer.interface, bytes);
            try writer.interface.flush();
        }
        try out.print("{s}: {d} bytes at D000h -> {s} (.bin/.hex/.bas), no execution\n", .{ name, bytes.len, directory });
    }
}

test "PC8001 Intel HEX checksum/address and BASIC data" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try hex(&output.writer, &.{ 0, 255, 85, 170 });
    try std.testing.expectEqualStrings(":04D0000000FF55AA2E\r\n:00000001FF\r\n", output.written());
    output.clearRetainingCapacity();
    try basic(&output.writer, &.{ 0, 255, 85, 170 });
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "100 DATA 0,255,85,170\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "50 END") != null);
}
