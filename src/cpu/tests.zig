const std = @import("std");
const Cpu = @import("../cpu/cpu.zig").Cpu;
const Bus = @import("../machine/bus.zig").Bus;
const Machine = @import("../machine/machine.zig").Machine;
const flags = @import("../cpu/flags.zig");
const instruction = @import("../cpu/instruction.zig");
const assembler = @import("../assembler/assembler.zig");
const disassembler = @import("../disassembler/disassembler.zig");
const video = @import("../machine/video.zig");
const trace = @import("../trace/trace.zig");
const SourceBuffer = @import("../tui/editor/buffer.zig").SourceBuffer;
const Frame = @import("../tui/render/frame.zig").Frame;
const input = @import("../tui/terminal/input.zig");
const command = @import("../tui/command.zig");
const Layout = @import("../tui/layout.zig").Layout;
const AppState = @import("../tui/state.zig").AppState;
const ExecutionState = @import("../tui/state.zig").ExecutionState;
const PromptMode = @import("../tui/state.zig").PromptMode;
const DisplayScale = @import("../tui/state.zig").DisplayScale;
const bus_waveform = @import("../tui/bus_waveform.zig");
const Rect = @import("../tui/layout.zig").Rect;
const breakpoint = @import("../debugger/breakpoint.zig");
const DebugSession = @import("../debugger/session.zig").DebugSession;

fn execute(program: []const u8) !struct { Cpu, Bus } {
    var bus = Bus{};
    @memcpy(bus.memory[0..program.len], program);
    var cpu = Cpu{};
    var n: usize = 0;
    while (!cpu.halted and n < 100) : (n += 1) _ = try cpu.step(&bus);
    return .{ cpu, bus };
}

