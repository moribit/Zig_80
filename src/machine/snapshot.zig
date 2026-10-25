const std = @import("std");
const Machine = @import("machine.zig").Machine;
const input = @import("input.zig");
const trace = @import("../trace/trace.zig");

const Bytes = struct {
    data: []const u8,
    pub fn jsonStringify(self: Bytes, writer: anytype) !void {
        try writer.beginArray();
        for (self.data) |value| try writer.write(value);
        try writer.endArray();
    }
};
const BankArrays = struct {
    data: []const [0x4000]u8,
    pub fn jsonStringify(self: BankArrays, writer: anytype) !void {
        try writer.beginArray();
        for (self.data) |*bank| try writer.write(Bytes{ .data = bank });
        try writer.endArray();
    }
};

/// Versioned export, independent of Zig struct layout and host byte order.
/// This is an inspection format, not yet a restore protocol.
pub fn write(machine: *const Machine, events: []const input.Event, captured: *const trace.TraceBuffer, writer: *std.Io.Writer) !void {
    var memory: [65536]u8 = undefined;
    for (0..memory.len) |i| memory[i] = machine.bus.read8(@intCast(i));
    var ordered: [4096]trace.BusEvent = undefined;
    for (0..captured.len) |i| ordered[i] = captured.get(i).?;
    try std.json.Stringify.value(.{
        .schema = "zig80.snapshot",
        .version = @as(u8, 1),
        .profile = machine.config,
        .cpu = machine.cpu,
        .memory_address_space = "logical-16bit",
        .memory = Bytes{ .data = &memory },
        .banks = machine.bus.banks.snapshot(),
        .physical_rom = BankArrays{ .data = if (machine.config.kind == .handheld) machine.bus.banks.rom[0..machine.config.rom_banks] else &.{} },
        .physical_ram = BankArrays{ .data = if (machine.config.kind == .handheld) machine.bus.banks.ram[0..machine.config.ram_banks] else &.{} },
        .display = .{ .width = machine.displayWidth(), .height = @as(u8, 64), .layout = "page-y8-lsb-top", .bytes = Bytes{ .data = machine.displayBytes() } },
        .devices = .{
            .input = machine.bus.devices.input,
            .input_irq_enabled = machine.bus.devices.input_irq_enabled,
            .input_irq = machine.bus.devices.input_irq,
            .timer_enabled = machine.bus.devices.timer_enabled,
            .timer_period = machine.bus.devices.config.timer_period,
            .timer_phase = machine.bus.devices.timer_phase,
            .timer_count = machine.bus.devices.timer_count,
            .timer_irq = machine.bus.devices.timer_irq,
            .frame_phase = machine.bus.devices.frame_phase,
            .frames = machine.bus.devices.frames,
            .display_address = machine.bus.devices.display.address,
        },
        .classic_frame_counter = machine.frame_counter,
        .classic_random_state = machine.random_state,
        .trace_accuracy = "logical-instruction",
        .trace_capacity = @as(usize, 4096),
        .trace_first_sequence = if (captured.len > 0) ordered[0].sequence else machine.bus.trace_sequence,
        .trace_next_sequence = machine.bus.trace_sequence,
        .trace = ordered[0..captured.len],
        .input_clock = "instruction-index-before-execution",
        .input_initial_state = @as(u8, 0),
        .input_events = events,
    }, .{}, writer);
    try writer.writeAll("\n");
}
