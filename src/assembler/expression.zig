const std = @import("std");
const AssembleError = @import("assembler.zig").AssembleError;
const Symbols = @import("assembler.zig").Symbols;

pub fn eval8(s: []const u8, syms: *Symbols, pc: u16, resolve: bool) AssembleError!u8 {
    const v = try eval(s, syms, pc, resolve);
    if (v > 0xff) return error.ValueOutOfRange;
    return @truncate(v);
}

pub fn eval(text_raw: []const u8, symbols: *Symbols, pc: u16, resolve: bool) AssembleError!u16 {
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
