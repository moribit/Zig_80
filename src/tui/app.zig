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
const trace = @import("../trace/trace.zig");
const bus_waveform = @import("bus_waveform.zig");

const heading = Style{ .fg = .cyan, .bold = true };
const section_label = Style{ .fg = .blue };
const auxiliary = Style{ .fg = .blue };
const structural = Style{ .fg = .magenta, .bold = true };
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
    } else if (state.active_screen == .bus and frame.height < 32) {
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
    frame.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', .{});
    frame.writeText(rect.x + 1, rect.y, "Zig_80 IDE", heading);
    if (rect.height > 1) {
        const path_limit = if (state.source.dirty) rect.x + rect.width -| 14 else rect.x + rect.width -| 1;
        writeTextClipped(frame, rect.x + 3, path_limit, rect.y + 1, if (state.source_path) |path| path else "untitled.asm", .{});
        if (state.source.dirty) frame.writeText(rect.x + rect.width -| 13, rect.y + 1, if (state.unicode_ui) "● Modified" else "* Modified", .{ .fg = .yellow, .bold = true });
    }
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
    const show_code = rect.width >= 64;
    const source_x = rect.x + if (show_code) @as(usize, 38) else 20;
    const right_margin: usize = if (rect.width >= 90) 18 else if (rect.width >= 64) 12 else 2;
    const source_limit = rect.x + rect.width -| (right_margin + 1);
    const rows = rect.height - 3;
    const cursor_line = state.source.lineAndColumn().line;
    const pc_line = state.sourceLineForPC(state.machine.cpu.registers.pc);
    if (state.follow_pc and pc_line != null) {
        const wanted = pc_line.? - 1;
        if (wanted < state.source.scroll_y) state.source.scroll_y = wanted;
        if (rows > 0 and wanted >= state.source.scroll_y + rows) state.source.scroll_y = wanted - rows + 1;
    } else state.source.ensureVisible(source_limit -| source_x, rows);
    const previous_line = if (state.linked_pc) |pc| state.sourceLineForPC(pc) else if (state.debug_session.previous) |snapshot| state.sourceLineForPC(snapshot.registers.pc) else null;
    renderGutterHeader(state, frame, rect, show_code, source_x);
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
        const base = Style{ .bold = execution, .reverse = cursor };
        if (cursor) frame.fillRect(rect.x + 1, y, rect.width - 2, 1, ' ', base);
        renderGutterSeparators(state, frame, rect, y, show_code, base);

        if (breakpoint) frame.set(rect.x + 1, y, if (state.unicode_ui) '●' else '*', withFg(base, .red));
        if (execution) frame.set(rect.x + 3, y, if (state.unicode_ui) '▶' else '>', withFg(base, .green));
        if (error_line) {
            frame.set(rect.x + 5, y, '!', withFg(base, .red));
        }
        if (prior) frame.set(rect.x + 7, y, if (state.unicode_ui) '▲' else '^', withFg(base, .yellow));
        if (cursor) frame.set(rect.x + 9, y, if (state.unicode_ui) '┃' else '|', base);
        frame.print(rect.x + 13, y, mergeStyle(base, auxiliary), "{d: >4}", .{line_index + 1});

        if (show_code) {
            if (line_info) |info| {
                frame.print(rect.x + 20, y, mergeStyle(base, auxiliary), "{X:0>4}", .{info.address});
                const decoded = disassembler.decodeBus(&state.machine.bus, info.address);
                for (0..@min(@as(usize, decoded.size), 4)) |index| frame.print(rect.x + 27 + index * 3, y, mergeStyle(base, auxiliary), "{X:0>2}", .{decoded.bytes[index]});
            } else {
                frame.writeText(rect.x + 20, y, "----", mergeStyle(base, auxiliary));
            }
        }
        const tokens = state.syntax_cache.tokens(line_index, text);
        writeHighlighted(frame, source_x, source_limit, y, text, state.source.scroll_x, tokens, base);
        renderSelection(state, frame, source_x, source_limit, y, line_index, text);

        const suffix_x = source_limit;
        var drew_overlay = false;
        if (state.execution_overlay) |overlay| {
            if (overlay.source_line == line_index + 1) {
                writeTextClipped(frame, suffix_x, rect.x + rect.width - 1, y, overlay.text[0..overlay.len], mergeStyle(base, .{ .fg = .yellow, .bold = true }));
                drew_overlay = true;
            }
        }
        if (!drew_overlay) if (line_info) |info| {
            const decoded = disassembler.decodeBus(&state.machine.bus, info.address);
            if (suffix_x + decoded.size * 3 < rect.x + rect.width - 1) {
                frame.writeText(suffix_x, y, "[", mergeStyle(base, auxiliary));
                for (0..@min(@as(usize, decoded.size), 4)) |index| frame.print(suffix_x + 1 + index * 3, y, mergeStyle(base, auxiliary), "{X:0>2}", .{decoded.bytes[index]});
                frame.writeText(suffix_x + 1 + decoded.size * 3, y, "]", mergeStyle(base, auxiliary));
            }
        };
        renderInlineDiagnostic(state, frame, source_x, source_limit, rect.x + rect.width - 1, y, line_index, text);
    }
    renderCompletion(state, frame, rect, source_x);
    renderEditorPrompt(state, frame, rect);
}

