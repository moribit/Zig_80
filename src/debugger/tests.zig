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

test "conditional hit count enabled and temporary breakpoints share one API" {
    var breaks = breakpoint.Breakpoints{};
    const condition = try breakpoint.parseCondition("A", "==", "0x2A");
    try std.testing.expect(breaks.addOptions(0x1234, .{ .condition = condition, .hit_target = 3 }));
    var registers = @import("../cpu/registers.zig").Registers{};
    registers.a = 0x2a;
    try std.testing.expect(!breaks.shouldBreak(0x1234, registers));
    try std.testing.expect(!breaks.shouldBreak(0x1234, registers));
    try std.testing.expect(breaks.shouldBreak(0x1234, registers));
    try std.testing.expect(breaks.setEnabled(0x1234, false));
    try std.testing.expect(!breaks.shouldBreak(0x1234, registers));
    try std.testing.expect(breaks.remove(0x1234));

    const flag_condition = try breakpoint.parseCondition("Z", "==", "1");
    registers.f = flags.Z;
    try std.testing.expect(breaks.addOptions(0x2000, .{ .condition = flag_condition, .temporary = true }));
    try std.testing.expect(breaks.shouldBreak(0x2000, registers));
    try std.testing.expect(!breaks.contains(0x2000));
}

test "debug session stops on ranged value watchpoint without replacing UI trace" {
    var machine = Machine{};
    const program = [_]u8{ 0x21, 0x00, 0x90, 0x36, 0x2a, 0x76 };
    try machine.load(&program);
    var visible_trace = trace.TraceBuffer{};
    machine.bus.trace_sink = visible_trace.sink();
    var session = DebugSession{};
    const value_condition = try breakpoint.parseValueCondition("!=", "0");
    try std.testing.expect(session.watchpoints.add(.{ .kind = .memory_write, .start = 0x9000, .end = 0x90ff, .condition = value_condition }));
    session.reset(&machine);
    _ = try session.step(&machine);
    try std.testing.expect(session.last_watchpoint == null);
    _ = try session.step(&machine);
    try std.testing.expectEqual(@as(?usize, 0), session.last_watchpoint);
    try std.testing.expectEqual(@as(u8, 0x2a), machine.bus.memory[0x9000]);
    try std.testing.expect(visible_trace.len > 0);
    try std.testing.expect(session.watch_trace.len > 0);
}
