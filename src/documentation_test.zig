const std = @import("std");
const assembler = @import("assembler/assembler.zig");
const instruction = @import("cpu/instruction.zig");
const memory = @import("machine/memory.zig");
const machine_input = @import("machine/input.zig");
const command = @import("tui/command.zig");

const tutorial_en_paths = [_][]const u8{
    "docs/tutorial/00-introduction.md",
    "docs/tutorial/01-cpu.md",
    "docs/tutorial/02-register.md",
    "docs/tutorial/03-memory.md",
    "docs/tutorial/04-branch.md",
    "docs/tutorial/05-stack.md",
    "docs/tutorial/06-display.md",
    "docs/tutorial/07-bus.md",
    "docs/tutorial/08-projects.md",
};

const tutorial_ja_paths = [_][]const u8{
    "docs/tutorial/00-introduction.ja.md",
    "docs/tutorial/01-cpu.ja.md",
    "docs/tutorial/02-register.ja.md",
    "docs/tutorial/03-memory.ja.md",
    "docs/tutorial/04-branch.ja.md",
    "docs/tutorial/05-stack.ja.md",
    "docs/tutorial/06-display.ja.md",
    "docs/tutorial/07-bus.ja.md",
    "docs/tutorial/08-projects.ja.md",
};

const documentation_paths = [_][]const u8{
    "README.md",
    "README.ja.md",
    "docs/README.md",
    "docs/README.ja.md",
    "docs/tutorial.md",
    "docs/tutorial.ja.md",
    "docs/tui.md",
    "docs/tui.ja.md",
    "docs/vision.md",
    "docs/vision.ja.md",
    "docs/roadmap.md",
    "docs/style-guide.md",
    "docs/style-guide.ja.md",
    "docs/web-documentation.md",
    "docs/tutorial/README.md",
    "docs/tutorial/README.ja.md",
} ++ tutorial_en_paths ++ tutorial_ja_paths ++ [_][]const u8{
    "docs/reference/README.md",
    "docs/reference/README.ja.md",
    "docs/reference/cli.md",
    "docs/reference/cli.ja.md",
    "docs/reference/assembler.md",
    "docs/reference/assembler.ja.md",
    "docs/reference/instructions.md",
    "docs/reference/instructions.ja.md",
    "docs/reference/debugger.md",
    "docs/reference/debugger.ja.md",
    "docs/reference/machine.md",
    "docs/reference/machine.ja.md",
    "docs/reference/keybindings.md",
    "docs/reference/keybindings.ja.md",
    "docs/guides/README.md",
    "docs/guides/README.ja.md",
    "docs/guides/game-development.md",
    "docs/guides/game-development.ja.md",
    "docs/guides/display.md",
    "docs/guides/display.ja.md",
    "docs/guides/input.md",
    "docs/guides/input.ja.md",
    "docs/guides/debugging.md",
    "docs/guides/debugging.ja.md",
    "docs/guides/profiling.md",
    "docs/guides/profiling.ja.md",
    "docs/guides/assets.md",
    "docs/guides/assets.ja.md",
    "docs/guides/hardware-basics.md",
    "docs/guides/hardware-basics.ja.md",
    "docs/architecture/README.md",
    "docs/architecture/README.ja.md",
    "docs/architecture/core.md",
    "docs/architecture/core.ja.md",
    "docs/architecture/hardware-target.md",
    "docs/architecture/hardware-target.ja.md",
};

fn read(path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(1024 * 1024));
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("documentation is missing expected text: {s}\n", .{needle});
        return error.TestExpectedEqual;
    }
}

fn checkLocalLinks(path: []const u8, contents: []const u8) !void {
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, contents, offset, "](")) |marker| {
        const target_start = marker + 2;
        const target_end = std.mem.indexOfScalarPos(u8, contents, target_start, ')') orelse return error.InvalidMarkdownLink;
        offset = target_end + 1;
        var target = contents[target_start..target_end];
        if (target.len == 0 or target[0] == '#' or std.mem.startsWith(u8, target, "http://") or std.mem.startsWith(u8, target, "https://") or std.mem.startsWith(u8, target, "mailto:")) continue;
        if (std.mem.indexOfScalar(u8, target, '#')) |fragment| target = target[0..fragment];
        const directory = std.fs.path.dirname(path) orelse ".";
        const resolved = try std.fs.path.join(std.testing.allocator, &.{ directory, target });
        defer std.testing.allocator.free(resolved);
        std.Io.Dir.cwd().access(std.testing.io, resolved, .{}) catch |err| {
            std.debug.print("broken local documentation link: {s} -> {s}\n", .{ path, target });
            return err;
        };
    }
}

test "all canonical Markdown local links resolve" {
    for (documentation_paths) |path| {
        const contents = try read(path);
        defer std.testing.allocator.free(contents);
        try checkLocalLinks(path, contents);
    }
}

