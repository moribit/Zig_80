const std = @import("std");
const Frame = @import("render/frame.zig").Frame;
const Style = @import("render/style.zig").Style;
const Rect = @import("layout.zig").Rect;
const trace = @import("../trace/trace.zig");

const label_width: usize = 8;
const cursor_style = Style{ .fg = .yellow, .bold = true };

pub const View = struct {
    /// Zero selects Fit. Other values are the logical zoom multiplier.
    zoom: usize = 2,
    pan: usize = 0,
    follow_cursor: bool = true,
};

/// Renders equal-width logical accesses. The horizontal axis is intentionally
/// event order, never inferred electrical timing or T-state duration.
pub fn render(frame: *Frame, rect: Rect, events: *const trace.TraceBuffer, selected_index: usize, unicode: bool) void {
    renderAnalyzer(frame, rect, events, selected_index, unicode, 0x7f, .{});
}

pub fn renderFiltered(frame: *Frame, rect: Rect, events: *const trace.TraceBuffer, selected_index: usize, unicode: bool, filter_mask: u8) void {
    renderAnalyzer(frame, rect, events, selected_index, unicode, filter_mask, .{});
}

pub fn renderAnalyzer(frame: *Frame, rect: Rect, events: *const trace.TraceBuffer, selected_index: usize, unicode: bool, filter_mask: u8, view: View) void {
    if (rect.width < label_width + 5 or rect.height < 5) return;
    frame.writeText(rect.x, rect.y, if (unicode) "LOGICAL ANALYZER — EVENT TIME, NOT CYCLE-ACCURATE" else "LOGICAL ANALYZER - EVENT TIME, NOT CYCLE-ACCURATE", .{ .fg = .yellow, .bold = true });

    var indices: [4096]usize = undefined;
    var filtered_len: usize = 0;
    for (0..events.len) |index| {
        const event = events.getPtr(index) orelse continue;
        if (!allows(filter_mask, event.kind)) continue;
        indices[filtered_len] = index;
        filtered_len += 1;
    }
    if (filtered_len == 0) {
        frame.writeText(rect.x + 2, rect.y + 2, "No bus events", .{});
        return;
    }

    const plot_x = rect.x + label_width;
    const plot_width = rect.width -| (label_width + 1);
    if (view.zoom == 0 and filtered_len > plot_width) {
        const stride = (filtered_len + plot_width - 1) / plot_width;
        var fitted_len: usize = 0;
        var source_slot: usize = 0;
        while (source_slot < filtered_len and fitted_len < plot_width) : (source_slot += stride) {
            indices[fitted_len] = indices[@min(source_slot + stride - 1, filtered_len - 1)];
            fitted_len += 1;
        }
        filtered_len = fitted_len;
    }
    const slot_width: usize = if (view.zoom == 0)
        @max(@as(usize, 1), plot_width / filtered_len)
    else switch (view.zoom) {
        1 => @as(usize, 5),
        2 => @as(usize, 7),
        else => @as(usize, 11),
    };
    const visible_count = @max(@as(usize, 1), @min(filtered_len, plot_width / slot_width));
    var selected_slot: usize = 0;
    for (indices[0..filtered_len], 0..) |index, slot| if (index <= selected_index) {
        selected_slot = slot;
    };
    var start = if (view.follow_cursor) selected_slot -| (visible_count / 2) else @min(view.pan, filtered_len - 1);
    if (start + visible_count > filtered_len) start = filtered_len - visible_count;
    const count = @min(visible_count, filtered_len - start);

    const two_level = rect.height >= 20;
    const groups_y = rect.y + 1;
    const ticks_y = groups_y + @intFromBool(two_level);
    const guides_y = ticks_y + 1;
    if (two_level) renderInstructionGroups(frame, groups_y, plot_x, plot_width, events, indices[0..filtered_len], start, count, slot_width);
    renderTicks(frame, ticks_y, plot_x, plot_width, events, indices[0..filtered_len], start, count, slot_width, selected_index);
    renderGuides(frame, guides_y, plot_x, plot_width, count, slot_width, unicode);
    const signal_start = guides_y + 1;
    const signals = [_]Signal{ .m1, .mreq, .iorq, .rd, .wr, .rfsh };
    for (signals, 0..) |signal, row| {
        if (two_level) {
            const high_y = signal_start + row * 2;
            if (high_y + 1 >= rect.y + rect.height) break;
            renderSignalPair(frame, high_y, plot_x, plot_width, events, indices[0..filtered_len], start, count, slot_width, selected_index, signal, unicode);
        } else {
            const y = signal_start + row;
            if (y >= rect.y + rect.height) break;
            renderSignalCompact(frame, y, plot_x, plot_width, events, indices[0..filtered_len], start, count, slot_width, selected_index, signal, unicode);
        }
    }

    const values_y = signal_start + if (two_level) signals.len * 2 else signals.len;
    if (values_y < rect.y + rect.height) renderValueRow(frame, values_y, plot_x, plot_width, "ADDR", events, indices[0..filtered_len], start, count, slot_width, selected_index, .address);
    if (values_y + 1 < rect.y + rect.height) renderValueRow(frame, values_y + 1, plot_x, plot_width, "DATA", events, indices[0..filtered_len], start, count, slot_width, selected_index, .data);
    if (values_y + 2 < rect.y + rect.height) renderValueRow(frame, values_y + 2, plot_x, plot_width, "TYPE", events, indices[0..filtered_len], start, count, slot_width, selected_index, .kind);

    if (selected_slot >= start and selected_slot < start + count) {
        const cursor_x = @min(plot_x + plot_width - 1, plot_x + (selected_slot - start + 1) * slot_width);
        const last_data_y = @min(rect.y + rect.height - 1, values_y + 2);
        for (groups_y..last_data_y + 1) |y| frame.set(cursor_x, y, if (unicode) '│' else '|', cursor_style);
        frame.set(cursor_x, guides_y, if (unicode) '│' else '|', cursor_style);
    }
    const detail_y = values_y + 3;
    if (detail_y < rect.y + rect.height) renderCursorDetail(frame, detail_y, rect, events.getPtr(selected_index), unicode);
}

