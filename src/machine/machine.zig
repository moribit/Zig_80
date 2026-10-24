const Bus = @import("bus.zig").Bus;
const Cpu = @import("../cpu/cpu.zig").Cpu;
const memory = @import("memory.zig");

pub const Machine = struct {
    bus: Bus = .{},
    cpu: Cpu = .{},
    frame_counter: u16 = 0,
    random_state: u16 = 0xace1,

    pub fn reset(self: *Machine) void {
        self.resetMachine();
    }
    pub fn resetCpu(self: *Machine) void {
        self.cpu.reset();
    }
    pub fn resetPeripherals(self: *Machine) void {
        self.frame_counter = 0;
        self.random_state = 0xace1;
        @memset(self.bus.memory[memory.vram_start .. memory.vram_end + 1], 0);
        self.setInput(0);
        self.syncDevices();
    }
    pub fn resetMachine(self: *Machine) void {
        self.resetCpu();
        @memset(self.bus.memory[memory.ram_start..], 0);
        self.bus.trace_sequence = 0;
        self.bus.beginInstruction(0, 0, 0);
        self.resetPeripherals();
    }
    pub fn powerOn(self: *Machine) void {
        const sink = self.bus.trace_sink;
        const debug_sink = self.bus.debug_trace_sink;
        self.* = .{};
        self.bus.trace_sink = sink;
        self.bus.debug_trace_sink = debug_sink;
        self.resetPeripherals();
    }
    pub fn load(self: *Machine, program: []const u8) error{ProgramTooLarge}!void {
        if (program.len > 0x8000) return error.ProgramTooLarge;
        self.powerOn();
        @memcpy(self.bus.memory[0..program.len], program);
    }
    pub fn setInput(self: *Machine, value: u8) void {
        // Peripheral state changes are not Z80 bus transactions and therefore
        // must not appear in the CPU's logical trace.
        self.bus.memory[memory.input_address] = value;
    }
    pub fn tickFrame(self: *Machine) void {
        self.frame_counter +%= 1;
        self.random_state = (self.random_state >> 1) ^ (if (self.random_state & 1 != 0) @as(u16, 0xb400) else 0);
        self.syncDevices();
    }
    fn syncDevices(self: *Machine) void {
        self.bus.memory[memory.frame_low] = @truncate(self.frame_counter);
        self.bus.memory[memory.frame_high] = @truncate(self.frame_counter >> 8);
        self.bus.memory[memory.random_address] = @truncate(self.random_state);
    }
};
