const std = @import("std");
const Io = std.Io;
const assembler = @import("../assembler/assembler.zig");
const diagnostics = @import("../assembler/diagnostics.zig");
const Machine = @import("../machine/machine.zig").Machine;
const DebugSession = @import("../debugger/session.zig").DebugSession;
const SourceBuffer = @import("editor/buffer.zig").SourceBuffer;
const TraceBuffer = @import("../trace/trace.zig").TraceBuffer;
const Command = @import("command.zig").Command;
const Screen = @import("command.zig").Screen;

pub const ExecutionState = enum { empty, assembled, paused, running, halted, breakpoint, limit_reached, faulted };
pub const BusView = enum { events, waveform };

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
    ui_now_ms: i64 = 0,
    toast: ?Toast = null,
    palette: CommandPalette = .{},
    register_highlight_until_ms: i64 = 0,
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
        self.register_highlight_until_ms = self.ui_now_ms + 1200;
        self.last_memory_write = null;
        for (0..self.trace.len) |index| {
            if (self.trace.get(index)) |event| {
                if (event.sequence >= first_new_sequence and event.kind == .memory_write) self.last_memory_write = event.address;
            }
        }
        if (self.trace_follow and self.trace.len > 0) self.selected_trace_event = self.trace.len - 1;
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
        if (self.palette.active) {
            try self.applyPalette(action, io);
            return;
        }
        const was_quit = std.meta.activeTag(action) == .quit;
        switch (action) {
            .insert_character => |value| {
                if (self.active_screen == .editor) try self.source.insert(value) else if (self.active_screen == .memory) self.memoryCharacter(value);
            },
            .newline => if (self.diagnostics_list.items.len > 0) {
                if (self.goToDiagnostic(0)) {
                    self.clearDiagnostics();
                }
            } else if (self.active_screen == .editor) try self.source.newline() else if (self.active_screen == .bus) self.jumpFromTrace() else if (self.active_screen == .memory) self.confirmMemoryInput(),
            .backspace => if (self.active_screen == .editor) self.source.backspace() else if (self.active_screen == .memory and self.memory_input.active and self.memory_input.len > 0) {
                self.memory_input.len -= 1;
            },
            .delete => if (self.active_screen == .editor) self.source.delete(),
            .move_cursor => |direction| self.moveView(direction),
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
            .quit => {
                if (self.source.dirty and !self.confirm_quit) {
                    self.confirm_quit = true;
                    self.setStatus("Unsaved changes: Ctrl+Q again to discard, or Ctrl+S to save", .{});
                } else self.quit_requested = true;
            },
            .tab => {
                if (self.active_screen == .bus) self.bus_view = if (self.bus_view == .events) .waveform else .events;
            },
            .cancel => if (self.active_screen == .memory and self.memory_input.active) {
                self.memory_input = .{};
                self.setStatus("Memory address input cancelled", .{});
            },
            .none => {},
        }
        if (!was_quit) self.confirm_quit = false;
    }

    pub fn tickUi(self: *AppState, now_ms: i64) void {
        self.ui_now_ms = now_ms;
        if (self.toast) |toast| {
            if (now_ms >= toast.expires_at_ms) self.toast = null;
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

    pub const palette_commands = [_][]const u8{ "Assemble", "Run", "Reset", "Go Address", "Toggle Breakpoint" };

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
                    0 => self.assemble(),
                    1 => self.runFromReset(),
                    2 => self.reset(),
                    3 => {
                        self.active_screen = .memory;
                        self.memory_input = .{ .active = true };
                    },
                    4 => self.toggleBreakpoint(),
                    else => {},
                }
            },
            .cancel, .open_palette => self.palette.active = false,
            .quit => self.quit_requested = true,
            .save => try self.save(io),
            else => {},
        }
    }

    fn moveView(self: *AppState, direction: @import("command.zig").Direction) void {
        switch (self.active_screen) {
            .editor => switch (direction) {
                .up => self.source.moveUp(),
                .down => self.source.moveDown(),
                .left => self.source.moveLeft(),
                .right => self.source.moveRight(),
                .home => self.source.moveHome(),
                .end => self.source.moveEnd(),
                .page_up => for (0..10) |_| self.source.moveUp(),
                .page_down => for (0..10) |_| self.source.moveDown(),
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
                .up => {
                    if (self.trace_follow and self.trace.len > 0) self.selected_trace_event = self.trace.len - 1;
                    self.trace_follow = false;
                    self.selected_trace_event -|= 1;
                },
                .down => {
                    self.trace_follow = false;
                    self.selected_trace_event = @min(self.selected_trace_event + 1, self.trace.len -| 1);
                    if (self.trace.len > 0 and self.selected_trace_event == self.trace.len - 1) self.trace_follow = true;
                },
                .end, .page_down => {
                    self.trace_follow = true;
                    self.selected_trace_event = self.trace.len -| 1;
                },
                .home, .page_up => {
                    self.trace_follow = false;
                    self.selected_trace_event = 0;
                },
                .left => {
                    self.trace_follow = false;
                    self.selected_trace_event -|= 1;
                },
                .right => {
                    self.trace_follow = false;
                    self.selected_trace_event = @min(self.selected_trace_event + 1, self.trace.len -| 1);
                    if (self.trace.len > 0 and self.selected_trace_event == self.trace.len - 1) self.trace_follow = true;
                },
            },
            else => {},
        }
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
};
