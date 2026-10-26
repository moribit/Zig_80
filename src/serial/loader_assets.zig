const std = @import("std");
const assembler = @import("../assembler/assembler.zig");
const wire = @import("loader_protocol.zig");
pub const Images = struct {
    stage0: []u8,
    stage1: [wire.stage1_size]u8 = @splat(0),
    stage1_code_size: usize,
    pub fn load(io: std.Io, allocator: std.mem.Allocator) !Images {
        var failure: assembler.FailureLocation = .{};
        var cold = try assembler.assembleFile(io, allocator, "examples/pc8001/loader/stage0.asm", &failure);
        defer cold.deinit();
        var resident = try assembler.assembleFile(io, allocator, "examples/pc8001/loader/stage1.asm", &failure);
        defer resident.deinit();
        if (cold.bytes.items.len > 512 or resident.bytes.items.len > wire.stage1_size) return error.LoaderImageTooLarge;
        var self: Images = .{ .stage0 = try allocator.dupe(u8, cold.bytes.items), .stage1_code_size = resident.bytes.items.len };
        @memcpy(self.stage1[0..resident.bytes.items.len], resident.bytes.items);
        return self;
    }
    pub fn deinit(self: *Images, allocator: std.mem.Allocator) void {
        allocator.free(self.stage0);
    }
};
pub fn basic(writer: *std.Io.Writer, bytes: []const u8) !void {
    try writer.print("10 CLEAR 300,&HCFFF:WIDTH 80,25\r\n20 P=&HE400:FOR I=1 TO {d}:READ A$:FOR J=1 TO LEN(A$) STEP 2:POKE P,VAL(\"&H\"+MID$(A$,J,2)):P=P+1:NEXT J:NEXT I\r\n30 H=255:L=255\r\n40 FOR I=0 TO {d}:H=H XOR PEEK(&HE400+I)\r\n50 FOR J=1 TO 8:X=INT(L/128):Y=INT(H/128)\r\n60 L=(L*2) MOD 256:H=(H*2+X) MOD 256\r\n70 IF Y<>0 THEN H=H XOR 16:L=L XOR 33\r\n80 NEXT J:NEXT I\r\n90 IF H*256+L<>{d} THEN PRINT \"CRC ERROR\":END\r\n100 DEFUSR0=&HE400\r\n110 PRINT \"CRC OK. HOST FIRST; THEN R=USR0(0)\":END\r\n", .{ (bytes.len + 15) / 16, bytes.len - 1, wire.crc(bytes) });
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
    try writer.writeAll("Original PC-8001 monitor uses S (NOT M) for Set Memory.\nBASIC first: CLEAR 300,&HCFFF then WIDTH 80,25 then MON.\nFor each group below, enter Sxxxx + RETURN, then the contiguous hex digits\n(two digits automatically advance one byte), then RETURN to finish the group.\nDo NOT type address labels, spaces, or <RETURN> literally.\n");
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = @min(16, bytes.len - offset);
        try writer.print("\nS{X:0>4}<RETURN>\n", .{@as(usize, wire.stage0_address) + offset});
        for (bytes[offset..][0..count]) |byte| try writer.print("{X:0>2}", .{byte});
        try writer.writeAll("<RETURN>\n");
        offset += count;
    }
    try writer.print("\nVerify with DE400,{X:0>4}<RETURN>; compare EVERY byte above.\nCTRL+B returns to BASIC. Start host (--loader stage0) FIRST, then DEFUSR0=&HE400 and R=USR0(0).\nDo not use G: this build's failure path requires a valid USR return stack.\nBytes={d}; CRC16-CCITT-FALSE={X:0>4}.\nHex digits={d}; S-address + row-return keystrokes={d} (excludes initial CLEAR/WIDTH/MON, dump and USR).\n", .{ @as(usize, wire.stage0_address) + bytes.len - 1, bytes.len, wire.crc(bytes), bytes.len * 2, bytes.len * 2 + 7 * ((bytes.len + 15) / 16) });
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
    try out.print("Stage 0: {d} bytes at E400; {d} hex digits, {d} monitor entry keystrokes\nStage 1: {d} code bytes, {d} padded bytes at D800\nGenerated {s}; no port opened, nothing executed.\n", .{ images.stage0.len, images.stage0.len * 2, images.stage0.len * 2 + 7 * ((images.stage0.len + 15) / 16), images.stage1_code_size, wire.stage1_size, directory });
}