fn renderGutterHeader(state: *const AppState, frame: *Frame, rect: Rect, show_code: bool, source_x: usize) void {
    const y = rect.y + 1;
    frame.writeText(rect.x + 1, y, "B", section_label);
    frame.writeText(rect.x + 3, y, "P", section_label);
    frame.writeText(rect.x + 5, y, "!", section_label);
    frame.writeText(rect.x + 7, y, "L", section_label);
    frame.writeText(rect.x + 9, y, "E", section_label);
    renderGutterSeparators(state, frame, rect, y, show_code, .{});
    frame.writeText(rect.x + 13, y, "LINE", section_label);
    if (show_code) {
        frame.writeText(rect.x + 20, y, "ADDR", section_label);
        frame.writeText(rect.x + 27, y, "BYTES", section_label);
    }
    frame.writeText(source_x, y, "SOURCE", heading);
}

fn renderGutterSeparators(state: *const AppState, frame: *Frame, rect: Rect, y: usize, show_code: bool, base: Style) void {
    const separator: u21 = if (state.unicode_ui) '│' else '|';
    const style = mergeStyle(base, auxiliary);
    frame.set(rect.x + 11, y, separator, style);
    frame.set(rect.x + 18, y, separator, style);
    if (show_code) {
        frame.set(rect.x + 25, y, separator, style);
        frame.set(rect.x + 36, y, separator, style);
    }
}

fn lineInfo(state: *const AppState, source_line: usize) ?@import("../assembler/assembler.zig").LineInfo {
    const assembly = if (state.assembly) |*value| value else return null;
    for (assembly.source_map.items.items) |line| if (line.line == source_line) return line;
    return null;
}

fn diagnosticOnLine(state: *const AppState, source_line: usize) bool {
    for (state.diagnostics_list.items) |owned| if (owned.value.line != null and owned.value.line.? == source_line) return true;
    return false;
}

fn writeHighlighted(frame: *Frame, start_x: usize, limit_x: usize, y: usize, text: []const u8, scroll: usize, tokens: *const editor_syntax.TokenList, base: Style) void {
    const visible = if (scroll < text.len) text[scroll..] else "";
    writeTextClipped(frame, start_x, limit_x, y, visible, base);
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
        const token_style = if (token.kind == .label) mergeStyle(base, structural) else mergeStyle(base, .{ .fg = color, .bold = token.kind == .mnemonic or token.kind == .directive });
        writeTextClipped(frame, start_x + visible_start - scroll, limit_x, y, token_text, token_style);
    }
}

fn renderSelection(state: *const AppState, frame: *Frame, source_x: usize, limit_x: usize, y: usize, line_index: usize, text: []const u8) void {
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
        if (x >= limit_x) continue;
        const cell = frame.get(x, y);
        var style = cell.style;
        style.reverse = !style.reverse;
        frame.set(x, y, cell.codepoint, style);
    }
}

fn renderInlineDiagnostic(state: *const AppState, frame: *Frame, source_x: usize, source_limit: usize, pane_limit: usize, y: usize, line_index: usize, text: []const u8) void {
    for (state.diagnostics_list.items) |owned| {
        const diagnostic = owned.value;
        if (diagnostic.line == null or diagnostic.line.? != line_index + 1) continue;
        if (diagnostic.column) |column_one| {
            const first = column_one -| 1;
            const last = @min(diagnostic.end_column orelse column_one, text.len);
            for (first..last) |column| {
                if (column < state.source.scroll_x) continue;
                const x = source_x + column - state.source.scroll_x;
                if (x >= source_limit) continue;
                const cell = frame.get(x, y);
                frame.set(x, y, cell.codepoint, withFg(cell.style, .red));
            }
        }
        const message_x = source_limit;
        const message_style = mergeStyle(frame.get(message_x, y).style, .{ .fg = .red, .bold = true });
        frame.writeText(message_x, y, "! ", message_style);
        writeTextClipped(frame, message_x + 2, pane_limit, y, diagnostic.message, message_style);
        return;
    }
}

