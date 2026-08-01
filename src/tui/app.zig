const std = @import("std");
const state_mod = @import("state.zig");
const AppState = state_mod.AppState;
const Frame = @import("render/frame.zig").Frame;
const Style = @import("render/style.zig").Style;
const Rect = @import("layout.zig").Rect;
const Layout = @import("layout.zig").Layout;
const flags = @import("../cpu/flags.zig");
const disassembler = @import("../disassembler/disassembler.zig");
const editor_syntax = @import("editor/syntax.zig");
const video = @import("../machine/video.zig");
const trace = @import("../trace/trace.zig");
const bus_waveform = @import("bus_waveform.zig");

const heading = Style{ .fg = .cyan, .bold = true };
const changed = Style{ .fg = .yellow, .bold = true };
const selected = Style{ .reverse = true };

pub fn render(state: *AppState, frame: *Frame) void {
    frame.unicode = state.unicode_ui;
    frame.clear();
    const layout = Layout.calculate(frame.width, frame.height);
    renderHeader(state, frame, layout.header);
    if (layout.compact) {
        if (frame.width < 40 or frame.height < 10) {
            frame.writeText(1, @min(3, frame.height -| 1), "Terminal is too small. Recommended: 80x24", .{ .bold = true });
        } else renderCompact(state, frame, layout.source);
    } else if (state.active_screen == .bus) {
        renderBus(state, frame, .{ .x = 0, .y = layout.source.y, .width = frame.width, .height = layout.status.y - layout.source.y + 1 });
    } else {
        const source_rect = Rect{ .x = layout.source.x, .y = layout.source.y, .width = layout.source.width + 1, .height = layout.source.height + 1 };
        const cpu_rect = Rect{ .x = layout.cpu.x, .y = layout.cpu.y, .width = layout.cpu.width, .height = layout.cpu.height + 1 };
        renderSource(state, frame, source_rect);
        renderCpuAndInstruction(state, frame, cpu_rect);
        renderLower(state, frame, layout.lower);
    }
    renderToast(state, frame, layout.status.y);
    if (state.palette.active) renderPalette(state, frame);
    renderStatus(state, frame, layout.status);
}

fn renderHeader(state: *const AppState, frame: *Frame, rect: Rect) void {
    if (rect.height == 0) return;
    frame.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', .{ .reverse = true });
    frame.print(1, rect.y, .{ .reverse = true, .bold = true }, "Zig_80 IDE - {s}{s}", .{ if (state.source_path) |path| path else "untitled.asm", if (state.source.dirty) " *" else "" });
    if (rect.height > 1) frame.writeText(1, rect.y + 1, contextHelp(state), .{});
}

fn contextHelp(state: *const AppState) []const u8 {
    if (state.palette.active) return "COMMANDS  Up/Down Select | Enter Execute | Esc Close";
    return switch (state.active_screen) {
        .editor => "SOURCE  Ctrl+S Save | Ctrl+F Search | Ctrl+Z/Y Undo/Redo | Ctrl+P Commands | Tab Indent",
        .debug => "CPU  Ctrl+T Step | Ctrl+Space Continue | Esc Pause | Tab Next | Shift+Tab Previous",
        .memory => "MEMORY  g Address | P PC | H HL | Enter Confirm | Esc Cancel | Tab Next",
        .bus => "BUS  [ ] Event | End Latest | Enter Follow Source | Tab Next Pane",
        .display => "VRAM  Ctrl+1..5 View | Tab Next Pane | Shift+Tab Previous",
        .help => "HELP  Ctrl+1..5 View | Ctrl+P Commands | Ctrl+Q Quit",
    };
}

fn renderCompact(state: *AppState, frame: *Frame, rect: Rect) void {
    switch (state.active_screen) {
        .editor => renderSource(state, frame, rect),
        .debug => renderCpuAndInstruction(state, frame, rect),
        .memory => renderMemory(state, frame, rect),
        .bus => renderBus(state, frame, rect),
        .display => renderDisplay(state, frame, rect),
        .help => renderHelp(state, frame, rect),
    }
}

fn paneBox(state: *const AppState, frame: *Frame, rect: Rect, title: []const u8, focused: bool) void {
    frame.box(rect.x, rect.y, rect.width, rect.height, title, heading);
    frame.writeText(rect.x + 2, rect.y, title, if (focused) .{ .reverse = true, .bold = true } else heading);
    _ = state;
}

