const std = @import("std");

test "instruction panel shows all four indexed bytes and shared timing" {
    var state = try AppState.init(std.testing.allocator, null, "ld (ix+0),0x42\n");
    defer state.deinit();
    state.assemble();
    var frame = try Frame.init(std.testing.allocator, 80, 16);
    defer frame.deinit();
    tui_app.renderInstruction(&state, &frame, .{ .x = 0, .y = 0, .width = 80, .height = 16 });
    try std.testing.expect(frameContains(&frame, "DD 36 00 42"));
    try std.testing.expect(frameContains(&frame, "19 T"));
}
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
const render_diff = @import("../tui/render/diff.zig");
const input = @import("../tui/terminal/input.zig");
const command = @import("../tui/command.zig");
const Layout = @import("../tui/layout.zig").Layout;
const AppState = @import("../tui/state.zig").AppState;
const ExecutionState = @import("../tui/state.zig").ExecutionState;
const PromptMode = @import("../tui/state.zig").PromptMode;
const DisplayScale = @import("../tui/state.zig").DisplayScale;
const tui_app = @import("../tui/app.zig");
const bus_waveform = @import("../tui/bus_waveform.zig");
const Rect = @import("../tui/layout.zig").Rect;
const editor_syntax = @import("../tui/editor/syntax.zig");
const breakpoint = @import("../debugger/breakpoint.zig");
const DebugSession = @import("../debugger/session.zig").DebugSession;
const machine_input = @import("../machine/input.zig");

fn frameContains(frame: *const Frame, text: []const u8) bool {
    if (text.len == 0) return true;
    for (0..frame.height) |y| {
        for (0..frame.width) |x| {
            if (x + text.len > frame.width) break;
            var matches = true;
            for (text, 0..) |character, offset| if (frame.get(x + offset, y).codepoint != character) {
                matches = false;
                break;
            };
            if (matches) return true;
        }
    }
    return false;
}

fn frameRowContains(frame: *const Frame, y: usize, text: []const u8) bool {
    if (y >= frame.height or text.len == 0) return false;
    for (0..frame.width) |x| {
        if (x + text.len > frame.width) break;
        var matches = true;
        for (text, 0..) |character, offset| if (frame.get(x + offset, y).codepoint != character) {
            matches = false;
            break;
        };
        if (matches) return true;
    }
    return false;
}

test "TUI game input mode isolates editor and records explicit releases" {
    var state = try AppState.init(std.testing.allocator, null, "halt\n");
    defer state.deinit();
    const original_source = try std.testing.allocator.dupe(u8, state.source.text());
    defer std.testing.allocator.free(original_source);
    try state.apply(.toggle_game_input, std.testing.io);
    try std.testing.expect(state.game_input_mode);
    try std.testing.expect(state.applyGameKey(.{ .code = .right }));
    try std.testing.expect(state.applyGameKey(.{ .code = .{ .character = 'j' } }));
    try std.testing.expectEqual(machine_input.Right | machine_input.A, state.machine.bus.memory[0xc400]);
    try std.testing.expectEqualStrings(original_source, state.source.text());
    try std.testing.expect(state.applyGameKey(.{ .code = .{ .character = 'J' } }));
    try std.testing.expectEqual(machine_input.Right, state.machine.bus.memory[0xc400]);
    state.tickUi(1000);
    try std.testing.expectEqual(@as(u8, 0), state.machine.bus.memory[0xc400]);
    try std.testing.expect(state.input_recording.len >= 4);
    try std.testing.expect(state.applyGameKey(.{ .code = .escape }));
    try std.testing.expect(!state.game_input_mode);
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
    const assemble = command.map(.{ .code = .{ .character = 'r' }, .ctrl = true });
    try std.testing.expect(assemble == .assemble);
    const save = command.map(input.decode(&.{19}).?);
    try std.testing.expect(save == .save);
    const bus_screen = command.map(input.decode("\x1b4").?);
    try std.testing.expect(bus_screen == .switch_screen);
    try std.testing.expectEqual(command.Screen.bus, bus_screen.switch_screen);
    try std.testing.expect(command.map(.{ .code = .tab }) == .next_pane);
    try std.testing.expect(command.map(.{ .code = .tab, .shift = true }) == .previous_pane);
    try std.testing.expect(command.map(.{ .code = .{ .function = 2 } }) == .none);
    try std.testing.expect(command.map(input.decode(&.{0}).?) == .continue_execution);
    const ctrl_one = command.map(input.decode("\x1b[49;5u").?);
    try std.testing.expect(ctrl_one == .switch_screen);
    try std.testing.expectEqual(command.Screen.editor, ctrl_one.switch_screen);
}

