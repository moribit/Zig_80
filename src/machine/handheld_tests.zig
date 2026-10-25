const std = @import("std");
const Machine = @import("machine.zig").Machine;
const profile = @import("profile.zig");
const display = @import("display.zig");
const Banks = @import("banking.zig").Banks;

test "VFD pixel page layout dirty bounds snapshots and PBM export" {
    var frame: display.Vfd = .{};
    frame.setPixel(255, 63, true);
    try std.testing.expect(frame.pixel(255, 63));
    try std.testing.expectEqual(@as(u8, 128), frame.bytes[2047]);
    const rect = frame.takeDirty().?;
    try std.testing.expectEqual(@as(u16, 255), rect.x);
    try std.testing.expectEqual(@as(u16, 1), rect.width);
    try std.testing.expect(frame.dirty == null);
    frame.setPixel(256, 64, true);
    try std.testing.expect(frame.dirty == null);
    const snapshot = frame.snapshot();
    frame.clear();
    try std.testing.expect(!frame.pixel(255, 63));
    try std.testing.expectEqual(@as(u8, 128), snapshot[2047]);
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try frame.writePbm(&out.writer);
    try std.testing.expect(std.mem.startsWith(u8, out.written(), "P1\n256 64\n"));
}

test "bank mapping separates ROM RAM physical banks and logical boundaries" {
    var banks: Banks = .{};
    banks.rom[0][0x3fff] = 0x12;
    banks.rom[1][0] = 0x34;
    try std.testing.expectEqual(@as(u8, 0x12), banks.read(0x3fff));
    try std.testing.expectEqual(@as(u8, 0x34), banks.read(0x4000));
    banks.write(0, 0xff);
    try std.testing.expectEqual(@as(u8, 0), banks.read(0));
    banks.write(0x8000, 0x42);
    try banks.map(2, .{ .kind = .ram, .bank = 2 });
    try std.testing.expectEqual(@as(u8, 0), banks.read(0x8000));
    try banks.map(2, .{ .kind = .ram, .bank = 0 });
    try std.testing.expectEqual(@as(u8, 0x42), banks.read(0x8000));
    const before = banks.snapshot();
    try std.testing.expectError(error.InvalidBank, banks.map(4, .{ .kind = .rom, .bank = 0 }));
    try std.testing.expectError(error.InvalidBank, banks.map(1, .{ .kind = .rom, .bank = 4 }));
    try std.testing.expectEqualDeep(before, banks.snapshot());
}

test "handheld port display input banking and deterministic device ticks" {
    const config: profile.Config = .{ .kind = .handheld, .clock_hz = 1000, .frame_hz = 100, .timer_period = 8 };
    var machine = try Machine.init(config);
    try machine.load(&.{ 0, 0, 0, 0x76 });
    machine.bus.output(config.ports.display_address_low, 0xff);
    machine.bus.output(config.ports.display_address_high, 7);
    machine.bus.output(config.ports.display_data, 128);
    try std.testing.expect(machine.bus.devices.display.frame.pixel(255, 63));
    try std.testing.expectEqual(@as(u11, 0), machine.bus.devices.display.address);
    machine.setInput(0x11);
    try std.testing.expectEqual(@as(u8, 0x11), machine.bus.input(config.ports.input));
    try std.testing.expectEqual(@as(u8, 0xff), machine.bus.input(0xdead));
    machine.bus.output(config.ports.timer_control, 1);
    _ = try machine.step();
    _ = try machine.step();
    _ = try machine.step();
    try std.testing.expectEqual(@as(u64, 12), machine.cpu.total_t_states);
    try std.testing.expectEqual(@as(u16, 1), machine.bus.devices.timer_count);
    try std.testing.expectEqual(@as(u64, 1), machine.bus.devices.frames);
    try std.testing.expect(machine.bus.devices.timer_irq);
    machine.bus.output(config.ports.timer_control, 0x81);
    try std.testing.expect(!machine.bus.devices.timer_irq);
    machine.bus.output(config.ports.ram_bank, 3);
    machine.bus.write8(0x8000, 0x42);
    machine.bus.output(config.ports.ram_bank, 0);
    try std.testing.expectEqual(@as(u8, 0), machine.bus.read8(0x8000));
    machine.bus.output(config.ports.ram_bank, 3);
    try std.testing.expectEqual(@as(u8, 0x42), machine.bus.read8(0x8000));
    machine.bus.output(config.ports.ram_bank, 255); // ignored, no partial map
    try std.testing.expectEqual(@as(u8, 3), machine.bus.input(config.ports.ram_bank));
    machine.reset();
    try std.testing.expectEqual(profile.Kind.handheld, machine.config.kind);
    try std.testing.expectEqual(@as(u8, 0), machine.bus.read8(0x8000));
    try std.testing.expectEqual(@as(u64, 0), machine.bus.devices.frames);
}