fn renderCompletion(state: *const AppState, frame: *Frame, rect: Rect, source_x: usize) void {
    if (!state.completion.active or state.editor_prompt.mode != .none) return;
    if (rect.width < 4 or rect.height < 4) return;
    const position = state.source.lineAndColumn();
    if (position.line < state.source.scroll_y) return;
    const row = position.line - state.source.scroll_y;
    if (row >= rect.height -| 3) return;
    const x = source_x + position.column -| state.source.scroll_x;
    const count = @min(state.completion.boundedLen(), @as(usize, 6));
    const width: usize = 18;
    const y = rect.y +| 3 +| row;
    const popup_height = count +| 2;
    const rect_right = rect.x +| rect.width;
    const rect_bottom = rect.y +| rect.height;
    if (x >= rect_right or y >= rect_bottom or width > rect_right - x or popup_height > rect_bottom - y) return;
    frame.fillRect(x, y, width, popup_height, ' ', .{});
    frame.box(x, y, width, popup_height, " COMPLETE ", .{ .fg = .cyan });
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

fn writeTextClipped(frame: *Frame, x_start: usize, limit_x: usize, y: usize, text: []const u8, style: Style) void {
    if (x_start >= limit_x or y >= frame.height) return;
    var view = std.unicode.Utf8View.init(text) catch return;
    var iterator = view.iterator();
    var x = x_start;
    while (x < limit_x) : (x += 1) {
        const codepoint = iterator.nextCodepoint() orelse break;
        frame.set(x, y, codepoint, style);
    }
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
    const cpu_height = @min(@as(usize, 9), rect.height - 5);
    renderCpu(state, frame, .{ .x = rect.x, .y = rect.y, .width = rect.width, .height = cpu_height });
    renderInstruction(state, frame, .{ .x = rect.x, .y = rect.y + cpu_height - 1, .width = rect.width, .height = rect.height - cpu_height + 1 });
}

pub fn renderCpu(state: *const AppState, frame: *Frame, rect: Rect) void {
    var title_buffer: [48]u8 = undefined;
    const linked_snapshot = state.linkedSnapshot();
    const title = if (linked_snapshot) |snapshot|
        std.fmt.bufPrint(&title_buffer, " CPU (Instruction #{d}) ", .{snapshot.instruction_index}) catch " CPU "
    else
        std.fmt.bufPrint(&title_buffer, " CPU ({s}) ", .{titleState(state.execution_state)}) catch " CPU ";
    paneBox(state, frame, rect, title, state.active_screen == .debug);
    if (rect.width < 14 or rect.height < 3) return;
    const r = if (linked_snapshot) |snapshot| snapshot.after.registers else state.machine.cpu.registers;
    const before = if (linked_snapshot) |snapshot| snapshot.before.registers else if (state.debug_session.previous) |snapshot| snapshot.registers else null;
    const historical = linked_snapshot != null and !state.trace_follow;
    const x = rect.x + 2;
    var y = rect.y + 1;
    frame.writeText(x, y, "REGISTERS", section_label);
    y += 1;
    if (y < rect.y + rect.height - 1) {
        renderPair(state, frame, x, y, "PC", r.pc, if (before) |old| old.pc else null, historical);
        if (rect.width >= 52) renderPair(state, frame, x + 16, y, "SP", r.sp, if (before) |old| old.sp else null, historical);
    }
    y += 1;
    if (rect.width < 52 and y < rect.y + rect.height - 1) renderPair(state, frame, x, y, "SP", r.sp, if (before) |old| old.sp else null, historical);
    y += 1;
    if (y < rect.y + rect.height - 1) {
        renderPair(state, frame, x, y, "AF", r.af(), if (before) |old| old.af() else null, historical);
        if (rect.width >= 52) renderPair(state, frame, x + 16, y, "BC", r.bc(), if (before) |old| old.bc() else null, historical);
    }
    y += 1;
    if (y < rect.y + rect.height - 1) {
        renderPair(state, frame, x, y, "DE", r.de(), if (before) |old| old.de() else null, historical);
        if (rect.width >= 52) renderPair(state, frame, x + 16, y, "HL", r.hl(), if (before) |old| old.hl() else null, historical);
    }
    y += 1;
    if (rect.width < 52 and y < rect.y + rect.height - 1) renderPair(state, frame, x, y, "BC", r.bc(), if (before) |old| old.bc() else null, historical);
    y += 1;
    if (rect.width < 52 and y < rect.y + rect.height - 1) renderPair(state, frame, x, y, "HL", r.hl(), if (before) |old| old.hl() else null, historical);
    if (rect.width >= 25) renderFlagsVertical(frame, rect, r.f);
}

fn renderPair(state: *const AppState, frame: *Frame, x: usize, y: usize, name: []const u8, value: u16, old: ?u16, linked: bool) void {
    const active_change = old != null and old.? != value and (linked or state.registerHighlightActive());
    if (active_change) {
        frame.print(x, y, changed, "{s} {X:0>4}{s}{X:0>4}", .{ name, old.?, if (state.unicode_ui) "↓" else ">", value });
    } else frame.print(x, y, .{}, "{s} {X:0>4}", .{ name, value });
}

fn renderFlagsVertical(frame: *Frame, rect: Rect, value: u8) void {
    const x = rect.x + rect.width -| 9;
    frame.writeText(x, rect.y + 1, "FLAGS", section_label);
    const items = [_]struct { []const u8, u8 }{ .{ "S", flags.S }, .{ "Z", flags.Z }, .{ "H", flags.H }, .{ "PV", flags.PV }, .{ "N", flags.N }, .{ "C", flags.C } };
    for (items, 0..) |item, index| {
        const y = rect.y + 2 + index;
        if (y >= rect.y + rect.height - 1) break;
        frame.print(x, y, .{}, "{s:<2} {d}", .{ item[0], @intFromBool(value & item[1] != 0) });
    }
}

pub fn renderInstruction(state: *AppState, frame: *Frame, rect: Rect) void {
    const pc = state.inspectionAddress() orelse state.linked_pc orelse state.machine.cpu.registers.pc;
    var title_buffer: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " INSTRUCTION ({X:0>4}) ", .{pc}) catch " INSTRUCTION ";
    paneBox(state, frame, rect, title, false);
    if (rect.width < 18 or rect.height < 3) return;
    const decoded = disassembler.decodeBus(&state.machine.bus, pc);
    var y = rect.y + 1;
    frame.print(rect.x + 2, y, if (state.instructionHighlightActive()) changed else heading, "{s}", .{disassembler.text(&decoded)});
    y += 1;
    if (rect.height >= 9) y += 1;
    if (y < rect.y + rect.height - 1) instructionField(frame, rect, y, "ADDRESS", "{X:0>4}", .{pc});
    y += 1;
    if (y < rect.y + rect.height - 1) {
        frame.writeText(rect.x + 2, y, "OPCODE", section_label);
        for (0..@min(@as(usize, decoded.size), 4)) |index| frame.print(rect.x + 12 + index * 3, y, auxiliary, "{X:0>2}", .{decoded.bytes[index]});
    }
    y += 1;
    if (y < rect.y + rect.height - 1) instructionField(frame, rect, y, "LENGTH", "{d} byte{s}", .{ decoded.size, if (decoded.size == 1) "" else "s" });
    y += 1;
    if (y < rect.y + rect.height - 1) instructionField(frame, rect, y, "TIMING", "{d} T", .{instructionTiming(state, decoded)});
    y += 1;
    if (y < rect.y + rect.height - 1) {
        frame.writeText(rect.x + 2, y, "DESCRIPTION", section_label);
        writeTextClipped(frame, rect.x + 15, rect.x + rect.width - 1, y, instructionDescription(decoded.bytes[0]), .{});
    }
    y += 1;
    if (y < rect.y + rect.height - 1) instructionField(frame, rect, y, "FLAGS", "{s}", .{(if (@import("../cpu/extended_metadata.zig").lookupEncoded(decoded.bytes[0..decoded.size])) |definition| definition.flagEffects() else flagsAffected(decoded.bytes[0]))});
}

