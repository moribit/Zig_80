const std = @import("std");
const assembler = @import("../assembler/assembler.zig");
const Cpu = @import("../cpu/cpu.zig").Cpu;
const Bus = @import("../machine/bus.zig").Bus;
const Usart = @import("usart_model.zig").Usart;

fn execute(name: []const u8, model: *Usart, short_timeout: bool) !Bus {
    var path_buffer: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "examples/pc8001/serial/{s}.asm", .{name});
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(source);
    const first = try std.mem.replaceOwned(u8, std.testing.allocator, source, "POLL_LIMIT equ 0xffff", if (short_timeout) "POLL_LIMIT equ 4" else "POLL_LIMIT equ 0xffff");
    defer std.testing.allocator.free(first);
    const text = try std.mem.replaceOwned(u8, std.testing.allocator, first, "POLL_ROUNDS equ 16", if (short_timeout) "POLL_ROUNDS equ 1" else "POLL_ROUNDS equ 16");
    defer std.testing.allocator.free(text);
    var failure: assembler.FailureLocation = .{};
    var image = try assembler.assembleSourceFile(std.testing.io, std.testing.allocator, path, text, &failure);
    defer image.deinit();
    try std.testing.expect(image.bytes.items.len <= 0x400);
    var bus: Bus = .{};
    @memset(&bus.memory, 0xa5);
    @memcpy(bus.memory[0xd000..][0..image.bytes.items.len], image.bytes.items);
    bus.memory[0xea66] = 0x97;
    bus.write16(0xcf00, 0xbeef);
    model.attach(&bus);
    var cpu: Cpu = .{};
    cpu.registers.pc = 0xd000;
    cpu.registers.sp = 0xcf00;
    cpu.registers.setAF(0x1234);
    cpu.registers.setBC(0x5678);
    cpu.registers.setDE(0x9abc);
    cpu.registers.setHL(0xdef0);
    cpu.registers.ix = 0x1357;
    cpu.registers.iy = 0x2468;
    for (0..100_000) |_| {
        _ = try cpu.step(&bus);
        if (cpu.registers.pc == 0xbeef) break;
    }
    try std.testing.expectEqual(@as(u16, 0xbeef), cpu.registers.pc);
    try std.testing.expectEqual(@as(u16, 0xcf02), cpu.registers.sp);
    try std.testing.expectEqual(@as(u16, 0x1234), cpu.registers.af());
    try std.testing.expectEqual(@as(u16, 0x5678), cpu.registers.bc());
    try std.testing.expectEqual(@as(u16, 0x9abc), cpu.registers.de());
    try std.testing.expectEqual(@as(u16, 0xdef0), cpu.registers.hl());
    try std.testing.expectEqual(@as(u16, 0x1357), cpu.registers.ix);
    try std.testing.expectEqual(@as(u16, 0x2468), cpu.registers.iy);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0x40, 0x4e, 0x37 }, model.controls[0..6]);
    try std.testing.expectEqual(@as(u8, 0x4e), model.mode);
    try std.testing.expectEqual(@as(u8, 0), model.command);
    try std.testing.expectEqual(@as(u8, 0x97), model.port30);
    try std.testing.expect(model.upper_port_seen);
    for (bus.memory, 0..) |byte, i| {
        const program = i >= 0xd000 and i < 0xd000 + image.bytes.items.len;
        const stack = i >= 0xcec0 and i <= 0xcf01;
        const buffer = i >= 0xd400 and i <= 0xd4ff;
        const report = i >= 0xd500 and i <= 0xd50b;
        if (!program and !stack and !buffer and !report and i != 0xea66) try std.testing.expectEqual(@as(u8, 0xa5), byte);
    }
    return bus;
}
test "PC8001 8251 transmit waits ready and TxEMPTY and preserves caller stack" {
    var model: Usart = .{};
    const bus = try execute("tx_test", &model, false);
    try std.testing.expectEqualStrings("HELLO FROM PC-8001\r\n", model.transmitted[0..model.transmitted_len]);
    try std.testing.expectEqual(@as(u8, 0), bus.read8(0xd500));
    try std.testing.expectEqual(@as(u16, @intCast(model.transmitted_len)), bus.read16(0xd501));
    try std.testing.expect(model.shifting == null and model.holding == null);
    try std.testing.expect(model.status_reads > model.transmitted_len);
}
test "PC8001 receive echo and full 00-FF binary pattern use the existing CPU" {
    var rx: Usart = .{ .receive = "HELLO FROM PICO 2", .rx_delay = 8 };
    const rx_bus = try execute("rx_test", &rx, false);
    try std.testing.expectEqual(@as(u8, 0), rx_bus.read8(0xd500));
    try std.testing.expectEqualStrings(rx.receive, rx_bus.memory[0xd400..][0..rx.receive.len]);
    var echo: Usart = .{ .receive = "HELLO FROM PICO 2" };
    const echo_bus = try execute("echo_test", &echo, false);
    try std.testing.expectEqual(@as(u8, 0), echo_bus.read8(0xd500));
    try std.testing.expectEqualStrings(echo.receive, echo.transmitted[0..echo.transmitted_len]);
    var pattern: [256]u8 = undefined;
    for (&pattern, 0..) |*byte, i| byte.* = @intCast(i);
    var binary: Usart = .{ .receive = &pattern };
    const binary_bus = try execute("pattern_test", &binary, false);
    try std.testing.expectEqual(@as(u8, 0), binary_bus.read8(0xd500));
    try std.testing.expectEqualSlices(u8, &pattern, &binary.transmitted);
    try std.testing.expectEqualSlices(u8, &pattern, binary_bus.memory[0xd400..0xd500]);
    try std.testing.expectEqual(@as(u16, 256), binary_bus.read16(0xd501));
    try std.testing.expectEqual(@as(u16, 256), binary_bus.read16(0xd503));
}
test "PC8001 bounded timeout CTS blocked framing overrun parity and mismatch diagnostics" {
    var missing: Usart = .{};
    const timeout = try execute("rx_test", &missing, true);
    try std.testing.expectEqual(@as(u8, 1), timeout.read8(0xd500));
    try std.testing.expectEqual(@as(u16, 1), timeout.read16(0xd507));
    var cts: Usart = .{ .cts = false };
    const blocked = try execute("tx_test", &cts, true);
    try std.testing.expectEqual(@as(u8, 1), blocked.read8(0xd500));
    try std.testing.expectEqual(@as(usize, 0), cts.transmitted_len);
    for ([_]u8{ 8, 16, 32 }) |status| {
        var failed: Usart = .{ .errors = status };
        const bus = try execute("rx_test", &failed, true);
        try std.testing.expectEqual(@as(u8, 2), bus.read8(0xd500));
        try std.testing.expectEqual(@as(u16, 1), bus.read16(0xd509));
        try std.testing.expect(bus.read8(0xd50b) & status != 0);
    }
    var mismatch: Usart = .{ .receive = "XELLO FROM PICO 2" };
    const mismatched = try execute("rx_test", &mismatch, false);
    try std.testing.expectEqual(@as(u8, 3), mismatched.read8(0xd500));
    try std.testing.expectEqual(@as(u16, 1), mismatched.read16(0xd505));
}
