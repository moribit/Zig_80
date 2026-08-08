const std = @import("std");

pub const Symbol = struct { name: []const u8, value: u16 };

pub const SymbolTable = struct {
    items: std.ArrayList(Symbol) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SymbolTable) void {
        for (self.items.items) |symbol| self.allocator.free(symbol.name);
        self.items.deinit(self.allocator);
    }

    pub fn add(self: *SymbolTable, name: []const u8, value: u16) !void {
        if (self.address(name) != null) return error.DuplicateSymbol;
        try self.items.append(self.allocator, .{ .name = try self.allocator.dupe(u8, name), .value = value });
    }

    pub fn address(self: *const SymbolTable, name: []const u8) ?u16 {
        for (self.items.items) |symbol| if (std.ascii.eqlIgnoreCase(symbol.name, name)) return symbol.value;
        return null;
    }

    pub fn label(self: *const SymbolTable, address_value: u16) ?[]const u8 {
        for (self.items.items) |symbol| if (symbol.value == address_value) return symbol.name;
        return null;
    }

    pub fn nearestLabel(self: *const SymbolTable, address_value: u16) ?Symbol {
        var best: ?Symbol = null;
        for (self.items.items) |symbol| if (symbol.value <= address_value and (best == null or symbol.value > best.?.value)) {
            best = symbol;
        };
        return best;
    }

    pub fn write(self: *const SymbolTable, writer: *std.Io.Writer) !void {
        try writer.writeAll("# zig80-symbols-v1\n");
        for (self.items.items) |symbol| try writer.print("{X:0>4} {s}\n", .{ symbol.value, symbol.name });
    }

    pub fn parse(allocator: std.mem.Allocator, text: []const u8) !SymbolTable {
        var table = SymbolTable.init(allocator);
        errdefer table.deinit();
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            var words = std.mem.tokenizeAny(u8, line, " \t");
            const value = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidSymbolFile, 16);
            const name = words.next() orelse return error.InvalidSymbolFile;
            if (words.next() != null) return error.InvalidSymbolFile;
            try table.add(name, value);
        }
        return table;
    }
};

pub const SourceMapEntry = struct {
    file_path: ?[]const u8,
    line: usize,
    address: u16,
    byte_offset: usize,
    byte_count: usize,
    source_line: []const u8,
};

pub const SourceMap = struct {
    items: std.ArrayList(SourceMapEntry) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SourceMap {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SourceMap) void {
        for (self.items.items) |entry| {
            if (entry.file_path) |path| self.allocator.free(path);
            self.allocator.free(entry.source_line);
        }
        self.items.deinit(self.allocator);
    }

    pub fn add(self: *SourceMap, entry: SourceMapEntry) !void {
        try self.items.append(self.allocator, .{
            .file_path = if (entry.file_path) |path| try self.allocator.dupe(u8, path) else null,
            .line = entry.line,
            .address = entry.address,
            .byte_offset = entry.byte_offset,
            .byte_count = entry.byte_count,
            .source_line = try self.allocator.dupe(u8, entry.source_line),
        });
    }

    pub fn sourceForAddress(self: *const SourceMap, address_value: u16) ?SourceMapEntry {
        for (self.items.items) |entry| if (entry.address == address_value) return entry;
        return null;
    }

    pub fn addressForSource(self: *const SourceMap, file_path: ?[]const u8, line: usize) ?u16 {
        for (self.items.items) |entry| if (entry.line == line and pathsEqual(entry.file_path, file_path)) return entry.address;
        return null;
    }

    pub fn write(self: *const SourceMap, writer: *std.Io.Writer) !void {
        try writer.writeAll("# zig80-source-map-v1\n");
        for (self.items.items) |entry| try writer.print("{X:0>4}\t{s}\t{d}\n", .{ entry.address, entry.file_path orelse "-", entry.line });
    }
};

fn pathsEqual(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs == null or rhs == null) return lhs == null and rhs == null;
    return std.mem.eql(u8, lhs.?, rhs.?);
}
