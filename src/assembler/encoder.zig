const std = @import("std");
const instruction = @import("../cpu/instruction.zig");
const assembler = @import("assembler.zig");
const AssembleError = assembler.AssembleError;
const Result = assembler.Result;
const Symbols = assembler.Symbols;
const eval = @import("expression.zig").eval;
const eval8 = @import("expression.zig").eval8;

pub fn encodeInstruction(allocator: std.mem.Allocator, mnemonic: []const u8, operands_raw: []const u8, symbols: *Symbols, pc: u16, output: ?*Result, resolve: bool) AssembleError!u16 {
    var normalized_buf: [128]u8 = undefined;
    var n: usize = 0;
    var in_character = false;
    for (operands_raw) |ch| {
        if (ch == '\'') in_character = !in_character;
        if (!in_character and (ch == ' ' or ch == '\t')) continue;
        if (n == normalized_buf.len) return error.InvalidOperand;
        normalized_buf[n] = if (in_character) ch else std.ascii.toUpper(ch);
        n += 1;
    }
    const ops = normalized_buf[0..n];
    if (std.ascii.eqlIgnoreCase(mnemonic, "rst")) {
        const vector = try eval(ops, symbols, pc, resolve);
        if (resolve and (vector > 0x38 or vector & 7 != 0)) return error.InvalidOperand;
        return emit1(allocator, output, 0xc7 | @as(u8, if (resolve) @intCast(vector) else 0));
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "im")) {
        const mode = try eval8(ops, symbols, pc, resolve);
        if (mode > 2) return error.InvalidOperand;
        return emitImm8(allocator, output, 0xed, switch (mode) {
            0 => 0x46,
            1 => 0x56,
            2 => 0x5e,
            else => unreachable,
        });
    }
    if (try encodeExtended(allocator, output, mnemonic, ops, symbols, pc, resolve)) |size| return size;
    if (std.ascii.eqlIgnoreCase(mnemonic, "nop")) return if (ops.len == 0) emit1(allocator, output, 0x00) else error.InvalidOperand;
    if (std.ascii.eqlIgnoreCase(mnemonic, "halt")) return if (ops.len == 0) emit1(allocator, output, 0x76) else error.InvalidOperand;
    if (std.ascii.eqlIgnoreCase(mnemonic, "ret")) return if (ops.len == 0) emit1(allocator, output, 0xc9) else error.InvalidOperand;
    if (std.ascii.eqlIgnoreCase(mnemonic, "jp")) {
        if (std.mem.startsWith(u8, ops, "NZ,")) return emitImm16(allocator, output, 0xc2, try eval(ops[3..], symbols, pc, resolve));
        if (std.mem.startsWith(u8, ops, "Z,")) return emitImm16(allocator, output, 0xca, try eval(ops[2..], symbols, pc, resolve));
        return emitImm16(allocator, output, 0xc3, try eval(ops, symbols, pc, resolve));
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "call")) return emitImm16(allocator, output, 0xcd, try eval(ops, symbols, pc, resolve));
    if (std.ascii.eqlIgnoreCase(mnemonic, "jr")) {
        var opcode: u8 = 0x18;
        var expression = ops;
        if (std.mem.startsWith(u8, ops, "NZ,")) {
            opcode = 0x20;
            expression = ops[3..];
        }
        if (std.mem.startsWith(u8, ops, "Z,")) {
            opcode = 0x28;
            expression = ops[2..];
        }
        const target = try eval(expression, symbols, pc, resolve);
        var offset: i32 = 0;
        if (resolve) {
            offset = @as(i16, @bitCast(target -% (pc +% 2)));
            if (offset < -128 or offset > 127) return error.RelativeOutOfRange;
        }
        return emitImm8(allocator, output, opcode, @bitCast(@as(i8, @intCast(offset))));
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "djnz")) {
        const target = try eval(ops, symbols, pc, resolve);
        var offset: i32 = 0;
        if (resolve) {
            offset = @as(i16, @bitCast(target -% (pc +% 2)));
            if (offset < -128 or offset > 127) return error.RelativeOutOfRange;
        }
        return emitImm8(allocator, output, 0x10, @bitCast(@as(i8, @intCast(offset))));
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "push") or std.ascii.eqlIgnoreCase(mnemonic, "pop")) {
        const push = std.ascii.eqlIgnoreCase(mnemonic, "push");
        const opcode: u8 = if (std.mem.eql(u8, ops, "AF")) (if (push) 0xf5 else 0xf1) else if (std.mem.eql(u8, ops, "BC")) (if (push) 0xc5 else 0xc1) else if (std.mem.eql(u8, ops, "DE")) (if (push) 0xd5 else 0xd1) else if (std.mem.eql(u8, ops, "HL")) (if (push) 0xe5 else 0xe1) else return error.InvalidOperand;
        return emit1(allocator, output, opcode);
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "inc") or std.ascii.eqlIgnoreCase(mnemonic, "dec")) {
        const inc = std.ascii.eqlIgnoreCase(mnemonic, "inc");
        const opcode: u8 = if (std.mem.eql(u8, ops, "A")) (if (inc) 0x3c else 0x3d) else if (std.mem.eql(u8, ops, "B")) (if (inc) 0x04 else 0x05) else if (std.mem.eql(u8, ops, "C")) (if (inc) 0x0c else 0x0d) else if (std.mem.eql(u8, ops, "D")) (if (inc) 0x14 else 0x15) else if (std.mem.eql(u8, ops, "E")) (if (inc) 0x1c else 0x1d) else if (std.mem.eql(u8, ops, "H")) (if (inc) 0x24 else 0x25) else if (std.mem.eql(u8, ops, "L")) (if (inc) 0x2c else 0x2d) else if (std.mem.eql(u8, ops, "HL")) (if (inc) 0x23 else 0x2b) else if (std.mem.eql(u8, ops, "(HL)")) (if (inc) 0x34 else 0x35) else return error.InvalidOperand;
        return emit1(allocator, output, opcode);
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "add") and std.mem.startsWith(u8, ops, "HL,")) {
        const opcode: u8 = if (std.mem.eql(u8, ops[3..], "BC")) 0x09 else if (std.mem.eql(u8, ops[3..], "DE")) 0x19 else if (std.mem.eql(u8, ops[3..], "HL")) 0x29 else if (std.mem.eql(u8, ops[3..], "SP")) 0x39 else return error.InvalidOperand;
        return emit1(allocator, output, opcode);
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "add") and std.mem.startsWith(u8, ops, "A,")) return encodeAlu(allocator, output, ops[2..], symbols, pc, resolve, 0x80, 0xc6);
    if (std.ascii.eqlIgnoreCase(mnemonic, "adc") and std.mem.startsWith(u8, ops, "A,")) return encodeAluWithMemory(allocator, output, ops[2..], symbols, pc, resolve, 0x88, 0xce);
    if (std.ascii.eqlIgnoreCase(mnemonic, "sub")) return encodeAlu(allocator, output, ops, symbols, pc, resolve, 0x90, 0xd6);
    if (std.ascii.eqlIgnoreCase(mnemonic, "sbc") and std.mem.startsWith(u8, ops, "A,")) return encodeAluWithMemory(allocator, output, ops[2..], symbols, pc, resolve, 0x98, 0xde);
    if (std.ascii.eqlIgnoreCase(mnemonic, "cp")) return encodeAlu(allocator, output, ops, symbols, pc, resolve, 0xb8, 0xfe);
    if (instruction.logicByMnemonic(mnemonic)) |family| {
        if (instruction.register8Code(ops)) |register_code| return emit1(allocator, output, family.register_base + register_code);
        return emitImm8(allocator, output, family.immediate_opcode, try eval8(ops, symbols, pc, resolve));
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "ld")) return encodeLd(allocator, output, ops, symbols, pc, resolve);
    if (cbOperation(mnemonic)) |operation| return encodeCb(allocator, output, operation, ops, symbols, pc, resolve);
    return error.InvalidOperand;
}

