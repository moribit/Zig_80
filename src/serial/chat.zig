const std = @import("std");
const wire = @import("chat_protocol.zig");
const Transport = @import("transport.zig").Transport;
const Http = @import("chat_http.zig").Connection;
const Ollama = @import("chat_ollama.zig");
const Queue = @import("chat_queue.zig").Queue;
const Normalizer = @import("chat_text.zig").Normalizer;

pub const usage =
    \\zig80 chat --target pc8001 --port PATH --enable-tx --voltage-confirmed
    \\  [--provider ollama] [--model gemma3:1b] [--ollama-url http://127.0.0.1:11434]
    \\  [--mock] [--no-deploy] [--max-response-chars 160] [--max-history 4]
    \\  [--timeout 60000] [--session-minutes 30] [--log FILE]
    \\  [--text-chunk-size 8] (1..32; smaller chunks reduce bursts, with more UART overhead)
    \\ESC/STOP ends the application and returns to the resident loader.
    \\--no-deploy only reconnects to a newly started application waiting for HELLO ACK.
    \\
;
const Options = struct {
    port: ?[]const u8 = null,
    model: []const u8 = "gemma3:1b",
    url: []const u8 = "http://127.0.0.1:11434",
    log: ?[]const u8 = null,
    mock: bool = false,
    no_deploy: bool = false,
    target: bool = false,
    tx: bool = false,
    voltage: bool = false,
    max_chars: usize = 160,
    max_history: usize = 4,
    text_chunk_size: u8 = 8,
    timeout_us: u64 = 60_000_000,
    session_us: u64 = 30 * 60_000_000,
};
fn parse(args: []const []const u8) !Options {
    var o: Options = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const flag = args[i];
        if (std.mem.eql(u8, flag, "--mock")) {
            o.mock = true;
            continue;
        }
        if (std.mem.eql(u8, flag, "--no-deploy")) {
            o.no_deploy = true;
            continue;
        }
        if (std.mem.eql(u8, flag, "--enable-tx")) {
            o.tx = true;
            continue;
        }
        if (std.mem.eql(u8, flag, "--voltage-confirmed")) {
            o.voltage = true;
            continue;
        }
        i += 1;
        if (i == args.len) return error.InvalidArguments;
        const value = args[i];
        if (std.mem.eql(u8, flag, "--port")) o.port = value else if (std.mem.eql(u8, flag, "--model")) o.model = value else if (std.mem.eql(u8, flag, "--ollama-url")) o.url = value else if (std.mem.eql(u8, flag, "--log")) o.log = value else if (std.mem.eql(u8, flag, "--target")) {
            if (!std.mem.eql(u8, value, "pc8001")) return error.UnsupportedTarget;
            o.target = true;
        } else if (std.mem.eql(u8, flag, "--provider")) {
            if (!std.mem.eql(u8, value, "ollama")) return error.UnsupportedProvider;
        } else if (std.mem.eql(u8, flag, "--max-response-chars")) {
            o.max_chars = try std.fmt.parseInt(usize, value, 10);
            if (o.max_chars == 0 or o.max_chars > 160) return error.InvalidResponseLimit;
        } else if (std.mem.eql(u8, flag, "--text-chunk-size")) {
            o.text_chunk_size = try std.fmt.parseInt(u8, value, 10);
            if (o.text_chunk_size == 0 or o.text_chunk_size > 32) return error.InvalidTextChunkSize;
        } else if (std.mem.eql(u8, flag, "--max-history")) {
            o.max_history = try std.fmt.parseInt(usize, value, 10);
            if (o.max_history > 8) return error.InvalidHistoryLimit;
        } else if (std.mem.eql(u8, flag, "--timeout")) {
            const n = try std.fmt.parseInt(u64, value, 10);
            if (n < 100 or n > 300000) return error.InvalidTimeout;
            o.timeout_us = n * 1000;
        } else if (std.mem.eql(u8, flag, "--session-minutes")) {
            const n = try std.fmt.parseInt(u64, value, 10);
            if (n == 0 or n > 60) return error.InvalidSessionLimit;
            o.session_us = n * 60_000_000;
        } else return error.InvalidArguments;
    }
    if (!o.target) return error.ExplicitTargetRequired;
    if (!o.tx or !o.voltage) return error.TransmitConfirmationRequired;
    if (o.port == null) return error.ExplicitPortRequired;
    if (o.model.len == 0 or o.model.len > 128) return error.InvalidModel;
    return o;
}

