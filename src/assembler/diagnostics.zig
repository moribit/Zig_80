pub fn message(err: anyerror) []const u8 {
    return switch (err) {
        error.DuplicateSymbol => "duplicate symbol",
        error.UndefinedSymbol => "undefined symbol",
        error.ValueOutOfRange => "value is out of range",
        error.RelativeOutOfRange => "JR target is out of range; use JP",
        else => "invalid assembly syntax",
    };
}
