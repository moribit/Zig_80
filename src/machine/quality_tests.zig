const std = @import("std");
const Machine = @import("machine.zig").Machine;
const input = @import("input.zig");
const memory = @import("memory.zig");

test "loading a shorter program clears previous program RAM and peripheral state" {
    var machine: Machine = .{};
    try machine.load(&.{ 0x3e, 0x42, 0x76 });
    machine.bus.memory[0x8000] = 0x99;
    machine.bus.memory[memory.vram_start] = 0xff;
    machine.setInput(0x11);
    machine.tickFrame();
    try machine.load(&.{0x76});
    try std.testing.expectEqual(@as(u8, 0), machine.bus.read8(1));
    try std.testing.expectEqual(@as(u8, 0), machine.bus.read8(0x8000));
    try std.testing.expectEqual(@as(u8, 0), machine.bus.read8(memory.vram_start));
    try std.testing.expectEqual(@as(u8, 0), machine.bus.read8(memory.input_address));
    try std.testing.expectEqual(@as(u16, 0xace1), machine.random_state);
    try std.testing.expectEqual(@as(u16, 0), machine.frame_counter);
}

test "equal timestamp replay preserves source order across many events" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(std.testing.allocator);
    for (0..40) |_| try text.appendSlice(std.testing.allocator, "0 press a\n0 release a\n");
    const events = try input.parseScript(std.testing.allocator, text.items);
    defer std.testing.allocator.free(events);
    for (events, 0..) |event, index| try std.testing.expectEqual(if (index % 2 == 0) input.Action.press else input.Action.release, event.action);
    var replay: input.Replay = .{ .events = events };
    try std.testing.expectEqual(@as(u8, 0), replay.advance(0).value);
}

test "reset contracts preserve ROM and separate CPU from peripheral reset" {
    var machine: Machine = .{};
    try machine.load(&.{0x76});
    machine.bus.memory[0x8000] = 0x12;
    machine.setInput(0x20);
    machine.tickFrame();
    machine.cpu.registers.a = 0x42;
    machine.resetCpu();
    try std.testing.expectEqual(@as(u8, 0), machine.cpu.registers.a);
    try std.testing.expectEqual(@as(u8, 0x12), machine.bus.read8(0x8000));
    try std.testing.expectEqual(@as(u8, 0x20), machine.bus.read8(memory.input_address));
    machine.cpu.registers.a = 0x42;
    machine.resetPeripherals();
    try std.testing.expectEqual(@as(u8, 0x42), machine.cpu.registers.a);
    try std.testing.expectEqual(@as(u16, 0xace1), machine.random_state);
    machine.reset();
    try std.testing.expectEqual(@as(u8, 0x76), machine.bus.read8(0));
    try std.testing.expectEqual(@as(u8, 0), machine.bus.read8(0x8000));
    const before = machine;
    const oversized: [0x8001]u8 = @splat(0);
    try std.testing.expectError(error.ProgramTooLarge, machine.load(&oversized));
    try std.testing.expectEqualDeep(before, machine);
    machine.powerOn();
    try std.testing.expectEqual(@as(u8, 0), machine.bus.read8(0));
}

test "replay reset and rewind restore explicit initial state deterministically" {
    const events = [_]input.Event{
        .{ .at_instruction = 0, .action = .press, .button = .a },
        .{ .at_instruction = 0, .action = .release, .button = .a },
        .{ .at_instruction = 3, .action = .press, .button = .b },
    };
    var replay: input.Replay = .{ .events = &events, .initial_state = .{ .value = input.Start } };
    try std.testing.expectEqual(input.Start, replay.advance(0).value);
    try std.testing.expectEqual(input.Start | input.B, replay.advance(3).value);
    try std.testing.expectEqual(input.Start, replay.advance(0).value);
    replay.reset();
    try std.testing.expectEqual(input.Start, replay.state.value);
    try std.testing.expectEqual(input.Start | input.B, replay.advance(3).value);
}

test "input diagnostics identify line column and error" {
    var diagnostic: input.ScriptDiagnostic = .{};
    try std.testing.expectError(error.InvalidInputAction, input.parseScriptLocated(std.testing.allocator, "# input\n12 explode a\n", &diagnostic));
    try std.testing.expectEqual(@as(usize, 2), diagnostic.line);
    try std.testing.expectEqual(@as(usize, 4), diagnostic.column);
    try std.testing.expectError(error.InvalidInputTimestamp, input.parseScriptLocated(std.testing.allocator, "-1 press a", &diagnostic));
    try std.testing.expectError(error.InvalidInputButton, input.parseScriptLocated(std.testing.allocator, "0 press fire", &diagnostic));
    try std.testing.expectError(error.InvalidInputEvent, input.parseScriptLocated(std.testing.allocator, "0 press a extra", &diagnostic));
}