const Turn = struct {
    prompt: [64]u8 = undefined,
    prompt_len: usize = 0,
    answer: [160]u8 = undefined,
    answer_len: usize = 0,
};
const Message = struct { role: []const u8, content: []const u8 };
const History = struct {
    turns: [8]Turn = undefined,
    len: usize = 0,
    fn add(self: *History, turn: Turn, limit: usize) void {
        if (limit == 0) return;
        if (self.len == limit) {
            for (1..self.len) |i| self.turns[i - 1] = self.turns[i];
            self.len -= 1;
        }
        self.turns[self.len] = turn;
        self.len += 1;
    }
    fn request(self: *const History, model: []const u8, prompt: []const u8, buffer: []u8) ![]const u8 {
        var messages: [18]Message = undefined;
        messages[0] = .{ .role = "system", .content = "You are chatting on a vintage 40-column computer. Always use plain ASCII English, no Markdown, Unicode or emojis. Use short sentences. Keep replies under 160 characters." };
        var count: usize = 1;
        for (self.turns[0..self.len]) |*turn| {
            messages[count] = .{ .role = "user", .content = turn.prompt[0..turn.prompt_len] };
            messages[count + 1] = .{ .role = "assistant", .content = turn.answer[0..turn.answer_len] };
            count += 2;
        }
        messages[count] = .{ .role = "user", .content = prompt };
        var writer = std.Io.Writer.fixed(buffer);
        try std.json.Stringify.value(.{ .model = model, .messages = messages[0 .. count + 1], .stream = true, .options = .{ .num_predict = 96 } }, .{}, &writer);
        return writer.buffered();
    }
};