test "stream input decoder preserves split escape alt and utf8 input" {
    var decoder: input.InputDecoder = .{};
    decoder.feed("\x1b[");
    try std.testing.expect(decoder.next(0) == null);
    decoder.feed("A");
    try std.testing.expect(decoder.next(1).?.code == .up);

    decoder.feed("\x1b");
    try std.testing.expect(decoder.next(10) == null);
    decoder.feed("x");
    const alt = decoder.next(11).?;
    try std.testing.expect(alt.alt);
    try std.testing.expectEqual(@as(u21, 'x'), alt.code.character);

    const lambda = "λ";
    decoder.feed(lambda[0..1]);
    try std.testing.expect(decoder.next(20) == null);
    decoder.feed(lambda[1..]);
    try std.testing.expectEqual(@as(u21, 0x03bb), decoder.next(21).?.code.character);
}

test "stream input decoder handles batches escape timeout unknown input and overflow" {
    var decoder: input.InputDecoder = .{};
    decoder.feed("abc");
    try std.testing.expectEqual(@as(u21, 'a'), decoder.next(0).?.code.character);
    try std.testing.expectEqual(@as(u21, 'b'), decoder.next(0).?.code.character);
    try std.testing.expectEqual(@as(u21, 'c'), decoder.next(0).?.code.character);

    decoder.feed("\x1b");
    try std.testing.expect(decoder.next(100) == null);
    try std.testing.expect(decoder.next(100 + input.escape_timeout_ms - 1) == null);
    try std.testing.expect(decoder.next(100 + input.escape_timeout_ms).?.code == .escape);

    decoder.feed("\x1b");
    try std.testing.expect(decoder.next(150) == null);
    decoder.feed("x");
    try std.testing.expect(decoder.next(150 + input.escape_timeout_ms).?.code == .escape);
    try std.testing.expectEqual(@as(u21, 'x'), decoder.next(151 + input.escape_timeout_ms).?.code.character);

    decoder.feed("\x1b[99~z");
    try std.testing.expectEqual(@as(u21, 'z'), decoder.next(200).?.code.character);

    var large: [300]u8 = @splat('q');
    decoder.feed(&large);
    var count: usize = 0;
    while (decoder.next(300) != null) count += 1;
    try std.testing.expectEqual(@as(usize, 256), count);
    decoder.feed(&.{ 0xff, 'k' });
    try std.testing.expectEqual(@as(u21, 'k'), decoder.next(301).?.code.character);
}
test "frame clips content and diff emits only changes" {
    var old = try Frame.init(std.testing.allocator, 8, 2);
    defer old.deinit();
    var next = try Frame.init(std.testing.allocator, 8, 2);
    defer next.deinit();
    next.writeText(1, 0, "CPU", .{ .bold = true });
    next.writeText(7, 1, "XY", .{});
    next.fillRect(std.math.maxInt(usize), std.math.maxInt(usize), 8, 8, 'X', .{});
    next.box(std.math.maxInt(usize), std.math.maxInt(usize), 8, 8, "OUTSIDE", .{});
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
    try std.testing.expectEqual(@as(usize, 84), normal.source.width);
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
    try std.testing.expect(invalid.diagnostics_list.items.len > 0);
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
    try std.testing.expectEqual(@as(u21, '┌'), compact.get(0, 2).codepoint);
    state.unicode_ui = false;
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
    try state.apply(.{ .insert_character = 'g' }, std.testing.io);
    for ("8120") |digit| try state.apply(.{ .insert_character = digit }, std.testing.io);
    try std.testing.expect(state.memory_input.active);
    try state.apply(.newline, std.testing.io);
    try std.testing.expectEqual(@as(u16, 0x8120), state.memory_address);
    state.active_screen = .bus;
    state.selected_trace_event = 0;
    try state.apply(.newline, std.testing.io);
    try std.testing.expectEqual(command.Screen.editor, state.active_screen);
    try std.testing.expectEqual(@as(usize, 1), state.source.lineAndColumn().line);
}

test "memory address input supports backspace cancel and visible state" {
    var state = try AppState.init(std.testing.allocator, null, "");
    defer state.deinit();
    state.active_screen = .memory;
    try state.apply(.{ .insert_character = 'g' }, std.testing.io);
    for ("12Z3") |digit| try state.apply(.{ .insert_character = digit }, std.testing.io);
    try state.apply(.backspace, std.testing.io);
    try state.apply(.{ .insert_character = 'A' }, std.testing.io);
    try state.apply(.{ .insert_character = 'F' }, std.testing.io);
    try state.apply(.newline, std.testing.io);
    try std.testing.expectEqual(@as(u16, 0x12af), state.memory_address);
    try state.apply(.{ .insert_character = 'g' }, std.testing.io);
    try state.apply(.cancel, std.testing.io);
    try std.testing.expect(!state.memory_input.active);
}

