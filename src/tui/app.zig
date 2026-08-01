const std = @import("std");
const AppState = @import("state.zig").AppState;
const Frame = @import("render/frame.zig").Frame;
const Style = @import("render/style.zig").Style;
const Rect = @import("layout.zig").Rect;
const Layout = @import("layout.zig").Layout;
const flags = @import("../cpu/flags.zig");
const disassembler = @import("../disassembler/disassembler.zig");
const video = @import("../machine/video.zig");
const trace = @import("../trace/trace.zig");

const heading = Style{ .fg = .cyan, .bold = true };
const changed = Style{ .fg = .yellow, .bold = true };
const selected = Style{ .reverse = true };

pub fn render(state: *AppState, frame: *Frame) void {
    frame.clear();
    const layout = Layout.calculate(frame.width, frame.height);
    renderHeader(state, frame, layout.header);
    if (layout.compact) {
        if (frame.width < 40 or frame.height < 10) {
            frame.writeText(1, @min(3, frame.height -| 1), "Terminal is too small. Recommended: 80x24", .{ .bold = true });
        } else renderCompact(state, frame, layout.source);
    } else {
        renderSource(state, frame, layout.source);
        renderCpu(state, frame, layout.cpu);
        renderLower(state, frame, layout.lower);
    }
    renderStatus(state, frame, layout.status);
}

fn renderHeader(state: *const AppState, frame: *Frame, rect: Rect) void {
    if (rect.height == 0) return;
    frame.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', .{ .reverse = true });
    frame.print(1, rect.y, .{ .reverse = true, .bold = true }, "Zig_80 - {s}{s}", .{ if (state.source_path) |path| path else "untitled.asm", if (state.source.dirty) " *" else "" });
    if (rect.height > 1) frame.writeText(1, rect.y + 1, "F1 Help F2 Assemble F5 Run F6 Step F7 Continue F8 Pause F9 Break | Alt+1..5 Views", .{});
}

fn renderCompact(state: *AppState, frame: *Frame, rect: Rect) void {
    switch (state.active_screen) {
        .editor => renderSource(state, frame, rect),
        .debug => renderCpu(state, frame, rect),
        .memory => renderMemory(state, frame, rect),
        .bus => renderBus(state, frame, rect),
        .display => renderDisplay(state, frame, rect),
        .help => renderHelp(frame, rect),
    }
}

fn renderSource(state: *AppState, frame: *Frame, rect: Rect) void {
    frame.box(rect.x, rect.y, rect.width, rect.height, " SOURCE ", heading);
    if (rect.width < 4 or rect.height < 3) return;
    const inner_width = rect.width - 2;
    const rows = rect.height - 2;
    state.source.ensureVisible(inner_width -| 8, rows);
    const cursor_line = state.source.lineAndColumn().line;
    const pc_line = state.sourceLineForPC(state.machine.cpu.registers.pc);
    for (0..rows) |row| {
        const line_index = state.source.scroll_y + row;
        const text = state.source.lineSlice(line_index) orelse break;
        var line_style: Style = .{};
        if (line_index == cursor_line) line_style = selected;
        const execution = pc_line != null and pc_line.? == line_index + 1;
        var breakpoint = false;
        if (state.assembly) |*assembly| for (assembly.lines.items) |line| if (line.line == line_index + 1 and state.debug_session.breakpoints.contains(line.address)) {
            breakpoint = true;
            break;
        };
        const execution_marker: u8 = if (execution) '>' else ' ';
        const breakpoint_marker: u8 = if (breakpoint) '*' else ' ';
        frame.print(rect.x + 1, rect.y + 1 + row, line_style, "{c}{c}{d: >4} ", .{ execution_marker, breakpoint_marker, line_index + 1 });
        const visible = if (state.source.scroll_x < text.len) text[state.source.scroll_x..] else "";
        frame.writeText(rect.x + 8, rect.y + 1 + row, visible, line_style);
    }
}

