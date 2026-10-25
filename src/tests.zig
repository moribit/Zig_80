test {
    _ = @import("serial/artifacts.zig");
    _ = @import("serial/protocol.zig");
    _ = @import("serial/z80_tests.zig");
    _ = @import("documentation_test.zig");
    _ = @import("cpu/tests.zig");
    _ = @import("assembler/tests.zig");
    _ = @import("disassembler/tests.zig");
    _ = @import("machine/tests.zig");
    _ = @import("debugger/tests.zig");
    _ = @import("trace/tests.zig");
    _ = @import("tui/tests.zig");
    _ = @import("cpu/quality_tests.zig");
    _ = @import("cpu/extension_tests.zig");
    _ = @import("machine/quality_tests.zig");
    _ = @import("machine/handheld_tests.zig");
}