test "logical bus waveform renders selection scrolling ascii and small terminals" {
    var state = try AppState.init(std.testing.allocator, null, "org 0\nld hl, 0xC000\nld (hl), 1\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.assemble();
    state.runFromReset();
    state.runSlice(10);
    state.active_screen = .bus;
    state.bus_view = .waveform;
    state.trace_follow = false;
    state.selected_trace_event = 1;
    var frame = try Frame.init(std.testing.allocator, 90, 16);
    defer frame.deinit();
    tui_app.renderBus(&state, &frame, Rect{ .x = 0, .y = 0, .width = 90, .height = 16 });
    var found_selected = false;
    for (4..frame.height - 1) |y| for (0..frame.width) |x| if (frame.get(x, y).style.reverse) {
        found_selected = true;
        break;
    };
    try std.testing.expect(found_selected);
    var recommended = try Frame.init(std.testing.allocator, 80, 24);
    defer recommended.deinit();
    tui_app.render(&state, &recommended);
    try std.testing.expect(frameContains(&recommended, "DATA"));
    const before = state.selected_trace_event;
    try state.apply(.{ .move_cursor = .right }, std.testing.io);
    try std.testing.expectEqual(before + 1, state.selected_trace_event);

    var ascii = try Frame.init(std.testing.allocator, 50, 14);
    defer ascii.deinit();
    bus_waveform.render(&ascii, Rect{ .x = 0, .y = 0, .width = 50, .height = 14 }, &state.trace, 0, false);
    var found_level = false;
    for (ascii.cells) |cell| if (cell.codepoint == '=' or cell.codepoint == '_') {
        found_level = true;
        break;
    };
    try std.testing.expect(found_level);
    ascii.clear();
    bus_waveform.render(&ascii, Rect{ .x = 0, .y = 0, .width = 24, .height = 14 }, &state.trace, state.trace.len - 1, false);
    var found_scrolled_selection = false;
    for (ascii.cells) |cell| if (cell.codepoint == '|') {
        found_scrolled_selection = true;
        break;
    };
    try std.testing.expect(found_scrolled_selection);
    var found_marker = false;
    for (ascii.cells) |cell| if (cell.codepoint == 'v' or cell.codepoint == '|') {
        found_marker = true;
        break;
    };
    try std.testing.expect(found_marker);
    var tiny = try Frame.init(std.testing.allocator, 18, 5);
    defer tiny.deinit();
    bus_waveform.render(&tiny, Rect{ .x = 0, .y = 0, .width = 18, .height = 5 }, &state.trace, 0, false);
}

test "assembler structured diagnostics carry source positions and navigate" {
    const cases = [_]struct { source: []const u8, expected: assembler.AssembleError }{
        .{ .source = "bogus a\n", .expected = error.InvalidMnemonic },
        .{ .source = "ld nope, 1\n", .expected = error.InvalidOperand },
        .{ .source = "jp missing\n", .expected = error.UndefinedSymbol },
        .{ .source = "x:\nx:\n", .expected = error.DuplicateSymbol },
        .{ .source = "db 999\n", .expected = error.ValueOutOfRange },
        .{ .source = ".bad 1\n", .expected = error.InvalidDirective },
        .{ .source = "db 1+\n", .expected = error.InvalidExpression },
        .{ .source = "db \"oops\n", .expected = error.UnterminatedString },
        .{ .source = "db 'xy'\n", .expected = error.InvalidCharacterLiteral },
        .{ .source = "jr far\norg 0x0200\nfar:\nhalt\n", .expected = error.RelativeOutOfRange },
    };
    for (cases) |case| {
        var failure: assembler.FailureLocation = .{};
        var result = assembler.assembleLocated(std.testing.allocator, case.source, &failure) catch |err| {
            try std.testing.expectEqual(case.expected, err);
            try std.testing.expect(failure.line >= 1);
            try std.testing.expect(failure.column >= 1);
            try std.testing.expect(failure.end_column >= failure.column);
            try std.testing.expect(failure.source_line.len > 0);
            continue;
        };
        result.deinit();
        return error.TestExpectedError;
    }

    var state = try AppState.init(std.testing.allocator, "bad.asm", "nop\njp missing\nhalt\n");
    defer state.deinit();
    state.assemble();
    try std.testing.expectEqual(@as(?usize, 2), state.diagnostics_list.items[0].value.line);
    try state.apply(.newline, std.testing.io);
    try std.testing.expectEqual(@as(usize, 1), state.source.lineAndColumn().line);
}

test "tui execution limits transition and reset counters while step remains explicit" {
    var state = try AppState.init(std.testing.allocator, null, "org 0\njp 0\n");
    defer state.deinit();
    state.assemble();
    state.execution_limits.max_instructions = 3;
    state.execution_limits.max_t_states = 1_000;
    state.runFromReset();
    state.runSlice(500);
    try std.testing.expectEqual(ExecutionState.limit_reached, state.execution_state);
    try std.testing.expectEqual(@as(u64, 3), state.executed_instructions);
    state.step();
    try std.testing.expectEqual(@as(u64, 4), state.executed_instructions);
    try std.testing.expectEqual(ExecutionState.paused, state.execution_state);
    state.reset();
    try std.testing.expectEqual(@as(u64, 0), state.executed_instructions);
    state.execution_limits.max_instructions = 100;
    state.execution_limits.max_t_states = 10;
    state.runFromReset();
    state.runSlice(500);
    try std.testing.expectEqual(ExecutionState.limit_reached, state.execution_state);
    try std.testing.expect(state.machine.cpu.total_t_states >= 10);
}

test "ide gutter renders markers generated address bytes and token styles" {
    var state = try AppState.init(std.testing.allocator, "gutter.asm", "ld hl, 0xC000\nhalt\n");
    defer state.deinit();
    try std.testing.expect(state.assembly != null); // startup auto-assembly
    var frame = try Frame.init(std.testing.allocator, 90, 8);
    defer frame.deinit();
    tui_app.renderSource(&state, &frame, Rect{ .x = 0, .y = 0, .width = 90, .height = 8 });
    try std.testing.expectEqual(@as(u21, '▶'), frame.get(3, 2).codepoint);
    try std.testing.expectEqual(@as(u21, '1'), frame.get(16, 2).codepoint);
    try std.testing.expectEqual(@as(u21, '0'), frame.get(20, 2).codepoint);
    try std.testing.expectEqual(@as(u21, '2'), frame.get(27, 2).codepoint);
    try std.testing.expectEqual(@import("../tui/render/style.zig").Color.cyan, frame.get(38, 2).style.fg);
    try std.testing.expect(frame.get(1, 2).style.reverse);
    try std.testing.expect(frame.get(88, 2).style.reverse);
    try std.testing.expectEqual(@import("../tui/render/style.zig").Color.blue, frame.get(20, 2).style.fg);
    try std.testing.expectEqual(@as(u21, '│'), frame.get(11, 2).codepoint);
    try std.testing.expectEqual(@as(u21, '│'), frame.get(18, 2).codepoint);

    state.source.moveEnd();
    try state.source.insert(' ');
    try std.testing.expect(state.source.dirty);
}

test "instruction detail shows address bytes mnemonic length timing and description" {
    var state = try AppState.init(std.testing.allocator, null, "ld hl, 0xC000\nhalt\n");
    defer state.deinit();
    var frame = try Frame.init(std.testing.allocator, 52, 11);
    defer frame.deinit();
    tui_app.renderInstruction(&state, &frame, Rect{ .x = 0, .y = 0, .width = 52, .height = 11 });
    try std.testing.expect(frameContains(&frame, "LD HL,0xC000"));
    try std.testing.expect(frameContains(&frame, "ADDRESS"));
    try std.testing.expect(frameContains(&frame, "OPCODE"));
    try std.testing.expect(frameContains(&frame, "LENGTH"));
    try std.testing.expect(frameContains(&frame, "TIMING"));
    try std.testing.expect(frameContains(&frame, "DESCRIPTION"));
    try std.testing.expect(frameContains(&frame, "FLAGS"));
    try std.testing.expectEqual(@import("../tui/render/style.zig").Color.blue, frame.get(2, 3).style.fg);
}

test "source visual hierarchy emphasizes labels and reserves a right margin" {
    var state = try AppState.init(std.testing.allocator, null, "start:\n    nop\n");
    defer state.deinit();
    var frame = try Frame.init(std.testing.allocator, 100, 9);
    defer frame.deinit();
    tui_app.renderSource(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 9 });
    try std.testing.expectEqual(@import("../tui/render/style.zig").Color.magenta, frame.get(38, 2).style.fg);
    try std.testing.expect(frame.get(38, 2).style.bold);
    try std.testing.expectEqual(@as(u21, ' '), frame.get(80, 3).codepoint);
}

