const std = @import("std");

pub const AssembleError = error{ InvalidSyntax, InvalidMnemonic, InvalidOperand, InvalidDirective, InvalidExpression, UnterminatedString, InvalidCharacterLiteral, DuplicateSymbol, UndefinedSymbol, ValueOutOfRange, RelativeOutOfRange, OutOfMemory };
pub const FailureLocation = struct {
    err: AssembleError = error.InvalidSyntax,
    line: usize = 0,
    column: usize = 0,
    end_column: usize = 0,
    source_line: []const u8 = "",
};
pub const Symbol = struct { name: []const u8, value: u16 };
pub const LineInfo = struct { line: usize, address: u16 };
pub const Result = struct {
    bytes: std.ArrayList(u8) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    lines: std.ArrayList(LineInfo) = .empty,
    allocator: std.mem.Allocator,
    pub fn deinit(self: *Result) void {
        self.bytes.deinit(self.allocator);
        for (self.symbols.items) |s| self.allocator.free(s.name);
        self.symbols.deinit(self.allocator);
        self.lines.deinit(self.allocator);
    }
};

const Symbols = std.StringHashMap(u16);

pub fn assemble(allocator: std.mem.Allocator, source: []const u8) AssembleError!Result {
    var ignored: FailureLocation = .{};
    return assembleLocated(allocator, source, &ignored);
}

pub fn assembleLocated(allocator: std.mem.Allocator, source: []const u8, failure: *FailureLocation) AssembleError!Result {
    var symbols = Symbols.init(allocator);
    defer symbols.deinit();
    try pass(source, allocator, &symbols, null, 1, failure);
    var result = Result{ .allocator = allocator };
    errdefer result.deinit();
    try pass(source, allocator, &symbols, &result, 2, failure);
    var it = symbols.iterator();
    while (it.next()) |entry| try result.symbols.append(allocator, .{ .name = try allocator.dupe(u8, entry.key_ptr.*), .value = entry.value_ptr.* });
    return result;
}

fn pass(source: []const u8, allocator: std.mem.Allocator, symbols: *Symbols, output: ?*Result, pass_number: u8, failure: *FailureLocation) AssembleError!void {
    var pc: u16 = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 0;
    while (lines.next()) |raw| {
        line_number += 1;
        pc = processLine(raw, line_number, allocator, symbols, output, pass_number, pc) catch |err| {
            failure.* = locateFailure(err, raw, line_number);
            return err;
        };
    }
}

fn processLine(raw: []const u8, line_number: usize, allocator: std.mem.Allocator, symbols: *Symbols, output: ?*Result, pass_number: u8, start_pc: u16) AssembleError!u16 {
    var pc = start_pc;
    const no_comment = if (std.mem.indexOfScalar(u8, raw, ';')) |i| raw[0..i] else raw;
    var text = std.mem.trim(u8, no_comment, " \t\r");
    if (text.len == 0) return pc;
    if (std.mem.indexOfScalar(u8, text, ':')) |colon| {
        const name = std.mem.trim(u8, text[0..colon], " \t");
        if (name.len == 0) return error.InvalidSyntax;
        if (pass_number == 1) {
            const gop = try symbols.getOrPut(name);
            if (gop.found_existing) return error.DuplicateSymbol;
            gop.value_ptr.* = pc;
        }
        text = std.mem.trim(u8, text[colon + 1 ..], " \t");
        if (text.len == 0) return pc;
    }
    var words = std.mem.tokenizeAny(u8, text, " \t");
    const first = words.next() orelse return pc;
    const rest = std.mem.trim(u8, text[first.len..], " \t");
    if (std.ascii.eqlIgnoreCase(first, "equ")) return error.InvalidDirective;
    if (std.ascii.eqlIgnoreCase(first, "org")) {
        pc = try eval(rest, symbols, pc, pass_number == 2);
        return pc;
    }
    // Also accept the conventional `NAME equ expression` form.
    if (words.next()) |second| if (std.ascii.eqlIgnoreCase(second, "equ")) {
        if (pass_number == 1) {
            const expression = std.mem.trim(u8, text[first.len + second.len + 1 ..], " \t");
            const value = try eval(expression, symbols, pc, false);
            const gop = try symbols.getOrPut(first);
            if (gop.found_existing) return error.DuplicateSymbol;
            gop.value_ptr.* = value;
        }
        return pc;
    };
    if (first[0] == '.') return error.InvalidDirective;
    if (!isMnemonic(first) and !std.ascii.eqlIgnoreCase(first, "db") and !std.ascii.eqlIgnoreCase(first, "dw")) return error.InvalidMnemonic;
    if (output) |out| try out.lines.append(allocator, .{ .line = line_number, .address = pc });
    if (std.ascii.eqlIgnoreCase(first, "db")) {
        pc = try emitData(allocator, rest, symbols, pc, output, false, pass_number == 2);
    } else if (std.ascii.eqlIgnoreCase(first, "dw")) {
        pc = try emitData(allocator, rest, symbols, pc, output, true, pass_number == 2);
    } else {
        const size = try encodeInstruction(allocator, first, rest, symbols, pc, output, pass_number == 2);
        pc +%= size;
    }
    return pc;
}

