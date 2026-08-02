const std = @import("std");
const Io = std.Io;
const Machine = @import("../machine/machine.zig").Machine;
const disassembler = @import("../disassembler/disassembler.zig");
const video = @import("../machine/video.zig");
const breakpoint = @import("breakpoint.zig");
const DebugSession = @import("session.zig").DebugSession;

pub fn repl(machine: *Machine, program: []const u8, reader: *Io.Reader, out: *Io.Writer) !void {
    var session = DebugSession{};
    session.reset(machine);
    try out.writeAll("Zig_80 debugger (type help)\n");
    while (true) {
        try showCurrent(machine, program, out);
        try out.writeAll("zig80> ");
        try out.flush();
        const raw = reader.takeDelimiterExclusive('\n') catch |e| switch (e) {
            error.EndOfStream => return,
            else => return e,
        };
        const line = std.mem.trim(u8, raw, " \t\r");
        var words = std.mem.tokenizeAny(u8, line, " \t");
        const cmd = words.next() orelse continue;
        if (eq(cmd, "q") or eq(cmd, "quit")) return;
        if (eq(cmd, "s") or eq(cmd, "step")) {
            const before = machine.cpu.registers;
            const step = session.step(machine) catch |e| {
                try out.print("error: {s}, opcode=0x{X:0>2}, PC=0x{X:0>4}\n", .{ @errorName(e), machine.cpu.last_unknown_opcode, machine.cpu.last_unknown_pc });
                continue;
            };
            try changes(before, machine.cpu.registers, step.t_states, out);
            continue;
        }
        if (eq(cmd, "c") or eq(cmd, "continue")) {
            var n: usize = 0;
            while (!machine.cpu.halted and n < 1_000_000) : (n += 1) {
                _ = session.step(machine) catch break;
                if (session.last_watchpoint != null or session.breakpoints.shouldBreak(machine.cpu.registers.pc, machine.cpu.registers)) break;
            }
            try out.print("stopped after {d} instructions\n", .{n});
            continue;
        }
        if (eq(cmd, "r") or eq(cmd, "registers")) {
            try registers(machine, out);
            continue;
        }
        if (eq(cmd, "m") or eq(cmd, "memory")) {
            const address = try number(words.next() orelse "");
            const len = try number(words.next() orelse "");
            for (0..len) |i| {
                if (i % 16 == 0) try out.print("\n{X:0>4}: ", .{address +% @as(u16, @intCast(i))});
                try out.print("{X:0>2} ", .{machine.bus.read8(address +% @as(u16, @intCast(i)))});
            }
            try out.writeByte('\n');
            continue;
        }
        if (eq(cmd, "disasm")) {
            var address = try number(words.next() orelse "");
            const count = try number(words.next() orelse "");
            for (0..count) |_| {
                if (address >= program.len) break;
                const d = disassembler.decode(program, address);
                try out.print("{X:0>4} {s}\n", .{ address, disassembler.text(&d) });
                address +%= d.size;
            }
            continue;
        }
        if (eq(cmd, "break")) {
            const first = words.next() orelse "";
            const parsed_address: ?u16 = number(first) catch null;
            const address = parsed_address orelse machine.cpu.registers.pc;
            var condition: ?breakpoint.Condition = null;
            var hit_target: u64 = 1;
            var temporary = false;
            var token: ?[]const u8 = if (parsed_address != null) words.next() else first;
            if (token) |value| {
                const lhs = if (eq(value, "if")) words.next() orelse "" else value;
                if (eq(lhs, "hit")) {
                    hit_target = try number64(words.next() orelse "");
                } else if (eq(lhs, "temporary")) {
                    temporary = true;
                } else {
                    condition = try breakpoint.parseCondition(lhs, words.next() orelse "", words.next() orelse "");
                    token = words.next();
                    if (token) |suffix| {
                        if (eq(suffix, "hit")) {
                            hit_target = try number64(words.next() orelse "");
                        } else if (eq(suffix, "temporary")) {
                            temporary = true;
                        }
                    }
                }
            }
            if (!session.breakpoints.addOptions(address, .{ .condition = condition, .hit_target = hit_target, .temporary = temporary })) try out.writeAll("breakpoint not added\n");
            continue;
        }
        if (eq(cmd, "delete")) {
            const address = try number(words.next() orelse "");
            _ = session.breakpoints.remove(address);
            continue;
        }
        if (eq(cmd, "enable") or eq(cmd, "disable")) {
            const address = try number(words.next() orelse "");
            _ = session.breakpoints.setEnabled(address, eq(cmd, "enable"));
            continue;
        }
        if (eq(cmd, "watch")) {
            const kind_text = words.next() orelse "";
            const kind: breakpoint.WatchKind = if (eq(kind_text, "read")) .memory_read else if (eq(kind_text, "write")) .memory_write else if (eq(kind_text, "io-read")) .io_read else if (eq(kind_text, "io-write")) .io_write else return error.InvalidWatchKind;
            const range = words.next() orelse "";
            const separator = std.mem.indexOf(u8, range, "..");
            const start = try number(if (separator) |index| range[0..index] else range);
            const end = try number(if (separator) |index| range[index + 2 ..] else range);
            var condition: ?breakpoint.Condition = null;
            if (words.next()) |if_token| {
                if (!eq(if_token, "if") or !eq(words.next() orelse "", "value")) return error.InvalidWatchCondition;
                condition = try breakpoint.parseValueCondition(words.next() orelse "", words.next() orelse "");
            }
            if (!session.watchpoints.add(.{ .kind = kind, .start = start, .end = end, .condition = condition })) try out.writeAll("watchpoint not added\n");
            continue;
        }
        if (eq(cmd, "input")) {
            machine.setInput(@truncate(try number(words.next() orelse "")));
            continue;
        }
        if (eq(cmd, "screen")) {
            try video.render(&machine.bus, out);
            continue;
        }
        if (eq(cmd, "reset")) {
            machine.reset();
            session.reset(machine);
            continue;
        }
        if (eq(cmd, "help")) {
            try out.writeAll("step/s, continue/c, registers/r, memory/m <address> <length>, disasm <address> <count>, break [address] [if] <register/flag> <op> <value> [hit N], delete/enable/disable <address>, watch <read/write> <address[..end]> [if value <op> N], input <value>, screen, reset, quit/q\n");
            continue;
        }
        try out.print("unknown command: {s}\n", .{cmd});
    }
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}
fn number(s: []const u8) !u16 {
    return if (std.mem.startsWith(u8, s, "0x")) std.fmt.parseInt(u16, s[2..], 16) else std.fmt.parseInt(u16, s, 10);
}
fn number64(s: []const u8) !u64 {
    return if (std.mem.startsWith(u8, s, "0x")) std.fmt.parseInt(u64, s[2..], 16) else std.fmt.parseInt(u64, s, 10);
}
fn showCurrent(machine: *Machine, program: []const u8, out: *Io.Writer) !void {
    const pc = machine.cpu.registers.pc;
    if (pc < program.len) {
        const d = disassembler.decode(program, pc);
        try out.print("{X:0>4}  {s}\n", .{ pc, disassembler.text(&d) });
    }
}
fn registers(machine: *Machine, out: *Io.Writer) !void {
    const r = machine.cpu.registers;
    try out.print("PC={X:0>4} SP={X:0>4} AF={X:0>4} BC={X:0>4}\nDE={X:0>4} HL={X:0>4}\n", .{ r.pc, r.sp, r.af(), r.bc(), r.de(), r.hl() });
}
fn changes(before: @import("../cpu/registers.zig").Registers, after: @import("../cpu/registers.zig").Registers, cycles: u16, out: *Io.Writer) !void {
    if (before.af() != after.af()) try out.print("AF: 0x{X:0>4} -> 0x{X:0>4}\n", .{ before.af(), after.af() });
    if (before.bc() != after.bc()) try out.print("BC: 0x{X:0>4} -> 0x{X:0>4}\n", .{ before.bc(), after.bc() });
    if (before.de() != after.de()) try out.print("DE: 0x{X:0>4} -> 0x{X:0>4}\n", .{ before.de(), after.de() });
    if (before.hl() != after.hl()) try out.print("HL: 0x{X:0>4} -> 0x{X:0>4}\n", .{ before.hl(), after.hl() });
    try out.print("PC: 0x{X:0>4} -> 0x{X:0>4}\nT-states: {d}\n", .{ before.pc, after.pc, cycles });
}