pub fn renderSource(state: *AppState, frame: *Frame, rect: Rect) void {
    var title_buffer: [64]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " SOURCE ({s}) ", .{if (state.source.dirty) "Dirty" else if (state.assembly != null) "Assembled" else "Edit"}) catch " SOURCE ";
    paneBox(state, frame, rect, title, state.active_screen == .editor);
    if (rect.width < 18 or rect.height < 3) return;
    const show_code = rect.width >= 52;
    const source_x = rect.x + if (show_code) @as(usize, 31) else 16;
    const rows = rect.height - 3;
    const cursor_line = state.source.lineAndColumn().line;
    const pc_line = state.sourceLineForPC(state.machine.cpu.registers.pc);
    if (state.follow_pc and pc_line != null) {
        const wanted = pc_line.? - 1;
        if (wanted < state.source.scroll_y) state.source.scroll_y = wanted;
        if (rows > 0 and wanted >= state.source.scroll_y + rows) state.source.scroll_y = wanted - rows + 1;
    } else state.source.ensureVisible(rect.width -| (source_x - rect.x + 1), rows);
    const previous_line = if (state.debug_session.previous) |snapshot| state.sourceLineForPC(snapshot.registers.pc) else null;
    frame.writeText(rect.x + 1, rect.y + 1, "BP PC ! ▲ ┃ LINE ADDR BYTES     SOURCE", .{ .bold = true });
    for (0..rows) |row| {
        const line_index = state.source.scroll_y + row;
        const text = state.source.lineSlice(line_index) orelse break;
        const y = rect.y + 2 + row;
        const cursor = line_index == cursor_line;
        const execution = pc_line != null and pc_line.? == line_index + 1;
        const prior = previous_line != null and previous_line.? == line_index + 1 and !execution;
        const error_line = diagnosticOnLine(state, line_index + 1);
        const line_info = lineInfo(state, line_index + 1);
        const breakpoint = if (line_info) |info| state.debug_session.breakpoints.contains(info.address) else false;
        const base = Style{ .bold = execution };

        if (breakpoint) frame.set(rect.x + 1, y, if (state.unicode_ui) '●' else '*', withFg(base, .red));
        if (execution) frame.set(rect.x + 3, y, if (state.unicode_ui) '▶' else '>', withFg(base, .green));
        if (error_line) {
            frame.set(rect.x + 5, y, '!', withFg(base, .red));
        }
        if (prior) frame.set(rect.x + 7, y, if (state.unicode_ui) '▲' else '^', withFg(base, .yellow));
        if (cursor) frame.set(rect.x + 9, y, if (state.unicode_ui) '┃' else '|', base);
        frame.print(rect.x + 11, y, base, "{d: >4}", .{line_index + 1});

        if (show_code) {
            if (line_info) |info| {
                frame.print(rect.x + 16, y, base, "{X:0>4}", .{info.address});
                const decoded = disassembler.decode(&state.machine.bus.memory, info.address);
                for (0..@min(@as(usize, decoded.size), 3)) |index| frame.print(rect.x + 21 + index * 3, y, base, "{X:0>2}", .{decoded.bytes[index]});
            } else {
                frame.writeText(rect.x + 16, y, "----", base);
            }
        }
        const visible = if (state.source.scroll_x < text.len) text[state.source.scroll_x..] else "";
        const tokens = state.syntax_cache.tokens(line_index, text);
        writeHighlighted(frame, source_x, y, text, state.source.scroll_x, tokens, base);
        renderSelection(state, frame, source_x, y, line_index, text);

        const suffix_x = source_x + codepointCount(visible) + 2;
        var drew_overlay = false;
        if (state.execution_overlay) |overlay| {
            if (overlay.source_line == line_index + 1) {
                frame.writeText(suffix_x, y, overlay.text[0..overlay.len], .{ .fg = .yellow, .bold = true });
                drew_overlay = true;
            }
        }
        if (!drew_overlay) if (line_info) |info| {
            const decoded = disassembler.decode(&state.machine.bus.memory, info.address);
            if (suffix_x + decoded.size * 3 < rect.x + rect.width - 1) {
                frame.writeText(suffix_x, y, "[", .{ .fg = .blue });
                for (0..@min(@as(usize, decoded.size), 3)) |index| frame.print(suffix_x + 1 + index * 3, y, .{ .fg = .blue }, "{X:0>2}", .{decoded.bytes[index]});
                frame.writeText(suffix_x + 1 + decoded.size * 3, y, "]", .{ .fg = .blue });
            }
        };
        renderInlineDiagnostic(state, frame, source_x, y, line_index, text);
    }
    renderCompletion(state, frame, rect, source_x);
    renderEditorPrompt(state, frame, rect);
}

