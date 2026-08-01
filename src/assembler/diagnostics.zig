pub const Severity = enum { note, warning, @"error" };

pub const Diagnostic = struct {
    severity: Severity = .@"error",
    message: []const u8,
    file_path: ?[]const u8 = null,
    line: ?usize = null,
    column: ?usize = null,
    end_column: ?usize = null,
    source_line: ?[]const u8 = null,
    hint: ?[]const u8 = null,
};

pub fn message(err: anyerror) []const u8 {
    return switch (err) {
        error.DuplicateSymbol => "duplicate symbol",
        error.UndefinedSymbol => "undefined symbol",
        error.ValueOutOfRange => "value is out of range",
        error.RelativeOutOfRange => "JR target is out of range; use JP",
        error.InvalidMnemonic => "invalid mnemonic",
        error.InvalidOperand => "invalid operand",
        error.InvalidDirective => "invalid directive",
        error.InvalidExpression => "invalid expression",
        error.UnterminatedString => "unterminated string",
        error.InvalidCharacterLiteral => "invalid character literal",
        else => "invalid assembly syntax",
    };
}

pub const OwnedDiagnostic = struct {
    allocator: @import("std").mem.Allocator,
    value: Diagnostic,

    pub fn init(allocator: @import("std").mem.Allocator, diagnostic: Diagnostic) !OwnedDiagnostic {
        const message_copy = try allocator.dupe(u8, diagnostic.message);
        errdefer allocator.free(message_copy);
        const file_copy = if (diagnostic.file_path) |text| try allocator.dupe(u8, text) else null;
        errdefer if (file_copy) |text| allocator.free(text);
        const source_copy = if (diagnostic.source_line) |text| try allocator.dupe(u8, text) else null;
        errdefer if (source_copy) |text| allocator.free(text);
        const hint_copy = if (diagnostic.hint) |text| try allocator.dupe(u8, text) else null;
        return .{ .allocator = allocator, .value = .{
            .severity = diagnostic.severity,
            .message = message_copy,
            .file_path = file_copy,
            .line = diagnostic.line,
            .column = diagnostic.column,
            .end_column = diagnostic.end_column,
            .source_line = source_copy,
            .hint = hint_copy,
        } };
    }

    pub fn deinit(self: *OwnedDiagnostic) void {
        self.allocator.free(self.value.message);
        if (self.value.file_path) |text| self.allocator.free(text);
        if (self.value.source_line) |text| self.allocator.free(text);
        if (self.value.hint) |text| self.allocator.free(text);
        self.* = undefined;
    }
};

pub fn fromError(err: anyerror, file_path: ?[]const u8) Diagnostic {
    return .{
        .message = message(err),
        .file_path = file_path,
        .hint = switch (err) {
            error.RelativeOutOfRange => "use JP for a target outside -128...+127",
            error.DuplicateSymbol => "rename or remove one definition",
            error.UndefinedSymbol => "define the symbol before encoding completes",
            else => null,
        },
    };
}

pub fn fromFailure(failure: anytype, file_path: ?[]const u8) Diagnostic {
    var diagnostic = fromError(failure.err, file_path);
    diagnostic.line = failure.line;
    diagnostic.column = failure.column;
    diagnostic.end_column = failure.end_column;
    diagnostic.source_line = failure.source_line;
    return diagnostic;
}
