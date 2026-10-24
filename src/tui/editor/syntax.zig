const std = @import("std");

pub const TokenKind = enum { plain, label, mnemonic, register, number, directive, comment, string, character };
pub const Token = struct { start: usize, end: usize, kind: TokenKind };
pub const TokenList = struct { items: [48]Token = undefined, len: usize = 0 };

pub const SyntaxCache = struct {
    const Slot = struct { line: usize = std.math.maxInt(usize), hash: u64 = 0, tokens: TokenList = .{} };
    slots: [128]Slot = @splat(.{}),

    pub fn tokens(self: *SyntaxCache, line_number: usize, line: []const u8) *const TokenList {
        const slot = &self.slots[line_number % self.slots.len];
        const hash = std.hash.Wyhash.hash(0, line);
        if (slot.line != line_number or slot.hash != hash) slot.* = .{ .line = line_number, .hash = hash, .tokens = tokenize(line) };
        return &slot.tokens;
    }
};

pub fn tokenize(line: []const u8) TokenList {
    var result: TokenList = .{};
    var index: usize = 0;
    var significant: usize = 0;
    while (index < line.len and result.len < result.items.len) {
        if (std.ascii.isWhitespace(line[index])) {
            index += 1;
            continue;
        }
        const start = index;
        if (line[index] == ';') {
            add(&result, start, line.len, .comment);
            break;
        }
        if (line[index] == '"') {
            index += 1;
            while (index < line.len and line[index] != '"') : (index += 1) {
                if (line[index] == '\\' and index + 1 < line.len) index += 1;
            }
            if (index < line.len) index += 1;
            add(&result, start, index, .string);
            significant += 1;
            continue;
        }
        if (line[index] == '\'') {
            index += 1;
            while (index < line.len and line[index] != '\'') : (index += 1) {
                if (line[index] == '\\' and index + 1 < line.len) index += 1;
            }
            if (index < line.len) index += 1;
            add(&result, start, index, .character);
            significant += 1;
            continue;
        }
        if (!isWord(line[index])) {
            index += 1;
            continue;
        }
        while (index < line.len and isWord(line[index])) : (index += 1) {}
        const word = line[start..index];
        var kind: TokenKind = .plain;
        if (index < line.len and line[index] == ':') {
            kind = .label;
        } else if (isOneOf(word, &directives)) {
            kind = .directive;
        } else if (isOneOf(word, &mnemonics)) {
            kind = .mnemonic;
        } else if (isOneOf(word, &registers)) {
            kind = .register;
        } else if (word.len > 0 and (std.ascii.isDigit(word[0]) or word[0] == '$' or word[0] == '%')) {
            kind = .number;
        } else if (significant == 0 and index < line.len and line[index] == ':') kind = .label;
        add(&result, start, index, kind);
        significant += 1;
    }
    return result;
}

pub const Completion = struct {
    active: bool = false,
    replace_start: usize = 0,
    replace_end: usize = 0,
    selected: usize = 0,
    items: [16][32]u8 = @splat(@splat(0)),
    lengths: [16]u8 = @splat(0),
    len: u8 = 0,

    pub fn item(self: *const Completion, index: usize) []const u8 {
        if (index >= self.items.len or index >= self.len) return "";
        const length = @min(@as(usize, self.lengths[index]), self.items[index].len);
        return self.items[index][0..length];
    }

    pub fn boundedLen(self: *const Completion) usize {
        return @min(@as(usize, self.len), self.items.len);
    }
};

pub fn complete(source: []const u8, cursor: usize, result: *Completion) void {
    result.* = .{};
    const line_start = lineStart(source, cursor);
    const before = source[line_start..cursor];
    if (std.mem.indexOfScalar(u8, before, ';') != null) return;
    var prefix_start = cursor;
    while (prefix_start > line_start and isIdentifier(source[prefix_start - 1])) : (prefix_start -= 1) {}
    const prefix = source[prefix_start..cursor];
    result.replace_start = prefix_start;
    result.replace_end = cursor;

    const logical = stripLabel(before);
    var words = std.mem.tokenizeAny(u8, logical, " \t,()");
    const first = words.next();
    const in_operand = first != null and (@intFromPtr(first.?.ptr) + first.?.len <= @intFromPtr(before.ptr) + prefix_start - line_start);
    if (!in_operand) {
        addMatches(result, prefix, &mnemonics);
        addMatches(result, prefix, &directives);
    } else {
        const mnemonic = first.?;
        const open_paren = std.mem.lastIndexOfScalar(u8, before, '(') != null and (std.mem.lastIndexOfScalar(u8, before, ')') orelse 0) < (std.mem.lastIndexOfScalar(u8, before, '(') orelse 0);
        if (open_paren and std.ascii.eqlIgnoreCase(mnemonic, "ld")) {
            addMatches(result, prefix, &.{ "hl", "bc", "de", "ix", "iy" });
        } else if (isOneOf(mnemonic, &.{ "push", "pop" })) {
            addMatches(result, prefix, &.{ "af", "bc", "de", "hl", "ix", "iy" });
        } else if (isOneOf(mnemonic, &.{ "jp", "jr", "call" })) {
            addMatches(result, prefix, &.{ "nz", "z", "nc", "c", "po", "pe", "p", "m" });
            addLabels(result, prefix, source);
        } else if (std.ascii.eqlIgnoreCase(mnemonic, "ld")) {
            addMatches(result, prefix, &registers);
            addLabels(result, prefix, source);
        } else if (isOneOf(mnemonic, &directives)) {
            addLabels(result, prefix, source);
        } else addMatches(result, prefix, &registers);
    }
    result.active = result.len > 0 and !(result.len == 1 and std.ascii.eqlIgnoreCase(result.item(0), prefix));
}