test "register pairs stay coherent" {
    var r = @import("../cpu/registers.zig").Registers{};
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

test "logical instruction metadata opcodes timing flags and edge cases" {
    try std.testing.expectEqual(@as(?u8, 6), instruction.register8Code("(hl)"));
    try std.testing.expectEqualStrings("A", instruction.register8Name(7));
    try std.testing.expect(instruction.ldRegisterOpcode(6, 6) == null);

    for (instruction.logic_families) |family| {
        for (0..8) |source_index| {
            const source: u8 = @intCast(source_index);
            var bus = Bus{};
            var trace_buffer = trace.TraceBuffer{};
            bus.trace_sink = trace_buffer.sink();
            bus.memory[0] = family.register_base + source;
            var cpu = Cpu{};
            cpu.registers.a = 0x5a;
            cpu.registers.b = 0x81;
            cpu.registers.c = 0x7f;
            cpu.registers.d = 0xff;
            cpu.registers.e = 0x01;
            cpu.registers.h = 0x90;
            cpu.registers.l = 0x00;
            bus.memory[0x9000] = 0xa5;
            const operand = switch (source) {
                0 => cpu.registers.b,
                1 => cpu.registers.c,
                2 => cpu.registers.d,
                3 => cpu.registers.e,
                4 => cpu.registers.h,
                5 => cpu.registers.l,
                6 => bus.memory[0x9000],
                7 => cpu.registers.a,
                else => unreachable,
            };
            const operation: flags.LogicOperation = if (std.mem.eql(u8, family.mnemonic, "AND")) .@"and" else if (std.mem.eql(u8, family.mnemonic, "XOR")) .xor else .@"or";
            const expected = flags.logic8(operation, 0x5a, operand);
            const step = try cpu.step(&bus);
            try std.testing.expectEqual(family.register_base + source, step.opcode);
            const expected_size = if (source == 6) family.indirect_size else family.register_size;
            try std.testing.expectEqual(@as(u16, expected_size), step.pc_after);
            try std.testing.expectEqual(if (source == 6) family.indirect_t_states else family.register_t_states, step.t_states);
            try std.testing.expectEqual(expected.value, cpu.registers.a);
            try std.testing.expectEqual(expected.flags, cpu.registers.f);
            try std.testing.expectEqual(@as(usize, if (source == 6) 2 else 1), trace_buffer.len);
            if (source == 6) try std.testing.expectEqual(trace.BusEventKind.memory_read, trace_buffer.get(1).?.kind);
        }

        var immediate_bus = Bus{};
        immediate_bus.memory[0] = family.immediate_opcode;
        immediate_bus.memory[1] = 0x3c;
        var immediate_cpu = Cpu{};
        immediate_cpu.registers.a = 0xc3;
        const operation: flags.LogicOperation = if (std.mem.eql(u8, family.mnemonic, "AND")) .@"and" else if (std.mem.eql(u8, family.mnemonic, "XOR")) .xor else .@"or";
        const expected = flags.logic8(operation, 0xc3, 0x3c);
        const step = try immediate_cpu.step(&immediate_bus);
        try std.testing.expectEqual(family.immediate_opcode, step.opcode);
        try std.testing.expectEqual(@as(u16, family.immediate_size), step.pc_after);
        try std.testing.expectEqual(family.immediate_t_states, step.t_states);
        try std.testing.expectEqual(expected.value, immediate_cpu.registers.a);
        try std.testing.expectEqual(expected.flags, immediate_cpu.registers.f);
    }

    try std.testing.expectEqual(@as(u8, flags.S | flags.H | flags.PV), flags.logic8(.@"and", 0xff, 0x81).flags);
    try std.testing.expectEqual(@as(u8, flags.Z | flags.PV), flags.logic8(.xor, 0xa5, 0xa5).flags);
    try std.testing.expectEqual(@as(u8, flags.S | flags.PV), flags.logic8(.@"or", 0x80, 0x01).flags);
}

test "register load family covers registers indirect memory timing and trace" {
    for (0..8) |destination_index| {
        for (0..8) |source_index| {
            const destination: u8 = @intCast(destination_index);
            const source: u8 = @intCast(source_index);
            const opcode = instruction.ldRegisterOpcode(destination, source) orelse continue;
            var bus = Bus{};
            var trace_buffer = trace.TraceBuffer{};
            bus.trace_sink = trace_buffer.sink();
            bus.memory[0] = opcode;
            var cpu = Cpu{};
            cpu.registers.setBC(0x1122);
            cpu.registers.setDE(0x3344);
            cpu.registers.setHL(0x9000);
            cpu.registers.a = 0x77;
            bus.memory[0x9000] = 0xaa;
            const source_value: u8 = switch (source) {
                0 => 0x11,
                1 => 0x22,
                2 => 0x33,
                3 => 0x44,
                4 => 0x90,
                5 => 0x00,
                6 => 0xaa,
                7 => 0x77,
                else => unreachable,
            };
            const step = try cpu.step(&bus);
            try std.testing.expectEqual(@as(u16, instruction.ldRegisterSize(destination, source)), step.pc_after);
            try std.testing.expectEqual(instruction.ldRegisterTStates(destination, source), step.t_states);
            if (destination == 6) {
                try std.testing.expectEqual(source_value, bus.memory[0x9000]);
                try std.testing.expectEqual(trace.BusEventKind.memory_write, trace_buffer.latest().?.kind);
            } else {
                const actual: u8 = switch (destination) {
                    0 => cpu.registers.b,
                    1 => cpu.registers.c,
                    2 => cpu.registers.d,
                    3 => cpu.registers.e,
                    4 => cpu.registers.h,
                    5 => cpu.registers.l,
                    7 => cpu.registers.a,
                    else => unreachable,
                };
                try std.testing.expectEqual(source_value, actual);
                if (source == 6) try std.testing.expectEqual(trace.BusEventKind.memory_read, trace_buffer.latest().?.kind);
            }
            try std.testing.expectEqual(@as(usize, if (destination == 6 or source == 6) 2 else 1), trace_buffer.len);
        }
    }
}

test "assembler and disassembler synchronize logical and register load families" {
    const source =
        \\org 0
        \\ld b,a
        \\ld c,(hl)
        \\ld (hl),d
        \\and b
        \\and (hl)
        \\and 0x55
        \\xor c
        \\xor (hl)
        \\xor 0xaa
        \\or d
        \\or (hl)
        \\or 0x80
    ;
    var assembled = try assembler.assemble(std.testing.allocator, source);
    defer assembled.deinit();
    const expected = [_]u8{ 0x47, 0x4e, 0x72, 0xa0, 0xa6, 0xe6, 0x55, 0xa9, 0xae, 0xee, 0xaa, 0xb2, 0xb6, 0xf6, 0x80 };
    try std.testing.expectEqualSlices(u8, &expected, assembled.bytes.items);

    const expected_text = [_][]const u8{
        "LD B,A", "LD C,(HL)", "LD (HL),D", "AND B", "AND (HL)", "AND 0x55",
        "XOR C",  "XOR (HL)",  "XOR 0xAA",  "OR D",  "OR (HL)",  "OR 0x80",
    };
    var address: u16 = 0;
    for (expected_text) |wanted| {
        const decoded = disassembler.decode(assembled.bytes.items, address);
        try std.testing.expectEqualStrings(wanted, disassembler.text(&decoded));
        address +%= decoded.size;
    }
    try std.testing.expectEqual(@as(usize, assembled.bytes.items.len), address);
    try std.testing.expectError(error.InvalidOperand, assembler.assemble(std.testing.allocator, "ld (hl),(hl)"));
}

test "phase one arithmetic loop and CB families assemble and disassemble" {
    const source =
        \\adc a,b
        \\adc a,(hl)
        \\adc a,0x12
        \\sbc a,c
        \\sbc a,(hl)
        \\sbc a,0x34
        \\inc (hl)
        \\dec (hl)
        \\add hl,bc
        \\add hl,de
        \\add hl,hl
        \\add hl,sp
        \\loop: djnz loop
        \\bit 3,b
        \\bit 7,(hl)
        \\res 2,c
        \\res 0,(hl)
        \\set 5,d
        \\set 7,(hl)
        \\rlc b
        \\rrc c
        \\rl d
        \\rr e
        \\sla h
        \\sra l
        \\srl (hl)
    ;
    var assembled = try assembler.assemble(std.testing.allocator, source);
    defer assembled.deinit();
    const expected = [_]u8{
        0x88, 0x8e, 0xce, 0x12, 0x99, 0x9e, 0xde, 0x34, 0x34, 0x35,
        0x09, 0x19, 0x29, 0x39, 0x10, 0xfe, 0xcb, 0x58, 0xcb, 0x7e,
        0xcb, 0x91, 0xcb, 0x86, 0xcb, 0xea, 0xcb, 0xfe, 0xcb, 0x00,
        0xcb, 0x09, 0xcb, 0x12, 0xcb, 0x1b, 0xcb, 0x24, 0xcb, 0x2d,
        0xcb, 0x3e,
    };
    try std.testing.expectEqualSlices(u8, &expected, assembled.bytes.items);
    var address: u16 = 0;
    while (address < assembled.bytes.items.len) {
        const decoded = disassembler.decode(assembled.bytes.items, address);
        try std.testing.expect(!std.mem.startsWith(u8, disassembler.text(&decoded), "DB"));
        address +%= decoded.size;
    }
    try std.testing.expectEqual(@as(usize, expected.len), address);
    try std.testing.expectError(error.ValueOutOfRange, assembler.assemble(std.testing.allocator, "bit 8,a"));
}

test "ADC SBC memory arithmetic and DJNZ timing edge cases" {
    try std.testing.expectEqual(@as(u8, flags.S | flags.H | flags.PV), flags.adc8(0x7f, 0, true).flags);
    try std.testing.expectEqual(@as(u8, flags.Z | flags.H | flags.C), flags.adc8(0xff, 0, true).flags);
    try std.testing.expectEqual(@as(u8, flags.H | flags.PV | flags.N), flags.sbc8(0x80, 0, true).flags);
    try std.testing.expectEqual(@as(u8, flags.S | flags.H | flags.N | flags.C), flags.sbc8(0, 0, true).flags);

    var bus = Bus{};
    bus.memory[0..6].* = .{ 0x34, 0x35, 0x09, 0x10, 0xfe, 0x76 };
    bus.memory[0x9000] = 0xff;
    var cpu = Cpu{};
    cpu.registers.setHL(0x9000);
    cpu.registers.setBC(0x1002);
    cpu.registers.b = 2;
    cpu.registers.f = flags.C | flags.S | flags.Z | flags.PV;
    var step = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 11), step.t_states);
    try std.testing.expectEqual(@as(u8, 0), bus.memory[0x9000]);
    try std.testing.expect(flags.isSet(cpu.registers.f, flags.C));
    step = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u8, 0xff), bus.memory[0x9000]);
    try std.testing.expectEqual(@as(u16, 11), step.t_states);
    const preserved_flags = cpu.registers.f & (flags.S | flags.Z | flags.PV);
    step = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 11), step.t_states);
    try std.testing.expectEqual(preserved_flags, cpu.registers.f & (flags.S | flags.Z | flags.PV));
    step = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 13), step.t_states);
    try std.testing.expectEqual(@as(u8, 1), cpu.registers.b);
    step = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u16, 8), step.t_states);
    try std.testing.expectEqual(@as(u8, 0), cpu.registers.b);
}