fn encodeExtended(a: std.mem.Allocator, out: ?*Result, mnemonic: []const u8, ops: []const u8, syms: *Symbols, pc: u16, resolve: bool) AssembleError!?u16 {
    const metadata = @import("../cpu/extended_metadata.zig");
    var buffer: [300]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{s}{s}{s}", .{ mnemonic, if (ops.len == 0) "" else " ", ops }) catch return error.InvalidOperand;
    for (text[0..mnemonic.len]) |*ch| ch.* = std.ascii.toUpper(ch.*);
    for (0..3) |pass_number| for (metadata.definitions) |definition| {
        if (definition.legacy) continue;
        if (std.mem.count(u8, definition.pattern, "{") != pass_number) continue;
        const matched = metadata.match(definition.pattern, text) orelse continue;
        var encoded: [4]u8 = undefined;
        var len: usize = 0;
        if (definition.prefix != 0) {
            encoded[len] = definition.prefix;
            len += 1;
        }
        encoded[len] = if (definition.indexed_cb) 0xcb else definition.opcode;
        len += 1;
        for (matched.values[0..matched.len], matched.kinds[0..matched.len]) |value, kind| {
            const v = if (kind == 'd') 0 else try eval(value, syms, pc, resolve);
            if (kind == 'w') {
                encoded[len] = @truncate(v);
                encoded[len + 1] = @truncate(v >> 8);
                len += 2;
            } else if (kind == 'r') {
                const offset: i16 = @bitCast(v -% (pc +% definition.size()));
                if (resolve and (offset < -128 or offset > 127)) return error.RelativeOutOfRange;
                encoded[len] = if (resolve) @bitCast(@as(i8, @intCast(offset))) else 0;
                len += 1;
            } else if (kind == 'd') {
                if (value[0] != '+' and value[0] != '-') return error.InvalidOperand;
                const magnitude = try eval(value[1..], syms, pc, resolve);
                if (resolve and magnitude > (if (value[0] == '-') @as(u16, 128) else @as(u16, 127))) return error.ValueOutOfRange;
                encoded[len] = if (value[0] == '-') 0 -% @as(u8, @truncate(magnitude)) else @truncate(magnitude);
                len += 1;
            } else {
                if (v > 255) return error.ValueOutOfRange;
                encoded[len] = @truncate(v);
                len += 1;
            }
        }
        if (definition.indexed_cb) {
            encoded[len] = definition.opcode;
            len += 1;
        }
        if (out) |result| try result.bytes.appendSlice(a, encoded[0..len]);
        return @intCast(len);
    };
    return null;
}

