const Bus = @import("bus.zig").Bus;
const Cpu = @import("../cpu/cpu.zig").Cpu;
const memory = @import("memory.zig");
const profile = @import("profile.zig");

pub const Machine = struct {
    config: profile.Config = .{},
    bus: Bus = .{},
    cpu: Cpu = .{},
    frame_counter: u16 = 0,
    random_state: u16 = 0xace1,

    pub fn init(config: profile.Config) !Machine {
        try config.validate();
        var self: Machine = .{ .config = config };
        self.powerOn();
        return self;
    }

    pub fn step(self: *Machine) @import("../cpu/cpu.zig").CpuError!@import("../cpu/cpu.zig").StepResult {
        if (self.config.kind == .handheld) self.cpu.setInt(self.bus.devices.interrupt(), 0xff);
        const result = try self.cpu.step(&self.bus);
        if (self.config.kind == .handheld) {
            const frames_before = self.bus.devices.frames;
            self.bus.devices.tick(result.t_states);
            var frames = self.bus.devices.frames -% frames_before;
            while (frames > 0) : (frames -= 1) self.tickFrame();
        }
        return result;
    }

    pub fn displayWidth(self: *const Machine) usize {
        return if (self.config.kind == .handheld) 256 else 128;
    }
    pub fn canWakeFromHalt(self: *const Machine) bool {
        return self.cpu.nmi_pending or (self.cpu.iff1 and (self.cpu.int_line or (self.config.kind == .handheld and (self.bus.devices.timer_enabled or self.bus.devices.input_irq_enabled))));
    }
    pub fn displayBytes(self: *const Machine) []const u8 {
        return if (self.config.kind == .handheld) &self.bus.devices.display.frame.bytes else self.bus.memory[memory.vram_start .. memory.vram_end + 1];
    }
    pub fn displayPixel(self: *const Machine, x: usize, y: usize) bool {
        if (x >= self.displayWidth() or y >= 64) return false;
        return self.displayBytes()[(y / 8) * self.displayWidth() + x] & (@as(u8, 1) << @as(u3, @intCast(y % 8))) != 0;
    }
    pub fn writeDisplayPbm(self: *const Machine, writer: *@import("std").Io.Writer) !void {
        try writer.print("P1\n{d} 64\n", .{self.displayWidth()});
        for (0..64) |y| {
            for (0..self.displayWidth()) |x| try writer.writeAll(if (self.displayPixel(x, y)) "1 " else "0 ");
            try writer.writeAll("\n");
        }
    }
    pub fn renderDisplay(self: *const Machine, writer: *@import("std").Io.Writer) !void {
        for (0..32) |row| {
            for (0..self.displayWidth()) |x| {
                const bits: u2 = @as(u2, @intFromBool(self.displayPixel(x, row * 2))) | (@as(u2, @intFromBool(self.displayPixel(x, row * 2 + 1))) << 1);
                try writer.writeAll(switch (bits) {
                    0 => " ",
                    1 => "▀",
                    2 => "▄",
                    3 => "█",
                });
            }
            try writer.writeAll("\n");
        }
    }

    pub fn reset(self: *Machine) void {
        self.resetMachine();
    }
    pub fn resetCpu(self: *Machine) void {
        self.cpu.reset();
    }
    pub fn resetPeripherals(self: *Machine) void {
        self.bus.devices = .{ .config = self.config };
        self.frame_counter = 0;
        self.random_state = 0xace1;
        @memset(self.bus.memory[memory.vram_start .. memory.vram_end + 1], 0);
        self.setInput(0);
        self.syncDevices();
    }
    pub fn resetMachine(self: *Machine) void {
        self.resetCpu();
        @memset(self.bus.memory[memory.ram_start..], 0);
        self.bus.banks.reset();
        self.bus.trace_sequence = 0;
        self.bus.beginInstruction(0, 0, 0);
        self.resetPeripherals();
    }
    pub fn powerOn(self: *Machine) void {
        const config = self.config;
        const sink = self.bus.trace_sink;
        const debug_sink = self.bus.debug_trace_sink;
        const port_device = self.bus.port_device;
        self.* = .{};
        self.config = config;
        self.bus.kind = config.kind;
        self.bus.banks.rom_count = config.rom_banks;
        self.bus.banks.ram_count = config.ram_banks;
        self.bus.port_device = port_device;
        self.bus.trace_sink = sink;
        self.bus.debug_trace_sink = debug_sink;
        self.resetPeripherals();
    }
    pub fn load(self: *Machine, program: []const u8) error{ProgramTooLarge}!void {
        if (program.len > 0x8000) return error.ProgramTooLarge;
        self.powerOn();
        if (self.config.kind == .handheld) {
            for (program, 0..) |byte, i| self.bus.banks.rom[i / 0x4000][i % 0x4000] = byte;
        } else @memcpy(self.bus.memory[0..program.len], program);
    }
    pub fn loadRomBank(self: *Machine, bank: u8, bytes: []const u8) error{ InvalidBank, ProgramTooLarge }!void {
        if (self.config.kind != .handheld or bank >= self.config.rom_banks) return error.InvalidBank;
        if (bytes.len > 0x4000) return error.ProgramTooLarge;
        @memset(&self.bus.banks.rom[bank], 0);
        @memcpy(self.bus.banks.rom[bank][0..bytes.len], bytes);
    }
    pub fn setInput(self: *Machine, value: u8) void {
        if (self.config.kind == .handheld) self.bus.devices.setInput(value);
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