fn instructionField(frame: *Frame, rect: Rect, y: usize, label: []const u8, comptime fmt: []const u8, args: anytype) void {
    frame.writeText(rect.x + 2, y, label, section_label);
    frame.print(rect.x + 12, y, .{ .bold = true }, fmt, args);
}

fn flagsAffected(opcode: u8) []const u8 {
    return switch (opcode) {
        0xc6, 0x80...0x85, 0x87, 0xd6, 0x90...0x95, 0x97, 0xfe, 0xb8...0xbd, 0xbf => "S Z H PV N C",
        0x3c, 0x04, 0x0c, 0x14, 0x1c, 0x24, 0x2c, 0x3d, 0x05, 0x0d, 0x15, 0x1d, 0x25, 0x2d => "S Z H PV N",
        else => "None",
    };
}

fn instructionTiming(state: *const AppState, decoded: disassembler.Decoded) u16 {
    const opcode = decoded.bytes[0];
    if (@import("../cpu/extended_metadata.zig").lookupEncoded(decoded.bytes[0..decoded.size])) |definition| {
        if (opcode != 0x20 and opcode != 0x28) return definition.t_states;
    }
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
    paneBox(state, frame, right, " BUS (0 events) ", state.active_screen == .bus);
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
    var title_buffer: [72]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " BUS ({d} events · Filter: {s}) ", .{ state.trace.len, busFilterName(state) }) catch " BUS ";
    paneBox(state, frame, rect, title, state.active_screen == .bus);
    if (rect.height < 4) return;
    if (state.trace.len == 0) {
        renderGettingStarted(state, frame, rect);
        return;
    }
    const selected_index = if (state.trace_follow) state.trace.len -| 1 else @min(state.selected_trace_event, state.trace.len -| 1);
    if (rect.width >= 70 and rect.height >= 6) {
        const split = rect.x + rect.width * 43 / 100;
        const list_rect = Rect{ .x = rect.x, .y = rect.y + 1, .width = split - rect.x + 1, .height = rect.height - 1 };
        const wave_rect = Rect{ .x = split + 1, .y = rect.y + 1, .width = rect.x + rect.width - split - 2, .height = rect.height - 2 };
        renderGroupedEvents(state, frame, list_rect, selected_index);
        bus_waveform.renderAnalyzer(frame, wave_rect, &state.trace, selected_index, state.unicode_ui, state.bus_filter.mask(), waveformView(state));
    } else if (state.bus_view == .waveform) {
        bus_waveform.renderAnalyzer(frame, rect, &state.trace, selected_index, state.unicode_ui, state.bus_filter.mask(), waveformView(state));
    } else renderGroupedEvents(state, frame, rect, selected_index);
}