pub fn wordAt(source: []const u8, cursor: usize) ?struct { start: usize, end: usize, text: []const u8 } {
    if (source.len == 0) return null;
    var start = @min(cursor, source.len);
    if (start == source.len or !isIdentifier(source[start])) {
        if (start == 0 or !isIdentifier(source[start - 1])) return null;
        start -= 1;
    }
    var end = start;
    while (start > 0 and isIdentifier(source[start - 1])) : (start -= 1) {}
    while (end < source.len and isIdentifier(source[end])) : (end += 1) {}
    return .{ .start = start, .end = end, .text = source[start..end] };
}

pub fn findLabelDefinition(source: []const u8, name: []const u8) ?usize {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 0;
    while (lines.next()) |line| : (line_number += 1) {
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (trimmed.len >= name.len and std.ascii.eqlIgnoreCase(trimmed[0..name.len], name)) {
            const rest = trimmed[name.len..];
            if ((rest.len > 0 and rest[0] == ':') or startsIgnoreCase(std.mem.trimStart(u8, rest, " \t"), "equ")) return line_number;
        }
    }
    return null;
}

pub const mnemonics = [_][]const u8{ "adc", "add", "and", "bit", "call", "ccf", "cp", "cpd", "cpdr", "cpi", "cpir", "cpl", "daa", "dec", "di", "djnz", "ei", "ex", "exx", "halt", "im", "in", "inc", "ind", "indr", "ini", "inir", "jp", "jr", "ld", "ldd", "lddr", "ldi", "ldir", "neg", "nop", "or", "otdr", "otir", "out", "outd", "outi", "pop", "push", "res", "ret", "reti", "retn", "rl", "rla", "rlc", "rlca", "rld", "rr", "rra", "rrc", "rrca", "rrd", "rst", "sbc", "scf", "set", "sla", "sll", "sra", "srl", "sub", "xor" };
pub const registers = [_][]const u8{ "a", "f", "b", "c", "d", "e", "h", "l", "af", "bc", "de", "hl", "ix", "iy", "sp", "pc", "i", "r", "af'" };
pub const directives = [_][]const u8{ "org", "equ", "db", "dw" };

fn add(result: *TokenList, start: usize, end: usize, kind: TokenKind) void {
    result.items[result.len] = .{ .start = start, .end = end, .kind = kind };
    result.len += 1;
}
fn addMatches(result: *Completion, prefix: []const u8, values: []const []const u8) void {
    for (values) |value| if (startsIgnoreCase(value, prefix)) addCompletion(result, value);
}
fn addLabels(result: *Completion, prefix: []const u8, source: []const u8) void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t");
        var end: usize = 0;
        while (end < trimmed.len and isIdentifier(trimmed[end])) : (end += 1) {}
        if (end == 0) continue;
        const rest = trimmed[end..];
        if ((rest.len > 0 and rest[0] == ':') or startsIgnoreCase(std.mem.trimStart(u8, rest, " \t"), "equ")) {
            if (startsIgnoreCase(trimmed[0..end], prefix)) addCompletion(result, trimmed[0..end]);
        }
    }
}
fn addCompletion(result: *Completion, value: []const u8) void {
    const count = result.boundedLen();
    if (count >= result.items.len or value.len > result.items[0].len) return;
    for (0..count) |i| if (std.ascii.eqlIgnoreCase(result.item(i), value)) return;
    @memcpy(result.items[count][0..value.len], value);
    result.lengths[count] = @intCast(value.len);
    result.len += 1;
}
fn stripLabel(line: []const u8) []const u8 {
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return line;
    return line[colon + 1 ..];
}
fn lineStart(source: []const u8, cursor: usize) usize {
    var i = @min(cursor, source.len);
    while (i > 0 and source[i - 1] != '\n') : (i -= 1) {}
    return i;
}
fn isWord(byte: u8) bool {
    return isIdentifier(byte) or byte == '.' or byte == '$' or byte == '%' or byte == '\'';
}
fn isIdentifier(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}
fn startsIgnoreCase(value: []const u8, prefix: []const u8) bool {
    return value.len >= prefix.len and std.ascii.eqlIgnoreCase(value[0..prefix.len], prefix);
}
fn isOneOf(token: []const u8, values: []const []const u8) bool {
    for (values) |value| if (std.ascii.eqlIgnoreCase(token, value)) return true;
    return false;
}