test "cpu register changes highlight temporarily and expire" {
    var state = try AppState.init(std.testing.allocator, null, "ld hl, 0xC000\nhalt\n");
    defer state.deinit();
    state.tickUi(100);
    state.step();
    var frame = try Frame.init(std.testing.allocator, 50, 9);
    defer frame.deinit();
    tui_app.renderCpu(&state, &frame, Rect{ .x = 0, .y = 0, .width = 50, .height = 9 });
    try std.testing.expect(frameContains(&frame, "HL 0000"));
    try std.testing.expect(frameContains(&frame, "REGISTERS"));
    try std.testing.expect(frameContains(&frame, "FLAGS"));
    state.tickUi(1400);
    frame.clear();
    tui_app.renderCpu(&state, &frame, Rect{ .x = 0, .y = 0, .width = 50, .height = 9 });
    try std.testing.expect(frameContains(&frame, "HL C000"));
    try std.testing.expect(!frameContains(&frame, "HL 0000"));
}

test "toast renders without color dependency and expires after two seconds" {
    var state = try AppState.init(std.testing.allocator, null, "");
    defer state.deinit();
    state.unicode_ui = false;
    state.tickUi(500);
    state.showToast(.success, "Saved", .{});
    var frame = try Frame.init(std.testing.allocator, 80, 24);
    defer frame.deinit();
    tui_app.renderToast(&state, &frame, 23);
    try std.testing.expect(frameContains(&frame, "+ Saved"));
    state.tickUi(2499);
    try std.testing.expect(state.toast != null);
    state.tickUi(2500);
    try std.testing.expect(state.toast == null);
}