fn renderGroupedEvents(state: *const AppState, frame: *Frame, rect: Rect, selected_index: usize) void {
    const selected_event = state.trace.getPtr(selected_index) orelse return;
    var title_buffer: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " INSTRUCTION #{d} ", .{selected_event.instruction_index}) catch " INSTRUCTION EVENTS ";
    paneBox(state, frame, rect, title, state.active_screen == .bus and state.bus_view == .events);
    frame.writeText(rect.x + 2, rect.y + 1, "PC", section_label);
    frame.print(rect.x + 13, rect.y + 1, .{ .bold = true }, "{X:0>4}", .{selected_event.pc});
    const decoded = disassembler.decodeBus(&state.machine.bus, selected_event.pc);
    if (rect.height > 3) {
        frame.writeText(rect.x + 2, rect.y + 2, "MNEMONIC", section_label);
        writeTextClipped(frame, rect.x + 13, rect.x + rect.width - 1, rect.y + 2, disassembler.text(&decoded), heading);
    }
    var first = selected_index;
    while (first > 0) {
        const previous = state.trace.getPtr(first - 1) orelse break;
        if (previous.instruction_index != selected_event.instruction_index) break;
        first -= 1;
    }
    var event_count: usize = 0;
    var memory_count: usize = 0;
    var io_count: usize = 0;
    var count_index = first;
    while (count_index < state.trace.len) : (count_index += 1) {
        const event = state.trace.getPtr(count_index) orelse break;
        if (event.instruction_index != selected_event.instruction_index) break;
        event_count += 1;
        switch (event.kind) {
            .memory_read, .memory_write => memory_count += 1,
            .io_read, .io_write => io_count += 1,
            else => {},
        }
    }
    if (rect.height > 4) {
        frame.writeText(rect.x + 2, rect.y + 3, "OPCODE", section_label);
        for (0..@min(@as(usize, decoded.size), 4)) |byte| frame.print(rect.x + 13 + byte * 3, rect.y + 3, auxiliary, "{X:0>2}", .{decoded.bytes[byte]});
    }
    if (rect.height > 5) frame.print(rect.x + 2, rect.y + 4, .{}, "EVENTS {d}   MEMORY {d}   I/O {d}", .{ event_count, memory_count, io_count });
    if (rect.height > 6) frame.writeText(rect.x + 2, rect.y + 5, "BUS EVENTS", section_label);
    var row: usize = 0;
    var index = first;
    while (index < state.trace.len and row < rect.height -| 8) : (index += 1) {
        const event = state.trace.getPtr(index) orelse break;
        if (event.instruction_index != selected_event.instruction_index) break;
        if (!state.bus_filter.allows(event.kind)) continue;
        const marker: u8 = if (index == selected_index) '>' else ' ';
        frame.print(rect.x + 2, rect.y + 6 + row, if (index == selected_index) selected else .{}, "{c} {d}  {s:<12} {X:0>4} {X:0>2}", .{ marker, event.event_index_in_instruction, shortKind(event.kind), event.address, event.data });
        row += 1;
    }
    if (rect.height > 7) frame.print(rect.x + 2, rect.y + rect.height - 2, auxiliary, "Sequence {d}", .{selected_event.sequence});
}

