const Registers = @import("../cpu/registers.zig").Registers;
const Machine = @import("../machine/machine.zig").Machine;
const Breakpoints = @import("breakpoint.zig").Breakpoints;
const StepResult = @import("../cpu/cpu.zig").StepResult;

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

    pub fn reset(self: *DebugSession, machine: *const Machine) void {
        self.previous = null;
        self.current = CpuSnapshot.capture(machine);
    }

    pub fn step(self: *DebugSession, machine: *Machine) !StepResult {
        self.previous = CpuSnapshot.capture(machine);
        const result = try machine.cpu.step(&machine.bus);
        self.current = CpuSnapshot.capture(machine);
        return result;
    }

    pub fn changedRegister(self: *const DebugSession, comptime name: []const u8) bool {
        const before = self.previous orelse return false;
        const after = self.current orelse return false;
        return @field(before.registers, name) != @field(after.registers, name);
    }
};