test "status bar reports execution counters trace usage and dirty state" {
    var state = try AppState.init(std.testing.allocator, null, "nop\nhalt\n");
    defer state.deinit();
    try state.source.insert(';');
    var frame = try Frame.init(std.testing.allocator, 100, 1);
    defer frame.deinit();
    tui_app.renderStatus(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 1 });
    try std.testing.expect(frameContains(&frame, "ASSEMBLED"));
    try std.testing.expect(frameContains(&frame, "PC 0000"));
    try std.testing.expect(frameContains(&frame, "Trace 0/4096"));
    try std.testing.expect(frameContains(&frame, "DIRTY"));
    try std.testing.expect(frameContains(&frame, "^F Search"));
}

test "frame borders merge into unicode junctions and ascii fallback" {
    var frame = try Frame.init(std.testing.allocator, 11, 7);
    defer frame.deinit();
    frame.box(0, 0, 6, 4, "", .{});
    frame.box(5, 0, 6, 4, "", .{});
    frame.box(0, 3, 6, 4, "", .{});
    frame.box(5, 3, 6, 4, "", .{});
    try std.testing.expectEqual(@as(u21, '┬'), frame.get(5, 0).codepoint);
    try std.testing.expectEqual(@as(u21, '├'), frame.get(0, 3).codepoint);
    try std.testing.expectEqual(@as(u21, '┼'), frame.get(5, 3).codepoint);
    try std.testing.expectEqual(@as(u21, '┤'), frame.get(10, 3).codepoint);
    try std.testing.expectEqual(@as(u21, '┴'), frame.get(5, 6).codepoint);
    frame.clear();
    frame.unicode = false;
    frame.box(0, 0, 6, 4, "", .{});
    frame.box(5, 0, 6, 4, "", .{});
    try std.testing.expectEqual(@as(u21, '+'), frame.get(5, 0).codepoint);
}