fn isMnemonic(text: []const u8) bool {
    const names = [_][]const u8{ "nop", "halt", "ret", "jp", "call", "jr", "push", "pop", "inc", "dec", "add", "sub", "cp", "ld" };
    for (names) |name| if (std.ascii.eqlIgnoreCase(text, name)) return true;
    return false;
}

fn locateFailure(err: AssembleError, raw: []const u8, line: usize) FailureLocation {
    const trimmed = std.mem.trimStart(u8, raw, " \t");
    var token_end = std.mem.indexOfAny(u8, trimmed, " \t:") orelse trimmed.len;
    var target = trimmed[0..token_end];
    if (err == error.InvalidOperand or err == error.UndefinedSymbol or err == error.ValueOutOfRange or err == error.RelativeOutOfRange or err == error.InvalidExpression or err == error.UnterminatedString or err == error.InvalidCharacterLiteral) {
        const first_end = std.mem.indexOfAny(u8, trimmed, " \t") orelse trimmed.len;
        const rest = std.mem.trimStart(u8, trimmed[first_end..], " \t");
        if (rest.len > 0) target = rest;
    }
    if (err == error.DuplicateSymbol) {
        token_end = std.mem.indexOfAny(u8, trimmed, ": \t") orelse trimmed.len;
        target = trimmed[0..token_end];
    }
    const column = if (target.len == 0) @as(usize, 1) else @intFromPtr(target.ptr) - @intFromPtr(raw.ptr) + 1;
    return .{ .err = err, .line = line, .column = column, .end_column = column + @max(target.len, 1) - 1, .source_line = raw };
}

fn emitData(allocator: std.mem.Allocator, text: []const u8, symbols: *Symbols, start: u16, output: ?*Result, word: bool, resolve: bool) AssembleError!u16 {
    var pc = start;
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |raw| {
        const item = std.mem.trim(u8, raw, " \t");
        if (!word and item.len > 0 and item[0] == '"' and (item.len < 2 or item[item.len - 1] != '"')) return error.UnterminatedString;
        if (!word and item.len >= 2 and item[0] == '"' and item[item.len - 1] == '"') {
            for (item[1 .. item.len - 1]) |ch| {
                if (output) |o| try o.bytes.append(allocator, ch);
                pc +%= 1;
            }
        } else {
            const value = try eval(item, symbols, pc, resolve);
            if (word) {
                if (output) |o| {
                    try o.bytes.append(allocator, @truncate(value));
                    try o.bytes.append(allocator, @truncate(value >> 8));
                }
                pc +%= 2;
            } else {
                if (value > 0xff) return error.ValueOutOfRange;
                if (output) |o| try o.bytes.append(allocator, @truncate(value));
                pc +%= 1;
            }
        }
    }
    return pc;
}

