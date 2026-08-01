const std = @import("std");
const Cpu = @import("cpu/cpu.zig").Cpu;
const Bus = @import("machine/bus.zig").Bus;
const Machine = @import("machine/machine.zig").Machine;
const flags = @import("cpu/flags.zig");
const assembler = @import("assembler/assembler.zig");
const disassembler = @import("disassembler/disassembler.zig");
const video = @import("machine/video.zig");
const trace = @import("trace/trace.zig");
const SourceBuffer = @import("tui/editor/buffer.zig").SourceBuffer;
const Frame = @import("tui/render/frame.zig").Frame;
const render_diff = @import("tui/render/diff.zig");
const input = @import("tui/terminal/input.zig");
const command = @import("tui/command.zig");
const Layout = @import("tui/layout.zig").Layout;
const AppState = @import("tui/state.zig").AppState;
const ExecutionState = @import("tui/state.zig").ExecutionState;
const tui_app = @import("tui/app.zig");

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
test "source buffer edits utf8 text and tracks cursor dirty state and scrolling" {
    var source = try SourceBuffer.init(std.testing.allocator, "ab\ncd");
    defer source.deinit();
    source.moveRight();
    try source.insert('X');
    try std.testing.expectEqualStrings("aXb\ncd", source.text());
    source.backspace();
    source.moveEnd();
    try source.newline();
    try source.insert(0x03bb);
    try std.testing.expect(std.unicode.utf8ValidateSlice(source.text()));
    source.moveLeft();
    source.delete();
    try std.testing.expectEqualStrings("ab\n\ncd", source.text());
    source.moveDown();
    source.ensureVisible(1, 1);
    try std.testing.expect(source.dirty);
    try std.testing.expect(source.scroll_y > 0);
    try std.testing.expect(source.goToLine(0));
    try std.testing.expectEqual(@as(usize, 0), source.cursor);
}
test "input decoder and keymap recognize terminal sequences and alternatives" {
    const up = input.decode("\x1b[A").?;
    try std.testing.expect(up.code == .up);
    const assemble = command.map(input.decode("\x1bOQ").?);
    try std.testing.expect(assemble == .assemble);
    const save = command.map(input.decode(&.{19}).?);
    try std.testing.expect(save == .save);
    const bus_screen = command.map(input.decode("\x1b4").?);
    try std.testing.expect(bus_screen == .switch_screen);
    try std.testing.expectEqual(command.Screen.bus, bus_screen.switch_screen);
    try std.testing.expect(command.map(.{ .code = .tab }) == .none);
}
test "frame clips content and diff emits only changes" {
    var old = try Frame.init(std.testing.allocator, 8, 2);
    defer old.deinit();
    var next = try Frame.init(std.testing.allocator, 8, 2);
    defer next.deinit();
    next.writeText(1, 0, "CPU", .{ .bold = true });
    next.writeText(7, 1, "XY", .{});
    try std.testing.expectEqual(@as(u21, 'C'), next.get(1, 0).codepoint);
    try std.testing.expectEqual(@as(u21, 'X'), next.get(7, 1).codepoint);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try render_diff.render(std.testing.allocator, &output, &old, &next, false);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "CPU") == null); // changed cells have cursor moves between them
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\x1b[1;2H") != null);
    old.cells[1] = next.cells[1];
    try render_diff.render(std.testing.allocator, &output, &old, &next, false);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\x1b[1;2H") == null);
}
test "layout supports normal and compact terminals" {
    const normal = Layout.calculate(120, 40);
    try std.testing.expect(!normal.compact);
    try std.testing.expectEqual(@as(usize, 72), normal.source.width);
    const compact = Layout.calculate(62, 18);
    try std.testing.expect(compact.compact);
    try std.testing.expectEqual(@as(usize, 17), compact.status.y);
}
test "app state assembles steps synchronizes source and resets" {
    var state = try AppState.init(std.testing.allocator, "test.asm", "org 0\nld hl, 0xC000\nld (hl), 1\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.assemble();
    try std.testing.expectEqual(ExecutionState.assembled, state.execution_state);
    try std.testing.expectEqual(@as(?usize, 2), state.sourceLineForPC(0));
    state.step();
    try std.testing.expectEqual(@as(u16, 0xc000), state.machine.cpu.registers.hl());
    try std.testing.expectEqual(ExecutionState.paused, state.execution_state);
    state.step();
    try std.testing.expectEqual(@as(?u16, 0xc000), state.last_memory_write);
    state.runFromReset();
    state.pause();
    try std.testing.expectEqual(ExecutionState.paused, state.execution_state);
    state.continueExecution();
    state.runSlice(20);
    try std.testing.expectEqual(ExecutionState.halted, state.execution_state);
    state.reset();
    try std.testing.expectEqual(@as(u16, 0), state.machine.cpu.registers.pc);
}
test "app state preserves source on assembly failure and stops at breakpoint" {
    var invalid = try AppState.init(std.testing.allocator, null, "jp missing\n");
    defer invalid.deinit();
    invalid.assemble();
    try std.testing.expectEqual(ExecutionState.faulted, invalid.execution_state);
    try std.testing.expect(invalid.diagnostic != null);
    try std.testing.expectEqualStrings("jp missing\n", invalid.source.text());

    var state = try AppState.init(std.testing.allocator, null, "org 0\nnop\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.assemble();
    state.source.moveDown();
    state.toggleBreakpoint();
    state.runFromReset();
    state.runSlice(4);
    try std.testing.expectEqual(ExecutionState.breakpoint, state.execution_state);
    state.continueExecution();
    state.runSlice(4);
    try std.testing.expectEqual(ExecutionState.halted, state.execution_state);
}
test "tui app renders source cpu bus and compact views without a terminal" {
    var state = try AppState.init(std.testing.allocator, "pixel.asm", "org 0\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.assemble();
    state.step();
    var normal = try Frame.init(std.testing.allocator, 100, 30);
    defer normal.deinit();
    tui_app.render(&state, &normal);
    try std.testing.expectEqual(@as(u21, 'Z'), normal.get(1, 0).codepoint);
    var compact = try Frame.init(std.testing.allocator, 60, 18);
    defer compact.deinit();
    state.active_screen = .display;
    tui_app.render(&state, &compact);
    try std.testing.expectEqual(@as(u21, '+'), compact.get(0, 2).codepoint);
}
test "memory accepts hexadecimal address input and bus selection jumps to source" {
    var state = try AppState.init(std.testing.allocator, null, "org 0\nld a, 1\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.assemble();
    state.step();
    state.active_screen = .memory;
    for ("8120") |digit| try state.apply(.{ .insert_character = digit }, std.testing.io);
    try std.testing.expectEqual(@as(u16, 0x8120), state.memory_address);
    state.active_screen = .bus;
    state.selected_trace_event = 0;
    try state.apply(.newline, std.testing.io);
    try std.testing.expectEqual(command.Screen.editor, state.active_screen);
    try std.testing.expectEqual(@as(usize, 1), state.source.lineAndColumn().line);
}
