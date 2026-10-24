const std = @import("std");

pub const Up: u8 = 1 << 0;
pub const Down: u8 = 1 << 1;
pub const Left: u8 = 1 << 2;
pub const Right: u8 = 1 << 3;
pub const A: u8 = 1 << 4;
pub const B: u8 = 1 << 5;
pub const Start: u8 = 1 << 6;

pub const Button = enum(u3) { up, down, left, right, a, b, start };
pub const Action = enum { press, release };
pub const Event = struct { at_instruction: u64, action: Action, button: Button };

pub fn mask(button: Button) u8 {
    return @as(u8, 1) << @intFromEnum(button);
}

pub const State = struct {
    value: u8 = 0,

    pub fn apply(self: *State, action: Action, button: Button) bool {
        const before = self.value;
        switch (action) {
            .press => self.value |= mask(button),
            .release => self.value &= ~mask(button),
        }
        return before != self.value;
    }

    pub fn pressed(self: State, button: Button) bool {
        return self.value & mask(button) != 0;
    }

    pub fn releaseAll(self: *State) void {
        self.value = 0;
    }
};

pub fn Recording(comptime capacity: usize) type {
    return struct {
        events: [capacity]Event = undefined,
        len: usize = 0,

        pub fn record(self: *@This(), event: Event) bool {
            if (self.len == capacity) return false;
            self.events[self.len] = event;
            self.len += 1;
            return true;
        }

        pub fn clear(self: *@This()) void {
            self.len = 0;
        }
    };
}

pub const Replay = struct {
    events: []const Event,
    next_index: usize = 0,
    state: State = .{},
    initial_state: State = .{},
    last_instruction: ?u64 = null,

    pub fn reset(self: *Replay) void {
        self.next_index = 0;
        self.state = self.initial_state;
        self.last_instruction = null;
    }

    pub fn advance(self: *Replay, instruction: u64) State {
        if (self.last_instruction) |last| {
            if (instruction < last) self.reset();
        } else self.state = self.initial_state;
        self.last_instruction = instruction;
        while (self.next_index < self.events.len and self.events[self.next_index].at_instruction <= instruction) : (self.next_index += 1) {
            const event = self.events[self.next_index];
            _ = self.state.apply(event.action, event.button);
        }
        return self.state;
    }
};

pub const ScriptDiagnostic = struct {
    line: usize = 0,
    column: usize = 0,
    err: anyerror = error.InvalidInputEvent,
};

pub fn parseScript(allocator: std.mem.Allocator, text: []const u8) ![]Event {
    var diagnostic: ScriptDiagnostic = .{};
    return parseScriptLocated(allocator, text, &diagnostic);
}

pub fn parseScriptLocated(allocator: std.mem.Allocator, text: []const u8, diagnostic: *ScriptDiagnostic) ![]Event {
    diagnostic.* = .{};
    var events: std.ArrayList(Event) = .empty;
    errdefer events.deinit(allocator);
    var line_number: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        line_number += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        diagnostic.* = .{ .line = line_number, .column = @intFromPtr(line.ptr) - @intFromPtr(raw.ptr) + 1 };
        errdefer |err| diagnostic.err = err;
        var words = std.mem.tokenizeAny(u8, line, " \t");
        const at = std.fmt.parseInt(u64, words.next() orelse return error.InvalidInputEvent, 10) catch return error.InvalidInputTimestamp;
        const action_text = words.next() orelse return error.InvalidInputEvent;
        diagnostic.column = @intFromPtr(action_text.ptr) - @intFromPtr(raw.ptr) + 1;
        const action: Action = if (std.ascii.eqlIgnoreCase(action_text, "press")) .press else if (std.ascii.eqlIgnoreCase(action_text, "release")) .release else return error.InvalidInputAction;
        const button_text = words.next() orelse return error.InvalidInputEvent;
        diagnostic.column = @intFromPtr(button_text.ptr) - @intFromPtr(raw.ptr) + 1;
        const button = parseButton(button_text) orelse return error.InvalidInputButton;
        if (words.next()) |extra| {
            diagnostic.column = @intFromPtr(extra.ptr) - @intFromPtr(raw.ptr) + 1;
            return error.InvalidInputEvent;
        }
        try events.append(allocator, .{ .at_instruction = at, .action = action, .button = button });
    }
    // std.mem.sort is stable: equal timestamps retain source press/release order.
    std.mem.sort(Event, events.items, {}, struct {
        fn lessThan(_: void, lhs: Event, rhs: Event) bool {
            return lhs.at_instruction < rhs.at_instruction;
        }
    }.lessThan);
    diagnostic.* = .{};
    return events.toOwnedSlice(allocator);
}

pub fn parseButton(text: []const u8) ?Button {
    inline for (std.enums.values(Button)) |value| if (std.ascii.eqlIgnoreCase(text, @tagName(value))) return value;
    return null;
}

pub fn writeScript(events: []const Event, writer: *std.Io.Writer) !void {
    for (events) |event| try writer.print("{d} {s} {s}\n", .{ event.at_instruction, @tagName(event.action), @tagName(event.button) });
}
