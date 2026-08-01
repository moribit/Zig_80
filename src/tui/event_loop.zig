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
    var decoder: input.InputDecoder = .{};

    while (!state.quit_requested) {
        const frame_now_ms: i64 = @intCast(@divTrunc(std.Io.Clock.awake.now(io).nanoseconds, std.time.ns_per_ms));
        state.tickUi(frame_now_ms);
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
        decoder.feed(input_buffer[0..count]);
        const now_ms: i64 = @intCast(@divTrunc(std.Io.Clock.awake.now(io).nanoseconds, std.time.ns_per_ms));
        while (decoder.next(now_ms)) |event| {
            const action = command.map(event);
            state.apply(action, io) catch |err| state.setStatus("Command failed: {s}", .{@errorName(err)});
        }
    }
}