test "documentation bilingual tutorial structure and links stay aligned" {
    try std.testing.expectEqual(tutorial_en_paths.len, tutorial_ja_paths.len);
    const en_index = try read("docs/tutorial/README.md");
    defer std.testing.allocator.free(en_index);
    const ja_index = try read("docs/tutorial/README.ja.md");
    defer std.testing.allocator.free(ja_index);
    for (tutorial_en_paths, tutorial_ja_paths, 0..) |en_path, ja_path, index| {
        var name_buffer: [32]u8 = undefined;
        const prefix = try std.fmt.bufPrint(&name_buffer, "{d:0>2}-", .{index});
        try expectContains(en_index, prefix);
        try expectContains(ja_index, prefix);
        const en = try read(en_path);
        defer std.testing.allocator.free(en);
        const ja = try read(ja_path);
        defer std.testing.allocator.free(ja);
        try expectContains(en, "## Challenge");
        try expectContains(ja, "## Challenge");
    }

    const projects_en = try read("docs/tutorial/08-projects.md");
    defer std.testing.allocator.free(projects_en);
    const projects_ja = try read("docs/tutorial/08-projects.ja.md");
    defer std.testing.allocator.free(projects_ja);
    for ([_][]const u8{ "pinpon.asm", "game_of_life.asm" }) |example| {
        try expectContains(projects_en, example);
        try expectContains(projects_ja, example);
    }

    // Reading each index catches missing top-level documentation structures.
    for ([_][]const u8{
        "docs/reference/README.md",
        "docs/reference/README.ja.md",
        "docs/guides/README.md",
        "docs/guides/README.ja.md",
        "docs/architecture/README.md",
        "docs/architecture/README.ja.md",
    }) |path| {
        const contents = try read(path);
        std.testing.allocator.free(contents);
    }
}

test "documentation assembly starters solutions and linked examples assemble" {
    for ([_][]const u8{
        "docs/tutorial/starters/counter.asm",
        "docs/tutorial/solutions/counter.asm",
        "docs/tutorial/starters/pixel.asm",
        "docs/tutorial/solutions/pixel.asm",
        "examples/halt.asm",
        "examples/add.asm",
        "examples/pixel.asm",
        "examples/moving_pixel.asm",
        "examples/pinpon.asm",
        "examples/game_of_life.asm",
    }) |path| {
        const source = try read(path);
        defer std.testing.allocator.free(source);
        var assembled = try assembler.assemble(std.testing.allocator, source);
        assembled.deinit();
    }
}

test "documented commands key bindings and machine map match implementation" {
    const main_source = try read("src/main.zig");
    defer std.testing.allocator.free(main_source);
    const cli_reference = try read("docs/reference/cli.md");
    defer std.testing.allocator.free(cli_reference);
    for ([_][]const u8{ "asm", "run", "debug", "disasm", "test", "explain", "tui" }) |name| {
        var command_buffer: [32]u8 = undefined;
        const invocation = try std.fmt.bufPrint(&command_buffer, "zig80 {s}", .{name});
        try expectContains(main_source, invocation);
        try expectContains(cli_reference, invocation);
    }

    const key_reference = try read("docs/reference/keybindings.md");
    defer std.testing.allocator.free(key_reference);
    const Binding = struct { character: u21, label: []const u8, expected: std.meta.Tag(command.Command) };
    const bindings = [_]Binding{
        .{ .character = 's', .label = "Ctrl+S", .expected = .save },
        .{ .character = 'q', .label = "Ctrl+Q", .expected = .quit },
        .{ .character = 'r', .label = "Ctrl+R", .expected = .assemble },
        .{ .character = 'e', .label = "Ctrl+E", .expected = .run },
        .{ .character = 't', .label = "Ctrl+T", .expected = .step_instruction },
        .{ .character = 'b', .label = "Ctrl+B", .expected = .toggle_breakpoint },
        .{ .character = 'p', .label = "Ctrl+P", .expected = .open_palette },
        .{ .character = 'f', .label = "Ctrl+F", .expected = .search },
    };
    for (bindings) |binding| {
        try expectContains(key_reference, binding.label);
        try std.testing.expectEqual(binding.expected, std.meta.activeTag(command.map(.{ .code = .{ .character = binding.character }, .ctrl = true })));
    }

    const machine_reference = try read("docs/reference/machine.md");
    defer std.testing.allocator.free(machine_reference);
    try std.testing.expectEqual(@as(u16, 0x8000), memory.ram_start);
    try std.testing.expectEqual(@as(u16, 0xc000), memory.vram_start);
    try std.testing.expectEqual(@as(u16, 0xc3ff), memory.vram_end);
    try std.testing.expectEqual(@as(u16, 0xc400), memory.input_address);
    for ([_][]const u8{ "0000-7FFF", "8000-BFFF", "C000-C3FF", "C400", "C401-C402", "C403", "C404-FFFF" }) |range| try expectContains(machine_reference, range);
    try std.testing.expectEqual(@as(u8, 0x01), machine_input.Up);
    try std.testing.expectEqual(@as(u8, 0x40), machine_input.Start);
}

test "instruction reference contains shared metadata families" {
    const reference = try read("docs/reference/instructions.md");
    defer std.testing.allocator.free(reference);
    for (instruction.fixed) |definition| try expectContains(reference, definition.mnemonic);
    for (instruction.assembler_mnemonics) |mnemonic| try expectContains(reference, mnemonic);
    for (instruction.logic_families) |family| {
        try expectContains(reference, family.mnemonic);
        const register_decoded = instruction.logicByOpcode(family.register_base).?;
        try std.testing.expectEqual(family.register_base, register_decoded.family.register_base);
        const immediate_decoded = instruction.logicByOpcode(family.immediate_opcode).?;
        try std.testing.expect(immediate_decoded.register_code == null);
    }
    try expectContains(reference, "LD r,r");
    try expectContains(reference, "LD r,(HL)");
    try expectContains(reference, "LD (HL),r");
}
