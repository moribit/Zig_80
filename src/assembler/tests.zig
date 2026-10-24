const std = @import("std");

test "relative branch assembly wraps logical addresses at FFFF" {
    var result = try assembler.assemble(std.testing.allocator, "org 0xffff\njr 0\n");
    defer result.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x18, 0xff }, result.bytes.items);
}

test "TUI assembles unsaved root buffer with the same includes as CLI" {
    var state = try AppState.init(std.testing.allocator, "tests/fixtures/include/root.asm", "include \"draw.inc\"\nld a,0x42\nhalt\n");
    defer state.deinit();
    state.assembly_io = std.testing.io;
    state.assemble();
    try std.testing.expect(state.assembly != null);
    var failure: assembler.FailureLocation = .{};
    var expected = try assembler.assembleSourceFile(std.testing.io, std.testing.allocator, "tests/fixtures/include/root.asm", state.source.text(), &failure);
    defer expected.deinit();
    try std.testing.expectEqualSlices(u8, expected.bytes.items, state.assembly.?.bytes.items);
    const bytes = state.assembly.?.bytes.items;
    try std.testing.expectEqualSlices(u8, &.{ 0x3e, 0x42, 0x76 }, bytes[bytes.len - 3 ..]);
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
const input = @import("../tui/terminal/input.zig");
const command = @import("../tui/command.zig");
const Layout = @import("../tui/layout.zig").Layout;
const AppState = @import("../tui/state.zig").AppState;
const ExecutionState = @import("../tui/state.zig").ExecutionState;
const PromptMode = @import("../tui/state.zig").PromptMode;
const DisplayScale = @import("../tui/state.zig").DisplayScale;
const bus_waveform = @import("../tui/bus_waveform.zig");
const Rect = @import("../tui/layout.zig").Rect;
const breakpoint = @import("../debugger/breakpoint.zig");
const DebugSession = @import("../debugger/session.zig").DebugSession;

test "file assembler resolves include incbin provenance diagnostics and cycles" {
    var failure: assembler.FailureLocation = .{};
    var assembled = try assembler.assembleFile(std.testing.io, std.testing.allocator, "tests/fixtures/include/root.asm", &failure);
    defer assembled.deinit();
    const expected = [_]u8{ 0x21, 0x00, 0xc0, 0x36, 0x18, 'A', 'B', '\n', 0x76 };
    try std.testing.expectEqualSlices(u8, &expected, assembled.bytes.items);
    try std.testing.expectEqual(@as(?u16, 0xc000), assembled.symbols.address("vram"));
    try std.testing.expectEqualStrings("draw", assembled.symbols.label(3).?);
    const included = assembled.source_map.sourceForAddress(3).?;
    try std.testing.expect(std.mem.endsWith(u8, included.file_path.?, "draw.inc"));
    try std.testing.expectEqual(@as(usize, 2), included.line);
    try std.testing.expectEqual(@as(?u16, 3), assembled.source_map.addressForSource(included.file_path, 2));

    var listing: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer listing.deinit();
    try assembler.writeListing(&assembled, &listing.writer);
    try std.testing.expect(std.mem.indexOf(u8, listing.writer.buffered(), "21 00 C0") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing.writer.buffered(), "ld hl,VRAM") != null);

    failure = .{};
    try std.testing.expectError(error.IncludeCycle, assembler.assembleFile(std.testing.io, std.testing.allocator, "tests/fixtures/include/cycle-a.asm", &failure));
    try std.testing.expect(std.mem.endsWith(u8, failure.file_path.?, "cycle-b.asm"));
    failure = .{};
    try std.testing.expectError(error.IncludeNotFound, assembler.assembleFile(std.testing.io, std.testing.allocator, "tests/fixtures/include/missing.asm", &failure));
    try std.testing.expectEqual(@as(usize, 1), failure.line);
    failure = .{};
    try std.testing.expectError(error.UndefinedSymbol, assembler.assembleFile(std.testing.io, std.testing.allocator, "tests/fixtures/include/error.asm", &failure));
    try std.testing.expect(std.mem.endsWith(u8, failure.file_path.?, "error.inc"));
    try std.testing.expectEqual(@as(usize, 1), failure.line);
}
test "assembler directives labels forward references and numbers" {
    const source = "org 0\nVALUE equ 0x2A\n jr next\n db \"A\", 0b10\nnext:\n ld a, VALUE\n dw next\n halt\n";
    var result = try assembler.assemble(std.testing.allocator, source);
    defer result.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x18, 0x02, 'A', 2, 0x3e, 0x2a, 4, 0, 0x76 }, result.bytes.items);
}
test "assembler errors" {
    try std.testing.expectError(error.DuplicateSymbol, assembler.assemble(std.testing.allocator, "x:\nx:\nhalt\n"));
    try std.testing.expectError(error.UndefinedSymbol, assembler.assemble(std.testing.allocator, "jp missing\n"));
    try std.testing.expectError(error.RelativeOutOfRange, assembler.assemble(std.testing.allocator, "jr far\norg 0x0200\nfar:\nhalt\n"));
}