fn renderCpu(state: *const AppState, frame: *Frame, rect: Rect) void {
    frame.box(rect.x, rect.y, rect.width, rect.height, " CPU ", heading);
    if (rect.width < 20 or rect.height < 4) return;
    const r = state.machine.cpu.registers;
    const x = rect.x + 2;
    var y = rect.y + 1;
    frame.print(x, y, pairStyle(state, "pc", "sp"), "PC {X:0>4}  SP {X:0>4}", .{ r.pc, r.sp });
    y += 1;
    frame.print(x, y, pairGroupStyle(state, "a", "f", "b", "c"), "AF {X:0>4}  BC {X:0>4}", .{ r.af(), r.bc() });
    y += 1;
    frame.print(x, y, pairGroupStyle(state, "d", "e", "h", "l"), "DE {X:0>4}  HL {X:0>4}", .{ r.de(), r.hl() });
    y += 1;
    frame.print(x, y, pairGroupStyle(state, "a", "f", "b", "c"), "A {X:0>2} F {X:0>2} B {X:0>2} C {X:0>2}", .{ r.a, r.f, r.b, r.c });
    y += 1;
    frame.print(x, y, pairGroupStyle(state, "d", "e", "h", "l"), "D {X:0>2} E {X:0>2} H {X:0>2} L {X:0>2}", .{ r.d, r.e, r.h, r.l });
    y += 1;
    frame.print(x, y, registerStyle(state, "f"), "Flags S Z H P N C: {d} {d} {d} {d} {d} {d}", .{ bit(r.f, flags.S), bit(r.f, flags.Z), bit(r.f, flags.H), bit(r.f, flags.PV), bit(r.f, flags.N), bit(r.f, flags.C) });
    y += 1;
    frame.print(x, y, .{}, "HALT {s}  T-states {d}", .{ if (state.machine.cpu.halted) "yes" else "no", state.machine.cpu.total_t_states });
    y += 2;
    if (y < rect.y + rect.height - 1) {
        const decoded = disassembler.decode(&state.machine.bus.memory, r.pc);
        frame.print(x, y, heading, "Current: {X:0>4} {s}", .{ r.pc, disassembler.text(&decoded) });
    }
}

fn registerStyle(state: *const AppState, comptime name: []const u8) Style {
    return if (state.debug_session.changedRegister(name)) changed else .{};
}
fn pairStyle(state: *const AppState, comptime first: []const u8, comptime second: []const u8) Style {
    return if (state.debug_session.changedRegister(first) or state.debug_session.changedRegister(second)) changed else .{};
}
fn pairGroupStyle(state: *const AppState, comptime a: []const u8, comptime b: []const u8, comptime c: []const u8, comptime d: []const u8) Style {
    return if (state.debug_session.changedRegister(a) or state.debug_session.changedRegister(b) or state.debug_session.changedRegister(c) or state.debug_session.changedRegister(d)) changed else .{};
}
fn bit(value: u8, mask: u8) u1 {
    return @intFromBool(value & mask != 0);
}

fn renderLower(state: *AppState, frame: *Frame, rect: Rect) void {
    if (state.diagnostic) |diagnostic| {
        frame.box(rect.x, rect.y, rect.width, rect.height, " DIAGNOSTICS ", .{ .fg = .red, .bold = true });
        frame.writeText(rect.x + 2, rect.y + 1, diagnostic.message, .{ .fg = .red, .bold = true });
        if (diagnostic.hint) |hint| frame.print(rect.x + 2, rect.y + 2, .{}, "hint: {s}", .{hint});
        return;
    }
    switch (state.active_screen) {
        .memory => renderMemory(state, frame, rect),
        .display => renderDisplay(state, frame, rect),
        .help => renderHelp(frame, rect),
        else => renderBus(state, frame, rect),
    }
}

