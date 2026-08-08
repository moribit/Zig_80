const std = @import("std");
const Io = std.Io;
const assembler = @import("assembler/assembler.zig");
const diagnostics = @import("assembler/diagnostics.zig");
const disassembler = @import("disassembler/disassembler.zig");
const Machine = @import("machine/machine.zig").Machine;
const video = @import("machine/video.zig");
const debugger = @import("debugger/debugger.zig");
const TuiState = @import("tui/state.zig").AppState;
const tui_event_loop = @import("tui/event_loop.zig");
const machine_input = @import("machine/input.zig");

const usage =
    \\Zig_80 - integrated Z80 development environment
    \\
    \\Usage:
    \\  zig80 asm <source.asm> -o <output.bin> [--symbols FILE] [--source-map FILE] [--listing FILE]
    \\  zig80 run <program.bin> [--max-instructions N] [--max-cycles N] [--input-script FILE] [--screen]
    \\  zig80 debug <program.bin>
    \\  zig80 disasm <program.bin>
    \\  zig80 test <program.bin>
    \\  zig80 explain <source.asm>
    \\  zig80 tui [source.asm]
    \\  zig80 --help
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    var out_buf: [4096]u8 = undefined;
    var out_writer = Io.File.stdout().writer(io, &out_buf);
    const out = &out_writer.interface;
    var err_buf: [1024]u8 = undefined;
    var err_writer = Io.File.stderr().writer(io, &err_buf);
    const errout = &err_writer.interface;
    defer out.flush() catch {};
    defer errout.flush() catch {};
    if (args.len < 2 or std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        try out.writeAll(usage);
        return;
    }
    const command = args[1];
    if (std.mem.eql(u8, command, "asm")) try asmCommand(io, allocator, args[2..], out, errout) else if (std.mem.eql(u8, command, "run")) try runCommand(io, allocator, args[2..], out) else if (std.mem.eql(u8, command, "disasm")) try disasmCommand(io, allocator, args[2..], out) else if (std.mem.eql(u8, command, "debug")) try debugCommand(io, allocator, args[2..], out) else if (std.mem.eql(u8, command, "test")) try testCommand(io, allocator, args[2..], out) else if (std.mem.eql(u8, command, "explain")) try explainCommand(io, allocator, args[2..], out) else if (std.mem.eql(u8, command, "tui")) try tuiCommand(io, allocator, args[2..], out, errout, init.environ_map) else {
        try errout.print("unknown command: {s}\n\n{s}", .{ command, usage });
        return error.InvalidCommand;
    }
}

fn tuiCommand(io: Io, allocator: std.mem.Allocator, args: []const []const u8, out: *Io.Writer, errout: *Io.Writer, environ: *std.process.Environ.Map) !void {
    if (args.len > 1) {
        try errout.writeAll("usage: zig80 tui [source.asm]\n");
        return error.InvalidArguments;
    }
    if (!try Io.File.stdin().isTty(io) or !try Io.File.stdout().isTty(io)) {
        try errout.writeAll("error: `zig80 tui` requires an interactive stdin and stdout TTY\n");
        try errout.flush();
        std.process.exit(1);
    }
    const path: ?[]const u8 = if (args.len == 1) args[0] else null;
    const source = if (path) |value| try Io.Dir.cwd().readFileAlloc(io, value, allocator, .limited(1024 * 1024)) else "";
    var state = try TuiState.init(allocator, path, source);
    defer state.deinit();
    state.attachTrace();
    const locale = environ.get("LC_ALL") orelse environ.get("LC_CTYPE") orelse environ.get("LANG") orelse "";
    state.unicode_ui = std.mem.indexOf(u8, locale, "UTF-8") != null or std.mem.indexOf(u8, locale, "utf-8") != null or std.mem.indexOf(u8, locale, "UTF8") != null or std.mem.indexOf(u8, locale, "utf8") != null;
    out.flush() catch {};
    errout.flush() catch {};
    const color = environ.get("NO_COLOR") == null and !(if (environ.get("TERM")) |term| std.mem.eql(u8, term, "dumb") else false);
    state.color_ui = color;
    tui_event_loop.run(io, allocator, &state, color) catch |err| switch (err) {
        error.NotATerminal => {
            try errout.writeAll("error: `zig80 tui` requires an interactive stdin and stdout TTY\n");
            return;
        },
        else => return err,
    };
}

