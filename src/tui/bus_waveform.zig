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
    if (rect.width < label_width + slot_width or rect.height < 4) return;
    frame.writeText(rect.x + 2, rect.y + 1, "Logical Bus Waveform - not cycle-accurate | Event slot", .{ .bold = true });
    if (rect.height < 6) return;
    const available = (rect.width -| (label_width + 2)) / slot_width;
    const count = @min(available, events.len);
    if (count == 0) {
        frame.writeText(rect.x + 2, rect.y + 2, "No bus events", .{});
        return;
    }
    const bounded_selected = @min(selected_index, events.len - 1);
    var start = bounded_selected -| (count / 2);
    if (start + count > events.len) start = events.len - count;

    renderSlots(frame, rect, events, start, count, bounded_selected, "Slot", .slot, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "M1", .m1, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "MREQ", .mreq, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "IORQ", .iorq, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "RD", .rd, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "WR", .wr, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "RFSH", .rfsh, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "ADDR", .address, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "DATA", .data, unicode);
    renderSlots(frame, rect, events, start, count, bounded_selected, "TYPE", .kind, unicode);
}

const Row = enum { slot, m1, mreq, iorq, rd, wr, rfsh, address, data, kind };

fn renderSlots(frame: *Frame, rect: Rect, events: *const trace.TraceBuffer, start: usize, count: usize, selected_index: usize, label: []const u8, row: Row, unicode: bool) void {
    const y = rect.y + 2 + @intFromEnum(row);
    if (y >= rect.y + rect.height - 1) return;
    frame.print(rect.x + 2, y, .{}, "{s:<5}", .{label});
    for (0..count) |offset| {
        const index = start + offset;
        const event = events.getPtr(index) orelse continue;
        const style = if (index == selected_index) selected else Style{};
        const x = rect.x + label_width + offset * slot_width;
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