fn waveformView(state: *const AppState) bus_waveform.View {
    return .{
        .zoom = switch (state.waveform_zoom) {
            .x1 => 1,
            .x2 => 2,
            .x4 => 4,
            .fit => 0,
        },
        .pan = state.waveform_pan,
        .follow_cursor = state.waveform_follow_cursor,
    };
}

fn busFilterName(state: *const AppState) []const u8 {
    if (state.bus_filter.mask() == 0x7f) return "All";
    if (state.bus_filter.memory_write and state.bus_filter.mask() == 0x08) return "Memory Write";
    return "Custom";
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

pub fn renderDisplay(state: *const AppState, frame: *Frame, rect: Rect) void {
    var title_buffer: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, " DISPLAY{s} ", .{if (state.displayChangeActive()) (if (state.unicode_ui) " ●" else " *") else ""}) catch " DISPLAY ";
    paneBox(state, frame, rect, title, state.active_screen == .display);
    if (rect.width < 18 or rect.height < 5) return;
    const scale: usize = @intFromEnum(state.display_scale);
    var status_buffer: [96]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buffer, "{d} x 64  1bpp  Scale {d}x  Frame {d:0>6}  Changed {d} px  FPS {d}", .{ state.machine.displayWidth(), scale, state.display_frame, state.display_changed_pixels, state.display_fps }) catch "";
    writeTextClipped(frame, rect.x + 2, rect.x + rect.width - 1, rect.y + 1, status, auxiliary);

    const show_info = state.active_screen == .display and rect.width >= 54;
    const info_width: usize = if (show_info) 20 else 0;
    const canvas = Rect{ .x = rect.x + 1, .y = rect.y + 2, .width = rect.width -| (2 + info_width), .height = rect.height -| 3 };
    if (show_info) renderDisplayCursorInfo(state, frame, .{ .x = rect.x + rect.width - info_width - 1, .y = rect.y + 2, .width = info_width, .height = rect.height - 3 });

    const pixels_per_cell_x: usize = if (scale == 1) 2 else 1;
    const pixels_per_cell_y: usize = if (scale == 1) 4 else if (scale == 2) 2 else 1;
    const cell_width: usize = if (scale == 4) 2 else 1;
    const cell_height: usize = if (scale == 4) 2 else 1;
    const visible_x = @min(state.machine.displayWidth(), canvas.width / cell_width * pixels_per_cell_x);
    const visible_y = @min(@as(usize, 64), canvas.height / cell_height * pixels_per_cell_y);
    const origin_x = viewportOrigin(state.display_cursor_x, visible_x, state.machine.displayWidth());
    const origin_y = viewportOrigin(state.display_cursor_y, visible_y, 64);
    const total_cell_width = (state.machine.displayWidth() + pixels_per_cell_x - 1) / pixels_per_cell_x * cell_width;
    const total_cell_height = (64 + pixels_per_cell_y - 1) / pixels_per_cell_y * cell_height;
    const draw_x = canvas.x + (canvas.width -| @min(canvas.width, total_cell_width)) / 2;
    const draw_y = canvas.y + (canvas.height -| @min(canvas.height, total_cell_height)) / 2;
    var py: usize = origin_y;
    var cell_y: usize = 0;
    while (py < origin_y + visible_y and cell_y * cell_height < canvas.height) : ({
        py += pixels_per_cell_y;
        cell_y += 1;
    }) {
        var px: usize = origin_x;
        var cell_x: usize = 0;
        while (px < origin_x + visible_x and cell_x * cell_width < canvas.width) : ({
            px += pixels_per_cell_x;
            cell_x += 1;
        }) {
            const visual = displayCell(state, px, py, pixels_per_cell_x, pixels_per_cell_y);
            const x = draw_x + cell_x * cell_width;
            const y = draw_y + cell_y * cell_height;
            const cursor_here = state.active_screen == .display and state.display_cursor_x >= px and state.display_cursor_x < px + pixels_per_cell_x and state.display_cursor_y >= py and state.display_cursor_y < py + pixels_per_cell_y;
            var style: Style = if (visual.dirty and state.displayChangeActive()) changed else if (visual.on) .{ .fg = .green, .bold = true } else .{};
            if (cursor_here) style.reverse = true;
            var symbol: u21 = if (visual.dirty and state.displayChangeActive() and !state.color_ui) (if (visual.on) '@' else '!') else visual.symbol;
            if (state.display_grid and scale >= 2 and !visual.on and (px % 8 == 0 or py % 8 == 0)) symbol = if (state.unicode_ui) '·' else '+';
            for (0..cell_height) |dy| for (0..cell_width) |dx| frame.set(x + dx, y + dy, symbol, style);
        }
    }
}

