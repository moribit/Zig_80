const std = @import("std");
const assembler = @import("assembler.zig");
const AssembleError = assembler.AssembleError;
const FailureLocation = assembler.FailureLocation;
const Result = assembler.Result;
const Symbols = assembler.Symbols;

pub fn assembleFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8, failure: *FailureLocation) AssembleError!Result {
    var context = FileAssembler{ .io = io, .allocator = allocator, .failure = failure };
    defer context.deinit();
    var symbols = Symbols.init(allocator);
    defer symbols.deinit();
    var pc: u16 = 0;
    try context.passFile(path, &symbols, null, 1, &pc);
    var assembled = Result.init(allocator);
    errdefer assembled.deinit();
    pc = 0;
    try context.passFile(path, &symbols, &assembled, 2, &pc);
    var iterator = symbols.iterator();
    while (iterator.next()) |entry| try assembled.symbols.add(entry.key_ptr.*, entry.value_ptr.*);
    return assembled;
}

const FileAssembler = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    failure: *FailureLocation,
    stack: [64][]const u8 = undefined,
    stack_len: usize = 0,
    owned_symbol_names: std.ArrayList([]u8) = .empty,

    fn deinit(self: *FileAssembler) void {
        for (self.owned_symbol_names.items) |name| self.allocator.free(name);
        self.owned_symbol_names.deinit(self.allocator);
    }

    fn passFile(self: *FileAssembler, path: []const u8, symbols: *assembler.Symbols, output: ?*Result, pass_number: u8, pc: *u16) AssembleError!void {
        if (self.stack_len == self.stack.len) return error.IncludeDepthExceeded;
        const resolved = std.fs.path.resolve(self.allocator, &.{path}) catch return error.OutOfMemory;
        defer self.allocator.free(resolved);
        for (self.stack[0..self.stack_len]) |active| if (std.mem.eql(u8, active, resolved)) return error.IncludeCycle;
        const active_path = self.allocator.dupe(u8, resolved) catch return error.OutOfMemory;
        self.stack[self.stack_len] = active_path;
        self.stack_len += 1;
        defer {
            self.stack_len -= 1;
            self.allocator.free(active_path);
        }
        const source = std.Io.Dir.cwd().readFileAlloc(self.io, resolved, self.allocator, .limited(16 * 1024 * 1024)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.IncludeNotFound;
        defer self.allocator.free(source);
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: usize = 0;
        while (lines.next()) |raw| {
            line_number += 1;
            if (startsFileDirective(raw, "include")) {
                const include_path = fileDirective(raw, "include") orelse {
                    self.failure.set(error.InvalidInclude, raw, line_number, resolved);
                    return error.InvalidInclude;
                };
                const child = std.fs.path.join(self.allocator, &.{ std.fs.path.dirname(resolved) orelse ".", include_path }) catch return error.OutOfMemory;
                defer self.allocator.free(child);
                self.passFile(child, symbols, output, pass_number, pc) catch |err| {
                    if (self.failure.line == 0) self.failure.set(err, raw, line_number, resolved);
                    return err;
                };
                continue;
            }
            if (startsFileDirective(raw, "incbin")) {
                const binary_path = fileDirective(raw, "incbin") orelse {
                    self.failure.set(error.InvalidInclude, raw, line_number, resolved);
                    return error.InvalidInclude;
                };
                const child = std.fs.path.join(self.allocator, &.{ std.fs.path.dirname(resolved) orelse ".", binary_path }) catch return error.OutOfMemory;
                defer self.allocator.free(child);
                const data = std.Io.Dir.cwd().readFileAlloc(self.io, child, self.allocator, .limited(16 * 1024 * 1024)) catch |err| {
                    const mapped: AssembleError = if (err == error.OutOfMemory) error.OutOfMemory else error.IncludeNotFound;
                    self.failure.set(mapped, raw, line_number, resolved);
                    return mapped;
                };
                defer self.allocator.free(data);
                if (data.len > 0xffff) {
                    self.failure.set(error.ValueOutOfRange, raw, line_number, resolved);
                    return error.ValueOutOfRange;
                }
                const byte_offset = if (output) |result| result.bytes.items.len else 0;
                if (output) |result| result.bytes.appendSlice(self.allocator, data) catch return error.OutOfMemory;
                if (output) |result| result.source_map.add(.{ .file_path = resolved, .line = line_number, .address = pc.*, .byte_offset = byte_offset, .byte_count = data.len, .source_line = raw }) catch return error.OutOfMemory;
                pc.* +%= @intCast(data.len);
                continue;
            }
            pc.* = assembler.processLine(raw, resolved, line_number, self.allocator, symbols, &self.owned_symbol_names, output, pass_number, pc.*) catch |err| {
                self.failure.set(err, raw, line_number, resolved);
                return err;
            };
        }
    }
};

fn fileDirective(raw: []const u8, name: []const u8) ?[]const u8 {
    const no_comment = if (std.mem.indexOfScalar(u8, raw, ';')) |index| raw[0..index] else raw;
    const text = std.mem.trim(u8, no_comment, " \t\r");
    if (text.len <= name.len or !std.ascii.eqlIgnoreCase(text[0..name.len], name)) return null;
    if (!std.ascii.isWhitespace(text[name.len])) return null;
    const operand = std.mem.trim(u8, text[name.len..], " \t");
    if (operand.len < 2 or operand[0] != '"' or operand[operand.len - 1] != '"') return null;
    return operand[1 .. operand.len - 1];
}

fn startsFileDirective(raw: []const u8, name: []const u8) bool {
    const no_comment = if (std.mem.indexOfScalar(u8, raw, ';')) |index| raw[0..index] else raw;
    var words = std.mem.tokenizeAny(u8, no_comment, " \t\r");
    const first = words.next() orelse return false;
    return std.ascii.eqlIgnoreCase(first, name);
}