const Signal = enum { m1, mreq, iorq, rd, wr, rfsh };
const ValueRow = enum { address, data, kind };

fn renderInstructionGroups(frame: *Frame, y: usize, plot_x: usize, plot_width: usize, events: *const trace.TraceBuffer, indices: []const usize, start: usize, count: usize, slot_width: usize) void {
    var offset: usize = 0;
    while (offset < count) {
        const event = events.getPtr(indices[start + offset]) orelse break;
        var group_count: usize = 1;
        while (offset + group_count < count) : (group_count += 1) {
            const next = events.getPtr(indices[start + offset + group_count]) orelse break;
            if (next.instruction_index != event.instruction_index) break;
        }
        const x = plot_x + offset * slot_width;
        const limit = @min(plot_x + plot_width, x + group_count * slot_width);
        var buffer: [32]u8 = undefined;
        const title = std.fmt.bufPrint(&buffer, "Instruction #{d}", .{event.instruction_index}) catch "Instruction";
        writeClipped(frame, x, limit, y, title, .{ .fg = .cyan, .bold = true });
        offset += group_count;
    }
}

fn renderGuides(frame: *Frame, y: usize, plot_x: usize, plot_width: usize, count: usize, slot_width: usize, unicode: bool) void {
    frame.writeText(plot_x - label_width + 1, y, if (unicode) "Time →" else "Time ->", .{ .fg = .cyan });
    for (0..count) |offset| {
        const x = plot_x + offset * slot_width + slot_width / 2;
        if (x >= plot_x + plot_width) break;
        frame.set(x, y, if (unicode) '┊' else ':', .{ .fg = .blue });
    }
}

