const std = @import("std");
const Io = std.Io;
const assembler = @import("../assembler/assembler.zig");
const diagnostics = @import("../assembler/diagnostics.zig");
const Machine = @import("../machine/machine.zig").Machine;
const DebugSession = @import("../debugger/session.zig").DebugSession;
const CpuSnapshot = @import("../debugger/session.zig").CpuSnapshot;
const SourceBuffer = @import("editor/buffer.zig").SourceBuffer;
const TraceBuffer = @import("../trace/trace.zig").TraceBuffer;
const Command = @import("command.zig").Command;
const Screen = @import("command.zig").Screen;
const editor_syntax = @import("editor/syntax.zig");

pub const ExecutionState = enum { empty, assembled, paused, running, halted, breakpoint, limit_reached, faulted };
pub const BusView = enum { events, waveform };

pub const DisplayScale = enum(u8) { x1 = 1, x2 = 2, x4 = 4 };

pub const BusFilter = packed struct {
    opcode_fetch: bool = true,
    operand_read: bool = true,
    memory_read: bool = true,
    memory_write: bool = true,
    io_read: bool = true,
    io_write: bool = true,
    other: bool = true,
    _padding: bool = false,

    pub fn allows(self: BusFilter, kind: @import("../trace/trace.zig").BusEventKind) bool {
        return switch (kind) {
            .opcode_fetch => self.opcode_fetch,
            .operand_read => self.operand_read,
            .memory_read => self.memory_read,
            .memory_write => self.memory_write,
            .io_read => self.io_read,
            .io_write => self.io_write,
            .refresh, .interrupt_ack => self.other,
        };
    }

    pub fn mask(self: BusFilter) u8 {
        return @bitCast(self);
    }
};

pub const ExecutionLimits = struct {
    pub const default_max_instructions: u64 = 10_000_000;
    pub const default_max_t_states: u64 = 100_000_000;
    max_instructions: u64 = default_max_instructions,
    max_t_states: u64 = default_max_t_states,
};

pub const MemoryAddressInput = struct {
    active: bool = false,
    digits: [4]u8 = undefined,
    len: usize = 0,
};

pub const ToastKind = enum { success, info, breakpoint, halted, @"error" };
pub const Toast = struct {
    kind: ToastKind = .info,
    text: [96]u8 = undefined,
    len: usize = 0,
    expires_at_ms: i64 = 0,
};

pub const CommandPalette = struct {
    active: bool = false,
    selected: usize = 0,
};

pub const PromptMode = enum { none, search, go_line, go_label, rename };
pub const EditorPrompt = struct {
    mode: PromptMode = .none,
    query: [64]u8 = undefined,
    len: usize = 0,
    rename_old: [32]u8 = undefined,
    rename_old_len: usize = 0,
    pub fn text(self: *const EditorPrompt) []const u8 {
        return self.query[0..self.len];
    }
};

pub const ExecutionOverlay = struct {
    source_line: usize,
    text: [64]u8 = undefined,
    len: usize = 0,
    expires_at_ms: i64,
};

pub const InstructionSnapshot = struct {
    instruction_index: u64,
    before: CpuSnapshot,
    after: CpuSnapshot,
};

