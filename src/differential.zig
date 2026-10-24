//! Optional SingleStepTests/z80 JSON runner. No external runtime dependencies.
const std = @import("std");
const Cpu = @import("cpu/cpu.zig").Cpu;
const Bus = @import("machine/bus.zig").Bus;
const trace = @import("trace/trace.zig");

const fields = .{ "a", "b", "c", "d", "e", "f", "h", "l", "pc", "sp", "ix", "iy", "i", "r" };
const alt_fields = .{ .{ "af_alt", "af_" }, .{ "bc_alt", "bc_" }, .{ "de_alt", "de_" }, .{ "hl_alt", "hl_" } };
fn number(value: std.json.Value, name: []const u8) u16 {
    return @intCast(value.object.get(name).?.integer);
}

const Ports = struct {
    value: u8 = 0xff,
    fn read(context: *anyopaque, _: u16) u8 {
        const self: *Ports = @ptrCast(@alignCast(context));
        return self.value;
    }
    fn write(_: *anyopaque, _: u16, _: u8) void {}
};

fn runFile(io: std.Io, path: []const u8, out: *std.Io.Writer) !struct { passed: usize, failed: usize } {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024));
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});
    var passed: usize = 0;
    var failed: usize = 0;
    for (parsed.value.array.items) |vector| {
        const initial = vector.object.get("initial").?;
        const final = vector.object.get("final").?;
        var cpu: Cpu = .{};
        inline for (fields) |field| @field(cpu.registers, field) = @intCast(number(initial, field));
        inline for (alt_fields) |field| @field(cpu.registers, field[0]) = number(initial, field[1]);
        cpu.iff1 = number(initial, "iff1") != 0;
        cpu.iff2 = number(initial, "iff2") != 0;
        cpu.interrupt_mode = @intCast(number(initial, "im"));
        // SST's ei/p/q and wz are internal implementation state, outside this
        // runner's documented architectural-state comparison.
        var bus: Bus = .{};
        for (initial.object.get("ram").?.array.items) |pair| bus.memory[@intCast(pair.array.items[0].integer)] = @intCast(pair.array.items[1].integer);
        var ports: Ports = .{};
        var events: trace.RingBuffer(64) = .{};
        bus.trace_sink = events.sink();
        if (vector.object.get("ports")) |values| if (values.array.items.len > 0) {
            ports.value = @intCast(values.array.items[0].array.items[1].integer);
        };
        bus.port_device = .{ .context = &ports, .read = Ports.read, .write = Ports.write };
        const step = cpu.step(&bus) catch {
            failed += 1;
            if (failed <= 5) try out.print("FAIL {s}: unsupported {s}\n", .{ path, vector.object.get("name").?.string });
            continue;
        };
        var matches = true;
        inline for (fields) |field| {
            const mask: u16 = if (comptime std.mem.eql(u8, field, "f")) 0xd7 else 0xffff;
            const expected = number(final, field) & mask;
            const actual = @as(u16, @field(cpu.registers, field)) & mask;
            if (expected != actual) {
                matches = false;
                if (failed < 5) try out.print("FAIL {s} {s}: {s} expected={X} actual={X}\n", .{ path, vector.object.get("name").?.string, field, expected, actual });
            }
        }
        inline for (alt_fields) |field| if (@field(cpu.registers, field[0]) != number(final, field[1])) {
            matches = false;
        };
        if (cpu.iff1 != (number(final, "iff1") != 0) or cpu.iff2 != (number(final, "iff2") != 0) or cpu.interrupt_mode != number(final, "im")) matches = false;
        for (final.object.get("ram").?.array.items) |pair| {
            if (bus.memory[@intCast(pair.array.items[0].integer)] != pair.array.items[1].integer) matches = false;
        }
        if (step.t_states != vector.object.get("cycles").?.array.items.len) matches = false;
        if (vector.object.get("ports")) |values| {
            var index: usize = 0;
            for (0..events.len) |i| {
                const event = events.get(i).?;
                if (event.kind != .io_read and event.kind != .io_write) continue;
                if (index >= values.array.items.len) {
                    matches = false;
                    break;
                }
                const port = values.array.items[index].array.items;
                if (event.address != port[0].integer or event.data != port[1].integer or (event.kind == .io_read) != std.mem.eql(u8, port[2].string, "r")) matches = false;
                index += 1;
            }
            if (index != values.array.items.len) matches = false;
        }
        if (matches) passed += 1 else failed += 1;
    }
    try out.print("{s}: {d} passed, {d} failed\n", .{ path, passed, failed });
    return .{ .passed = passed, .failed = failed };
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    defer output.interface.flush() catch {};
    if (args.len < 2) return error.ExpectedJsonPaths;
    var passed: usize = 0;
    var failed: usize = 0;
    for (args[1..]) |path| {
        const result = try runFile(init.io, path, &output.interface);
        passed += result.passed;
        failed += result.failed;
    }
    try output.interface.print("TOTAL {d} passed, {d} failed (documented flags only; no cycle-pin comparison)\n", .{ passed, failed });
    if (failed != 0) return error.DifferentialMismatch;
}
