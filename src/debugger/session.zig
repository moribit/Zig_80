const Registers = @import("../cpu/registers.zig").Registers;
const Machine = @import("../machine/machine.zig").Machine;
const Breakpoints = @import("breakpoint.zig").Breakpoints;
const StepResult = @import("../cpu/cpu.zig").StepResult;
const trace = @import("../trace/trace.zig");
const Watchpoints = @import("breakpoint.zig").Watchpoints;

pub const CpuSnapshot = struct {
    registers: Registers,
    halted: bool,
    total_t_states: u64,

    pub fn capture(machine: *const Machine) CpuSnapshot {
        return .{ .registers = machine.cpu.registers, .halted = machine.cpu.halted, .total_t_states = machine.cpu.total_t_states };
    }
};

pub const DebugSession = struct {
    breakpoints: Breakpoints = .{},
    previous: ?CpuSnapshot = null,
    current: ?CpuSnapshot = null,
    watchpoints: Watchpoints = .{},
    watch_trace: trace.RingBuffer(32) = .{},
    last_watchpoint: ?usize = null,

    pub fn reset(self: *DebugSession, machine: *Machine) void {
        self.previous = null;
        self.current = CpuSnapshot.capture(machine);
        self.last_watchpoint = null;
        self.watch_trace.clear();
        machine.bus.debug_trace_sink = self.watch_trace.sink();
    }

    pub fn step(self: *DebugSession, machine: *Machine) !StepResult {
        machine.bus.debug_trace_sink = self.watch_trace.sink();
        self.watch_trace.clear();
        self.last_watchpoint = null;
        self.previous = CpuSnapshot.capture(machine);
        const result = try machine.step();
        self.current = CpuSnapshot.capture(machine);
        for (0..self.watch_trace.len) |index| if (self.watch_trace.get(index)) |event| {
            if (self.watchpoints.match(event)) |watchpoint| {
                self.last_watchpoint = watchpoint;
                break;
            }
        };
        return result;
    }

    pub fn changedRegister(self: *const DebugSession, comptime name: []const u8) bool {
        const before = self.previous orelse return false;
        const after = self.current orelse return false;
        return @field(before.registers, name) != @field(after.registers, name);
    }
};