fn encodeInstruction(allocator: std.mem.Allocator, mnemonic: []const u8, operands_raw: []const u8, symbols: *Symbols, pc: u16, output: ?*Result, resolve: bool) AssembleError!u16 {
    var normalized_buf: [128]u8 = undefined;
    var n: usize = 0;
    for (operands_raw) |ch| if (ch != ' ' and ch != '\t') {
        if (n == normalized_buf.len) return error.InvalidOperand;
        normalized_buf[n] = std.ascii.toUpper(ch);
        n += 1;
    };
    const ops = normalized_buf[0..n];
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
            offset = @as(i32, target) - (@as(i32, pc) + 2);
            if (offset < -128 or offset > 127) return error.RelativeOutOfRange;
        }
        return emitImm8(allocator, output, opcode, @bitCast(@as(i8, @intCast(offset))));
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "push") or std.ascii.eqlIgnoreCase(mnemonic, "pop")) {
        const push = std.ascii.eqlIgnoreCase(mnemonic, "push");
        const opcode: u8 = if (std.mem.eql(u8, ops, "AF")) (if (push) 0xf5 else 0xf1) else if (std.mem.eql(u8, ops, "BC")) (if (push) 0xc5 else 0xc1) else if (std.mem.eql(u8, ops, "DE")) (if (push) 0xd5 else 0xd1) else if (std.mem.eql(u8, ops, "HL")) (if (push) 0xe5 else 0xe1) else return error.InvalidOperand;
        return emit1(allocator, output, opcode);
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "inc") or std.ascii.eqlIgnoreCase(mnemonic, "dec")) {
        const inc = std.ascii.eqlIgnoreCase(mnemonic, "inc");
        const opcode: u8 = if (std.mem.eql(u8, ops, "A")) (if (inc) 0x3c else 0x3d) else if (std.mem.eql(u8, ops, "B")) (if (inc) 0x04 else 0x05) else if (std.mem.eql(u8, ops, "C")) (if (inc) 0x0c else 0x0d) else if (std.mem.eql(u8, ops, "D")) (if (inc) 0x14 else 0x15) else if (std.mem.eql(u8, ops, "E")) (if (inc) 0x1c else 0x1d) else if (std.mem.eql(u8, ops, "H")) (if (inc) 0x24 else 0x25) else if (std.mem.eql(u8, ops, "L")) (if (inc) 0x2c else 0x2d) else if (std.mem.eql(u8, ops, "HL")) (if (inc) 0x23 else 0x2b) else return error.InvalidOperand;
        return emit1(allocator, output, opcode);
    }
    if (std.ascii.eqlIgnoreCase(mnemonic, "add") and std.mem.startsWith(u8, ops, "A,")) return encodeAlu(allocator, output, ops[2..], symbols, pc, resolve, 0x80, 0xc6);
    if (std.ascii.eqlIgnoreCase(mnemonic, "sub")) return encodeAlu(allocator, output, ops, symbols, pc, resolve, 0x90, 0xd6);
    if (std.ascii.eqlIgnoreCase(mnemonic, "cp")) return encodeAlu(allocator, output, ops, symbols, pc, resolve, 0xb8, 0xfe);
    if (std.ascii.eqlIgnoreCase(mnemonic, "ld")) return encodeLd(allocator, output, ops, symbols, pc, resolve);
    return error.InvalidOperand;
}

fn encodeAlu(a: std.mem.Allocator, out: ?*Result, op: []const u8, syms: *Symbols, pc: u16, resolve: bool, base: u8, immediate: u8) AssembleError!u16 {
    if (regCode(op)) |r| return emit1(a, out, base + r);
    return emitImm8(a, out, immediate, try eval8(op, syms, pc, resolve));
}

fn encodeLd(a: std.mem.Allocator, out: ?*Result, ops: []const u8, syms: *Symbols, pc: u16, resolve: bool) AssembleError!u16 {
    if (std.mem.eql(u8, ops, "A,(HL)")) return emit1(a, out, 0x7e);
    if (std.mem.eql(u8, ops, "(HL),A")) return emit1(a, out, 0x77);
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
fn eval8(s: []const u8, syms: *Symbols, pc: u16, resolve: bool) AssembleError!u8 {
    const v = try eval(s, syms, pc, resolve);
    if (v > 0xff) return error.ValueOutOfRange;
    return @truncate(v);
}

fn eval(text_raw: []const u8, symbols: *Symbols, pc: u16, resolve: bool) AssembleError!u16 {
    const text = std.mem.trim(u8, text_raw, " \t");
    if (text.len == 0) return error.InvalidExpression;
    var split_at: ?usize = null;
    var subtract = false;
    for (text, 0..) |ch, i| if (i > 0 and (ch == '+' or ch == '-')) {
        split_at = i;
        subtract = ch == '-';
        break;
    };
    if (split_at) |i| {
        const lhs = try eval(text[0..i], symbols, pc, resolve);
        const rhs = try eval(text[i + 1 ..], symbols, pc, resolve);
        return if (subtract) lhs -% rhs else lhs +% rhs;
    }
    if (std.mem.eql(u8, text, "$")) return pc;
    if (text[0] == '\'') {
        if (text.len != 3 or text[text.len - 1] != '\'') return error.InvalidCharacterLiteral;
        return text[1];
    }
    if (symbols.get(text)) |value| return value;
    var symbol_it = symbols.iterator();
    while (symbol_it.next()) |entry| if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, text)) return entry.value_ptr.*;
    const parsed = if (text.len > 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) std.fmt.parseInt(u16, text[2..], 16) else if (text.len > 2 and text[0] == '0' and (text[1] == 'b' or text[1] == 'B')) std.fmt.parseInt(u16, text[2..], 2) else std.fmt.parseInt(u16, text, 10);
    return parsed catch |parse_err| {
        if (parse_err == error.Overflow) return error.ValueOutOfRange;
        const identifier = std.ascii.isAlphabetic(text[0]) or text[0] == '_';
        if (identifier) return if (resolve) error.UndefinedSymbol else 0;
        return error.InvalidExpression;
    };
}
