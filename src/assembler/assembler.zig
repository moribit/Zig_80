const std = @import("std");
const instruction = @import("../cpu/instruction.zig");
const eval = @import("expression.zig").eval;
const encodeInstruction = @import("encoder.zig").encodeInstruction;
const program_symbols = @import("../symbols/symbols.zig");

pub const AssembleError = error{ InvalidSyntax, InvalidMnemonic, InvalidOperand, InvalidDirective, InvalidExpression, UnterminatedString, InvalidCharacterLiteral, DuplicateSymbol, UndefinedSymbol, ValueOutOfRange, RelativeOutOfRange, InvalidInclude, IncludeNotFound, IncludeCycle, IncludeDepthExceeded, OutOfMemory };
pub const FailureLocation = struct {
    err: AssembleError = error.InvalidSyntax,
    line: usize = 0,
    column: usize = 0,
    end_column: usize = 0,
    source_line: []const u8 = "",
    file_path: ?[]const u8 = null,
    source_storage: [1024]u8 = undefined,
    file_storage: [1024]u8 = undefined,

    pub fn set(self: *FailureLocation, err: AssembleError, raw: []const u8, line_number: usize, path: ?[]const u8) void {
        self.* = .{ .err = err, .line = line_number };
        const source_len = @min(raw.len, self.source_storage.len);
        @memcpy(self.source_storage[0..source_len], raw[0..source_len]);
        self.source_line = self.source_storage[0..source_len];
        if (path) |value| {
            const path_len = @min(value.len, self.file_storage.len);
            @memcpy(self.file_storage[0..path_len], value[0..path_len]);
            self.file_path = self.file_storage[0..path_len];
        }
        locateFailureColumns(self, raw);
    }
};
pub const Symbol = program_symbols.Symbol;
pub const LineInfo = program_symbols.SourceMapEntry;
pub const Result = struct {
    bytes: std.ArrayList(u8) = .empty,
    symbols: program_symbols.SymbolTable,
    source_map: program_symbols.SourceMap,
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) Result {
        return .{ .allocator = allocator, .symbols = .init(allocator), .source_map = .init(allocator) };
    }
    pub fn deinit(self: *Result) void {
        self.bytes.deinit(self.allocator);
        self.symbols.deinit();
        self.source_map.deinit();
    }
};

pub const Symbols = std.StringHashMap(u16);

pub fn assemble(allocator: std.mem.Allocator, source: []const u8) AssembleError!Result {
    var ignored: FailureLocation = .{};
    return assembleLocated(allocator, source, &ignored);
}

pub fn assembleLocated(allocator: std.mem.Allocator, source: []const u8, failure: *FailureLocation) AssembleError!Result {
    var symbols = Symbols.init(allocator);
    defer symbols.deinit();
    try pass(source, null, allocator, &symbols, null, 1, failure);
    var result = Result.init(allocator);
    errdefer result.deinit();
    try pass(source, null, allocator, &symbols, &result, 2, failure);
    var it = symbols.iterator();
    while (it.next()) |entry| try result.symbols.add(entry.key_ptr.*, entry.value_ptr.*);
    return result;
}

pub const assembleFile = @import("file_loader.zig").assembleFile;

pub fn writeListing(result: *const Result, writer: *std.Io.Writer) !void {
    for (result.source_map.items.items) |entry| {
        try writer.print("{X:0>4}  ", .{entry.address});
        for (0..@min(entry.byte_count, 8)) |index| try writer.print("{X:0>2} ", .{result.bytes.items[entry.byte_offset + index]});
        for (@min(entry.byte_count, 8)..8) |_| try writer.writeAll("   ");
        try writer.print(" {s}\n", .{entry.source_line});
    }
}

fn pass(source: []const u8, file_path: ?[]const u8, allocator: std.mem.Allocator, symbols: *Symbols, output: ?*Result, pass_number: u8, failure: *FailureLocation) AssembleError!void {
    var pc: u16 = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 0;
    while (lines.next()) |raw| {
        line_number += 1;
        pc = processLine(raw, file_path, line_number, allocator, symbols, null, output, pass_number, pc) catch |err| {
            failure.set(err, raw, line_number, file_path);
            return err;
        };
    }
}

