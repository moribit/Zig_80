const std = @import("std");
const Cpu = @import("cpu/cpu.zig").Cpu;
const Bus = @import("machine/bus.zig").Bus;
const Machine = @import("machine/machine.zig").Machine;
const flags = @import("cpu/flags.zig");
const assembler = @import("assembler/assembler.zig");
const disassembler = @import("disassembler/disassembler.zig");
const video = @import("machine/video.zig");

fn execute(program: []const u8) !struct { Cpu, Bus } {
    var bus = Bus{};
    @memcpy(bus.memory[0..program.len], program);
    var cpu = Cpu{};
    var n: usize = 0;
    while (!cpu.halted and n < 100) : (n += 1) _ = try cpu.step(&bus);
    return .{ cpu, bus };
}

test "register pairs stay coherent" {
    var r = @import("cpu/registers.zig").Registers{};
    r.setBC(0x1234);
    try std.testing.expectEqual(@as(u8, 0x12), r.b);
    try std.testing.expectEqual(@as(u16, 0x1234), r.bc());
}
test "bus is little endian and wraps at ffff" {
    var b = Bus{};
    b.write16(0xffff, 0x1234);
    try std.testing.expectEqual(@as(u8, 0x34), b.read8(0xffff));
    try std.testing.expectEqual(@as(u8, 0x12), b.read8(0));
    try std.testing.expectEqual(@as(u16, 0x1234), b.read16(0xffff));
}
test "load add flags and halt" {
    const state = try execute(&.{ 0x3e, 0xff, 0x06, 0x01, 0x80, 0x76 });
    try std.testing.expectEqual(@as(u8, 0), state[0].registers.a);
    try std.testing.expect(flags.isSet(state[0].registers.f, flags.Z));
    try std.testing.expect(flags.isSet(state[0].registers.f, flags.C));
    try std.testing.expect(flags.isSet(state[0].registers.f, flags.H));
    try std.testing.expectEqual(@as(u16, 6), state[0].registers.pc);
}
test "call ret push pop and sp" {
    const state = try execute(&.{ 0x31, 0x00, 0x90, 0xcd, 0x08, 0x00, 0x76, 0x00, 0x01, 0x34, 0x12, 0xc5, 0x01, 0, 0, 0xc1, 0xc9 });
    try std.testing.expectEqual(@as(u16, 0x1234), state[0].registers.bc());
    try std.testing.expectEqual(@as(u16, 0x9000), state[0].registers.sp);
}
test "jr positive and negative" {
    var b = Bus{};
    b.memory[0] = 0x18;
    b.memory[1] = 2;
    b.memory[4] = 0x18;
    b.memory[5] = 0xfc;
    var c = Cpu{};
    _ = try c.step(&b);
    try std.testing.expectEqual(@as(u16, 4), c.registers.pc);
    _ = try c.step(&b);
    try std.testing.expectEqual(@as(u16, 2), c.registers.pc);
}
test "unknown opcode reports location" {
    var b = Bus{};
    b.memory[0] = 0xdd;
    var c = Cpu{};
    try std.testing.expectError(error.UnknownOpcode, c.step(&b));
    try std.testing.expectEqual(@as(u16, 0), c.last_unknown_pc);
    try std.testing.expectEqual(@as(u8, 0xdd), c.last_unknown_opcode);
}
test "assembler directives labels forward references and numbers" {
    const source = "org 0\nVALUE equ 0x2A\n jr next\n db \"A\", 0b10\nnext:\n ld a, VALUE\n dw next\n halt\n";
    var result = try assembler.assemble(std.testing.allocator, source);
    defer result.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x18, 0x02, 'A', 2, 0x3e, 0x2a, 4, 0, 0x76 }, result.bytes.items);
}
test "assembler errors" {
    try std.testing.expectError(error.DuplicateSymbol, assembler.assemble(std.testing.allocator, "x:\nx:\nhalt\n"));
    try std.testing.expectError(error.UndefinedSymbol, assembler.assemble(std.testing.allocator, "jp missing\n"));
    try std.testing.expectError(error.RelativeOutOfRange, assembler.assemble(std.testing.allocator, "jr far\norg 0x0200\nfar:\nhalt\n"));
}
test "disassembler known immediate and unknown" {
    const data = [_]u8{ 0x21, 0, 0xc0, 0xdd };
    const a = disassembler.decode(&data, 0);
    try std.testing.expectEqualStrings("LD HL,0xC000", disassembler.text(&a));
    const b = disassembler.decode(&data, 3);
    try std.testing.expectEqualStrings("DB 0xDD", disassembler.text(&b));
}
test "machine load devices and video" {
    var m = Machine{};
    try m.load(&.{0x76});
    try std.testing.expectEqual(@as(u8, 0x76), m.bus.read8(0));
    m.bus.write8(0xc000, 1);
    try std.testing.expect(video.pixel(&m.bus, 0, 0));
    m.setInput(0x11);
    try std.testing.expectEqual(@as(u8, 0x11), m.bus.read8(0xc400));
    m.tickFrame();
    try std.testing.expectEqual(@as(u8, 1), m.bus.read8(0xc401));
}