const DisplayCell = struct { symbol: u21, on: bool, dirty: bool };

fn displayCell(state: *const AppState, x: usize, y: usize, width: usize, height: usize) DisplayCell {
    var on = false;
    var dirty = false;
    var bits: u8 = 0;
    for (0..height) |dy| for (0..width) |dx| {
        if (x + dx >= state.machine.displayWidth() or y + dy >= 64) continue;
        const value = state.machine.displayPixel(x + dx, y + dy);
        on = on or value;
        dirty = dirty or state.display_dirty[(y + dy) * state.machine.displayWidth() + x + dx];
        if (value and width == 1 and height == 2) bits |= @as(u8, 1) << @intCast(dy);
    };
    const symbol: u21 = if (width == 1 and height == 2 and state.unicode_ui)
        (if (bits == 3) '█' else if (bits == 1) '▀' else if (bits == 2) '▄' else ' ')
    else if (on) (if (state.unicode_ui) '█' else '#') else ' ';
    return .{ .symbol = symbol, .on = on, .dirty = dirty };
}

fn viewportOrigin(cursor: u8, visible: usize, total: usize) usize {
    if (visible >= total) return 0;
    return @min(@as(usize, cursor) -| (visible / 2), total - visible);
}

fn renderDisplayCursorInfo(state: *const AppState, frame: *Frame, rect: Rect) void {
    if (rect.width == 0) return;
    const x = state.display_cursor_x;
    const y = state.display_cursor_y;
    const address: u16 = (if (state.machine.config.kind == .classic) @as(u16, 0xC000) else 0) + @as(u16, y / 8) * @as(u16, @intCast(state.machine.displayWidth())) + x;
    const value = state.machine.displayPixel(x, y);
    frame.writeText(rect.x + 1, rect.y, "PIXEL", section_label);
    if (rect.height > 1) frame.print(rect.x + 1, rect.y + 1, .{ .bold = true }, "{d},{d}", .{ x, y });
    if (rect.height > 3) frame.writeText(rect.x + 1, rect.y + 3, if (state.machine.config.kind == .classic) "VRAM ADDRESS" else "VRAM OFFSET", section_label);
    if (rect.height > 4) frame.print(rect.x + 1, rect.y + 4, .{ .bold = true }, "{X:0>4}", .{address});
    if (rect.height > 6) frame.print(rect.x + 1, rect.y + 6, section_label, "BIT  {d}", .{y % 8});
    if (rect.height > 7) frame.print(rect.x + 1, rect.y + 7, .{ .bold = true }, "VALUE  {d}", .{@intFromBool(value)});
    if (rect.height > 9) frame.writeText(rect.x + 1, rect.y + 9, "Arrows: inspect", auxiliary);
    if (rect.height > 11) frame.writeText(rect.x + 1, rect.y + 11, "WRITER", section_label);
    if (rect.height > 12) if (state.display_writer_pc) |pc| {
        const decoded = disassembler.decodeBus(&state.machine.bus, pc);
        frame.print(rect.x + 1, rect.y + 12, .{ .bold = true }, "#{d}  {X:0>4}", .{ state.display_writer_instruction orelse 0, pc });
        if (rect.height > 13) writeTextClipped(frame, rect.x + 1, rect.x + rect.width, rect.y + 13, disassembler.text(&decoded), heading);
    } else frame.writeText(rect.x + 1, rect.y + 12, "No VRAM write", auxiliary);
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
    const state_name = statusName(state.execution_state);
    const dirty_name = if (state.source.dirty) "DIRTY" else "CLEAN";
    frame.print(rect.x + 1, rect.y, statusBadgeStyle(state.execution_state), "[{s}]", .{state_name});
    const dirty_x = rect.x + state_name.len + 4;
    frame.print(dirty_x, rect.y, .{ .fg = if (state.source.dirty) .yellow else .green, .reverse = true, .bold = true }, "[{s}]", .{dirty_name});
    var metrics_buffer: [160]u8 = undefined;
    const metrics = if (state.game_input_mode or state.game_input.value != 0)
        std.fmt.bufPrint(&metrics_buffer, "PC {X:0>4}  Instr {d}  T-State {d}  Trace {d}/4096  Input {X:0>2} GAME", .{ state.machine.cpu.registers.pc, state.executed_instructions, state.machine.cpu.total_t_states, state.trace.len, state.game_input.value }) catch ""
    else
        std.fmt.bufPrint(&metrics_buffer, "PC {X:0>4}  Instr {d}  T-State {d}  Trace {d}/4096", .{ state.machine.cpu.registers.pc, state.executed_instructions, state.machine.cpu.total_t_states, state.trace.len }) catch "";
    const metrics_x = dirty_x + dirty_name.len + 4;
    frame.writeText(metrics_x, rect.y, metrics, .{ .reverse = true });
    const help = statusHelp(state);
    if (metrics_x - rect.x + metrics.len + help.len + 3 <= rect.width) frame.writeText(rect.x + rect.width - help.len - 2, rect.y, help, .{ .reverse = true });
}