fn readFile(io: Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(65536));
}

fn asmCommand(io: Io, allocator: std.mem.Allocator, args: []const []const u8, out: *Io.Writer, errout: *Io.Writer) !void {
    if (args.len < 3) {
        try errout.writeAll("usage: zig80 asm <source.asm> -o <output.bin> [--symbols FILE] [--source-map FILE] [--listing FILE]\n");
        return error.InvalidArguments;
    }
    var output_path: ?[]const u8 = null;
    var symbols_path: ?[]const u8 = null;
    var source_map_path: ?[]const u8 = null;
    var listing_path: ?[]const u8 = null;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const option = args[index];
        if (index + 1 >= args.len) return error.InvalidArguments;
        index += 1;
        if (std.mem.eql(u8, option, "-o")) output_path = args[index] else if (std.mem.eql(u8, option, "--symbols")) symbols_path = args[index] else if (std.mem.eql(u8, option, "--source-map")) source_map_path = args[index] else if (std.mem.eql(u8, option, "--listing")) listing_path = args[index] else return error.InvalidArguments;
    }
    const binary_path = output_path orelse return error.InvalidArguments;
    var failure: assembler.FailureLocation = .{};
    var assembled = assembler.assembleFile(io, allocator, args[0], &failure) catch |e| {
        const diagnostic = diagnostics.fromFailure(failure, args[0]);
        try errout.print("{s}:{d}:{d}: error: {s}\n", .{ diagnostic.file_path orelse args[0], diagnostic.line orelse 0, diagnostic.column orelse 0, diagnostic.message });
        if (diagnostic.source_line) |line| {
            try errout.print("    {s}\n    ", .{line});
            for (1..diagnostic.column orelse 1) |_| try errout.writeByte(' ');
            try errout.writeAll("^\n");
        }
        if (diagnostic.hint) |hint| try errout.print("hint: {s}\n", .{hint});
        return e;
    };
    defer assembled.deinit();
    const file = try Io.Dir.cwd().createFile(io, binary_path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, assembled.bytes.items);
    try out.print("assembled {d} bytes -> {s}\n", .{ assembled.bytes.items.len, binary_path });
    if (assembled.symbols.items.items.len > 0) {
        try out.writeAll("symbols:\n");
        for (assembled.symbols.items.items) |s| try out.print("  {s} = 0x{X:0>4}\n", .{ s.name, s.value });
    }
    if (symbols_path) |path| {
        const symbol_file = try Io.Dir.cwd().createFile(io, path, .{});
        defer symbol_file.close(io);
        var buffer: [4096]u8 = undefined;
        var writer = symbol_file.writer(io, &buffer);
        try assembled.symbols.write(&writer.interface);
        try writer.interface.flush();
    }
    if (source_map_path) |path| {
        const map_file = try Io.Dir.cwd().createFile(io, path, .{});
        defer map_file.close(io);
        var buffer: [4096]u8 = undefined;
        var writer = map_file.writer(io, &buffer);
        try assembled.source_map.write(&writer.interface);
        try writer.interface.flush();
    }
    if (listing_path) |path| {
        const listing_file = try Io.Dir.cwd().createFile(io, path, .{});
        defer listing_file.close(io);
        var buffer: [4096]u8 = undefined;
        var writer = listing_file.writer(io, &buffer);
        try assembler.writeListing(&assembled, &writer.interface);
        try writer.interface.flush();
    }
}

