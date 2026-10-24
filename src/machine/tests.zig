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
const machine_input = @import("../machine/input.zig");

test "input state recording script and replay preserve simultaneous press release" {
    var state = machine_input.State{};
    try std.testing.expect(state.apply(.press, .right));
    try std.testing.expect(state.apply(.press, .a));
    try std.testing.expect(state.pressed(.right));
    try std.testing.expect(state.pressed(.a));
    try std.testing.expect(state.apply(.release, .right));
    try std.testing.expect(!state.pressed(.right));
    try std.testing.expect(state.pressed(.a));

    const script =
        \\120 press a
        \\0 press right
        \\100 release right
        \\125 release a
    ;
    const events = try machine_input.parseScript(std.testing.allocator, script);
    defer std.testing.allocator.free(events);
    try std.testing.expectEqual(@as(usize, 4), events.len);
    try std.testing.expectEqual(@as(u64, 0), events[0].at_instruction);
    var replay = machine_input.Replay{ .events = events };
    try std.testing.expect(replay.advance(0).pressed(.right));
    try std.testing.expect(!replay.advance(100).pressed(.right));
    try std.testing.expect(replay.advance(120).pressed(.a));
    try std.testing.expect(!replay.advance(125).pressed(.a));
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
