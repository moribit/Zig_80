const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("../machine/bus.zig").Bus;
const trace = @import("../trace/trace.zig");
const disassembler = @import("../disassembler/disassembler.zig");
const flags = @import("flags.zig");
const assembler = @import("../assembler/assembler.zig");

test "ED and indexed CB decode faults preserve registers R timing and memory" {
    for ([_][4]u8{ .{ 0xed, 0, 0, 0 }, .{ 0xdd, 0xcb, 0xff, 0x36 }, .{ 0xfd, 0, 0, 0 } }) |bytes| {
        var bus: Bus = .{};
        var events: trace.RingBuffer(8) = .{};
        bus.trace_sink = events.sink();
        for (bytes, 0..) |byte, i| bus.memory[0xfffe +% @as(u16, @intCast(i))] = byte;
        bus.memory[0x8000] = 0x42;
        var cpu: Cpu = .{ .instruction_index = 9, .total_t_states = 123, .iff1 = true };
        cpu.registers.pc = 0xfffe;
        cpu.registers.r = 0xff;
        cpu.registers.ix = 0x8001;
        cpu.registers.f = 0x93;
        const before = cpu.registers;
        try std.testing.expectError(error.UnknownOpcode, cpu.step(&bus));
        try std.testing.expectEqualDeep(before, cpu.registers);
        try std.testing.expect(cpu.iff1);
        try std.testing.expectEqual(@as(u64, 9), cpu.instruction_index);
        try std.testing.expectEqual(@as(u64, 123), cpu.total_t_states);
        try std.testing.expectEqual(@as(u8, 0x42), bus.read8(0x8000));
        try std.testing.expectEqual(@as(?u8, bytes[0]), cpu.fault.?.prefix);
        for (0..events.len) |i| try std.testing.expect(events.get(i).?.kind == .opcode_fetch or events.get(i).?.kind == .operand_read);
    }
}

test "CPU core statically accepts a bus with no Machine or peripheral dependencies" {
    const TestBus = struct {
        bytes: [65536]u8 = @splat(0),
        pub fn beginInstruction(_: *@This(), _: u64, _: u64, _: u16) void {}
        pub fn readOpcode(self: *@This(), address: u16) u8 {
            return self.bytes[address];
        }
        pub fn readOperand8(self: *@This(), address: u16) u8 {
            return self.bytes[address];
        }
        pub fn readData8(self: *@This(), address: u16) u8 {
            return self.bytes[address];
        }
        pub fn readOperand16(self: *@This(), address: u16) u16 {
            return @as(u16, self.bytes[address]) | (@as(u16, self.bytes[address +% 1]) << 8);
        }
        pub fn write8(self: *@This(), address: u16, value: u8) void {
            self.bytes[address] = value;
        }
        pub fn write16(self: *@This(), address: u16, value: u16) void {
            self.write8(address, @truncate(value));
            self.write8(address +% 1, @truncate(value >> 8));
        }
        pub fn input(_: *@This(), _: u16) u8 {
            return 0xff;
        }
        pub fn output(_: *@This(), _: u16, _: u8) void {}
        pub fn acknowledgeInterrupt(_: *@This(), _: u8) void {}
    };
    var bus: TestBus = .{};
    bus.bytes[0] = 0x3e;
    bus.bytes[1] = 0x42;
    var cpu: Cpu = .{};
    _ = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u8, 0x42), cpu.registers.a);
}

test "unsupported CB at wrapping PC preserves state and only traces instruction bytes" {
    var bus: Bus = .{};
    var events: trace.RingBuffer(8) = .{};
    bus.trace_sink = events.sink();
    bus.memory[0xffff] = 0xcb;
    bus.memory[0] = 0x36; // undocumented SLL (HL)
    var cpu: Cpu = .{ .instruction_index = 8, .total_t_states = 32 };
    cpu.registers.pc = 0xffff;
    cpu.registers.setHL(0x8000);
    cpu.registers.a = 0x42;
    const before = cpu.registers;
    try std.testing.expectError(error.UnknownOpcode, cpu.step(&bus));
    try std.testing.expectEqualDeep(before, cpu.registers);
    try std.testing.expectEqual(@as(u64, 8), cpu.instruction_index);
    try std.testing.expectEqual(@as(u64, 32), cpu.total_t_states);
    try std.testing.expectEqual(@as(u8, 0), bus.read8(0x8000));
    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqual(trace.BusEventKind.opcode_fetch, events.get(1).?.kind);
    try std.testing.expectEqual(@as(u16, 0xffff), cpu.last_unknown_pc);
    try std.testing.expectEqual(@as(u8, 0x36), cpu.last_unknown_opcode);
}

test "push writes high byte first and wraps stack at zero" {
    var bus: Bus = .{};
    var events: trace.RingBuffer(8) = .{};
    bus.trace_sink = events.sink();
    bus.memory[0x100] = 0xc5;
    var cpu: Cpu = .{};
    cpu.registers.pc = 0x100;
    cpu.registers.sp = 1;
    cpu.registers.setBC(0x1234);
    const result = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 11), result.t_states);
    try std.testing.expectEqual(@as(u16, 0xffff), cpu.registers.sp);
    try std.testing.expectEqual(@as(u16, 0), events.get(1).?.address);
    try std.testing.expectEqual(@as(u8, 0x12), events.get(1).?.data);
    try std.testing.expectEqual(@as(u16, 0xffff), events.get(2).?.address);
    try std.testing.expectEqual(@as(u16, 0x1234), bus.read16(0xffff));
}