fn lineInfo(state: *const AppState, source_line: usize) ?@import("../assembler/assembler.zig").LineInfo {
    const assembly = if (state.assembly) |*value| value else return null;
    for (assembly.lines.items) |line| if (line.line == source_line) return line;
    return null;
}

fn diagnosticOnLine(state: *const AppState, source_line: usize) bool {
    for (state.diagnostics_list.items) |owned| if (owned.value.line != null and owned.value.line.? == source_line) return true;
    return false;
}

fn writeHighlighted(frame: *Frame, start_x: usize, y: usize, text: []const u8, scroll: usize, tokens: *const editor_syntax.TokenList, base: Style) void {
    const visible = if (scroll < text.len) text[scroll..] else "";
    frame.writeText(start_x, y, visible, base);
    for (tokens.items[0..tokens.len]) |token| {
        if (token.end <= scroll) continue;
        const visible_start = @max(token.start, scroll);
        const token_text = text[visible_start..token.end];
        const color: @import("render/style.zig").Color = switch (token.kind) {
            .label => .magenta,
            .mnemonic => .cyan,
            .register => .yellow,
            .number => .green,
            .directive => .blue,
            .comment => .green,
            .string => .magenta,
            .character => .magenta,
            .plain => .default,
        };
        frame.writeText(start_x + visible_start - scroll, y, token_text, mergeStyle(base, .{ .fg = color, .bold = token.kind == .label or token.kind == .mnemonic or token.kind == .directive }));
    }
}

fn renderSelection(state: *const AppState, frame: *Frame, source_x: usize, y: usize, line_index: usize, text: []const u8) void {
    const range = state.source.selectionRange() orelse return;
    const line_start = state.source.absoluteLineStart(line_index) orelse return;
    const start = @max(range.start, line_start);
    const end = @min(range.end, line_start + text.len);
    if (start >= end) return;
    const local_start = start - line_start;
    const local_end = end - line_start;
    for (local_start..local_end) |column| {
        if (column < state.source.scroll_x) continue;
        const x = source_x + column - state.source.scroll_x;
        const cell = frame.get(x, y);
        var style = cell.style;
        style.reverse = !style.reverse;
        frame.set(x, y, cell.codepoint, style);
    }
}

fn renderInlineDiagnostic(state: *const AppState, frame: *Frame, source_x: usize, y: usize, line_index: usize, text: []const u8) void {
    for (state.diagnostics_list.items) |owned| {
        const diagnostic = owned.value;
        if (diagnostic.line == null or diagnostic.line.? != line_index + 1) continue;
        if (diagnostic.column) |column_one| {
            const first = column_one -| 1;
            const last = @min(diagnostic.end_column orelse column_one, text.len);
            for (first..last) |column| {
                if (column < state.source.scroll_x) continue;
                const x = source_x + column - state.source.scroll_x;
                const cell = frame.get(x, y);
                frame.set(x, y, cell.codepoint, withFg(cell.style, .red));
            }
        }
        const message_x = source_x + codepointCount(text) + 2;
        frame.print(message_x, y, .{ .fg = .red, .bold = true }, "! {s}", .{diagnostic.message});
        return;
    }
}

fn renderCompletion(state: *const AppState, frame: *Frame, rect: Rect, source_x: usize) void {
    if (!state.completion.active or state.editor_prompt.mode != .none) return;
    const position = state.source.lineAndColumn();
    if (position.line < state.source.scroll_y) return;
    const row = position.line - state.source.scroll_y;
    if (row >= rect.height - 3) return;
    const x = source_x + position.column -| state.source.scroll_x;
    const count = @min(state.completion.len, @as(usize, 6));
    const width: usize = 18;
    const y = rect.y + 3 + row;
    if (y + count + 2 >= rect.y + rect.height or x + width >= rect.x + rect.width) return;
    frame.fillRect(x, y, width, count + 2, ' ', .{});
    frame.box(x, y, width, count + 2, " COMPLETE ", .{ .fg = .cyan });
    for (0..count) |index| frame.print(x + 2, y + 1 + index, if (index == state.completion.selected) selected else .{}, "{s}", .{state.completion.item(index)});
}