fn encodeAlu(a: std.mem.Allocator, out: ?*Result, op: []const u8, syms: *Symbols, pc: u16, resolve: bool, base: u8, immediate: u8) AssembleError!u16 {
    if (regCode(op)) |r| return emit1(a, out, base + r);
    return emitImm8(a, out, immediate, try eval8(op, syms, pc, resolve));
}

fn encodeAluWithMemory(a: std.mem.Allocator, out: ?*Result, op: []const u8, syms: *Symbols, pc: u16, resolve: bool, base: u8, immediate: u8) AssembleError!u16 {
    if (instruction.register8Code(op)) |r| return emit1(a, out, base + r);
    return emitImm8(a, out, immediate, try eval8(op, syms, pc, resolve));
}

fn cbOperation(mnemonic: []const u8) ?instruction.CbOperation {
    inline for (.{ .{ "RLC", instruction.CbOperation.rlc }, .{ "RRC", instruction.CbOperation.rrc }, .{ "RL", instruction.CbOperation.rl }, .{ "RR", instruction.CbOperation.rr }, .{ "SLA", instruction.CbOperation.sla }, .{ "SRA", instruction.CbOperation.sra }, .{ "SRL", instruction.CbOperation.srl }, .{ "BIT", instruction.CbOperation.bit }, .{ "RES", instruction.CbOperation.res }, .{ "SET", instruction.CbOperation.set } }) |entry| {
        if (std.ascii.eqlIgnoreCase(mnemonic, entry[0])) return entry[1];
    }
    return null;
}

fn encodeCb(a: std.mem.Allocator, out: ?*Result, operation: instruction.CbOperation, ops: []const u8, syms: *Symbols, pc: u16, resolve: bool) AssembleError!u16 {
    var bit: u3 = 0;
    var register_text = ops;
    if (operation == .bit or operation == .res or operation == .set) {
        const comma = std.mem.indexOfScalar(u8, ops, ',') orelse return error.InvalidOperand;
        const value = try eval8(ops[0..comma], syms, pc, resolve);
        if (value > 7) return error.ValueOutOfRange;
        bit = @truncate(value);
        register_text = ops[comma + 1 ..];
    }
    const register = instruction.register8Code(register_text) orelse return error.InvalidOperand;
    if (out) |o| {
        try o.bytes.append(a, 0xcb);
        try o.bytes.append(a, instruction.cbOpcode(operation, bit, register));
    }
    return 2;
}