pub fn processLine(raw: []const u8, file_path: ?[]const u8, line_number: usize, allocator: std.mem.Allocator, symbols: *Symbols, owned_symbol_names: ?*std.ArrayList([]u8), output: ?*Result, pass_number: u8, start_pc: u16) AssembleError!u16 {
    var pc = start_pc;
    const no_comment = if (std.mem.indexOfScalar(u8, raw, ';')) |i| raw[0..i] else raw;
    var text = std.mem.trim(u8, no_comment, " \t\r");
    if (text.len == 0) return pc;
    if (std.mem.indexOfScalar(u8, text, ':')) |colon| {
        const name = std.mem.trim(u8, text[0..colon], " \t");
        if (name.len == 0) return error.InvalidSyntax;
        if (pass_number == 1) {
            try defineSymbol(allocator, symbols, owned_symbol_names, name, pc);
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
            try defineSymbol(allocator, symbols, owned_symbol_names, first, value);
        }
        return pc;
    };
    if (first[0] == '.') return error.InvalidDirective;
    if (!isMnemonic(first) and !std.ascii.eqlIgnoreCase(first, "db") and !std.ascii.eqlIgnoreCase(first, "dw")) return error.InvalidMnemonic;
    const byte_offset = if (output) |out| out.bytes.items.len else 0;
    if (std.ascii.eqlIgnoreCase(first, "db")) {
        pc = try emitData(allocator, rest, symbols, pc, output, false, pass_number == 2);
    } else if (std.ascii.eqlIgnoreCase(first, "dw")) {
        pc = try emitData(allocator, rest, symbols, pc, output, true, pass_number == 2);
    } else {
        const size = try encodeInstruction(allocator, first, rest, symbols, pc, output, pass_number == 2);
        pc +%= size;
    }
    if (output) |out| try out.source_map.add(.{ .file_path = file_path, .line = line_number, .address = start_pc, .byte_offset = byte_offset, .byte_count = out.bytes.items.len - byte_offset, .source_line = raw });
    return pc;
}

fn defineSymbol(allocator: std.mem.Allocator, symbols: *Symbols, owned_symbol_names: ?*std.ArrayList([]u8), name: []const u8, value: u16) AssembleError!void {
    var iterator = symbols.iterator();
    while (iterator.next()) |entry| if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, name)) return error.DuplicateSymbol;
    var key = name;
    if (owned_symbol_names) |owned| {
        const copy = allocator.dupe(u8, name) catch return error.OutOfMemory;
        owned.append(allocator, copy) catch {
            allocator.free(copy);
            return error.OutOfMemory;
        };
        key = copy;
        symbols.put(key, value) catch {
            owned.items.len -= 1;
            allocator.free(copy);
            return error.OutOfMemory;
        };
        return;
    }
    symbols.put(key, value) catch return error.OutOfMemory;
}

fn isMnemonic(text: []const u8) bool {
    return instruction.isAssemblerMnemonic(text);
}

fn locateFailureColumns(failure: *FailureLocation, raw: []const u8) void {
    const trimmed = std.mem.trimStart(u8, raw, " \t");
    var token_end = std.mem.indexOfAny(u8, trimmed, " \t:") orelse trimmed.len;
    var target = trimmed[0..token_end];
    if (failure.err == error.InvalidOperand or failure.err == error.UndefinedSymbol or failure.err == error.ValueOutOfRange or failure.err == error.RelativeOutOfRange or failure.err == error.InvalidExpression or failure.err == error.UnterminatedString or failure.err == error.InvalidCharacterLiteral) {
        const first_end = std.mem.indexOfAny(u8, trimmed, " \t") orelse trimmed.len;
        const rest = std.mem.trimStart(u8, trimmed[first_end..], " \t");
        if (rest.len > 0) target = rest;
    }
    if (failure.err == error.DuplicateSymbol) {
        token_end = std.mem.indexOfAny(u8, trimmed, ": \t") orelse trimmed.len;
        target = trimmed[0..token_end];
    }
    const column = if (target.len == 0) @as(usize, 1) else @intFromPtr(target.ptr) - @intFromPtr(raw.ptr) + 1;
    failure.column = column;
    failure.end_column = column + @max(target.len, 1) - 1;
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