fn renderEditorPrompt(state: *const AppState, frame: *Frame, rect: Rect) void {
    if (state.editor_prompt.mode == .none or rect.height < 4) return;
    const label = switch (state.editor_prompt.mode) {
        .search => "Search",
        .go_line => "Go line",
        .go_label => "Go label",
        .rename => "Rename to",
        .none => "",
    };
    const y = rect.y + rect.height - 2;
    frame.fillRect(rect.x + 1, y, rect.width - 2, 1, ' ', .{ .reverse = true });
    frame.print(rect.x + 2, y, .{ .reverse = true, .bold = true }, "{s}: {s}_", .{ label, state.editor_prompt.text() });
}

fn codepointCount(text: []const u8) usize {
    return std.unicode.utf8CountCodepoints(text) catch text.len;
}

fn mergeStyle(base: Style, overlay: Style) Style {
    return .{ .fg = overlay.fg, .bg = base.bg, .bold = base.bold or overlay.bold, .reverse = base.reverse or overlay.reverse };
}

fn withFg(base: Style, color: @import("render/style.zig").Color) Style {
    var result = base;
    result.fg = color;
    result.bold = true;
    return result;
}

fn renderCpuAndInstruction(state: *AppState, frame: *Frame, rect: Rect) void {
    if (rect.height < 10) {
        renderCpu(state, frame, rect);
        return;
    }
    const cpu_height = @min(@as(usize, 8), rect.height - 4);
    renderCpu(state, frame, .{ .x = rect.x, .y = rect.y, .width = rect.width, .height = cpu_height });
    renderInstruction(state, frame, .{ .x = rect.x, .y = rect.y + cpu_height - 1, .width = rect.width, .height = rect.height - cpu_height + 1 });
}

pub fn renderCpu(state: *const AppState, frame: *Frame, rect: Rect) void {
    var title_buffer: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " CPU ({s}) ", .{titleState(state.execution_state)}) catch " CPU ";
    paneBox(state, frame, rect, title, state.active_screen == .debug);
    if (rect.width < 14 or rect.height < 3) return;
    const r = state.machine.cpu.registers;
    const x = rect.x + 2;
    var y = rect.y + 1;
    renderPair(state, frame, x, y, "AF", r.af(), pairChanged(state, "a", "f"));
    y += 1;
    if (y < rect.y + rect.height - 1) renderPair(state, frame, x, y, "BC", r.bc(), pairChanged(state, "b", "c"));
    y += 1;
    if (y < rect.y + rect.height - 1) renderPair(state, frame, x, y, "DE", r.de(), pairChanged(state, "d", "e"));
    y += 1;
    if (y < rect.y + rect.height - 1) renderPair(state, frame, x, y, "HL", r.hl(), pairChanged(state, "h", "l"));
    y += 1;
    if (y < rect.y + rect.height - 1) renderPair(state, frame, x, y, "SP", r.sp, state.debug_session.previous != null and state.debug_session.previous.?.registers.sp != r.sp);
    y += 1;
    if (y < rect.y + rect.height - 1) renderPair(state, frame, x, y, "PC", r.pc, state.debug_session.previous != null and state.debug_session.previous.?.registers.pc != r.pc);
}

fn renderPair(state: *const AppState, frame: *Frame, x: usize, y: usize, name: []const u8, value: u16, did_change: bool) void {
    const active_change = did_change and state.registerHighlightActive();
    frame.print(x, y, if (active_change) changed else .{}, "{s} {X:0>4}{s}", .{ name, value, if (active_change) " *" else "" });
}

fn pairChanged(state: *const AppState, comptime high: []const u8, comptime low: []const u8) bool {
    return state.debug_session.changedRegister(high) or state.debug_session.changedRegister(low);
}