fn renderCursorDetail(frame: *Frame, y: usize, rect: Rect, event: ?*const trace.BusEvent, unicode: bool) void {
    const selected = event orelse return;
    var buffer: [112]u8 = undefined;
    const separator = if (unicode) "│" else "|";
    const text = std.fmt.bufPrint(&buffer, "Cursor #{d} {s} PC {X:0>4} {s} {s} {s} data {X:0>2}", .{ selected.sequence, separator, selected.pc, separator, kindName(selected.kind), separator, selected.data }) catch return;
    writeClipped(frame, rect.x, rect.x + rect.width, y, text, .{ .fg = .yellow, .bold = true });
}

fn renderTicks(frame: *Frame, y: usize, plot_x: usize, plot_width: usize, events: *const trace.TraceBuffer, indices: []const usize, start: usize, count: usize, slot_width: usize, selected_index: usize) void {
    frame.writeText(plot_x - label_width + 1, y, "EVENT", .{ .fg = .blue });
    for (0..count) |offset| {
        const index = indices[start + offset];
        const event = events.getPtr(index) orelse continue;
        const x = plot_x + offset * slot_width;
        if (x >= plot_x + plot_width) break;
        frame.print(x, y, if (index == selected_index) cursor_style else .{ .fg = .blue }, "{d}", .{event.sequence % 1000});
    }
}

fn writeClipped(frame: *Frame, x: usize, limit: usize, y: usize, text: []const u8, style: Style) void {
    var cursor = x;
    var index: usize = 0;
    while (index < text.len and cursor < limit) {
        const sequence = std.unicode.Utf8View.initUnchecked(text[index..]);
        var iterator = sequence.iterator();
        const codepoint = iterator.nextCodepoint() orelse break;
        frame.set(cursor, y, codepoint, style);
        const bytes = std.unicode.utf8CodepointSequenceLength(codepoint) catch 1;
        index += bytes;
        cursor += 1;
    }
}

fn renderSignalPair(frame: *Frame, high_y: usize, plot_x: usize, plot_width: usize, events: *const trace.TraceBuffer, indices: []const usize, start: usize, count: usize, slot_width: usize, selected_index: usize, signal: Signal, unicode: bool) void {
    frame.print(plot_x - label_width + 1, high_y, .{}, "{s:<6}", .{signalName(signal)});
    for (0..count) |offset| {
        const slot = start + offset;
        const event = events.getPtr(indices[slot]) orelse continue;
        const asserted = signalValue(event, signal);
        const x = plot_x + offset * slot_width;
        if (x >= plot_x + plot_width) break;
        const style = if (indices[slot] == selected_index) Style{ .fg = .yellow, .bold = true } else Style{};
        if (unicode and asserted and slot_width >= 3) {
            frame.set(x, high_y, '─', style);
            frame.set(x + 1, high_y, '┐', style);
            frame.set(x + 1, high_y + 1, '└', style);
            fillHorizontal(frame, x + 2, high_y + 1, slot_width -| 3, plot_x + plot_width, '─', style);
            const rise_x = @min(x + slot_width - 1, plot_x + plot_width - 1);
            frame.set(rise_x, high_y, '┌', style);
            frame.set(rise_x, high_y + 1, '┘', style);
        } else if (unicode) {
            fillHorizontal(frame, x, high_y + @intFromBool(asserted), slot_width, plot_x + plot_width, '─', style);
        } else if (asserted and slot_width >= 3) {
            frame.set(x, high_y, '=', style);
            frame.set(x + 1, high_y, '|', style);
            frame.set(x + 1, high_y + 1, '|', style);
            fillHorizontal(frame, x + 2, high_y + 1, slot_width -| 3, plot_x + plot_width, '_', style);
            const rise_x = @min(x + slot_width - 1, plot_x + plot_width - 1);
            frame.set(rise_x, high_y, '|', style);
            frame.set(rise_x, high_y + 1, '|', style);
        } else {
            fillHorizontal(frame, x, high_y + @intFromBool(asserted), slot_width, plot_x + plot_width, if (asserted) '_' else '=', style);
        }
    }
}

