const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("../machine/bus.zig").Bus;
const flags = @import("flags.zig");
const assembler = @import("../assembler/assembler.zig");
const disassembler = @import("../disassembler/disassembler.zig");

test "DAA also adjusts invalid BCD accumulator states after subtraction" {
    var bus: Bus = .{};
    bus.memory[0] = 0x27;
    var cpu: Cpu = .{};
    cpu.registers.a = 0xf3;
    cpu.registers.f = flags.N;
    _ = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u8, 0x93), cpu.registers.a);
    try std.testing.expectEqual(@as(u8, 0x87), cpu.registers.f & 0xd7);
}

test "shared extension metadata roundtrips and executes every declared encoding" {
    for (@import("extended_metadata.zig").definitions) |definition| {
        var bytes: [4]u8 = @splat(0);
        var index: usize = 0;
        if (definition.prefix != 0) {
            bytes[0] = definition.prefix;
            index = 1;
        }
        bytes[index] = definition.opcode;
        if (definition.indexed_cb) {
            bytes[1] = 0xcb;
            bytes[3] = definition.opcode;
        }
        const decoded = disassembler.decode(bytes[0..definition.size()], 0);
        var assembled = assembler.assemble(std.testing.allocator, disassembler.text(&decoded)) catch |err| {
            std.debug.print("metadata roundtrip failed: {s} ({s})\n", .{ disassembler.text(&decoded), @errorName(err) });
            return err;
        };
        defer assembled.deinit();
        try std.testing.expectEqualSlices(u8, bytes[0..definition.size()], assembled.bytes.items);
        var bus: Bus = .{};
        @memcpy(bus.memory[0..definition.size()], assembled.bytes.items);
        var cpu: Cpu = .{};
        cpu.registers.setHL(0x8000);
        const step = try cpu.step(&bus);
        try std.testing.expect(step.t_states == definition.t_states or step.t_states == definition.taken_t_states);
    }
}

test "DAA covers all valid packed BCD addition and subtraction pairs" {
    for (0..100) |a| for (0..100) |b| {
        const packed_a: u8 = @intCast((a / 10) * 16 + a % 10);
        const packed_b: u8 = @intCast((b / 10) * 16 + b % 10);
        inline for (.{ false, true }) |subtract| {
            var bus: Bus = .{};
            bus.memory[0] = 0x27;
            var cpu: Cpu = .{};
            const result = if (subtract) flags.sub8(packed_a, packed_b) else flags.add8(packed_a, packed_b);
            cpu.registers.a = result.value;
            cpu.registers.f = result.flags;
            _ = try cpu.step(&bus);
            const expected = if (subtract) (a + 100 - b) % 100 else (a + b) % 100;
            try std.testing.expectEqual(@as(u8, @intCast((expected / 10) * 16 + expected % 10)), cpu.registers.a);
            try std.testing.expectEqual(if (subtract) a < b else a + b >= 100, cpu.registers.f & flags.C != 0);
        }
    };
}

test "memory ALU ADD SUB CP execute with seven T states" {
    for ([_]u8{ 0x86, 0x96, 0xbe }) |op| {
        var bus: Bus = .{};
        bus.memory[0] = op;
        bus.memory[0x8000] = 1;
        var cpu: Cpu = .{};
        cpu.registers.setHL(0x8000);
        cpu.registers.a = 0x7f;
        const step = try cpu.step(&bus);
        try std.testing.expectEqual(@as(u16, 7), step.t_states);
        try std.testing.expectEqual(@as(u8, if (op == 0x86) 0x80 else if (op == 0xbe) 0x7f else 0x7e), cpu.registers.a);
    }
}

test "EI delays INT through following instruction and RETI restores execution" {
    var bus: Bus = .{};
    @memcpy(bus.memory[0..4], &[_]u8{ 0xfb, 0x00, 0x76, 0x00 });
    @memcpy(bus.memory[0x38..0x3a], &[_]u8{ 0xed, 0x4d });
    var cpu: Cpu = .{};
    cpu.interrupt_mode = 1;
    cpu.setInt(true, 0xff);
    _ = try cpu.step(&bus); // EI
    try std.testing.expectEqual(@as(u16, 1), cpu.registers.pc);
    _ = try cpu.step(&bus); // NOP, still inhibited
    try std.testing.expectEqual(@as(u16, 2), cpu.registers.pc);
    const interrupt = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 13), interrupt.t_states);
    try std.testing.expectEqual(@as(u16, 0x38), cpu.registers.pc);
    cpu.setInt(false, 0xff);
    _ = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 2), cpu.registers.pc);
}

test "NMI wakes HALT and IM2 vector wraps FFFF" {
    var bus: Bus = .{};
    var cpu: Cpu = .{};
    bus.memory[0] = 0x76;
    _ = try cpu.step(&bus);
    cpu.requestNmi();
    const nmi = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 11), nmi.t_states);
    try std.testing.expectEqual(@as(u16, 0x66), cpu.registers.pc);
    try std.testing.expect(!cpu.halted);
    cpu.reset();
    cpu.iff1 = true;
    cpu.interrupt_mode = 2;
    cpu.registers.i = 0xff;
    cpu.registers.sp = 0x9000;
    bus.memory[0xffff] = 0x34;
    bus.memory[0] = 0x12;
    cpu.setInt(true, 0xff);
    const interrupt = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 19), interrupt.t_states);
    try std.testing.expectEqual(@as(u16, 0x1234), cpu.registers.pc);
}

test "all condition codes select CALL and RET timing and stack effects" {
    const masks = [_]u8{ flags.Z, flags.Z, flags.C, flags.C, flags.PV, flags.PV, flags.S, flags.S };
    for (masks, 0..) |mask, cc| for (0..2) |taken| {
        var bus: Bus = .{};
        bus.memory[0] = 0xc4 + @as(u8, @intCast(cc)) * 8;
        bus.memory[1] = 0x00;
        bus.memory[2] = 0x01;
        bus.memory[0x100] = 0xc0 + @as(u8, @intCast(cc)) * 8;
        var cpu: Cpu = .{};
        cpu.registers.f = if ((taken != 0) == (cc % 2 == 1)) mask else 0;
        const step = try cpu.step(&bus);
        try std.testing.expectEqual(@as(u16, if (taken == 0) 10 else 17), step.t_states);
        try std.testing.expectEqual(@as(u16, if (taken == 0) 3 else 0x100), cpu.registers.pc);
        if (taken != 0) {
            const ret = try cpu.step(&bus);
            try std.testing.expectEqual(@as(u16, 11), ret.t_states);
            try std.testing.expectEqual(@as(u16, 3), cpu.registers.pc);
            try std.testing.expectEqual(@as(u16, 0xffff), cpu.registers.sp);
        }
    };
}