pub fn renderInstruction(state: *AppState, frame: *Frame, rect: Rect) void {
    const pc = state.inspectionAddress() orelse state.machine.cpu.registers.pc;
    var title_buffer: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " INSTRUCTION ({X:0>4}) ", .{pc}) catch " INSTRUCTION ";
    paneBox(state, frame, rect, title, false);
    if (rect.width < 18 or rect.height < 3) return;
    const decoded = disassembler.decode(&state.machine.bus.memory, pc);
    var y = rect.y + 1;
    frame.print(rect.x + 2, y, .{}, "Address      {X:0>4}", .{pc});
    y += 1;
    if (y < rect.y + rect.height - 1) {
        frame.writeText(rect.x + 2, y, "Opcode       ", .{});
        for (0..@min(@as(usize, decoded.size), 3)) |index| frame.print(rect.x + 15 + index * 3, y, .{}, "{X:0>2}", .{decoded.bytes[index]});
    }
    y += 1;
    if (y < rect.y + rect.height - 1) frame.print(rect.x + 2, y, heading, "Mnemonic     {s}", .{disassembler.text(&decoded)});
    y += 1;
    if (y < rect.y + rect.height - 1) frame.print(rect.x + 2, y, .{}, "Length       {d} byte{s}", .{ decoded.size, if (decoded.size == 1) "" else "s" });
    y += 1;
    if (y < rect.y + rect.height - 1) frame.print(rect.x + 2, y, .{}, "Timing       {d} T (emulated)", .{instructionTiming(state, decoded.bytes[0])});
    y += 1;
    if (y < rect.y + rect.height - 1) frame.print(rect.x + 2, y, .{}, "Description  {s}", .{instructionDescription(decoded.bytes[0])});
    y += 1;
    if (y < rect.y + rect.height - 1) frame.print(rect.x + 2, y, .{}, "Flags        {s}", .{flagsAffected(decoded.bytes[0])});
}

fn flagsAffected(opcode: u8) []const u8 {
    return switch (opcode) {
        0xc6, 0x80...0x85, 0x87, 0xd6, 0x90...0x95, 0x97, 0xfe, 0xb8...0xbd, 0xbf => "S Z H PV N C",
        0x3c, 0x04, 0x0c, 0x14, 0x1c, 0x24, 0x2c, 0x3d, 0x05, 0x0d, 0x15, 0x1d, 0x25, 0x2d => "S Z H PV N",
        else => "None",
    };
}

fn instructionTiming(state: *const AppState, opcode: u8) u16 {
    return switch (opcode) {
        0x00, 0x76 => 4,
        0x01, 0x11, 0x21, 0x31 => 10,
        0x3e, 0x06, 0x0e, 0x16, 0x1e, 0x26, 0x2e => 7,
        0x7e, 0x77 => 7,
        0x36 => 10,
        0x3a, 0x32 => 13,
        0x2a, 0x22 => 16,
        0x3c, 0x04, 0x0c, 0x14, 0x1c, 0x24, 0x2c, 0x80...0x85, 0x87, 0x90...0x95, 0x97, 0xb8...0xbd, 0xbf => 4,
        0x23, 0x2b => 6,
        0xc6, 0xd6, 0xfe => 7,
        0xc3, 0xc2, 0xca => 10,
        0x18 => 12,
        0x20 => if (state.machine.cpu.registers.f & flags.Z == 0) 12 else 7,
        0x28 => if (state.machine.cpu.registers.f & flags.Z != 0) 12 else 7,
        0xcd => 17,
        0xc9 => 10,
        0xf5, 0xc5, 0xd5, 0xe5 => 11,
        0xf1, 0xc1, 0xd1, 0xe1 => 10,
        else => 4,
    };
}

fn instructionDescription(opcode: u8) []const u8 {
    return switch (opcode) {
        0x00 => "No operation.",
        0x76 => "Enter the halted state in the current emulator.",
        0x01, 0x11, 0x21, 0x31 => "Load an immediate 16-bit value into a register pair.",
        0x3e, 0x06, 0x0e, 0x16, 0x1e, 0x26, 0x2e => "Load an immediate 8-bit value into a register.",
        0x36 => "Write an immediate byte to the address in HL.",
        0xc3, 0xc2, 0xca => "Jump to an absolute address.",
        0x18, 0x20, 0x28 => "Jump using a signed relative offset.",
        0xcd => "Call a subroutine and save the return address.",
        0xc9 => "Return from a subroutine.",
        else => "Execute the decoded Z80 operation.",
    };
}

fn renderLower(state: *AppState, frame: *Frame, rect: Rect) void {
    if (state.diagnostics_list.items.len > 0) {
        renderDiagnostics(state, frame, rect);
        return;
    }
    switch (state.active_screen) {
        .memory => renderMemory(state, frame, rect),
        .display => renderDisplay(state, frame, rect),
        .help => renderHelp(state, frame, rect),
        else => if (state.trace.len == 0) renderGettingStarted(state, frame, rect) else renderBus(state, frame, rect),
    }
}