fn statusBadgeStyle(value: state_mod.ExecutionState) Style {
    return .{ .fg = switch (value) {
        .running => .green,
        .halted => .cyan,
        .breakpoint, .watchpoint, .limit_reached => .yellow,
        .faulted => .red,
        .paused => .blue,
        .assembled => .cyan,
        .empty => .default,
    }, .reverse = true, .bold = true };
}

fn statusHelp(state: *const AppState) []const u8 {
    if (state.palette.active) return "Up/Down Select  Enter Run  Esc Close";
    if (state.editor_prompt.mode != .none) return "Enter Next/Confirm  Esc Cancel";
    return switch (state.active_screen) {
        .editor => "^S Save  ^F Search  ^P Palette",
        .debug => "^T Step  ^E Run  Esc Pause",
        .memory => "g Address  P PC  H HL",
        .bus => "[] Cursor  +/- Zoom  Shift+Left/Right Pan",
        .display => "Arrows Inspect  ^P Scale/Grid",
        .help => "^P Palette  ^Q Quit",
    };
}

fn statusName(value: state_mod.ExecutionState) []const u8 {
    return switch (value) {
        .empty => "READY",
        .assembled => "ASSEMBLED",
        .running => "RUNNING",
        .paused => "PAUSED",
        .halted => "HALTED",
        .breakpoint => "BREAKPOINT",
        .watchpoint => "WATCHPOINT",
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
        .watchpoint => "Watchpoint",
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
    const height = @min(state_mod.AppState.palette_commands.len + 3, frame.height -| 4);
    if (width < 20 or height < 7) return;
    const rect = Rect{ .x = (frame.width - width) / 2, .y = (frame.height - height) / 2, .width = width, .height = height };
    frame.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', .{});
    frame.box(rect.x, rect.y, rect.width, rect.height, " COMMAND PALETTE ", .{ .fg = .cyan, .bold = true });
    const rows = height - 3;
    var start = state.palette.selected -| (rows / 2);
    if (start + rows > state_mod.AppState.palette_commands.len) start = state_mod.AppState.palette_commands.len -| rows;
    for (state_mod.AppState.palette_commands[start..@min(start + rows, state_mod.AppState.palette_commands.len)], start..) |command, index| {
        const marker: u8 = if (index == state.palette.selected) '>' else ' ';
        frame.print(rect.x + 2, rect.y + 1 + index - start, if (index == state.palette.selected) selected else .{}, "{c} {s}", .{ marker, command });
    }
    frame.writeText(rect.x + 2, rect.y + height - 2, "Enter Execute | Esc Close", .{});
}
