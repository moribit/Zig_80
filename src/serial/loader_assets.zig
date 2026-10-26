const std = @import("std");
const assembler = @import("../assembler/assembler.zig");
const wire = @import("loader_protocol.zig");
pub const Images = struct {
    stage0: []u8,
    mini: []u8,
    stage1: [wire.stage1_size]u8 = @splat(0),
    stage1_code_size: usize,
    pub fn load(io: std.Io, allocator: std.mem.Allocator) !Images {
        var failure: assembler.FailureLocation = .{};
        var cold = try assembler.assembleFile(io, allocator, "examples/pc8001/loader/stage0.asm", &failure);
        defer cold.deinit();
        var resident = try assembler.assembleFile(io, allocator, "examples/pc8001/loader/stage1.asm", &failure);
        defer resident.deinit();
        var mini = try assembler.assembleFile(io, allocator, "examples/pc8001/loader/mini_stage0.asm", &failure);
        defer mini.deinit();
        if (cold.bytes.items.len != wire.relay_size or mini.bytes.items.len > 100 or resident.bytes.items.len > wire.stage1_size) return error.LoaderImageTooLarge;
        const relay_copy = try allocator.dupe(u8, cold.bytes.items);
        errdefer allocator.free(relay_copy);
        var self: Images = .{ .stage0 = relay_copy, .mini = try allocator.dupe(u8, mini.bytes.items), .stage1_code_size = resident.bytes.items.len };
        @memcpy(self.stage1[0..resident.bytes.items.len], resident.bytes.items);
        return self;
    }
    pub fn deinit(self: *Images, allocator: std.mem.Allocator) void {
        allocator.free(self.stage0);
        allocator.free(self.mini);
    }
};
pub fn basic(writer: *std.Io.Writer, bytes: []const u8) !void {
    return basicAt(writer, bytes, wire.stage0_address);
}
pub fn basicAt(writer: *std.Io.Writer, bytes: []const u8, base: u16) !void {
    try writer.print("10 CLEAR 300,&HCFFF:WIDTH 80,25\r\n20 P=&H{X:0>4}:FOR I=1 TO {d}:READ A$:FOR J=1 TO LEN(A$) STEP 2:POKE P,VAL(\"&H\"+MID$(A$,J,2)):P=P+1:NEXT J:NEXT I\r\n30 H=255:L=255\r\n40 FOR I=0 TO {d}:H=H XOR PEEK(&H{X:0>4}+I)\r\n50 FOR J=1 TO 8:X=INT(L/128):Y=INT(H/128)\r\n60 L=(L*2) MOD 256:H=(H*2+X) MOD 256\r\n70 IF Y<>0 THEN H=H XOR 16:L=L XOR 33\r\n80 NEXT J:NEXT I\r\n90 IF H*256+L<>{d} THEN PRINT \"CRC ERROR\":END\r\n100 DEFUSR0=&H{X:0>4}\r\n110 PRINT \"CRC OK. HOST FIRST; THEN R=USR0(0)\":END\r\n", .{ base, (bytes.len + 15) / 16, bytes.len - 1, base, wire.crc(bytes), base });
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += @min(16, bytes.len - offset)) {
        try writer.print("{d} DATA \"", .{1000 + offset / 16 * 10});
        for (bytes[offset..][0..@min(16, bytes.len - offset)]) |byte| {
            try writer.print("{X:0>2}", .{byte});
        }
        try writer.writeAll("\"\r\n");
    }
}
pub fn monitor(writer: *std.Io.Writer, bytes: []const u8) !void {
    return monitorAt(writer, bytes, wire.stage0_address);
}
pub fn monitorAt(writer: *std.Io.Writer, bytes: []const u8, base: u16) !void {
    try writer.writeAll("Original PC-8001 monitor uses S (NOT M) for Set Memory.\nBASIC first: CLEAR 300,&HCFFF then WIDTH 80,25 then MON.\nFor each group below, enter Sxxxx + RETURN, then the contiguous hex digits\n(two digits automatically advance one byte), then RETURN to finish the group.\nDo NOT type address labels, spaces, or <RETURN> literally.\n");
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = @min(16, bytes.len - offset);
        try writer.print("\nS{X:0>4}<RETURN>\n", .{@as(usize, base) + offset});
        for (bytes[offset..][0..count]) |byte| try writer.print("{X:0>2}", .{byte});
        try writer.writeAll("<RETURN>\n");
        offset += count;
    }
    try writer.print("\nVerify with D{X:0>4},{X:0>4}<RETURN>; compare EVERY byte above.\nCTRL+B returns to BASIC. Start host (--loader {s}) FIRST, then DEFUSR0=&H{X:0>4} and R=USR0(0).\nDo not use G: the relay needs a valid USR stack. Mini failure requires reset.\nBytes={d}; CRC16-CCITT-FALSE={X:0>4}.\nHex digits={d}; S-address + row-return keystrokes={d} (excludes initial CLEAR/WIDTH/MON, dump and USR).\n", .{ base, @as(usize, base) + bytes.len - 1, if (base == wire.mini_address) "mini" else "stage0", base, bytes.len, wire.crc(bytes), bytes.len * 2, bytes.len * 2 + 7 * ((bytes.len + 15) / 16) });
}
pub fn monitorInput(writer: *std.Io.Writer, bytes: []const u8, base: u16, tape: bool) !void {
    try writer.writeAll("CLEAR 300,&HCFFF\rWIDTH 80,25\rMON\r");
    if (tape) try writer.writeAll("L\r") else {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const count = @min(16, bytes.len - offset);
            try writer.print("S{X:0>4}\r", .{@as(usize, base) + offset});
            for (bytes[offset..][0..count]) |byte| try writer.print("{X:0>2}", .{byte});
            try writer.writeByte('\r');
            offset += count;
        }
    }
    try writer.print("D{X:0>4},{X:0>4}\r", .{ base, @as(usize, base) + bytes.len - 1 });
    try writer.writeByte(2); // CTRL+B is one operation in the input-count model.
    try writer.print("DEFUSR0=&H{X:0>4}\rR=USR0(0)\r", .{base});
}
fn writeVariant(io: std.Io, allocator: std.mem.Allocator, directory: []const u8, prefix: []const u8, bytes: []const u8, base: u16) !void {
    var cmt: std.Io.Writer.Allocating = .init(allocator);
    defer cmt.deinit();
    try @import("cassette.zig").writeCmt(&cmt.writer, base, bytes);
    for ([_][]const u8{ ".bin", ".hex", ".bas", "-monitor.txt", ".cmt", ".wav" }) |extension| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ directory, prefix, extension });
        defer allocator.free(path);
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(io, &buffer);
        const out = &writer.interface;
        if (std.mem.eql(u8, extension, ".bin")) try out.writeAll(bytes) else if (std.mem.eql(u8, extension, ".hex")) try @import("artifacts.zig").writeHex(out, bytes, base) else if (std.mem.eql(u8, extension, ".bas")) try basicAt(out, bytes, base) else if (std.mem.eql(u8, extension, "-monitor.txt")) try monitorAt(out, bytes, base) else if (std.mem.eql(u8, extension, ".cmt")) try out.writeAll(cmt.written()) else try @import("cassette.zig").writeWav(out, cmt.written());
        try out.flush();
    }
}
fn writeMetrics(io: std.Io, allocator: std.mem.Allocator, directory: []const u8, images: *const Images, out: *std.Io.Writer) !void {
    const path = try std.fmt.allocPrint(allocator, "{s}/input-counts.json", .{directory});
    defer allocator.free(path);
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buffer: [2048]u8 = undefined;
    var json = file.writer(io, &buffer);
    try json.interface.writeAll("{\n  \"counting\": \"PC characters; RETURN=1, CTRL+B=1; includes setup, dump/CRC verification and USR; excludes modifier keys, host CLI and audio player\",\n");
    for ([_][]const u8{ images.mini, images.stage0 }, 0..) |bytes, i| {
        const base: u16 = if (i == 0) wire.mini_address else wire.stage0_address;
        var basic_text: std.Io.Writer.Allocating = .init(allocator);
        defer basic_text.deinit();
        try basicAt(&basic_text.writer, bytes, base);
        const basic_count = basic_text.written().len - std.mem.count(u8, basic_text.written(), "\r\n") + "NEW\rRUN\rR=USR0(0)\r".len;
        var keys: std.Io.Writer.Allocating = .init(allocator);
        defer keys.deinit();
        try monitorInput(&keys.writer, bytes, base, false);
        const mon_count = keys.written().len;
        keys.clearRetainingCapacity();
        try monitorInput(&keys.writer, bytes, base, true);
        try json.interface.print("  \"{s}\": {{\"machine_bytes\":{d},\"data_lines\":{d},\"basic_file_bytes\":{d},\"basic_total\":{d},\"monitor_total\":{d},\"cassette_total\":{d}}}{s}\n", .{ if (i == 0) "mini" else "relay", bytes.len, (bytes.len + 15) / 16, basic_text.written().len, basic_count, mon_count, keys.written().len, if (i == 0) "," else "" });
        try out.print("{s}: {d} machine bytes, monitor total={d}, BASIC total={d}, CMT/WAV total={d} PC characters\n", .{ if (i == 0) "Mini Stage 0" else "Relay Stage 1", bytes.len, mon_count, basic_count, keys.written().len });
    }
    try json.interface.writeAll("}\n");
    try json.interface.flush();
}
pub fn generate(io: std.Io, allocator: std.mem.Allocator, directory: []const u8, out: *std.Io.Writer) !void {
    var images = try Images.load(io, allocator);
    defer images.deinit(allocator);
    try std.Io.Dir.cwd().createDirPath(io, directory);
    for ([_][]const u8{ "stage0.bin", "stage0.hex", "stage0.bas", "stage0-monitor.txt", "stage1.bin" }) |name| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory, name });
        defer allocator.free(path);
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(io, &buffer);
        if (std.mem.eql(u8, name, "stage0.bin")) try writer.interface.writeAll(images.stage0) else if (std.mem.eql(u8, name, "stage1.bin")) try writer.interface.writeAll(&images.stage1) else if (std.mem.endsWith(u8, name, ".hex")) try @import("artifacts.zig").writeHex(&writer.interface, images.stage0, wire.stage0_address) else if (std.mem.endsWith(u8, name, ".bas")) try basic(&writer.interface, images.stage0) else try monitor(&writer.interface, images.stage0);
        try writer.interface.flush();
    }
    try writeVariant(io, allocator, directory, "mini-stage0", images.mini, wire.mini_address);
    try writeVariant(io, allocator, directory, "relay-stage1", images.stage0, wire.stage0_address);
    try writeMetrics(io, allocator, directory, &images, out);
    try out.print("Resident: {d} code bytes, {d} padded bytes at D800 (legacy stage1.bin)\nLegacy stage0.* remains the unchanged E400 relay; mini-stage0.* is the new E300 front-end.\nGenerated {s}; no port opened, nothing played or executed.\n", .{ images.stage1_code_size, wire.stage1_size, directory });
}