test "machine profile configuration rejects duplicate ports and zero clock" {
    var config: profile.Config = .{ .kind = .handheld, .clock_hz = 0 };
    try std.testing.expectError(error.InvalidMachineConfig, Machine.init(config));
    config.clock_hz = 4_000_000;
    config.ports.input = config.ports.display_data;
    try std.testing.expectError(error.DuplicatePort, Machine.init(config));
}

test "timer interrupts wake HALT on the next instruction boundary" {
    var machine = try Machine.init(.{ .kind = .handheld, .timer_period = 16 });
    try machine.load(&.{ 0xfb, 0, 0x76 });
    machine.cpu.interrupt_mode = 1;
    machine.bus.output(machine.config.ports.timer_control, 1);
    _ = try machine.step(); // EI 4
    _ = try machine.step(); // NOP 4
    _ = try machine.step(); // HALT 4
    try std.testing.expect(machine.canWakeFromHalt());
    _ = try machine.step(); // idle 4, timer expires
    try std.testing.expectEqual(@as(u64, 3), machine.cpu.instruction_index);
    const accepted = try machine.step();
    try std.testing.expectEqual(@as(u16, 13), accepted.t_states);
    try std.testing.expectEqual(@as(u16, 0x38), machine.cpu.registers.pc);
    try std.testing.expect(!machine.cpu.halted);
}

test "real time pacing conversion preserves fractional T states across slices" {
    const Pacer = @import("clock.zig").Pacer;
    var pacer: Pacer = .{};
    var total: u64 = 0;
    for (0..1000) |_| total += pacer.budget(1_000_000, 3_579_545);
    try std.testing.expectEqual(@as(u64, 3_579_545), total);
    try std.testing.expectEqual(@as(u64, 0), pacer.remainder);
}

test "configurable input ports latch press and release IRQ and acknowledge explicitly" {
    var config: profile.Config = .{ .kind = .handheld };
    config.ports.input = 0x70;
    config.ports.input_control = 0x71;
    var machine = try Machine.init(config);
    machine.bus.output(0x1271, 1);
    machine.setInput(0x11);
    try std.testing.expectEqual(@as(u8, 0x11), machine.bus.input(0xff70));
    try std.testing.expectEqual(@as(u8, 0xff), machine.bus.input(0x10));
    try std.testing.expect(machine.bus.devices.input_irq);
    machine.bus.output(0x71, 0x81);
    try std.testing.expect(!machine.bus.devices.input_irq);
    machine.setInput(0);
    try std.testing.expect(machine.bus.devices.input_irq);
}

test "ROM bank loading clears tails and invalid loads preserve state" {
    var machine = try Machine.init(.{ .kind = .handheld });
    try machine.loadRomBank(2, &.{ 1, 2, 3 });
    try machine.loadRomBank(2, &.{0x42});
    try std.testing.expectEqual(@as(u8, 0), machine.bus.banks.rom[2][1]);
    try std.testing.expectError(error.InvalidBank, machine.loadRomBank(4, &.{0}));
    try std.testing.expectEqual(@as(u8, 0x42), machine.bus.banks.rom[2][0]);
    machine.reset();
    try std.testing.expectEqual(@as(u8, 0x42), machine.bus.banks.rom[2][0]);
}

fn runSample(name: []const u8, input_text: []const u8) !Machine {
    const assembler = @import("../assembler/assembler.zig");
    const input = @import("input.zig");
    var failure: assembler.FailureLocation = .{};
    var assembled = try assembler.assembleFile(std.testing.io, std.testing.allocator, name, &failure);
    defer assembled.deinit();
    const events = try input.parseScript(std.testing.allocator, input_text);
    defer std.testing.allocator.free(events);
    var replay: input.Replay = .{ .events = events };
    var machine = try Machine.init(.{ .kind = .handheld });
    try machine.load(assembled.bytes.items);
    try machine.loadRomBank(2, &.{0x5a});
    for (0..100_000) |_| {
        machine.setInput(replay.advance(machine.cpu.instruction_index).value);
        _ = try machine.step();
        if (machine.cpu.halted) return machine;
    }
    return error.SampleDidNotHalt;
}