test "CB operations cover registers memory flags and timing" {
    const cases = [_]struct { operation: instruction.CbOperation, input: u8, carry: bool, expected: u8 }{
        .{ .operation = .rlc, .input = 0x81, .carry = false, .expected = 0x03 },
        .{ .operation = .rrc, .input = 0x81, .carry = false, .expected = 0xc0 },
        .{ .operation = .rl, .input = 0x80, .carry = true, .expected = 0x01 },
        .{ .operation = .rr, .input = 0x01, .carry = true, .expected = 0x80 },
        .{ .operation = .sla, .input = 0x81, .carry = false, .expected = 0x02 },
        .{ .operation = .sra, .input = 0x81, .carry = false, .expected = 0xc0 },
        .{ .operation = .srl, .input = 0x81, .carry = false, .expected = 0x40 },
    };
    for (cases) |case| {
        var bus = Bus{};
        bus.memory[0] = 0xcb;
        bus.memory[1] = instruction.cbOpcode(case.operation, 0, 0);
        var cpu = Cpu{};
        cpu.registers.b = case.input;
        cpu.registers.f = if (case.carry) flags.C else 0;
        const step = try cpu.step(&bus);
        try std.testing.expectEqual(case.expected, cpu.registers.b);
        try std.testing.expectEqual(@as(u16, 8), step.t_states);
    }

    var memory_bus = Bus{};
    memory_bus.memory[0..8].* = .{ 0xcb, 0x46, 0xcb, 0x86, 0xcb, 0xc6, 0xcb, 0x3e };
    memory_bus.memory[0x9000] = 1;
    var memory_cpu = Cpu{};
    memory_cpu.registers.setHL(0x9000);
    memory_cpu.registers.f = flags.C;
    var step = try memory_cpu.step(&memory_bus);
    try std.testing.expectEqual(@as(u16, 12), step.t_states);
    try std.testing.expectEqual(@as(u8, flags.C | flags.H), memory_cpu.registers.f);
    step = try memory_cpu.step(&memory_bus);
    try std.testing.expectEqual(@as(u16, 15), step.t_states);
    try std.testing.expectEqual(@as(u8, 0), memory_bus.memory[0x9000]);
    const preserved = memory_cpu.registers.f;
    _ = try memory_cpu.step(&memory_bus);
    try std.testing.expectEqual(@as(u8, 1), memory_bus.memory[0x9000]);
    try std.testing.expectEqual(preserved, memory_cpu.registers.f);
    step = try memory_cpu.step(&memory_bus);
    try std.testing.expectEqual(@as(u16, 15), step.t_states);
    try std.testing.expectEqual(@as(u8, 0), memory_bus.memory[0x9000]);
    try std.testing.expect(flags.isSet(memory_cpu.registers.f, flags.C));
}

