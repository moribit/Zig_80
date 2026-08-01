pub const Severity = enum { note, warning, @"error" };

pub const Diagnostic = struct {
    severity: Severity = .@"error",
    message: []const u8,
    file_path: ?[]const u8 = null,
    line: ?usize = null,
    column: ?usize = null,
    source_line: ?[]const u8 = null,
    hint: ?[]const u8 = null,
};

pub fn message(err: anyerror) []const u8 {
    return switch (err) {
        error.DuplicateSymbol => "duplicate symbol",
        error.UndefinedSymbol => "undefined symbol",
        error.ValueOutOfRange => "value is out of range",
        error.RelativeOutOfRange => "JR target is out of range; use JP",
        else => "invalid assembly syntax",
    };
}

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