test "dynamic layout replaces empty bus with getting started and expands after trace" {
    var state = try AppState.init(std.testing.allocator, null, "nop\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    var frame = try Frame.init(std.testing.allocator, 100, 30);
    defer frame.deinit();
    tui_app.render(&state, &frame);
    try std.testing.expect(frameContains(&frame, "GETTING STARTED"));
    state.step();
    tui_app.render(&state, &frame);
    try std.testing.expect(frameContains(&frame, "INSTRUCTION #"));
    try std.testing.expect(frameContains(&frame, "MNEMONIC"));
    try std.testing.expect(frameContains(&frame, "EVENTS"));
    try std.testing.expect(frameContains(&frame, "LOGICAL ANALYZER"));
}

test "pane focus context help and command palette follow active state" {
    var state = try AppState.init(std.testing.allocator, null, "nop\nhalt\n");
    defer state.deinit();
    var frame = try Frame.init(std.testing.allocator, 100, 30);
    defer frame.deinit();
    tui_app.render(&state, &frame);
    try std.testing.expect(frameRowContains(&frame, 0, "Zig_80 IDE"));
    try std.testing.expect(frameRowContains(&frame, 1, "untitled.asm"));
    try std.testing.expect(!frameRowContains(&frame, 0, "Ctrl+"));
    try std.testing.expect(!frameRowContains(&frame, 1, "Ctrl+"));
    try state.source.insert(' ');
    tui_app.render(&state, &frame);
    try std.testing.expect(frameRowContains(&frame, 1, "Modified"));
    try std.testing.expect(frame.get(3, 2).style.reverse); // SOURCE title
    try state.apply(.{ .switch_screen = .debug }, std.testing.io);
    tui_app.render(&state, &frame);
    try std.testing.expect(frame.get(73, 2).style.reverse); // CPU title
    try std.testing.expect(frameContains(&frame, "^T Step"));
    try state.apply(.next_pane, std.testing.io);
    try std.testing.expectEqual(command.Screen.memory, state.active_screen);
    try state.apply(.previous_pane, std.testing.io);
    try std.testing.expectEqual(command.Screen.debug, state.active_screen);

    const palette_key = command.map(.{ .code = .{ .character = 'p' }, .ctrl = true });
    try std.testing.expect(palette_key == .open_palette);
    try state.apply(palette_key, std.testing.io);
    tui_app.render(&state, &frame);
    try std.testing.expect(frameContains(&frame, "COMMAND PALETTE"));
    try std.testing.expect(frameContains(&frame, "assemble"));
    try state.apply(.cancel, std.testing.io);
    try std.testing.expect(!state.palette.active);
}

test "z80 syntax tokenizer classifies editor language tokens" {
    const tokens = editor_syntax.tokenize("start: ld hl,0xC000 ; text \"ignored\"");
    try std.testing.expect(tokens.len >= 5);
    try std.testing.expectEqual(editor_syntax.TokenKind.label, tokens.items[0].kind);
    try std.testing.expectEqual(editor_syntax.TokenKind.mnemonic, tokens.items[1].kind);
    try std.testing.expectEqual(editor_syntax.TokenKind.register, tokens.items[2].kind);
    try std.testing.expectEqual(editor_syntax.TokenKind.number, tokens.items[3].kind);
    try std.testing.expectEqual(editor_syntax.TokenKind.comment, tokens.items[4].kind);
    const literals = editor_syntax.tokenize("db \"hello\", 'A'");
    try std.testing.expectEqual(editor_syntax.TokenKind.directive, literals.items[0].kind);
    try std.testing.expectEqual(editor_syntax.TokenKind.string, literals.items[1].kind);
    try std.testing.expectEqual(editor_syntax.TokenKind.character, literals.items[2].kind);
}

test "completion uses mnemonic register directive operand and source labels" {
    var completion: editor_syntax.Completion = .{};
    editor_syntax.complete("l", 1, &completion);
    try std.testing.expect(completion.active);
    try std.testing.expect(completionHas(&completion, "ld"));
    try std.testing.expect(completionHas(&completion, "ldi"));
    editor_syntax.complete("or", 2, &completion);
    try std.testing.expect(completionHas(&completion, "org"));
    editor_syntax.complete("start:\n ld h", 12, &completion);
    try std.testing.expect(completionHas(&completion, "hl"));
    editor_syntax.complete("start:\n jp st", 13, &completion);
    try std.testing.expect(completionHas(&completion, "start"));
    editor_syntax.complete("ld (", 4, &completion);
    try std.testing.expect(completionHas(&completion, "ix"));
}

test "source editor auto indents selects indents and supports undo redo" {
    var source = try SourceBuffer.init(std.testing.allocator, "loop:");
    defer source.deinit();
    source.cursor = source.text().len;
    try source.newline();
    try std.testing.expectEqualStrings("loop:\n    ", source.text());
    try source.insert('l');
    try source.insert('d');
    try std.testing.expect(try source.undo());
    try std.testing.expectEqualStrings("loop:\n    l", source.text());
    try std.testing.expect(try source.redo());
    try std.testing.expectEqualStrings("loop:\n    ld", source.text());
    source.move(.home, false);
    source.move(.end, true);
    try std.testing.expect(source.selectionRange() != null);
    try source.indent(false);
    try std.testing.expect(std.mem.indexOf(u8, source.text(), "        ld") != null);
}

test "editor search jump history rename hover and execution overlay are integrated" {
    var state = try AppState.init(std.testing.allocator, null, "start:\n ld hl,0xC000\n jp start\n halt\n");
    defer state.deinit();
    _ = state.source.goToLine(2);
    state.source.moveEnd();
    try state.apply(.jump_definition, std.testing.io);
    try std.testing.expectEqual(@as(usize, 0), state.source.lineAndColumn().line);
    try state.apply(.jump_back, std.testing.io);
    try std.testing.expectEqual(@as(usize, 2), state.source.lineAndColumn().line);

    _ = state.source.goToLine(0);
    try state.apply(.open_palette, std.testing.io);
    state.palette.selected = 2;
    try state.apply(.newline, std.testing.io);
    try std.testing.expectEqual(PromptMode.rename, state.editor_prompt.mode);
    try state.apply(.{ .insert_character = 'm' }, std.testing.io);
    try state.apply(.{ .insert_character = 'a' }, std.testing.io);
    try state.apply(.{ .insert_character = 'i' }, std.testing.io);
    try state.apply(.{ .insert_character = 'n' }, std.testing.io);
    try state.apply(.newline, std.testing.io);
    try std.testing.expect(std.mem.indexOf(u8, state.source.text(), "main:") != null);
    try std.testing.expect(std.mem.indexOf(u8, state.source.text(), "jp main") != null);

    try state.apply(.search, std.testing.io);
    try state.apply(.{ .insert_character = 'h' }, std.testing.io);
    try state.apply(.{ .insert_character = 'a' }, std.testing.io);
    try state.apply(.{ .insert_character = 'l' }, std.testing.io);
    try state.apply(.{ .insert_character = 't' }, std.testing.io);
    try std.testing.expectEqual(@as(usize, 3), state.source.lineAndColumn().line);
    try state.apply(.cancel, std.testing.io);

    state.assemble();
    _ = state.source.goToLine(1);
    state.source.moveHome();
    state.source.moveRight();
    try std.testing.expectEqual(@as(u16, 0), state.inspectionAddress().?);
    state.step();
    try std.testing.expect(state.execution_overlay != null);
    try std.testing.expectEqualStrings("HL ← C000", state.execution_overlay.?.text[0..state.execution_overlay.?.len]);
    try std.testing.expect(state.follow_pc);
}

fn completionHas(completion: *const editor_syntax.Completion, wanted: []const u8) bool {
    for (0..completion.boundedLen()) |index| if (std.mem.eql(u8, completion.item(index), wanted)) return true;
    return false;
}

test "source frame renders completion inline code diagnostics overlay and selection" {
    var completion_state = try AppState.init(std.testing.allocator, null, "");
    defer completion_state.deinit();
    try completion_state.apply(.{ .insert_character = 'l' }, std.testing.io);
    var frame = try Frame.init(std.testing.allocator, 100, 14);
    defer frame.deinit();
    tui_app.renderSource(&completion_state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 14 });
    try std.testing.expect(frameContains(&frame, "COMPLETE"));
    try std.testing.expect(frameContains(&frame, "ldi"));
    var short_frame = try Frame.init(std.testing.allocator, 48, 5);
    defer short_frame.deinit();
    tui_app.renderSource(&completion_state, &short_frame, Rect{ .x = 0, .y = 0, .width = 48, .height = 5 });

    // Rendering must remain bounded even if mutable completion metadata is stale.
    completion_state.completion.active = true;
    completion_state.completion.len = std.math.maxInt(u8);
    completion_state.completion.selected = std.math.maxInt(usize);
    completion_state.completion.lengths[0] = std.math.maxInt(u8);
    tui_app.renderSource(&completion_state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 14 });
    try std.testing.expectEqual(@as(usize, 16), completion_state.completion.boundedLen());

    var state = try AppState.init(std.testing.allocator, null, "ld hl,0xC000\nhalt\n");
    defer state.deinit();
    frame.clear();
    tui_app.renderSource(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 14 });
    try std.testing.expect(frameContains(&frame, "SOURCE"));
    try std.testing.expect(frameContains(&frame, "[21 00 C0 ]"));
    state.source.move(.right, true);
    frame.clear();
    tui_app.renderSource(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 14 });
    try std.testing.expect(!frame.get(38, 2).style.reverse); // selection contrasts with current-line highlight
    try std.testing.expect(frame.get(86, 2).style.reverse); // highlight includes line-end and right margin
    state.source.selection_anchor = null;
    state.unicode_ui = false;
    state.step();
    frame.clear();
    tui_app.renderSource(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 14 });
    try std.testing.expect(frameContains(&frame, "HL <- C000"));

    var broken = try AppState.init(std.testing.allocator, null, "jp missing\n");
    defer broken.deinit();
    frame.clear();
    tui_app.renderSource(&broken, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 14 });
    try std.testing.expect(frameContains(&frame, "! undefined symbol"));
}

