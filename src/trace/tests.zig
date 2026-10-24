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

test "trace records logical opcode operand read and memory write events" {
    var events = trace.RingBuffer(8){};
    var bus = Bus{};
    bus.trace_sink = events.sink();
    bus.memory[0..6].* = .{ 0x21, 0x00, 0xc0, 0x36, 0x01, 0x76 };
    var cpu = Cpu{};
    _ = try cpu.step(&bus);
    _ = try cpu.step(&bus);
    try std.testing.expectEqual(@as(usize, 6), events.len);
    try std.testing.expectEqual(trace.BusEventKind.opcode_fetch, events.get(0).?.kind);
    try std.testing.expectEqual(trace.BusEventKind.operand_read, events.get(1).?.kind);
    try std.testing.expectEqual(@as(u8, 0), events.get(0).?.event_index_in_instruction);
    try std.testing.expectEqual(@as(u8, 1), events.get(1).?.event_index_in_instruction);
    try std.testing.expectEqual(@as(u8, 0), events.get(3).?.event_index_in_instruction);
    try std.testing.expectEqual(trace.BusEventKind.memory_write, events.latest().?.kind);
    try std.testing.expectEqual(@as(u16, 0xc000), events.latest().?.address);
    try std.testing.expectEqual(@as(u64, 1), events.latest().?.instruction_index);
}
test "trace ring buffer discards oldest events without allocation" {
    var events = trace.RingBuffer(2){};
    const base = trace.BusEvent{ .sequence = 0, .instruction_index = 0, .t_state_start = 0, .kind = .memory_read, .address = 0, .data = 0, .signals = .{}, .pc = 0 };
    events.record(base);
    var second = base;
    second.sequence = 1;
    events.record(second);
    var third = base;
    third.sequence = 2;
    events.record(third);
    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqual(@as(u64, 1), events.get(0).?.sequence);
    try std.testing.expectEqual(@as(u64, 2), events.get(1).?.sequence);
}
test "disabled trace has no side effects or sequence updates" {
    var bus = Bus{};
    bus.memory[0] = 0x76;
    var cpu = Cpu{};
    _ = try cpu.step(&bus);
    try std.testing.expectEqual(@as(u64, 0), bus.trace_sequence);
}
