const Bus = @import("bus.zig").Bus;
const Cpu = @import("../cpu/cpu.zig").Cpu;
const memory = @import("memory.zig");

pub const Machine = struct {
    bus: Bus = .{},
    cpu: Cpu = .{},
    frame_counter: u16 = 0,
    random_state: u16 = 0xace1,

    pub fn reset(self: *Machine) void {
        self.cpu.reset();
        self.frame_counter = 0;
        self.syncDevices();
    }
    pub fn load(self: *Machine, program: []const u8) error{ProgramTooLarge}!void {
        if (program.len > 0x8000) return error.ProgramTooLarge;
        @memcpy(self.bus.memory[0..program.len], program);
        self.cpu.reset();
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