fn renderDiagnostics(state: *const AppState, frame: *Frame, rect: Rect) void {
    const diagnostic = state.diagnostics_list.items[0].value;
    paneBox(state, frame, rect, " DIAGNOSTICS ", false);
    frame.print(rect.x + 2, rect.y + 1, .{ .fg = .red, .bold = true }, "{s}:{d}:{d}: error: {s}", .{ diagnostic.file_path orelse "<source>", diagnostic.line orelse 0, diagnostic.column orelse 0, diagnostic.message });
    if (rect.height > 3) if (diagnostic.source_line) |line| frame.print(rect.x + 2, rect.y + 2, .{}, "! {s}", .{line});
    if (rect.height > 4) if (diagnostic.hint) |hint| frame.print(rect.x + 2, rect.y + 3, .{}, "hint: {s} | Enter: source", .{hint});
}

pub fn renderGettingStarted(state: *const AppState, frame: *Frame, rect: Rect) void {
    const split = rect.x + rect.width * 2 / 3;
    const left = Rect{ .x = rect.x, .y = rect.y, .width = split - rect.x + 1, .height = rect.height };
    const right = Rect{ .x = split, .y = rect.y, .width = rect.x + rect.width - split, .height = rect.height };
    paneBox(state, frame, left, " GETTING STARTED ", false);
    frame.writeText(left.x + 2, left.y + 1, "QUICK ACTIONS", .{ .bold = true });
    if (left.height > 3) frame.writeText(left.x + 2, left.y + 2, "Ctrl+R Assemble   Ctrl+E Run   Ctrl+T Step", .{});
    if (left.height > 4) frame.writeText(left.x + 2, left.y + 3, "Ctrl+Space Continue   Ctrl+P Command Palette", .{});
    paneBox(state, frame, right, " BUS ", state.active_screen == .bus);
    frame.writeText(right.x + 2, right.y + 1, "Waiting for events", .{});
}

fn renderMemory(state: *const AppState, frame: *Frame, rect: Rect) void {
    var title_buffer: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " MEMORY ({X:0>4}) ", .{state.memory_address}) catch " MEMORY ";
    paneBox(state, frame, rect, title, state.active_screen == .memory);
    if (rect.width < 30 or rect.height < 3) return;
    var first_row = rect.y + 1;
    if (state.memory_input.active) {
        var input_buffer: [4]u8 = undefined;
        frame.print(rect.x + 2, first_row, .{ .reverse = true, .bold = true }, "Go to address: 0x{s}  Enter: confirm  Esc: cancel", .{state.memoryInputText(&input_buffer)});
        first_row += 1;
    } else frame.writeText(rect.x + 2, first_row, "G Address | P PC | H HL", .{});
    const rows = rect.height -| (first_row - rect.y + 1);
    const columns = @min(@as(usize, 16), (rect.width -| 8) / 3);
    for (0..rows) |row| {
        const address = state.memory_address +% @as(u16, @intCast(row * 16));
        frame.print(rect.x + 2, first_row + row, .{}, "{X:0>4} ", .{address});
        for (0..columns) |column| {
            const cell_address = address +% @as(u16, @intCast(column));
            const style: Style = if (state.last_memory_write != null and state.last_memory_write.? == cell_address) changed else .{};
            frame.print(rect.x + 7 + column * 3, first_row + row, style, "{X:0>2}", .{state.machine.bus.read8(cell_address)});
        }
    }
}

