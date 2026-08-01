const key = @import("terminal/key.zig");

pub const Screen = enum { editor, debug, memory, bus, display, help };
pub const Direction = enum { up, down, left, right, home, end, page_up, page_down };
pub const Command = union(enum) {
    insert_character: u21,
    newline,
    backspace,
    delete,
    move_cursor: Direction,
    save,
    assemble,
    run,
    pause,
    continue_execution,
    step_instruction,
    reset,
    toggle_breakpoint,
    switch_screen: Screen,
    show_help,
    quit,
    none,
};

pub fn map(event: key.KeyEvent) Command {
    switch (event.code) {
        .character => |character| {
            if (event.ctrl) return switch (character) {
                's' => .save,
                'q', 'c' => .quit,
                'r' => .reset,
                'a' => .assemble,
                'g' => .run,
                'n' => .step_instruction,
                'p' => .pause,
                'e' => .continue_execution,
                'b' => .toggle_breakpoint,
                else => .none,
            };
            if (event.alt and character >= '1' and character <= '5') return .{ .switch_screen = @enumFromInt(character - '1') };
            if (character == '?') return .show_help;
            return .{ .insert_character = character };
        },
        .enter => return .newline,
        .backspace => return .backspace,
        .delete => return .delete,
        .up => return .{ .move_cursor = .up },
        .down => return .{ .move_cursor = .down },
        .left => return .{ .move_cursor = .left },
        .right => return .{ .move_cursor = .right },
        .home => return .{ .move_cursor = .home },
        .end => return .{ .move_cursor = .end },
        .page_up => return .{ .move_cursor = .page_up },
        .page_down => return .{ .move_cursor = .page_down },
        .function => |number| return switch (number) {
            1 => .show_help,
            2 => .assemble,
            5 => .run,
            6 => .step_instruction,
            7 => .continue_execution,
            8 => .pause,
            9 => .toggle_breakpoint,
            else => .none,
        },
        .escape, .tab => return .none,
    }
}