fn encodeLd(a: std.mem.Allocator, out: ?*Result, ops: []const u8, syms: *Symbols, pc: u16, resolve: bool) AssembleError!u16 {
    if (std.mem.indexOfScalar(u8, ops, ',')) |register_comma| {
        const destination = instruction.register8Code(ops[0..register_comma]);
        const source = instruction.register8Code(ops[register_comma + 1 ..]);
        if (destination != null and source != null) {
            const opcode = instruction.ldRegisterOpcode(destination.?, source.?) orelse return error.InvalidOperand;
            return emit1(a, out, opcode);
        }
    }
    if (std.mem.startsWith(u8, ops, "(HL),")) return emitImm8(a, out, 0x36, try eval8(ops[5..], syms, pc, resolve));
    if (std.mem.startsWith(u8, ops, "A,(")) return emitImm16(a, out, 0x3a, try eval(try stripParens(ops[2..]), syms, pc, resolve));
    if (std.mem.startsWith(u8, ops, "HL,(")) return emitImm16(a, out, 0x2a, try eval(try stripParens(ops[3..]), syms, pc, resolve));
    if (std.mem.startsWith(u8, ops, "(") and std.mem.endsWith(u8, ops, "),A")) return emitImm16(a, out, 0x32, try eval(ops[1 .. ops.len - 3], syms, pc, resolve));
    if (std.mem.startsWith(u8, ops, "(") and std.mem.endsWith(u8, ops, "),HL")) return emitImm16(a, out, 0x22, try eval(ops[1 .. ops.len - 4], syms, pc, resolve));
    const comma = std.mem.indexOfScalar(u8, ops, ',') orelse return error.InvalidOperand;
    const dst = ops[0..comma];
    const value_text = ops[comma + 1 ..];
    const op8: ?u8 = if (std.mem.eql(u8, dst, "A")) 0x3e else if (std.mem.eql(u8, dst, "B")) 0x06 else if (std.mem.eql(u8, dst, "C")) 0x0e else if (std.mem.eql(u8, dst, "D")) 0x16 else if (std.mem.eql(u8, dst, "E")) 0x1e else if (std.mem.eql(u8, dst, "H")) 0x26 else if (std.mem.eql(u8, dst, "L")) 0x2e else null;
    if (op8) |opcode| return emitImm8(a, out, opcode, try eval8(value_text, syms, pc, resolve));
    const op16: u8 = if (std.mem.eql(u8, dst, "BC")) 0x01 else if (std.mem.eql(u8, dst, "DE")) 0x11 else if (std.mem.eql(u8, dst, "HL")) 0x21 else if (std.mem.eql(u8, dst, "SP")) 0x31 else return error.InvalidOperand;
    return emitImm16(a, out, op16, try eval(value_text, syms, pc, resolve));
}

fn regCode(s: []const u8) ?u8 {
    return if (std.mem.eql(u8, s, "B")) 0 else if (std.mem.eql(u8, s, "C")) 1 else if (std.mem.eql(u8, s, "D")) 2 else if (std.mem.eql(u8, s, "E")) 3 else if (std.mem.eql(u8, s, "H")) 4 else if (std.mem.eql(u8, s, "L")) 5 else if (std.mem.eql(u8, s, "A")) 7 else null;
}
fn stripParens(s: []const u8) AssembleError![]const u8 {
    if (s.len < 2 or s[0] != '(' or s[s.len - 1] != ')') return error.InvalidOperand;
    return s[1 .. s.len - 1];
}
fn emit1(a: std.mem.Allocator, out: ?*Result, op: u8) AssembleError!u16 {
    if (out) |o| try o.bytes.append(a, op);
    return 1;
}
fn emitImm8(a: std.mem.Allocator, out: ?*Result, op: u8, v: u8) AssembleError!u16 {
    if (out) |o| {
        try o.bytes.append(a, op);
        try o.bytes.append(a, v);
    }
    return 2;
}
fn emitImm16(a: std.mem.Allocator, out: ?*Result, op: u8, v: u16) AssembleError!u16 {
    if (out) |o| {
        try o.bytes.append(a, op);
        try o.bytes.append(a, @truncate(v));
        try o.bytes.append(a, @truncate(v >> 8));
    }
    return 3;
}