test "CB opcode matrix covers every documented register and bit operand" {
    const rotations = [_]instruction.CbOperation{ .rlc, .rrc, .rl, .rr, .sla, .sra, .srl };
    for (rotations) |operation| {
        for (0..8) |register_index| {
            const register: u8 = @intCast(register_index);
            var bus = Bus{};
            bus.memory[0] = 0xcb;
            bus.memory[1] = instruction.cbOpcode(operation, 0, register);
            bus.memory[0x9000] = 0x81;
            var cpu = Cpu{};
            cpu.registers.setBC(0x8181);
            cpu.registers.setDE(0x8181);
            cpu.registers.setHL(0x9000);
            cpu.registers.a = 0x81;
            cpu.registers.f = flags.C;
            const operand_value: u8 = switch (register) {
                4 => 0x90,
                5 => 0,
                else => 0x81,
            };
            const expected = flags.rotateShift(operation, operand_value, flags.C);
            const step = try cpu.step(&bus);
            const actual: u8 = switch (register) {
                0 => cpu.registers.b,
                1 => cpu.registers.c,
                2 => cpu.registers.d,
                3 => cpu.registers.e,
                4 => cpu.registers.h,
                5 => cpu.registers.l,
                6 => bus.memory[0x9000],
                7 => cpu.registers.a,
                else => unreachable,
            };
            try std.testing.expectEqual(expected.value, actual);
            try std.testing.expectEqual(expected.flags, cpu.registers.f);
            try std.testing.expectEqual(instruction.cbTStates(operation, register), step.t_states);
            try std.testing.expectEqual(@as(u16, 2), step.pc_after);
        }
    }

    for ([_]instruction.CbOperation{ .bit, .res, .set }) |operation| {
        for (0..8) |bit_index| {
            const bit: u3 = @intCast(bit_index);
            for (0..8) |register_index| {
                const register: u8 = @intCast(register_index);
                var bus = Bus{};
                bus.memory[0] = 0xcb;
                bus.memory[1] = instruction.cbOpcode(operation, bit, register);
                bus.memory[0x9000] = 0xaa;
                var cpu = Cpu{};
                cpu.registers.setBC(0xaaaa);
                cpu.registers.setDE(0xaaaa);
                cpu.registers.setHL(0x9000);
                cpu.registers.a = 0xaa;
                cpu.registers.f = flags.C;
                const operand_value: u8 = switch (register) {
                    4 => 0x90,
                    5 => 0,
                    else => 0xaa,
                };
                const old_flags = cpu.registers.f;
                const step = try cpu.step(&bus);
                try std.testing.expectEqual(instruction.cbTStates(operation, register), step.t_states);
                try std.testing.expectEqual(@as(u16, 2), step.pc_after);
                if (operation == .bit) {
                    try std.testing.expectEqual(flags.bitTest(bit, operand_value, old_flags), cpu.registers.f);
                } else {
                    const mask = @as(u8, 1) << bit;
                    const expected = if (operation == .res) operand_value & ~mask else operand_value | mask;
                    const actual: u8 = switch (register) {
                        0 => cpu.registers.b,
                        1 => cpu.registers.c,
                        2 => cpu.registers.d,
                        3 => cpu.registers.e,
                        4 => cpu.registers.h,
                        5 => cpu.registers.l,
                        6 => bus.memory[0x9000],
                        7 => cpu.registers.a,
                        else => unreachable,
                    };
                    try std.testing.expectEqual(expected, actual);
                    try std.testing.expectEqual(old_flags, cpu.registers.f);
                }
            }
        }
    }
}

test "absolute load advances PC past the 16-bit address" {
    var bus = Bus{};
    bus.memory[0..4].* = .{ 0x3a, 0x00, 0xc4, 0x76 };
    bus.write8(0xc400, 0x42);
    var cpu = Cpu{};
    const step = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u8, 0x42), cpu.registers.a);
    try std.testing.expectEqual(@as(u16, 3), cpu.registers.pc);
    try std.testing.expectEqual(@as(u16, 3), step.pc_after);
    _ = try cpu.step(&bus);
    try std.testing.expect(cpu.halted);
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