fn renderSignalCompact(frame: *Frame, y: usize, plot_x: usize, plot_width: usize, events: *const trace.TraceBuffer, indices: []const usize, start: usize, count: usize, slot_width: usize, selected_index: usize, signal: Signal, unicode: bool) void {
    frame.print(plot_x - label_width + 1, y, .{}, "{s:<6}", .{signalName(signal)});
    for (0..count) |offset| {
        const slot = start + offset;
        const event = events.getPtr(indices[slot]) orelse continue;
        const asserted = signalValue(event, signal);
        const x = plot_x + offset * slot_width;
        const style = if (indices[slot] == selected_index) Style{ .fg = .yellow, .bold = true } else Style{};
        frame.set(x, y, if (asserted) '_' else if (unicode) '─' else '=', style);
        fillHorizontal(frame, x + 1, y, slot_width -| 1, plot_x + plot_width, if (asserted) '_' else if (unicode) '─' else '=', style);
    }
}

fn renderValueRow(frame: *Frame, y: usize, plot_x: usize, plot_width: usize, label: []const u8, events: *const trace.TraceBuffer, indices: []const usize, start: usize, count: usize, slot_width: usize, selected_index: usize, row: ValueRow) void {
    frame.print(plot_x - label_width + 1, y, .{}, "{s:<6}", .{label});
    for (0..count) |offset| {
        const index = indices[start + offset];
        const event = events.getPtr(index) orelse continue;
        const x = plot_x + offset * slot_width;
        if (x >= plot_x + plot_width) break;
        const style = if (index == selected_index) cursor_style else Style{ .fg = .blue };
        switch (row) {
            .address => if (slot_width >= 6)
                frame.print(x, y, style, "[{X:0>4}]", .{event.address})
            else if (slot_width >= 4)
                frame.print(x, y, style, "[{X:0>2}]", .{@as(u8, @truncate(event.address))}),
            .data => if (slot_width >= 4) frame.print(x, y, style, "[{X:0>2}]", .{event.data}),
            .kind => frame.writeText(x, y, shortKind(event.kind)[0..@min(shortKind(event.kind).len, slot_width)], style),
        }
    }
}

fn fillHorizontal(frame: *Frame, x: usize, y: usize, width: usize, limit: usize, glyph: u21, style: Style) void {
    for (0..width) |offset| {
        if (x + offset >= limit) break;
        frame.set(x + offset, y, glyph, style);
    }
}

fn signalValue(event: *const trace.BusEvent, signal: Signal) bool {
    return switch (signal) {
        .m1 => event.signals.m1,
        .mreq => event.signals.mreq,
        .iorq => event.signals.iorq,
        .rd => event.signals.rd,
        .wr => event.signals.wr,
        .rfsh => event.signals.rfsh,
    };
}

fn signalName(signal: Signal) []const u8 {
    return switch (signal) {
        .m1 => "M1",
        .mreq => "/MREQ",
        .iorq => "/IORQ",
        .rd => "/RD",
        .wr => "/WR",
        .rfsh => "/RFSH",
    };
}

fn allows(mask: u8, kind: trace.BusEventKind) bool {
    const bit: u3 = switch (kind) {
        .opcode_fetch => 0,
        .operand_read => 1,
        .memory_read => 2,
        .memory_write => 3,
        .io_read => 4,
        .io_write => 5,
        .refresh, .interrupt_ack => 6,
    };
    return mask & (@as(u8, 1) << bit) != 0;
}

fn shortKind(kind: trace.BusEventKind) []const u8 {
    return switch (kind) {
        .opcode_fetch => "OP",
        .operand_read => "ARG",
        .memory_read => "READ",
        .memory_write => "WRITE",
        .io_read => "IN",
        .io_write => "OUT",
        .refresh => "RFSH",
        .interrupt_ack => "INT",
    };
}

fn kindName(kind: trace.BusEventKind) []const u8 {
    return switch (kind) {
        .opcode_fetch => "Opcode Fetch",
        .operand_read => "Operand Read",
        .memory_read => "Memory Read",
        .memory_write => "Memory Write",
        .io_read => "I/O Read",
        .io_write => "I/O Write",
        .refresh => "Refresh",
        .interrupt_ack => "Interrupt Ack",
    };
}