const Bridge = struct {
    channel: *Transport,
    out: *std.Io.Writer,
    receiver: wire.Receiver = .{},
    sender: wire.Sender = .{},
    parser: wire.Parser = .{},
    last_byte: u64 = 0,
    prompt: [64]u8 = undefined,
    prompt_len: usize = 0,
    prompt_ready: bool = false,
    connected: bool = false,
    closed: bool = false,
    session_end: u64,

    fn event(self: *Bridge, name: []const u8, count: usize) !void {
        if (self.channel.session.log) |log| {
            try log.print("{{\"event\":\"{s}\",\"host_us\":{d},\"count\":{d}}}\n", .{ name, self.channel.now(), count });
            try log.flush();
        }
    }
    fn textEvent(self: *Bridge, text: []const u8) !void {
        if (self.channel.session.log) |log| {
            try std.json.Stringify.value(.{ .event = "display_ack", .host_us = self.channel.now(), .text = text }, .{}, log);
            try log.writeByte('\n');
            try log.flush();
        }
    }
    fn transmit(self: *Bridge, frame: wire.Frame) !void {
        var buffer: [wire.max_frame]u8 = undefined;
        const bytes = try wire.encode(&buffer, frame.kind, frame.seq, frame.payload[0..frame.len]);
        const deadline = self.channel.now() + 3_000_000;
        try self.channel.send(bytes, deadline);
        try self.channel.drain(deadline);
    }
    fn next(self: *Bridge, until: u64) !?wire.Frame {
        while (self.channel.now() < until) {
            if (self.channel.now() >= self.session_end) return error.ChatSessionExpired;
            const b = self.channel.readByte(until) catch |err| switch (err) {
                error.LoaderTimeout => return null,
                else => return err,
            };
            const now = self.channel.now();
            if (now -| self.last_byte > 2_000_000) self.parser.reset();
            self.last_byte = now;
            const frame = self.parser.feed(b) catch {
                try self.event("chat_invalid_frame", 1);
                continue;
            };
            if (frame) |f| return f;
        }
        return null;
    }
    fn accept(self: *Bridge, frame: wire.Frame) !void {
        if (frame.kind == .ack) return;
        // Validate before advancing a receiver or acknowledging a frame.
        switch (frame.kind) {
            .hello => if (!std.mem.eql(u8, frame.payload[0..frame.len], "C1")) return error.ChatVersionMismatch,
            .cancel => if (frame.len != 0) return error.InvalidChatFrame,
            .prompt => {
                if (!self.connected or frame.len < 2 or frame.payload[0] > 1) return error.InvalidChatFrame;
                for (frame.payload[1..frame.len]) |b| if (b < 32 or b > 126) return error.InvalidChatFrame;
            },
            else => return error.InvalidChatFrame,
        }
        switch (self.receiver.accept(frame)) {
            .rejected => return,
            .duplicate => {
                try self.transmit(wire.ack(frame.seq));
                return;
            },
            .accepted => {},
        }
        if (frame.kind == .prompt) {
            if (self.prompt_ready or self.prompt_len + frame.len - 1 > 64) return error.PromptTooLarge;
            @memcpy(self.prompt[self.prompt_len..][0 .. frame.len - 1], frame.payload[1..frame.len]);
            self.prompt_len += frame.len - 1;
            self.prompt_ready = frame.payload[0] == 1;
        }
        if (frame.kind == .cancel) self.closed = true;
        try self.transmit(wire.ack(frame.seq));
    }
    fn send(self: *Bridge, kind: wire.Kind, payload: []const u8) !void {
        var frame = try self.sender.begin(kind, payload, 2);
        while (true) {
            try self.transmit(frame);
            const deadline = self.channel.now() + 4_000_000;
            while (self.channel.now() < deadline) {
                if (try self.next(deadline)) |incoming| {
                    if (self.sender.acknowledge(incoming)) {
                        try self.event("chat_frame_ack", payload.len);
                        return;
                    }
                    try self.accept(incoming);
                    if (self.closed) return error.ChatClosed;
                }
            }
            frame = try self.sender.timeout();
            try self.event("chat_retry", 1);
        }
    }
    fn handshake(self: *Bridge, model: []const u8) !void {
        const deadline = self.channel.now() + 15_000_000;
        while (self.channel.now() < deadline) {
            if (try self.next(deadline)) |frame| {
                if (frame.kind != .hello or frame.seq != 0) return error.ChatHelloRequired;
                try self.accept(frame);
                self.connected = true;
                var ready: [22]u8 = undefined;
                ready[0..2].* = .{ 'C', '1' };
                const label_len = @min(model.len, 20);
                for (model[0..label_len], 0..) |b, i| ready[i + 2] = if (b >= 32 and b < 127) std.ascii.toUpper(b) else '?';
                try self.send(.ready, ready[0 .. label_len + 2]);
                return;
            }
        }
        return error.ChatHelloTimeout;
    }
    fn generate(self: *Bridge, allocator: std.mem.Allocator, options: Options, history: *History) !void {
        var turn: Turn = .{};
        turn.prompt_len = self.prompt_len;
        @memcpy(turn.prompt[0..turn.prompt_len], self.prompt[0..turn.prompt_len]);
        self.prompt_ready = false;
        self.prompt_len = 0;
        try self.event("prompt", turn.prompt_len);
        var json: [8192]u8 = undefined;
        const request = try history.request(options.model, turn.prompt[0..turn.prompt_len], &json);
        var http: ?Http = if (options.mock) null else try Http.open(self.channel.session.port.io, options.url, request);
        defer if (http) |*connection| connection.close();
        var decoder: Ollama.Decoder = .{};
        var normalizer: Normalizer = .{ .remaining = options.max_chars };
        var queue: Queue = .{ .chunk_size = options.text_chunk_size, .flush_us = 100_000 };
        var done = false;
        var buffer: [32]u8 = undefined;
        const mock_chunks = [_][]const u8{ "HELLO!\n", "I AM GEMMA.\n", "NICE TO MEET YOU." };
        var mock_index: usize = 0;
        var next_mock = self.channel.now();
        var activity = self.channel.now();
        while (!done or queue.len > 0) {
            if (try self.next(self.channel.now() + 1_000)) |incoming| try self.accept(incoming);
            if (self.closed) return error.ChatClosed;
            if (queue.peek(self.channel.now(), done, &buffer)) |text| {
                try self.send(.text, text);
                try self.event("text_ack", text.len);
                try self.textEvent(text);
                try queue.consume(text.len, self.channel.now());
                activity = self.channel.now();
                continue;
            }
            if (!done and queue.len < 32) {
                if (options.mock) {
                    if (self.channel.now() >= next_mock) {
                        if (mock_index == mock_chunks.len) {
                            done = true;
                            try self.event("model_done", 0);
                        } else {
                            for (mock_chunks[mock_index]) |b| if (try normalizer.feed(b)) |c| {
                                try queue.push(c, self.channel.now());
                                turn.answer[turn.answer_len] = c;
                                turn.answer_len += 1;
                            };
                            try self.event("model_chunk", mock_index);
                            mock_index += 1;
                            next_mock = self.channel.now() + 500_000;
                        }
                    }
                } else {
                    http_bytes: for (0..1024) |_| {
                        const byte = try http.?.next() orelse break;
                        activity = self.channel.now();
                        if (try decoder.feed(allocator, byte)) |parsed| {
                            defer parsed.deinit();
                            const chunk = try Ollama.getEvent(parsed.value);
                            for (chunk.text) |b| if (try normalizer.feed(b)) |c| {
                                try queue.push(c, self.channel.now());
                                turn.answer[turn.answer_len] = c;
                                turn.answer_len += 1;
                            };
                            done = chunk.done;
                            try self.event(if (done) "model_done" else "model_chunk", chunk.text.len);
                            break :http_bytes;
                        }
                    }
                }
                if (normalizer.remaining == 0) {
                    done = true;
                    if (http) |*connection| connection.close();
                    http = null;
                    try self.event("model_limit", turn.answer_len);
                }
            }
            if (!done and self.channel.now() - activity > options.timeout_us) return error.OllamaTimeout;
            try self.channel.poll(self.channel.now() + 1_000);
        }
        if (normalizer.finish()) |c| {
            buffer[0] = c;
            try self.send(.text, buffer[0..1]);
            turn.answer[turn.answer_len] = c;
            turn.answer_len += 1;
        }
        try self.send(.done, "");
        try self.event("answer_complete", turn.answer_len);
        history.add(turn, options.max_history);
        try self.out.print("Answer complete: {d} ASCII characters, history={d} turns\n", .{ turn.answer_len, history.len });
        try self.out.flush();
    }
    fn serve(self: *Bridge, allocator: std.mem.Allocator, options: Options) !void {
        try self.handshake(if (options.mock) "MOCK" else options.model);
        try self.out.print("Chat ready: model={s} provider={s} text_chunk_size={d}; type on PC-8001, ESC/STOP exits\n", .{ options.model, if (options.mock) "mock" else "ollama", options.text_chunk_size });
        try self.event("text_chunk_size", options.text_chunk_size);
        try self.out.flush();
        var history: History = .{};
        while (!self.closed) {
            if (try self.next(self.channel.now() + 20_000)) |frame| try self.accept(frame);
            if (self.prompt_ready) self.generate(allocator, options, &history) catch |err| switch (err) {
                error.ChatClosed => return,
                error.DeviceDisconnected, error.Interrupted, error.ChatSessionExpired, error.RetryLimit => return err,
                else => {
                    try self.event("provider_error", 1);
                    try self.out.print("Inference failed: {s}\n", .{@errorName(err)});
                    try self.out.flush();
                    try self.send(.err, "");
                },
            };
        }
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: []const []const u8, out: *std.Io.Writer, _: *std.Io.Writer) !void {
    if (args.len == 0 or std.mem.eql(u8, args[0], "--help")) {
        try out.writeAll(usage);
        return;
    }
    const options = try parse(args);
    // All assembly and file creation precede ARM.
    var failure: @import("../assembler/assembler.zig").FailureLocation = .{};
    var image = try @import("../assembler/assembler.zig").assembleFile(io, allocator, "examples/pc8001/chat.asm", &failure);
    defer image.deinit();
    if (image.bytes.items.len > 0x715) return error.ChatCodeOverlapsBuffers;
    var log_file: ?std.Io.File = null;
    var log_buffer: [4096]u8 = undefined;
    var log_writer: std.Io.File.Writer = undefined;
    if (options.log) |path| {
        if (std.mem.eql(u8, path, options.port.?) or std.mem.eql(u8, path, "examples/pc8001/chat.asm")) return error.UnsafeLogPath;
        log_file = try std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true });
        log_writer = log_file.?.writer(io, &log_buffer);
    }
    defer if (log_file) |file| {
        log_writer.interface.flush() catch {};
        file.close(io);
    };
    var signals = @import("cli.zig").Signals.init();
    defer signals.deinit();
    var channel = try Transport.open(io, options.port.?, out, if (log_file != null) &log_writer.interface else null, 3_000_000);
    defer channel.close();
    if (!options.no_deploy) _ = try @import("deploy.zig").uploadApplication(&channel, image.bytes.items, out);
    var bridge: Bridge = .{ .channel = &channel, .out = out, .session_end = channel.now() + options.session_us };
    bridge.serve(allocator, options) catch |err| {
        if (err == error.Interrupted or err == error.ChatSessionExpired) {
            @import("cli.zig").clearInterrupt();
            bridge.session_end = channel.now() + 3_000_000;
            // Best effort application CANCEL; never re-arm after transport loss.
            if (bridge.connected) bridge.send(.cancel, "") catch {};
        }
        return err;
    };
    try channel.finish(channel.now() + 3_000_000);
    try out.writeAll("Chat ended; TX released.\n");
}

