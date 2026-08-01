const std = @import("std");
const AppState = @import("state.zig").AppState;
const Frame = @import("render/frame.zig").Frame;
const diff = @import("render/diff.zig");
const app = @import("app.zig");
const input = @import("terminal/input.zig");
const command = @import("command.zig");
const terminal = @import("terminal/terminal.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, state: *AppState, color: bool) !void {
    var session = try terminal.TerminalSession.begin(io);
    defer session.deinit();
    var size = try terminal.getSize(io);
    var previous = try Frame.init(allocator, size.width, size.height);
    defer previous.deinit();
    var next = try Frame.init(allocator, size.width, size.height);
    defer next.deinit();
    var has_previous = false;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    try output.ensureTotalCapacity(allocator, size.width * size.height / 2);
    var input_buffer: [128]u8 = undefined;

    while (!state.quit_requested) {
        if (state.execution_state == .running) state.runSlice(500);
        const new_size = terminal.getSize(io) catch size;
        if (new_size.width != size.width or new_size.height != size.height) {
            previous.deinit();
            next.deinit();
            previous = try Frame.init(allocator, new_size.width, new_size.height);
            next = try Frame.init(allocator, new_size.width, new_size.height);
            size = new_size;
            has_previous = false;
        }
        app.render(state, &next);
        try diff.render(allocator, &output, if (has_previous) &previous else null, &next, color);
        if (output.items.len > 0) try std.Io.File.stdout().writeStreamingAll(io, output.items);
        const temporary = previous;
        previous = next;
        next = temporary;
        has_previous = true;

        const count = try terminal.readInput(&input_buffer, 16);
        var offset: usize = 0;
        while (offset < count) {
            const decoded = input.decodeOne(input_buffer[offset..count]) orelse break;
            const action = command.map(decoded.event);
            state.apply(action, io) catch |err| state.setStatus("Command failed: {s}", .{@errorName(err)});
            offset += decoded.consumed;
        }
    }
}