fn renderMemory(state: *const AppState, frame: *Frame, rect: Rect) void {
    frame.box(rect.x, rect.y, rect.width, rect.height, " MEMORY ", heading);
    if (rect.width < 55 or rect.height < 3) return;
    const rows = rect.height - 2;
    for (0..rows) |row| {
        const address = state.memory_address +% @as(u16, @intCast(row * 16));
        frame.print(rect.x + 2, rect.y + 1 + row, .{}, "{X:0>4} ", .{address});
        for (0..16) |column| {
            const cell_address = address +% @as(u16, @intCast(column));
            const style: Style = if (state.last_memory_write != null and state.last_memory_write.? == cell_address) changed else .{};
            frame.print(rect.x + 7 + column * 3, rect.y + 1 + row, style, "{X:0>2}", .{state.machine.bus.read8(cell_address)});
        }
    }
}

fn renderBus(state: *const AppState, frame: *Frame, rect: Rect) void {
    frame.box(rect.x, rect.y, rect.width, rect.height, " BUS EVENTS - instruction-level modeled, not cycle-accurate ", heading);
    if (rect.height < 3) return;
    frame.writeText(rect.x + 2, rect.y + 1, "T-State   Instr  Type          Addr Data Signals", .{ .bold = true });
    const rows = rect.height - 4;
    const selected_index = if (state.trace_follow) state.trace.len -| 1 else @min(state.selected_trace_event, state.trace.len -| 1);
    const start = selected_index -| (rows -| 1);
    for (0..rows) |row| {
        const event = state.trace.get(start + row) orelse break;
        var signal_buffer: [32]u8 = undefined;
        var length: usize = 0;
        appendSignal(&signal_buffer, &length, event.signals.m1, "M1 ");
        appendSignal(&signal_buffer, &length, event.signals.mreq, "MREQ ");
        appendSignal(&signal_buffer, &length, event.signals.iorq, "IORQ ");
        appendSignal(&signal_buffer, &length, event.signals.rd, "RD ");
        appendSignal(&signal_buffer, &length, event.signals.wr, "WR");
        frame.print(rect.x + 2, rect.y + 2 + row, if (start + row == selected_index) selected else .{}, "{d:0>8}  #{d:<5} {s:<13} {X:0>4} {X:0>2} {s}", .{ event.t_state_start, event.instruction_index, trace.kindName(event.kind), event.address, event.data, signal_buffer[0..length] });
    }
    if (state.trace.get(selected_index)) |event| frame.print(rect.x + 2, rect.y + rect.height - 2, .{ .bold = true }, "Selected seq={d} PC={X:0>4} duration=modeled | Enter: source", .{ event.sequence, event.pc });
}

fn appendSignal(buffer: []u8, length: *usize, enabled: bool, name: []const u8) void {
    if (!enabled or length.* + name.len > buffer.len) return;
    @memcpy(buffer[length.*..][0..name.len], name);
    length.* += name.len;
}

fn renderDisplay(state: *const AppState, frame: *Frame, rect: Rect) void {
    frame.box(rect.x, rect.y, rect.width, rect.height, " DISPLAY 128x64 (ASCII fallback) ", heading);
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

fn renderHelp(frame: *Frame, rect: Rect) void {
    frame.box(rect.x, rect.y, rect.width, rect.height, " HELP ", heading);
    const lines = [_][]const u8{
        "Ctrl+S Save | Ctrl+Q Quit | Ctrl+A Assemble | Ctrl+G Run | Ctrl+N Step | Ctrl+P Pause",
        "F2 Assemble | F5 Run | F6 Step | F7 Continue | F8 Pause | F9 Breakpoint",
        "Alt+1 Editor | Alt+2 Debug | Alt+3 Memory | Alt+4 Bus | Alt+5 Display | ? Help",
        "Memory: arrows scroll; Home PC; End HL; PageUp SP; PageDown VRAM",
    };
    for (lines, 0..) |line, index| if (index + 1 < rect.height) frame.writeText(rect.x + 2, rect.y + 1 + index, line, .{});
}

fn renderStatus(state: *const AppState, frame: *Frame, rect: Rect) void {
    if (rect.height == 0) return;
    frame.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', .{ .reverse = true });
    frame.print(rect.x + 1, rect.y, .{ .reverse = true }, "{s} | PC={X:0>4} | {d} T-states | {s}", .{ @tagName(state.execution_state), state.machine.cpu.registers.pc, state.machine.cpu.total_t_states, state.statusText() });
}