test "INC HL indirect disassembly preserves mnemonic" {
    const decoded = disassembler.decode(&.{0x34}, 0);
    try std.testing.expectEqualStrings("INC (HL)", disassembler.text(&decoded));
}

test "exhaustive documented ADC SBC flags use signed and nibble arithmetic oracle" {
    for (0..256) |ai| for (0..256) |bi| for (0..2) |ci| {
        const a: u8 = @intCast(ai);
        const b: u8 = @intCast(bi);
        const signed_a: i16 = @as(i8, @bitCast(a));
        const signed_b: i16 = @as(i8, @bitCast(b));
        const c: i16 = @intCast(ci);
        inline for (.{ false, true }) |subtract| {
            const wide: i32 = if (subtract) @as(i32, a) - b - c else @as(i32, a) + b + c;
            const signed: i16 = if (subtract) signed_a - signed_b - c else signed_a + signed_b + c;
            const low: i16 = if (subtract) @as(i16, a & 15) - (b & 15) - c else @as(i16, a & 15) + (b & 15) + c;
            const expected: u8 = @truncate(@as(u32, @bitCast(wide)));
            var f: u8 = if (subtract) flags.N else 0;
            if (expected & 128 != 0) f |= flags.S;
            if (expected == 0) f |= flags.Z;
            if (low < 0 or low > 15) f |= flags.H;
            if (signed < -128 or signed > 127) f |= flags.PV;
            if (wide < 0 or wide > 255) f |= flags.C;
            const actual = if (subtract) flags.sbc8(a, b, ci != 0) else flags.adc8(a, b, ci != 0);
            try std.testing.expectEqual(expected, actual.value);
            try std.testing.expectEqual(f, actual.flags);
            if (ci == 0) {
                const plain = if (subtract) flags.sub8(a, b) else flags.add8(a, b);
                try std.testing.expectEqual(expected, plain.value);
                try std.testing.expectEqual(f, plain.flags);
            }
        }
    };
}

test "INC DEC exhaustive values preserve carry and documented boundary flags" {
    for (0..256) |i| for (0..2) |carry| {
        const value: u8 = @intCast(i);
        const old: u8 = if (carry == 0) 0 else flags.C;
        const inc = flags.inc8(value, old);
        const dec = flags.dec8(value, old);
        try std.testing.expectEqual(value +% 1, inc.value);
        try std.testing.expectEqual(value -% 1, dec.value);
        try std.testing.expectEqual(old, inc.flags & flags.C);
        try std.testing.expectEqual(old, dec.flags & flags.C);
        try std.testing.expectEqual(value == 0x7f, inc.flags & flags.PV != 0);
        try std.testing.expectEqual(value == 0x80, dec.flags & flags.PV != 0);
        try std.testing.expectEqual(value & 15 == 15, inc.flags & flags.H != 0);
        try std.testing.expectEqual(value & 15 == 0, dec.flags & flags.H != 0);
    };
}

test "complete program matches encoding disassembly CPU memory and logical trace golden" {
    var assembled = try assembler.assemble(std.testing.allocator, @embedFile("testdata/store.asm"));
    defer assembled.deinit();
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    const writer = &output.writer;
    try writer.writeAll("bytes");
    for (assembled.bytes.items) |byte| try writer.print(" {X:0>2}", .{byte});
    try writer.writeAll("\n");
    var pc: u16 = 0;
    while (pc < assembled.bytes.items.len) {
        const decoded = disassembler.decode(assembled.bytes.items, pc);
        try writer.print("{X:0>4} {s}\n", .{ pc, disassembler.text(&decoded) });
        pc += decoded.size;
    }
    var bus: Bus = .{};
    @memcpy(bus.memory[0..assembled.bytes.items.len], assembled.bytes.items);
    var events: trace.RingBuffer(32) = .{};
    bus.trace_sink = events.sink();
    var cpu: Cpu = .{};
    while (!cpu.halted and cpu.instruction_index < 20) {
        const step = try cpu.step(&bus);
        try writer.print("step {X:0>4}->{X:0>4} A={X:0>2} F={X:0>2} SP={X:0>4} T={d}\n", .{ step.pc_before, step.pc_after, cpu.registers.a, cpu.registers.f, cpu.registers.sp, step.t_states });
    }
    for (0..events.len) |i| {
        const event = events.get(i).?;
        try writer.print("trace {d} {d} {s} {X:0>4} {X:0>2}\n", .{ event.instruction_index, event.event_index_in_instruction, @tagName(event.kind), event.address, event.data });
    }
    try writer.print("final PC={X:0>4} instructions={d} T={d} memory[8000]={X:0>2}\n", .{ cpu.registers.pc, cpu.instruction_index, cpu.total_t_states, bus.read8(0x8000) });
    try std.testing.expectEqualStrings(@embedFile("testdata/store.golden"), output.written());
}