pub fn renderBus(state: *const AppState, frame: *Frame, rect: Rect) void {
    var title_buffer: [80]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " BUS ({d} events) - LOGICAL ONLY / NOT CYCLE ACCURATE ", .{state.trace.len}) catch " BUS - LOGICAL ONLY / NOT CYCLE ACCURATE ";
    paneBox(state, frame, rect, title, state.active_screen == .bus);
    if (rect.height < 4) return;
    if (state.trace.len == 0) {
        renderGettingStarted(state, frame, rect);
        return;
    }
    frame.writeText(rect.x + 2, rect.y + 1, "Equal-width logical access slots; no electrical or T-state duration is inferred.", .{ .bold = true });
    const selected_index = if (state.trace_follow) state.trace.len -| 1 else @min(state.selected_trace_event, state.trace.len -| 1);
    if (rect.width >= 70 and rect.height >= 6) {
        const split = rect.x + rect.width * 43 / 100;
        const list_rect = Rect{ .x = rect.x, .y = rect.y + 2, .width = split - rect.x + 1, .height = rect.height - 2 };
        const wave_rect = Rect{ .x = split, .y = rect.y + 2, .width = rect.x + rect.width - split, .height = rect.height - 2 };
        renderGroupedEvents(state, frame, list_rect, selected_index);
        paneBox(state, frame, wave_rect, " LOGICAL WAVEFORM ", state.active_screen == .bus and state.bus_view == .waveform);
        bus_waveform.render(frame, wave_rect, &state.trace, selected_index, state.unicode_ui);
    } else if (state.bus_view == .waveform) {
        bus_waveform.render(frame, rect, &state.trace, selected_index, state.unicode_ui);
    } else renderGroupedEvents(state, frame, rect, selected_index);
}

fn renderGroupedEvents(state: *const AppState, frame: *Frame, rect: Rect, selected_index: usize) void {
    const selected_event = state.trace.getPtr(selected_index) orelse return;
    var title_buffer: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " INSTRUCTION #{d} ", .{selected_event.instruction_index}) catch " INSTRUCTION EVENTS ";
    paneBox(state, frame, rect, title, state.active_screen == .bus and state.bus_view == .events);
    frame.print(rect.x + 2, rect.y + 1, .{ .bold = true }, "Instruction #{d}  PC={X:0>4}", .{ selected_event.instruction_index, selected_event.pc });
    var first = selected_index;
    while (first > 0) {
        const previous = state.trace.getPtr(first - 1) orelse break;
        if (previous.instruction_index != selected_event.instruction_index) break;
        first -= 1;
    }
    var row: usize = 0;
    var index = first;
    while (index < state.trace.len and row < rect.height -| 3) : (index += 1) {
        const event = state.trace.getPtr(index) orelse break;
        if (event.instruction_index != selected_event.instruction_index) break;
        const marker: u8 = if (index == selected_index) '>' else ' ';
        frame.print(rect.x + 2, rect.y + 2 + row, if (index == selected_index) selected else .{}, "{c} {d}: {s:<12} {X:0>4} {X:0>2}", .{ marker, event.event_index_in_instruction, shortKind(event.kind), event.address, event.data });
        row += 1;
    }
    if (rect.height > 3) frame.print(rect.x + 2, rect.y + rect.height - 2, .{}, "seq={d} | Enter: source", .{selected_event.sequence});
}

fn shortKind(kind: trace.BusEventKind) []const u8 {
    return switch (kind) {
        .opcode_fetch => "Opcode Fetch",
        .operand_read => "Operand Read",
        .memory_read => "Memory Read",
        .memory_write => "Memory Write",
        .io_read => "I/O Read",
        .io_write => "I/O Write",
        .refresh => "Refresh",
        .interrupt_ack => "Interrupt",
    };
}

fn renderDisplay(state: *const AppState, frame: *Frame, rect: Rect) void {
    paneBox(state, frame, rect, " VRAM (128x64, 1bpp) ", state.active_screen == .display);
    const columns = @min(@as(usize, 64), rect.width -| 2);
    const rows = @min(@as(usize, 16), rect.height -| 2);
    for (0..rows) |row| for (0..columns) |column| {
        var on = false;
        for (0..4) |dy| for (0..2) |dx| if (video.pixel(&state.machine.bus, @intCast(column * 2 + dx), @intCast(row * 4 + dy))) {
            on = true;
        };
        frame.set(rect.x + 1 + column, rect.y + 1 + row, if (on) '#' else '.', if (on) .{ .fg = .green, .bold = true } else .{});
    };
}

fn renderHelp(state: *const AppState, frame: *Frame, rect: Rect) void {
    paneBox(state, frame, rect, " HELP ", state.active_screen == .help);
    const lines = [_][]const u8{
        "Ctrl+S Save | Ctrl+Q Quit | Ctrl+P Command Palette",
        "Ctrl+R Assemble | Ctrl+E Run | Ctrl+T Step | Ctrl+Space Continue | Esc Pause",
        "Tab Next Pane | Shift+Tab Previous | Ctrl+1..5 View",
        "Source: Tab Indent | Shift+Arrow Select | Ctrl+F Search | Ctrl+] Definition",
        "Markers: > current PC | * breakpoint | ! diagnostic | ^ previous | | edit cursor",
    };
    for (lines, 0..) |line, index| if (index + 1 < rect.height) frame.writeText(rect.x + 2, rect.y + 1 + index, line, .{});
}