test "all handheld samples run headlessly and assert peripheral results" {
    const pixel = try runSample("examples/handheld/pixel.asm", "");
    try std.testing.expect(pixel.displayPixel(0, 0));
    const moving = try runSample("examples/handheld/moving.asm", "");
    try std.testing.expect(!moving.displayPixel(0, 0));
    try std.testing.expect(moving.displayPixel(1, 0));
    const buttons = try runSample("examples/handheld/buttons.asm", "0 press a\n0 press left\n");
    try std.testing.expectEqual(@as(u8, 1), buttons.bus.read8(0x8000));
    const timer = try runSample("examples/handheld/timer.asm", "");
    try std.testing.expectEqual(@as(u8, 3), timer.bus.read8(0x8000));
    const interrupt = try runSample("examples/handheld/interrupt.asm", "");
    try std.testing.expectEqual(@as(u8, 3), interrupt.bus.read8(0x8000));
    const banks = try runSample("examples/handheld/banking.asm", "");
    try std.testing.expectEqual(@as(u8, 0x11), banks.bus.read8(0xc001));
    try std.testing.expectEqual(@as(u8, 0x5a), banks.bus.read8(0xc000));
    try std.testing.expectEqual(@as(u8, 0x22), banks.bus.banks.ram[2][0]);
}

test "identical replay produces identical machine snapshots and ordered trace" {
    const input = @import("input.zig");
    const trace = @import("../trace/trace.zig");
    const snapshot = @import("snapshot.zig");
    const events = try input.parseScript(std.testing.allocator, "0 press a\n2 release a\n2 press b\n");
    defer std.testing.allocator.free(events);
    var outputs: [2]std.Io.Writer.Allocating = .{ .init(std.testing.allocator), .init(std.testing.allocator) };
    defer for (&outputs) |*out| out.deinit();
    for (&outputs) |*out| {
        var machine = try Machine.init(.{ .kind = .handheld });
        try machine.load(&.{ 0xdb, 0x10, 0x32, 0, 0x80, 0x76 });
        var captured: trace.TraceBuffer = .{};
        machine.bus.trace_sink = captured.sink();
        var replay: input.Replay = .{ .events = events };
        while (!machine.cpu.halted) {
            machine.setInput(replay.advance(machine.cpu.instruction_index).value);
            _ = try machine.step();
        }
        try snapshot.write(&machine, events, &captured, &out.writer);
    }
    try std.testing.expectEqualSlices(u8, outputs[0].written(), outputs[1].written());
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, outputs[0].written(), .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("logical-instruction", parsed.value.object.get("trace_accuracy").?.string);
    try std.testing.expectEqual(@as(usize, 65536), parsed.value.object.get("memory").?.array.items.len);
    try std.testing.expectEqual(@as(usize, 2048), parsed.value.object.get("display").?.object.get("bytes").?.array.items.len);
}

test "TUI and headless share handheld execution and VFD rendering" {
    const AppState = @import("../tui/state.zig").AppState;
    const Frame = @import("../tui/render/frame.zig").Frame;
    const app = @import("../tui/app.zig");
    var state = try AppState.init(std.testing.allocator, null, "ld a,1\nout (0x42),a\nhalt\n");
    defer state.deinit();
    state.machine = try Machine.init(.{ .kind = .handheld });
    state.attachTrace();
    state.assemble();
    state.step();
    state.step();
    state.step();
    try std.testing.expect(state.machine.displayPixel(0, 0));
    try std.testing.expectEqual(@as(u16, 1), state.display_changed_pixels);
    var frame = try Frame.init(std.testing.allocator, 100, 40);
    defer frame.deinit();
    state.active_screen = .display;
    app.renderDisplay(&state, &frame, .{ .x = 0, .y = 0, .width = 100, .height = 40 });
    try std.testing.expectEqual(@as(u21, '2'), frame.get(2, 1).codepoint);
}