test "step follows an offscreen PC without moving the edit cursor" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(std.testing.allocator);
    for (0..30) |_| try source.appendSlice(std.testing.allocator, "nop\n");
    try source.appendSlice(std.testing.allocator, "halt\n");
    var state = try AppState.init(std.testing.allocator, null, source.items);
    defer state.deinit();
    state.unicode_ui = false;
    const edit_cursor = state.source.cursor;
    for (0..20) |_| state.step();
    var frame = try Frame.init(std.testing.allocator, 100, 9);
    defer frame.deinit();
    tui_app.renderSource(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 9 });
    try std.testing.expect(state.source.scroll_y > 0);
    try std.testing.expectEqual(edit_cursor, state.source.cursor);
    try std.testing.expect(frameContains(&frame, ">"));
}

test "display tracks scale status dirty pixels cursor grid and fps" {
    var state = try AppState.init(std.testing.allocator, null, "ld hl,0xC000\nld (hl),1\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.color_ui = false;
    state.unicode_ui = false;
    state.tickUi(100);
    state.step();
    state.step();
    try std.testing.expectEqual(@as(u64, 1), state.display_frame);
    try std.testing.expectEqual(@as(u16, 1), state.display_changed_pixels);
    try std.testing.expect(state.display_dirty[0]);
    try std.testing.expect(state.displayChangeActive());

    state.active_screen = .display;
    state.display_scale = .x2;
    state.display_grid = true;
    state.display_cursor_x = 0;
    state.display_cursor_y = 0;
    var frame = try Frame.init(std.testing.allocator, 90, 24);
    defer frame.deinit();
    tui_app.renderDisplay(&state, &frame, Rect{ .x = 0, .y = 0, .width = 90, .height = 24 });
    try std.testing.expect(frameContains(&frame, "Scale 2x"));
    try std.testing.expect(frameContains(&frame, "Changed 1 px"));
    try std.testing.expect(frameContains(&frame, "VRAM ADDRESS"));
    try std.testing.expect(frameContains(&frame, "C000"));
    try std.testing.expect(frameContains(&frame, "VALUE  1"));
    try std.testing.expect(frameContains(&frame, "DISPLAY *"));
    try std.testing.expect(frameContains(&frame, "+"));

    state.tickUi(1100);
    try std.testing.expectEqual(@as(u16, 1), state.display_fps);
    try std.testing.expect(!state.displayChangeActive());
}

test "display palette and bus filter synchronize selected instruction" {
    var state = try AppState.init(std.testing.allocator, null, "ld hl,0xC000\nld (hl),1\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.runFromReset();
    state.runSlice(10);

    try state.apply(.open_palette, std.testing.io);
    state.palette.selected = 14;
    try state.apply(.newline, std.testing.io);
    try std.testing.expectEqual(command.Screen.display, state.active_screen);
    try std.testing.expectEqual(DisplayScale.x4, state.display_scale);

    try state.apply(.open_palette, std.testing.io);
    state.palette.selected = 17;
    try state.apply(.newline, std.testing.io);
    try std.testing.expectEqual(command.Screen.bus, state.active_screen);
    const selected = state.trace.get(state.selected_trace_event).?;
    try std.testing.expectEqual(trace.BusEventKind.memory_write, selected.kind);
    try std.testing.expectEqual(@as(?u16, selected.pc), state.linked_pc);
    try std.testing.expectEqual(@as(u8, 0), state.display_cursor_x);
    try std.testing.expectEqual(@as(u8, 0), state.display_cursor_y);

    var frame = try Frame.init(std.testing.allocator, 100, 18);
    defer frame.deinit();
    tui_app.renderBus(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 18 });
    try std.testing.expect(frameContains(&frame, "Filter: Memory Write"));
    try std.testing.expect(frameContains(&frame, "WRITE"));

    frame.clear();
    tui_app.renderInstruction(&state, &frame, Rect{ .x = 0, .y = 0, .width = 42, .height = 12 });
    try std.testing.expect(frameContains(&frame, "LD (HL),0x01"));

    state.bus_filter = .{};
    state.selected_trace_event = 0;
    state.trace_follow = false;
    try state.apply(.{ .move_cursor = .right }, std.testing.io);
    frame.clear();
    tui_app.renderCpu(&state, &frame, Rect{ .x = 0, .y = 0, .width = 42, .height = 12 });
    try std.testing.expect(frameContains(&frame, "CPU (Instruction #0)"));
    try std.testing.expect(frameContains(&frame, "HL 0000"));
}

test "logic analyzer renders time transitions zoom pan and cursor" {
    var state = try AppState.init(std.testing.allocator, null, "ld hl,0xC000\nld (hl),1\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.runFromReset();
    state.runSlice(10);

    var frame = try Frame.init(std.testing.allocator, 100, 22);
    defer frame.deinit();
    bus_waveform.renderAnalyzer(&frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 22 }, &state.trace, 1, true, 0x7f, .{ .zoom = 2 });
    try std.testing.expect(frameContains(&frame, "Time"));
    try std.testing.expect(frameContains(&frame, "NOT CYCLE-ACCURATE"));
    try std.testing.expect(frameContains(&frame, "Instruction #0"));
    try std.testing.expect(frameContains(&frame, "/MREQ"));
    try std.testing.expect(frameContains(&frame, "[0000]"));
    try std.testing.expect(frameContains(&frame, "[21]"));
    try std.testing.expect(frameContains(&frame, "Cursor #1"));
    try std.testing.expect(frameContains(&frame, "Operand Read"));
    try std.testing.expectEqual(@as(u21, '│'), frame.get(22, 16).codepoint);
    var found_corner = false;
    var found_cursor = false;
    for (frame.cells) |cell| {
        found_corner = found_corner or cell.codepoint == '┌' or cell.codepoint == '┐' or cell.codepoint == '└' or cell.codepoint == '┘';
        found_cursor = found_cursor or cell.codepoint == '│' and cell.style.fg == .yellow;
    }
    try std.testing.expect(found_corner);
    try std.testing.expect(found_cursor);

    frame.clear();
    bus_waveform.renderAnalyzer(&frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 22 }, &state.trace, 0, false, 0x7f, .{ .zoom = 4 });
    try std.testing.expectEqual(@as(u21, '2'), frame.get(30, 2).codepoint); // 11-cell zoom spacing
    frame.clear();
    bus_waveform.renderAnalyzer(&frame, Rect{ .x = 0, .y = 0, .width = 25, .height = 22 }, &state.trace, 0, false, 0x7f, .{ .zoom = 1, .pan = 1, .follow_cursor = false });
    try std.testing.expectEqual(@as(u21, '1'), frame.get(8, 2).codepoint);
}