pub fn renderStatus(state: *const AppState, frame: *Frame, rect: Rect) void {
    if (rect.height == 0) return;
    frame.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', .{ .reverse = true });
    frame.print(rect.x + 1, rect.y, .{ .reverse = true, .bold = true }, "[{s}] [{s}]  PC {X:0>4}  I {d}  T {d}  TRACE {d}/4096 {d}%", .{ statusName(state.execution_state), if (state.source.dirty) "DIRTY" else "CLEAN", state.machine.cpu.registers.pc, state.executed_instructions, state.machine.cpu.total_t_states, state.trace.len, state.trace.len * 100 / 4096 });
}

fn statusName(value: state_mod.ExecutionState) []const u8 {
    return switch (value) {
        .empty => "READY",
        .assembled => "ASSEMBLED",
        .running => "RUNNING",
        .paused => "PAUSED",
        .halted => "HALTED",
        .breakpoint => "BREAKPOINT",
        .faulted => "FAULT",
        .limit_reached => "LIMIT",
    };
}

fn titleState(value: state_mod.ExecutionState) []const u8 {
    return switch (value) {
        .empty => "Ready",
        .assembled => "Assembled",
        .running => "Running",
        .paused => "Paused",
        .halted => "Halted",
        .breakpoint => "Breakpoint",
        .faulted => "Fault",
        .limit_reached => "Limit",
    };
}

pub fn renderToast(state: *const AppState, frame: *Frame, status_y: usize) void {
    const toast = state.toast orelse return;
    if (state.ui_now_ms >= toast.expires_at_ms or status_y < 3) return;
    const width = @min(@as(usize, 34), frame.width -| 2);
    if (width < 12) return;
    const rect = Rect{ .x = frame.width - width - 1, .y = status_y - 3, .width = width, .height = 3 };
    frame.box(rect.x, rect.y, rect.width, rect.height, "", toastStyle(toast.kind));
    frame.set(rect.x + 2, rect.y + 1, toastIcon(state, toast.kind), toastStyle(toast.kind));
    frame.writeText(rect.x + 4, rect.y + 1, toast.text[0..toast.len], toastStyle(toast.kind));
}

fn toastStyle(kind: state_mod.ToastKind) Style {
    return switch (kind) {
        .success => .{ .fg = .green, .bold = true },
        .breakpoint => .{ .fg = .red, .bold = true },
        .halted => .{ .fg = .cyan, .bold = true },
        .@"error" => .{ .fg = .red, .bold = true },
        .info => .{ .fg = .yellow, .bold = true },
    };
}

fn toastIcon(state: *const AppState, kind: state_mod.ToastKind) u21 {
    if (!state.unicode_ui) return switch (kind) {
        .success => '+',
        .@"error" => '!',
        .breakpoint => '*',
        .halted => '#',
        .info => 'i',
    };
    return switch (kind) {
        .success => '✓',
        .@"error" => '!',
        .breakpoint => '●',
        .halted => '■',
        .info => '•',
    };
}

fn renderPalette(state: *const AppState, frame: *Frame) void {
    const width = @min(@as(usize, 44), frame.width -| 4);
    const height = state_mod.AppState.palette_commands.len + 3;
    if (width < 20 or frame.height < height + 2) return;
    const rect = Rect{ .x = (frame.width - width) / 2, .y = (frame.height - height) / 2, .width = width, .height = height };
    frame.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', .{});
    frame.box(rect.x, rect.y, rect.width, rect.height, " COMMAND PALETTE ", .{ .fg = .cyan, .bold = true });
    for (state_mod.AppState.palette_commands, 0..) |command, index| {
        const marker: u8 = if (index == state.palette.selected) '>' else ' ';
        frame.print(rect.x + 2, rect.y + 1 + index, if (index == state.palette.selected) selected else .{}, "{c} {s}", .{ marker, command });
    }
    frame.writeText(rect.x + 2, rect.y + height - 2, "Enter Execute | Esc Close", .{});
}