test "chat options require explicit electrical confirmations and bounded resources" {
    try std.testing.expectError(error.TransmitConfirmationRequired, parse(&.{ "--target", "pc8001", "--port", "mock" }));
    const options = try parse(&.{ "--target", "pc8001", "--port", "mock", "--enable-tx", "--voltage-confirmed", "--mock" });
    try std.testing.expect(options.mock);
    try std.testing.expectEqual(@as(usize, 160), options.max_chars);
    try std.testing.expectEqual(@as(u8, 8), options.text_chunk_size);
    try std.testing.expectError(error.InvalidTextChunkSize, parse(&.{ "--text-chunk-size", "0" }));
    try std.testing.expectError(error.InvalidTextChunkSize, parse(&.{ "--text-chunk-size", "33" }));
    var history: History = .{};
    var turn: Turn = .{};
    turn.prompt[0] = 'A';
    turn.prompt_len = 1;
    for (0..10) |_| history.add(turn, 4);
    try std.testing.expectEqual(@as(usize, 4), history.len);
    var bytes: [8192]u8 = undefined;
    const request = try history.request("gemma3:1b", "HELLO", &bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, request, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("stream").?.bool);
    try std.testing.expectEqual(@as(usize, 10), parsed.value.object.get("messages").?.array.items.len);
}
