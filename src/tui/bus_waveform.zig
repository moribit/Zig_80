const Frame = @import("render/frame.zig").Frame;
const Style = @import("render/style.zig").Style;
const Rect = @import("layout.zig").Rect;
const trace = @import("../trace/trace.zig");

const slot_width: usize = 6;
const label_width: usize = 7;
const selected = Style{ .reverse = true, .bold = true };

/// Renders equal-width logical event slots. It deliberately does not infer
/// electrical timing or T-state duration from the event stream.
pub fn render(frame: *Frame, rect: Rect, events: *const trace.TraceBuffer, selected_index: usize, unicode: bool) void {
    renderFiltered(frame, rect, events, selected_index, unicode, 0x7f);
}

pub fn renderFiltered(frame: *Frame, rect: Rect, events: *const trace.TraceBuffer, selected_index: usize, unicode: bool, filter_mask: u8) void {
    if (rect.width < label_width + slot_width or rect.height < 4) return;
    frame.writeText(rect.x + 2, rect.y + 1, "Logical Bus Waveform - not cycle-accurate | Event slot", .{ .bold = true });
    if (rect.height < 6) return;
    var indices: [4096]usize = undefined;
    var filtered_len: usize = 0;
    for (0..events.len) |index| {
        const event = events.getPtr(index) orelse continue;
        if (!allows(filter_mask, event.kind)) continue;
        indices[filtered_len] = index;
        filtered_len += 1;
    }
    const available = (rect.width -| (label_width + 2)) / slot_width;
    const count = @min(available, filtered_len);
    if (count == 0) {
        frame.writeText(rect.x + 2, rect.y + 2, "No bus events", .{});
        return;
    }
    var selected_slot: usize = 0;
    for (indices[0..filtered_len], 0..) |index, slot| if (index <= selected_index) {
        selected_slot = slot;
    };
    var start = selected_slot -| (count / 2);
    if (start + count > filtered_len) start = filtered_len - count;

    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "Slot", .slot, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "M1", .m1, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "MREQ", .mreq, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "IORQ", .iorq, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "RD", .rd, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "WR", .wr, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "RFSH", .rfsh, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "ADDR", .address, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "DATA", .data, unicode);
    renderSlots(frame, rect, events, indices[0..filtered_len], start, count, selected_index, "TYPE", .kind, unicode);
}

const Row = enum { slot, m1, mreq, iorq, rd, wr, rfsh, address, data, kind };

fn renderSlots(frame: *Frame, rect: Rect, events: *const trace.TraceBuffer, indices: []const usize, start: usize, count: usize, selected_index: usize, label: []const u8, row: Row, unicode: bool) void {
    const y = rect.y + 2 + @intFromEnum(row);
    if (y >= rect.y + rect.height - 1) return;
    frame.print(rect.x + 2, y, .{}, "{s:<5}", .{label});
    for (0..count) |offset| {
        const index = indices[start + offset];
        const event = events.getPtr(index) orelse continue;
        const style = if (index == selected_index) selected else Style{};
        const x = rect.x + label_width + offset * slot_width;
        if (index == selected_index and x > rect.x) frame.set(x - 1, y, if (row == .slot) (if (unicode) '▼' else 'v') else (if (unicode) '│' else '|'), .{ .fg = .yellow, .bold = true });
        switch (row) {
            .slot => frame.print(x, y, style, "{d:0>5}", .{event.sequence % 100_000}),
            .m1 => signal(frame, x, y, style, event.signals.m1, unicode),
            .mreq => signal(frame, x, y, style, event.signals.mreq, unicode),
            .iorq => signal(frame, x, y, style, event.signals.iorq, unicode),
            .rd => signal(frame, x, y, style, event.signals.rd, unicode),
            .wr => signal(frame, x, y, style, event.signals.wr, unicode),
            .rfsh => signal(frame, x, y, style, event.signals.rfsh, unicode),
            .address => frame.print(x, y, style, "{X:0>4} ", .{event.address}),
            .data => frame.print(x, y, style, " {X:0>2}  ", .{event.data}),
            .kind => frame.print(x, y, style, "{s:^5}", .{shortKind(event.kind)}),
        }
    }
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

fn signal(frame: *Frame, x: usize, y: usize, style: Style, high: bool, unicode: bool) void {
    if (unicode) {
        frame.writeText(x, y, if (high) " ─██─" else " ────", style);
    } else frame.writeText(x, y, if (high) "--##-" else "-----", style);
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