fn runCommand(io: Io, allocator: std.mem.Allocator, args: []const []const u8, out: *Io.Writer) !void {
    if (args.len < 1) {
        try out.writeAll("usage: zig80 run <program.bin> [--max-instructions N] [--max-cycles N] [--input-script FILE] [--screen]\n");
        return error.InvalidArguments;
    }
    const data = try readFile(io, allocator, args[0]);
    var max_instructions: usize = 1_000_000;
    var max_cycles: u64 = 10_000_000;
    var screen = false;
    var input_events: []machine_input.Event = &.{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--screen")) screen = true else if (std.mem.eql(u8, args[i], "--max-instructions") and i + 1 < args.len) {
            i += 1;
            max_instructions = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--max-cycles") and i + 1 < args.len) {
            i += 1;
            max_cycles = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--input-script") and i + 1 < args.len) {
            i += 1;
            const input_source = try Io.Dir.cwd().readFileAlloc(io, args[i], allocator, .limited(1024 * 1024));
            input_events = try machine_input.parseScript(allocator, input_source);
        } else return error.InvalidArguments;
    }
    var machine = Machine{};
    try machine.load(data);
    var count: usize = 0;
    var cycles: u64 = 0;
    var reason: []const u8 = "instruction limit";
    var replay = machine_input.Replay{ .events = input_events };
    while (count < max_instructions and cycles < max_cycles) {
        machine.setInput(replay.advance(count).value);
        const step = machine.cpu.step(&machine.bus) catch |e| {
            try out.print("unknown opcode 0x{X:0>2} at PC=0x{X:0>4}\n", .{ machine.cpu.last_unknown_opcode, machine.cpu.last_unknown_pc });
            return e;
        };
        count += 1;
        cycles += step.t_states;
        if (step.halted) {
            reason = "HALT";
            break;
        }
    }
    if (cycles >= max_cycles) reason = "cycle limit";
    try out.print("stopped: {s}; instructions={d}, T-states={d}, PC=0x{X:0>4}\n", .{ reason, count, cycles, machine.cpu.registers.pc });
    if (screen) try video.render(&machine.bus, out);
}

fn disasmCommand(io: Io, allocator: std.mem.Allocator, args: []const []const u8, out: *Io.Writer) !void {
    if (args.len != 1) return error.InvalidArguments;
    const data = try readFile(io, allocator, args[0]);
    var address: usize = 0;
    while (address < data.len) {
        const d = disassembler.decode(data, @intCast(address));
        try out.print("{X:0>4}  ", .{address});
        for (0..3) |j| if (j < d.size) try out.print("{X:0>2} ", .{d.bytes[j]}) else try out.writeAll("   ");
        try out.print("  {s}\n", .{disassembler.text(&d)});
        address += d.size;
    }
}

fn debugCommand(io: Io, allocator: std.mem.Allocator, args: []const []const u8, out: *Io.Writer) !void {
    if (args.len != 1) return error.InvalidArguments;
    const data = try readFile(io, allocator, args[0]);
    var machine = Machine{};
    try machine.load(data);
    var in_buf: [1024]u8 = undefined;
    var in_reader = Io.File.stdin().reader(io, &in_buf);
    try debugger.repl(&machine, data, &in_reader.interface, out);
}

fn testCommand(io: Io, allocator: std.mem.Allocator, args: []const []const u8, out: *Io.Writer) !void {
    if (args.len != 1) return error.InvalidArguments;
    const data = try readFile(io, allocator, args[0]);
    var machine = Machine{};
    try machine.load(data);
    var n: usize = 0;
    while (!machine.cpu.halted and n < 100_000) : (n += 1) _ = try machine.cpu.step(&machine.bus);
    if (!machine.cpu.halted) {
        try out.print("FAIL {s}: did not HALT\n", .{args[0]});
        return error.TestFailed;
    }
    try out.print("PASS {s} ({d} instructions)\n", .{ args[0], n });
}

fn explainCommand(io: Io, allocator: std.mem.Allocator, args: []const []const u8, out: *Io.Writer) !void {
    if (args.len != 1) return error.InvalidArguments;
    const source = try Io.Dir.cwd().readFileAlloc(io, args[0], allocator, .limited(1024 * 1024));
    var assembled = try assembler.assemble(allocator, source);
    defer assembled.deinit();
    try out.print("{s}: {d} output bytes\n", .{ args[0], assembled.bytes.items.len });
    var address: usize = 0;
    while (address < assembled.bytes.items.len) {
        const d = disassembler.decode(assembled.bytes.items, @intCast(address));
        try out.print("0x{X:0>4}: {s} ({d} byte{s})\n", .{ address, disassembler.text(&d), d.size, if (d.size == 1) "" else "s" });
        address += d.size;
    }
}
