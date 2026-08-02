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
    toggle_game_input,
    switch_screen: Screen,
    show_help,
    open_palette,
    palette_or_colon,
    help_or_question,
    next_pane,
    previous_pane,
    undo,
    redo,
    search,
    jump_definition,
    jump_back,
    jump_forward,
    select_cursor: Direction,
    quit,
    cancel,
    none,
};

pub fn map(event: key.KeyEvent) Command {
    switch (event.code) {
        .character => |character| {
            if (event.ctrl) return switch (character) {
                's' => .save,
                'q', 'c' => .quit,
                'r' => .assemble,
                'e' => .run,
                't' => .step_instruction,
                'b' => .toggle_breakpoint,
                ' ' => .continue_execution,
                'p' => .open_palette,
                'z' => .undo,
                'y' => .redo,
                'f' => .search,
                'g' => .toggle_game_input,
                ']' => .jump_definition,
                '1'...'5' => .{ .switch_screen = @enumFromInt(character - '1') },
                else => .none,
            };
            if (event.alt and character >= '1' and character <= '5') return .{ .switch_screen = @enumFromInt(character - '1') };
            if (character == '?') return .help_or_question;
            if (character == ':') return .palette_or_colon;
            return .{ .insert_character = character };
        },
        .enter => return .newline,
        .backspace => return .backspace,
        .delete => return .delete,
        .up => return if (event.shift) .{ .select_cursor = .up } else .{ .move_cursor = .up },
        .down => return if (event.shift) .{ .select_cursor = .down } else .{ .move_cursor = .down },
        .left => return if (event.alt) .jump_back else if (event.shift) .{ .select_cursor = .left } else .{ .move_cursor = .left },
        .right => return if (event.alt) .jump_forward else if (event.shift) .{ .select_cursor = .right } else .{ .move_cursor = .right },
        .home => return .{ .move_cursor = .home },
        .end => return .{ .move_cursor = .end },
        .page_up => return .{ .move_cursor = .page_up },
        .page_down => return .{ .move_cursor = .page_down },
        .function => return .none,
        .escape => return .cancel,
        .tab => return if (event.shift) .previous_pane else .next_pane,
    }
}