pub const AppState = struct {
    allocator: std.mem.Allocator,
    source_path: ?[]u8 = null,
    source: SourceBuffer,
    assembly: ?assembler.Result = null,
    machine: Machine = .{},
    debug_session: DebugSession = .{},
    trace: TraceBuffer = .{},
    active_screen: Screen = .editor,
    execution_state: ExecutionState = .empty,
    status: [160]u8 = undefined,
    status_len: usize = 0,
    diagnostics_list: std.ArrayList(diagnostics.OwnedDiagnostic) = .empty,
    last_memory_write: ?u16 = null,
    memory_address: u16 = 0xc000,
    trace_scroll: usize = 0,
    selected_trace_event: usize = 0,
    trace_follow: bool = true,
    bus_view: BusView = .events,
    execution_limits: ExecutionLimits = .{},
    executed_instructions: u64 = 0,
    memory_input: MemoryAddressInput = .{},
    unicode_ui: bool = true,
    color_ui: bool = true,
    ui_now_ms: i64 = 0,
    toast: ?Toast = null,
    palette: CommandPalette = .{},
    completion: editor_syntax.Completion = .{},
    syntax_cache: editor_syntax.SyntaxCache = .{},
    editor_prompt: EditorPrompt = .{},
    jump_history: [64]usize = undefined,
    jump_history_len: usize = 0,
    jump_history_index: usize = 0,
    execution_overlay: ?ExecutionOverlay = null,
    execution_overlay_enabled: bool = true,
    follow_pc: bool = false,
    register_highlight_until_ms: i64 = 0,
    instruction_highlight_until_ms: i64 = 0,
    display_scale: DisplayScale = .x2,
    display_grid: bool = false,
    display_cursor_x: u8 = 0,
    display_cursor_y: u8 = 0,
    display_frame: u64 = 0,
    display_changed_pixels: u16 = 0,
    display_change_until_ms: i64 = 0,
    display_snapshot: [1024]u8 = [_]u8{0} ** 1024,
    display_dirty: [8192]bool = [_]bool{false} ** 8192,
    display_fps: u16 = 0,
    display_fps_window_ms: i64 = 0,
    display_fps_window_frames: u16 = 0,
    bus_filter: BusFilter = .{},
    linked_pc: ?u16 = null,
    linked_instruction_index: ?u64 = null,
    instruction_snapshots: [4096]?InstructionSnapshot = [_]?InstructionSnapshot{null} ** 4096,
    quit_requested: bool = false,
    confirm_quit: bool = false,
    ignore_breakpoint_once: bool = false,

    pub fn init(allocator: std.mem.Allocator, path: ?[]const u8, text: []const u8) !AppState {
        var self = AppState{ .allocator = allocator, .source = try SourceBuffer.init(allocator, text) };
        errdefer self.source.deinit();
        if (path) |value| self.source_path = try allocator.dupe(u8, value);
        if (text.len > 0) self.assemble() else self.setStatus("Ready", .{});
        return self;
    }

    pub fn deinit(self: *AppState) void {
        self.source.deinit();
        if (self.source_path) |path| self.allocator.free(path);
        if (self.assembly) |*result| result.deinit();
        self.clearDiagnostics();
        self.diagnostics_list.deinit(self.allocator);
    }

    pub fn attachTrace(self: *AppState) void {
        self.machine.bus.trace_sink = self.trace.sink();
    }

    pub fn statusText(self: *const AppState) []const u8 {
        return self.status[0..self.status_len];
    }

    pub fn setStatus(self: *AppState, comptime fmt: []const u8, args: anytype) void {
        const value = std.fmt.bufPrint(&self.status, fmt, args) catch {
            self.status_len = 0;
            return;
        };
        self.status_len = value.len;
    }

    pub fn assemble(self: *AppState) void {
        self.clearDiagnostics();
        if (self.assembly) |*old| old.deinit();
        self.assembly = null;
        var failure: assembler.FailureLocation = .{};
        const result = assembler.assembleLocated(self.allocator, self.source.text(), &failure) catch |err| {
            if (diagnostics.OwnedDiagnostic.init(self.allocator, diagnostics.fromFailure(failure, self.source_path))) |owned| {
                self.diagnostics_list.append(self.allocator, owned) catch {
                    var temporary = owned;
                    temporary.deinit();
                };
            } else |_| {}
            self.execution_state = .faulted;
            self.setStatus("Assembly failed: {s}", .{diagnostics.message(err)});
            self.showToast(.@"error", "Assembly failed", .{});
            return;
        };
        self.assembly = result;
        self.loadAssembly();
        self.execution_state = .assembled;
        self.setStatus("Assembled {d} bytes, {d} symbols", .{ result.bytes.items.len, result.symbols.items.len });
        self.showToast(.success, "Assembled {d} bytes", .{result.bytes.items.len});
    }

    fn loadAssembly(self: *AppState) void {
        const result = if (self.assembly) |*value| value else return;
        const sink = self.machine.bus.trace_sink;
        self.machine = .{};
        self.machine.bus.trace_sink = sink;
        self.machine.load(result.bytes.items) catch {
            self.execution_state = .faulted;
            self.setStatus("Program is too large", .{});
            return;
        };
        self.trace.clear();
        self.machine.bus.trace_sequence = 0;
        self.debug_session.reset(&self.machine);
        self.last_memory_write = null;
        self.executed_instructions = 0;
        self.linked_pc = null;
        self.linked_instruction_index = null;
        @memset(&self.instruction_snapshots, null);
        self.resetDisplayTracking();
    }

    pub fn runFromReset(self: *AppState) void {
        if (self.assembly == null) self.assemble();
        if (self.assembly == null) return;
        self.loadAssembly();
        self.execution_state = .running;
        self.ignore_breakpoint_once = false;
        self.setStatus("Running", .{});
    }

    pub fn continueExecution(self: *AppState) void {
        if (self.execution_state == .halted or self.execution_state == .limit_reached or self.assembly == null) return;
        self.ignore_breakpoint_once = self.execution_state == .breakpoint;
        self.execution_state = .running;
        self.setStatus("Running", .{});
    }

    pub fn pause(self: *AppState) void {
        if (self.execution_state == .running) {
            self.execution_state = .paused;
            self.setStatus("Paused", .{});
        }
    }

    pub fn step(self: *AppState) void {
        if (self.assembly == null) self.assemble();
        if (self.assembly == null or self.machine.cpu.halted) return;
        // Step is an explicit operation and is allowed to execute one instruction
        // after a cooperative Run/Continue limit was reached.
        self.stepOnce();
        if (!self.machine.cpu.halted and self.execution_state != .faulted) self.execution_state = .paused;
    }

    fn stepOnce(self: *AppState) void {
        const first_new_sequence = self.machine.bus.trace_sequence;
        const result = self.debug_session.step(&self.machine) catch |err| {
            self.execution_state = .faulted;
            self.setStatus("Execution fault: {s}", .{@errorName(err)});
            return;
        };
        self.executed_instructions +|= 1;
        if (self.debug_session.previous) |before| if (self.debug_session.current) |after| {
            const instruction_index = self.machine.cpu.instruction_index -% 1;
            self.instruction_snapshots[instruction_index % self.instruction_snapshots.len] = .{ .instruction_index = instruction_index, .before = before, .after = after };
        };
        self.register_highlight_until_ms = self.ui_now_ms + 1200;
        self.instruction_highlight_until_ms = self.ui_now_ms + 300;
        self.last_memory_write = null;
        for (0..self.trace.len) |index| {
            if (self.trace.get(index)) |event| {
                if (event.sequence >= first_new_sequence and event.kind == .memory_write) self.last_memory_write = event.address;
            }
        }
        self.updateExecutionOverlay(first_new_sequence);
        self.updateDisplayTracking();
        self.follow_pc = true;
        if (self.trace_follow and self.trace.len > 0) {
            self.selected_trace_event = self.trace.len - 1;
            self.syncTraceSelection();
        }
        if (result.halted) {
            self.execution_state = .halted;
            self.setStatus("HALT at PC=0x{X:0>4}", .{result.pc_after});
            self.showToast(.halted, "Halted at 0x{X:0>4}", .{result.pc_after});
        }
    }

    pub fn runSlice(self: *AppState, maximum: usize) void {
        if (self.execution_state != .running) return;
        for (0..maximum) |_| {
            if (self.executed_instructions >= self.execution_limits.max_instructions or self.machine.cpu.total_t_states >= self.execution_limits.max_t_states) {
                self.execution_state = .limit_reached;
                self.setStatus("LIMIT REACHED Instructions: {d} T-states: {d}", .{ self.executed_instructions, self.machine.cpu.total_t_states });
                self.showToast(.@"error", "Execution limit reached", .{});
                return;
            }
            const pc = self.machine.cpu.registers.pc;
            if (!self.ignore_breakpoint_once and self.debug_session.breakpoints.contains(pc)) {
                self.execution_state = .breakpoint;
                self.setStatus("Breakpoint at 0x{X:0>4}", .{pc});
                self.showToast(.breakpoint, "Breakpoint at 0x{X:0>4}", .{pc});
                return;
            }
            self.ignore_breakpoint_once = false;
            self.stepOnce();
            if (self.execution_state != .running) return;
        }
    }

    pub fn reset(self: *AppState) void {
        if (self.assembly != null) self.loadAssembly();
        self.execution_state = if (self.assembly == null) .empty else .assembled;
        self.setStatus("Reset", .{});
    }

    pub fn sourceLineForPC(self: *const AppState, pc: u16) ?usize {
        const result = if (self.assembly) |*value| value else return null;
        for (result.lines.items) |line| if (line.address == pc) return line.line;
        return null;
    }

    pub fn toggleBreakpoint(self: *AppState) void {
        const line_number = self.source.lineAndColumn().line + 1;
        const result = if (self.assembly) |*value| value else {
            self.setStatus("Assemble before setting a source breakpoint", .{});
            return;
        };
        for (result.lines.items) |line| if (line.line == line_number) {
            if (self.debug_session.breakpoints.remove(line.address)) {
                self.setStatus("Removed breakpoint at 0x{X:0>4}", .{line.address});
                self.showToast(.info, "Breakpoint removed", .{});
            } else {
                _ = self.debug_session.breakpoints.add(line.address);
                self.setStatus("Added breakpoint at 0x{X:0>4}", .{line.address});
                self.showToast(.breakpoint, "Breakpoint added", .{});
            }
            return;
        };
        self.setStatus("No instruction on this source line", .{});
    }

    pub fn save(self: *AppState, io: Io) !void {
        const path = self.source_path orelse return error.NoSourcePath;
        const file = try Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, self.source.text());
        self.source.dirty = false;
        self.assemble();
        self.setStatus("Saved and assembled {s}", .{path});
        self.showToast(.success, "Saved", .{});
    }

    pub fn apply(self: *AppState, action: Command, io: Io) !void {
        if (self.editor_prompt.mode != .none) {
            try self.applyEditorPrompt(action);
            return;
        }
        if (self.palette.active) {
            try self.applyPalette(action, io);
            return;
        }
        const was_quit = std.meta.activeTag(action) == .quit;
        switch (action) {
            .insert_character => |value| {
                if (self.active_screen == .editor) {
                    self.follow_pc = false;
                    if (value == ' ' and self.completion.active) try self.acceptCompletion(true) else {
                        try self.source.insert(value);
                        self.refreshCompletion();
                    }
                } else if (value == 'b') {
                    self.toggleBreakpoint();
                } else if (value == 'g') {
                    self.active_screen = .memory;
                    self.memory_input = .{ .active = true };
                } else if (self.active_screen == .memory) {
                    self.memoryCharacter(value);
                } else if (self.active_screen == .bus and value == '[') {
                    self.moveView(.left);
                } else if (self.active_screen == .bus and value == ']') self.moveView(.right);
            },
            .newline => if (self.active_screen == .editor and self.completion.active) {
                try self.acceptCompletion(false);
            } else if (self.diagnostics_list.items.len > 0) {
                if (self.goToDiagnostic(0)) {
                    self.clearDiagnostics();
                }
            } else if (self.active_screen == .editor) {
                if (!self.jumpToDefinition()) try self.source.newline();
                self.refreshCompletion();
            } else if (self.active_screen == .bus) self.jumpFromTrace() else if (self.active_screen == .memory) self.confirmMemoryInput(),
            .backspace => if (self.active_screen == .editor) {
                self.source.backspace();
                self.refreshCompletion();
            } else if (self.active_screen == .memory and self.memory_input.active and self.memory_input.len > 0) {
                self.memory_input.len -= 1;
            },
            .delete => if (self.active_screen == .editor) {
                self.source.delete();
                self.refreshCompletion();
            },
            .move_cursor => |direction| {
                if (self.active_screen == .editor and self.completion.active and (direction == .up or direction == .down)) {
                    if (direction == .up) self.completion.selected -|= 1 else self.completion.selected = @min(self.completion.selected + 1, self.completion.len - 1);
                } else {
                    self.completion.active = false;
                    if (self.active_screen == .editor) self.follow_pc = false;
                    self.moveView(direction);
                }
            },
            .select_cursor => |direction| self.selectSource(direction),
            .save => try self.save(io),
            .assemble => self.assemble(),
            .run => self.runFromReset(),
            .pause => self.pause(),
            .continue_execution => self.continueExecution(),
            .step_instruction => self.step(),
            .reset => self.reset(),
            .toggle_breakpoint => self.toggleBreakpoint(),
            .switch_screen => |screen| self.active_screen = screen,
            .show_help => self.active_screen = .help,
            .open_palette => self.palette = .{ .active = true },
            .palette_or_colon => {
                if (self.active_screen == .editor) {
                    try self.source.insert(':');
                } else self.palette = .{ .active = true };
            },
            .help_or_question => {
                if (self.active_screen == .editor) {
                    try self.source.insert('?');
                    self.refreshCompletion();
                } else self.active_screen = .help;
            },
            .next_pane => if (self.active_screen == .editor) {
                try self.source.indent(false);
                self.refreshCompletion();
            } else self.focusPane(true),
            .previous_pane => if (self.active_screen == .editor) {
                try self.source.indent(true);
                self.refreshCompletion();
            } else self.focusPane(false),
            .undo => if (try self.source.undo()) self.afterHistoryEdit("Undo"),
            .redo => if (try self.source.redo()) self.afterHistoryEdit("Redo"),
            .search => self.openPrompt(.search),
            .jump_definition => _ = self.jumpToDefinition(),
            .jump_back => self.jumpHistory(false),
            .jump_forward => self.jumpHistory(true),
            .quit => {
                if (self.source.dirty and !self.confirm_quit) {
                    self.confirm_quit = true;
                    self.setStatus("Unsaved changes: Ctrl+Q again to discard, or Ctrl+S to save", .{});
                } else self.quit_requested = true;
            },
            .cancel => {
                if (self.active_screen == .memory and self.memory_input.active) {
                    self.memory_input = .{};
                    self.setStatus("Memory address input cancelled", .{});
                } else self.pause();
            },
            .none => {},
        }
        if (!was_quit) self.confirm_quit = false;
    }

    pub fn tickUi(self: *AppState, now_ms: i64) void {
        self.ui_now_ms = now_ms;
        if (self.display_fps_window_ms == 0) self.display_fps_window_ms = now_ms;
        const fps_elapsed = now_ms - self.display_fps_window_ms;
        if (fps_elapsed >= 1000) {
            const rate = @divTrunc(@as(i64, self.display_fps_window_frames) * 1000, @max(@as(i64, 1), fps_elapsed));
            self.display_fps = @intCast(@min(@as(i64, 65535), rate));
            self.display_fps_window_frames = 0;
            self.display_fps_window_ms = now_ms;
        }
        if (self.toast) |toast| {
            if (now_ms >= toast.expires_at_ms) self.toast = null;
        }
        if (self.execution_overlay) |overlay| {
            if (now_ms >= overlay.expires_at_ms) self.execution_overlay = null;
        }
        if (self.display_changed_pixels > 0 and now_ms >= self.display_change_until_ms) {
            self.display_changed_pixels = 0;
            @memset(&self.display_dirty, false);
        }
    }

    pub fn showToast(self: *AppState, kind: ToastKind, comptime fmt: []const u8, args: anytype) void {
        var toast = Toast{ .kind = kind, .expires_at_ms = self.ui_now_ms + 2000 };
        const text = std.fmt.bufPrint(&toast.text, fmt, args) catch return;
        toast.len = text.len;
        self.toast = toast;
    }

    pub fn registerHighlightActive(self: *const AppState) bool {
        return self.ui_now_ms < self.register_highlight_until_ms;
    }

    pub fn instructionHighlightActive(self: *const AppState) bool {
        return self.ui_now_ms < self.instruction_highlight_until_ms;
    }

    pub fn displayChangeActive(self: *const AppState) bool {
        return self.ui_now_ms < self.display_change_until_ms;
    }

    pub fn linkedSnapshot(self: *const AppState) ?InstructionSnapshot {
        const instruction_index = self.linked_instruction_index orelse return null;
        const snapshot = self.instruction_snapshots[instruction_index % self.instruction_snapshots.len] orelse return null;
        return if (snapshot.instruction_index == instruction_index) snapshot else null;
    }

    pub const palette_commands = [_][]const u8{ "go line", "go label", "rename label", "search", "breakpoint", "assemble", "run", "step", "continue", "memory", "display", "bus", "display scale 1x", "display scale 2x", "display scale 4x", "display grid", "bus filter all", "bus filter memory write", "quit" };

    fn applyPalette(self: *AppState, action: Command, io: Io) !void {
        switch (action) {
            .move_cursor => |direction| switch (direction) {
                .up => self.palette.selected -|= 1,
                .down => self.palette.selected = @min(self.palette.selected + 1, palette_commands.len - 1),
                else => {},
            },
            .newline => {
                const selected = self.palette.selected;
                self.palette.active = false;
                switch (selected) {
                    0 => self.openPrompt(.go_line),
                    1 => self.openPrompt(.go_label),
                    2 => self.openRenamePrompt(),
                    3 => self.openPrompt(.search),
                    4 => self.toggleBreakpoint(),
                    5 => self.assemble(),
                    6 => self.runFromReset(),
                    7 => self.step(),
                    8 => self.continueExecution(),
                    9 => self.active_screen = .memory,
                    10 => self.active_screen = .display,
                    11 => self.active_screen = .bus,
                    12 => {
                        self.display_scale = .x1;
                        self.active_screen = .display;
                    },
                    13 => {
                        self.display_scale = .x2;
                        self.active_screen = .display;
                    },
                    14 => {
                        self.display_scale = .x4;
                        self.active_screen = .display;
                    },
                    15 => {
                        self.display_grid = !self.display_grid;
                        self.active_screen = .display;
                    },
                    16 => {
                        self.bus_filter = .{};
                        self.active_screen = .bus;
                        self.alignTraceSelection();
                    },
                    17 => {
                        self.bus_filter = .{ .opcode_fetch = false, .operand_read = false, .memory_read = false, .io_read = false, .io_write = false, .other = false };
                        self.active_screen = .bus;
                        self.alignTraceSelection();
                    },
                    18 => {
                        if (self.source.dirty and !self.confirm_quit) {
                            self.confirm_quit = true;
                            self.palette.active = true;
                            self.setStatus("Unsaved changes: choose quit again to discard, or Ctrl+S to save", .{});
                        } else self.quit_requested = true;
                    },
                    else => {},
                }
            },
            .cancel, .open_palette => self.palette.active = false,
            .quit => {
                if (self.source.dirty and !self.confirm_quit) {
                    self.confirm_quit = true;
                    self.setStatus("Unsaved changes: Ctrl+Q again to discard, or Ctrl+S to save", .{});
                } else self.quit_requested = true;
            },
            .save => try self.save(io),
            else => {},
        }
    }

    fn refreshCompletion(self: *AppState) void {
        editor_syntax.complete(self.source.text(), self.source.cursor, &self.completion);
    }

    fn acceptCompletion(self: *AppState, trailing_space: bool) !void {
        if (!self.completion.active or self.completion.selected >= self.completion.len) return;
        const item = self.completion.item(self.completion.selected);
        try self.source.replaceRange(self.completion.replace_start, self.completion.replace_end, item);
        self.completion.active = false;
        if (trailing_space) try self.source.insert(' ');
    }

    fn afterHistoryEdit(self: *AppState, action: []const u8) void {
        self.completion.active = false;
        self.setStatus("{s}", .{action});
    }

    fn selectSource(self: *AppState, direction: @import("command.zig").Direction) void {
        if (self.active_screen != .editor) return;
        self.follow_pc = false;
        switch (direction) {
            .up => self.source.move(.up, true),
            .down => self.source.move(.down, true),
            .left => self.source.move(.left, true),
            .right => self.source.move(.right, true),
            .home => self.source.move(.home, true),
            .end => self.source.move(.end, true),
            .page_up, .page_down => {},
        }
        self.completion.active = false;
    }

    fn openPrompt(self: *AppState, mode: PromptMode) void {
        self.active_screen = .editor;
        self.editor_prompt = .{ .mode = mode };
        self.completion.active = false;
    }

    fn openRenamePrompt(self: *AppState) void {
        const word = editor_syntax.wordAt(self.source.text(), self.source.cursor) orelse {
            self.setStatus("Place the cursor on a label before Rename Label", .{});
            return;
        };
        if (editor_syntax.findLabelDefinition(self.source.text(), word.text) == null) {
            self.setStatus("{s} is not a defined label", .{word.text});
            return;
        }
        if (word.text.len > 32) return;
        self.openPrompt(.rename);
        @memcpy(self.editor_prompt.rename_old[0..word.text.len], word.text);
        self.editor_prompt.rename_old_len = word.text.len;
    }

    fn applyEditorPrompt(self: *AppState, action: Command) !void {
        switch (action) {
            .insert_character => |value| self.appendPrompt(value),
            .palette_or_colon => self.appendPrompt(':'),
            .help_or_question => self.appendPrompt('?'),
            .backspace => if (self.editor_prompt.len > 0) {
                self.editor_prompt.len = previousUtf8(self.editor_prompt.query[0..self.editor_prompt.len], self.editor_prompt.len);
                if (self.editor_prompt.mode == .search) self.findQuery(false);
            },
            .newline => {
                switch (self.editor_prompt.mode) {
                    .search => self.findQuery(true),
                    .go_line => {
                        const line = std.fmt.parseInt(usize, self.editor_prompt.text(), 10) catch 0;
                        if (line > 0) _ = self.source.goToLine(line - 1);
                        self.editor_prompt = .{};
                    },
                    .go_label => {
                        if (editor_syntax.findLabelDefinition(self.source.text(), self.editor_prompt.text())) |line| self.jumpToLine(line);
                        self.editor_prompt = .{};
                    },
                    .rename => {
                        const old = self.editor_prompt.rename_old[0..self.editor_prompt.rename_old_len];
                        const new = self.editor_prompt.text();
                        if (new.len > 0) {
                            const count = try self.source.replaceAllIdentifier(old, new);
                            self.setStatus("Renamed {s} to {s} at {d} locations", .{ old, new, count });
                        }
                        self.editor_prompt = .{};
                    },
                    .none => {},
                }
            },
            .cancel => self.editor_prompt = .{},
            .search => self.findQuery(true),
            else => {},
        }
    }

    fn appendPrompt(self: *AppState, value: u21) void {
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(value, &encoded) catch return;
        if (self.editor_prompt.len + len <= self.editor_prompt.query.len) {
            @memcpy(self.editor_prompt.query[self.editor_prompt.len..][0..len], encoded[0..len]);
            self.editor_prompt.len += len;
            if (self.editor_prompt.mode == .search) self.findQuery(false);
        }
    }

    fn findQuery(self: *AppState, next: bool) void {
        const query = self.editor_prompt.text();
        if (query.len == 0) return;
        const text = self.source.text();
        const start = if (next) @min(self.source.cursor + 1, text.len) else 0;
        const found = std.mem.indexOfPos(u8, text, start, query) orelse std.mem.indexOf(u8, text, query) orelse return;
        self.source.cursor = found;
        self.source.selection_anchor = found + query.len;
    }

    fn jumpToDefinition(self: *AppState) bool {
        if (self.active_screen != .editor) return false;
        const word = editor_syntax.wordAt(self.source.text(), self.source.cursor) orelse return false;
        const line = editor_syntax.findLabelDefinition(self.source.text(), word.text) orelse return false;
        if (line == self.source.lineAndColumn().line) return false;
        self.jumpToLine(line);
        self.setStatus("Definition: {s}", .{word.text});
        return true;
    }

    fn jumpToLine(self: *AppState, line: usize) void {
        if (self.jump_history_len == 0) {
            self.jump_history[self.jump_history_len] = self.source.cursor;
            self.jump_history_len += 1;
        } else if (self.jump_history_index + 1 < self.jump_history_len) {
            self.jump_history_len = self.jump_history_index + 1;
        }
        _ = self.source.goToLine(line);
        if (self.jump_history_len < self.jump_history.len) {
            self.jump_history[self.jump_history_len] = self.source.cursor;
            self.jump_history_len += 1;
            self.jump_history_index = self.jump_history_len - 1;
        }
    }

    fn jumpHistory(self: *AppState, forward: bool) void {
        if (forward) {
            if (self.jump_history_index + 1 >= self.jump_history_len) return;
            self.jump_history_index += 1;
            self.source.cursor = self.jump_history[self.jump_history_index];
        } else {
            if (self.jump_history_index == 0) return;
            self.jump_history_index -= 1;
            self.source.cursor = self.jump_history[self.jump_history_index];
        }
        self.source.selection_anchor = null;
    }

    pub fn inspectionAddress(self: *AppState) ?u16 {
        if (self.active_screen != .editor) return null;
        const position = self.source.lineAndColumn();
        const line = self.source.lineSlice(position.line) orelse return null;
        const tokens = self.syntax_cache.tokens(position.line, line);
        const start = self.source.absoluteLineStart(position.line) orelse return null;
        var on_mnemonic = false;
        for (tokens.items[0..tokens.len]) |token| if (token.kind == .mnemonic and self.source.cursor >= start + token.start and self.source.cursor <= start + token.end) {
            on_mnemonic = true;
            break;
        };
        if (!on_mnemonic) return null;
        const assembly = if (self.assembly) |*value| value else return null;
        for (assembly.lines.items) |info| if (info.line == position.line + 1) return info.address;
        return null;
    }

    fn updateExecutionOverlay(self: *AppState, first_sequence: u64) void {
        if (!self.execution_overlay_enabled) return;
        const before = self.debug_session.previous orelse return;
        const after = self.debug_session.current orelse return;
        const source_line = self.sourceLineForPC(before.registers.pc) orelse return;
        var overlay = ExecutionOverlay{ .source_line = source_line, .expires_at_ms = self.ui_now_ms + 1800 };
        var text: []const u8 = "";
        for (0..self.trace.len) |index| if (self.trace.get(index)) |event| {
            if (event.sequence >= first_sequence and event.kind == .memory_write) {
                const arrow = if (self.unicode_ui) "←" else "<-";
                text = if (event.address >= 0xC000 and event.address < 0xC400)
                    std.fmt.bufPrint(&overlay.text, "VRAM[{X:0>4}] {s} {X:0>2}", .{ event.address, arrow, event.data }) catch ""
                else
                    std.fmt.bufPrint(&overlay.text, "[{X:0>4}] {s} {X:0>2}", .{ event.address, arrow, event.data }) catch "";
            }
        };
        if (text.len == 0) {
            const arrow = if (self.unicode_ui) "←" else "<-";
            if (after.registers.hl() != before.registers.hl()) text = std.fmt.bufPrint(&overlay.text, "HL {s} {X:0>4}", .{ arrow, after.registers.hl() }) catch "" else if (after.registers.bc() != before.registers.bc()) text = std.fmt.bufPrint(&overlay.text, "BC {s} {X:0>4}", .{ arrow, after.registers.bc() }) catch "" else if (after.registers.de() != before.registers.de()) text = std.fmt.bufPrint(&overlay.text, "DE {s} {X:0>4}", .{ arrow, after.registers.de() }) catch "" else if (after.registers.sp != before.registers.sp) text = std.fmt.bufPrint(&overlay.text, "SP {s} {X:0>4}", .{ arrow, after.registers.sp }) catch "" else if (after.registers.af() != before.registers.af()) text = std.fmt.bufPrint(&overlay.text, "AF {s} {X:0>4}", .{ arrow, after.registers.af() }) catch "" else if (after.halted and !before.halted) text = std.fmt.bufPrint(&overlay.text, "HALT", .{}) catch "";
        }
        overlay.len = text.len;
        if (overlay.len > 0) self.execution_overlay = overlay;
    }

    fn focusPane(self: *AppState, forward: bool) void {
        const current: usize = if (self.active_screen == .help) 0 else @intFromEnum(self.active_screen);
        self.active_screen = if (forward)
            @enumFromInt((current + 1) % 5)
        else
            @enumFromInt((current + 4) % 5);
    }

    fn moveView(self: *AppState, direction: @import("command.zig").Direction) void {
        switch (self.active_screen) {
            .editor => switch (direction) {
                .up => self.source.move(.up, false),
                .down => self.source.move(.down, false),
                .left => self.source.move(.left, false),
                .right => self.source.move(.right, false),
                .home => self.source.move(.home, false),
                .end => self.source.move(.end, false),
                .page_up => for (0..10) |_| self.source.move(.up, false),
                .page_down => for (0..10) |_| self.source.move(.down, false),
            },
            .memory => switch (direction) {
                .up => self.memory_address -%= 16,
                .down => self.memory_address +%= 16,
                .left => self.memory_address -%= 1,
                .right => self.memory_address +%= 1,
                .home => self.memory_address = self.machine.cpu.registers.pc,
                .end => self.memory_address = self.machine.cpu.registers.hl(),
                .page_up => self.memory_address = self.machine.cpu.registers.sp,
                .page_down => self.memory_address = 0xc000,
            },
            .bus => switch (direction) {
                .up, .left => self.selectFilteredEvent(false),
                .down, .right => self.selectFilteredEvent(true),
                .end, .page_down => {
                    self.selected_trace_event = self.trace.len -| 1;
                    self.alignTraceSelection();
                },
                .home, .page_up => {
                    self.trace_follow = false;
                    self.selected_trace_event = 0;
                    var index: usize = 0;
                    while (index < self.trace.len) : (index += 1) if (self.trace.get(index)) |event| {
                        if (self.bus_filter.allows(event.kind)) {
                            self.selected_trace_event = index;
                            break;
                        }
                    };
                },
            },
            .display => switch (direction) {
                .up => self.display_cursor_y -|= 1,
                .down => self.display_cursor_y = @min(self.display_cursor_y +| 1, 63),
                .left => self.display_cursor_x -|= 1,
                .right => self.display_cursor_x = @min(self.display_cursor_x +| 1, 127),
                .home => self.display_cursor_x = 0,
                .end => self.display_cursor_x = 127,
                .page_up => self.display_cursor_y -|= 8,
                .page_down => self.display_cursor_y = @min(self.display_cursor_y +| 8, 63),
            },
            else => {},
        }
        if (self.active_screen == .bus) self.syncTraceSelection();
    }

    fn memoryCharacter(self: *AppState, codepoint: u21) void {
        if (!self.memory_input.active) {
            if (codepoint == 'g' or codepoint == 'G') {
                self.memory_input = .{ .active = true };
                self.setStatus("Go to memory address", .{});
            } else if (codepoint == 'p' or codepoint == 'P') {
                self.memory_address = self.machine.cpu.registers.pc;
            } else if (codepoint == 'h' or codepoint == 'H') {
                self.memory_address = self.machine.cpu.registers.hl();
            }
            return;
        }
        const digit: ?u4 = if (codepoint >= '0' and codepoint <= '9') @intCast(codepoint - '0') else if (codepoint >= 'a' and codepoint <= 'f') @intCast(codepoint - 'a' + 10) else if (codepoint >= 'A' and codepoint <= 'F') @intCast(codepoint - 'A' + 10) else null;
        if (digit) |value| if (self.memory_input.len < 4) {
            self.memory_input.digits[self.memory_input.len] = "0123456789ABCDEF"[value];
            self.memory_input.len += 1;
        };
    }

    fn confirmMemoryInput(self: *AppState) void {
        if (!self.memory_input.active or self.memory_input.len != 4) return;
        self.memory_address = std.fmt.parseInt(u16, self.memory_input.digits[0..4], 16) catch return;
        self.memory_input = .{};
        self.setStatus("Memory address: 0x{X:0>4}", .{self.memory_address});
    }

    pub fn memoryInputText(self: *const AppState, buffer: *[4]u8) []const u8 {
        @memset(buffer, '_');
        if (self.memory_input.active) @memcpy(buffer[0..self.memory_input.len], self.memory_input.digits[0..self.memory_input.len]);
        return buffer;
    }

    pub fn goToDiagnostic(self: *AppState, index: usize) bool {
        if (index >= self.diagnostics_list.items.len) return false;
        const diagnostic = self.diagnostics_list.items[index].value;
        const line = diagnostic.line orelse return false;
        if (self.source.goToLine(line - 1)) {
            self.active_screen = .editor;
            return true;
        }
        return false;
    }

    fn clearDiagnostics(self: *AppState) void {
        for (self.diagnostics_list.items) |*diagnostic| diagnostic.deinit();
        self.diagnostics_list.clearRetainingCapacity();
    }

    fn jumpFromTrace(self: *AppState) void {
        const event = self.trace.get(self.selected_trace_event) orelse return;
        const source_line = self.sourceLineForPC(event.pc) orelse {
            self.setStatus("No source line for trace PC 0x{X:0>4}", .{event.pc});
            return;
        };
        if (self.source.goToLine(source_line - 1)) {
            self.active_screen = .editor;
            self.setStatus("Moved to source line {d} for trace event #{d}", .{ source_line, event.sequence });
        }
    }

    fn resetDisplayTracking(self: *AppState) void {
        @memcpy(&self.display_snapshot, self.machine.bus.memory[0xC000..0xC400]);
        @memset(&self.display_dirty, false);
        self.display_changed_pixels = 0;
        self.display_frame = 0;
        self.display_fps = 0;
        self.display_fps_window_frames = 0;
        self.display_fps_window_ms = self.ui_now_ms;
        self.display_change_until_ms = 0;
    }

    fn updateDisplayTracking(self: *AppState) void {
        var changed: u16 = 0;
        var began_change = false;
        for (0..self.display_snapshot.len) |byte_index| {
            const value = self.machine.bus.memory[0xC000 + byte_index];
            const difference = value ^ self.display_snapshot[byte_index];
            if (difference == 0) continue;
            if (!began_change) {
                @memset(&self.display_dirty, false);
                began_change = true;
            }
            for (0..8) |bit| if (difference & (@as(u8, 1) << @intCast(bit)) != 0) {
                const x = byte_index % 128;
                const y = byte_index / 128 * 8 + bit;
                self.display_dirty[y * 128 + x] = true;
                changed +|= 1;
            };
            self.display_snapshot[byte_index] = value;
        }
        if (changed > 0) {
            self.display_changed_pixels = changed;
            self.display_frame +|= 1;
            self.display_fps_window_frames +|= 1;
            self.display_change_until_ms = self.ui_now_ms + 300;
        }
    }

    fn syncTraceSelection(self: *AppState) void {
        const event = self.trace.get(self.selected_trace_event) orelse return;
        self.linked_pc = event.pc;
        self.linked_instruction_index = event.instruction_index;
        if (event.kind == .memory_write and event.address >= 0xC000 and event.address < 0xC400) {
            const offset = event.address - 0xC000;
            self.display_cursor_x = @intCast(offset % 128);
            const byte_row: u8 = @intCast(offset / 128);
            self.display_cursor_y = byte_row * 8 + if (event.data == 0) 0 else @ctz(event.data);
        }
    }

    fn alignTraceSelection(self: *AppState) void {
        if (self.trace.len == 0) return;
        var index = @min(self.selected_trace_event, self.trace.len - 1);
        while (true) {
            const event = self.trace.get(index) orelse break;
            if (self.bus_filter.allows(event.kind)) {
                self.selected_trace_event = index;
                self.trace_follow = index == self.trace.len - 1;
                self.syncTraceSelection();
                return;
            }
            if (index == 0) break;
            index -= 1;
        }
        index = @min(self.selected_trace_event + 1, self.trace.len);
        while (index < self.trace.len) : (index += 1) {
            const event = self.trace.get(index) orelse continue;
            if (self.bus_filter.allows(event.kind)) {
                self.selected_trace_event = index;
                self.trace_follow = index == self.trace.len - 1;
                self.syncTraceSelection();
                return;
            }
        }
    }

    fn selectFilteredEvent(self: *AppState, forward: bool) void {
        if (self.trace.len == 0) return;
        var index = if (self.trace_follow) self.trace.len - 1 else self.selected_trace_event;
        self.trace_follow = false;
        while (true) {
            if (forward) {
                if (index + 1 >= self.trace.len) break;
                index += 1;
            } else {
                if (index == 0) break;
                index -= 1;
            }
            const event = self.trace.get(index) orelse continue;
            if (!self.bus_filter.allows(event.kind)) continue;
            self.selected_trace_event = index;
            self.trace_follow = index == self.trace.len - 1;
            return;
        }
    }
};

fn previousUtf8(text: []const u8, position: usize) usize {
    var index = position - 1;
    while (index > 0 and text[index] & 0xc0 == 0x80) : (index -= 1) {}
    return index;
}