test "phase two cards expose bus summary display writer vertical flags and overlay toggle" {
    var state = try AppState.init(std.testing.allocator, null, "ld hl,0xC000\nld (hl),1\nhalt\n");
    defer state.deinit();
    state.attachTrace();
    state.step();
    state.step();

    var frame = try Frame.init(std.testing.allocator, 100, 22);
    defer frame.deinit();
    state.active_screen = .bus;
    tui_app.renderBus(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 22 });
    try std.testing.expect(frameContains(&frame, "OPCODE"));
    try std.testing.expect(frameContains(&frame, "MEMORY 1"));
    try std.testing.expect(frameContains(&frame, "I/O 0"));

    frame.clear();
    state.active_screen = .display;
    tui_app.renderDisplay(&state, &frame, Rect{ .x = 0, .y = 0, .width = 100, .height = 22 });
    try std.testing.expect(frameContains(&frame, "WRITER"));
    try std.testing.expect(frameContains(&frame, "LD (HL),0x01"));

    frame.clear();
    tui_app.renderCpu(&state, &frame, Rect{ .x = 0, .y = 0, .width = 44, .height = 12 });
    try std.testing.expect(frameContains(&frame, "S  0"));
    try std.testing.expect(frameContains(&frame, "PV 0"));

    try state.apply(.open_palette, std.testing.io);
    state.palette.selected = 22;
    try state.apply(.newline, std.testing.io);
    try std.testing.expect(!state.execution_overlay_enabled);
    try std.testing.expect(state.execution_overlay == null);
}
