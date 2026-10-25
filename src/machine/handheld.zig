const profile = @import("profile.zig");
const display = @import("display.zig");

pub const Devices = struct {
    config: profile.Config = .{ .kind = .handheld },
    display: display.Controller = .{},
    input: u8 = 0,
    input_irq_enabled: bool = false,
    input_irq: bool = false,
    timer_enabled: bool = false,
    timer_phase: u64 = 0,
    timer_count: u16 = 0,
    timer_irq: bool = false,
    frame_phase: u64 = 0,
    frames: u64 = 0,

    pub fn setInput(self: *Devices, value: u8) void {
        if (self.input != value and self.input_irq_enabled) self.input_irq = true;
        self.input = value;
    }
    pub fn interrupt(self: *const Devices) bool {
        return self.timer_irq or self.input_irq;
    }

    /// All advancement is by emulated T-states, never OS wall time.
    pub fn tick(self: *Devices, t_states: u16) void {
        self.frame_phase += @as(u64, t_states) * self.config.frame_hz;
        while (self.frame_phase >= self.config.clock_hz) {
            self.frame_phase -= self.config.clock_hz;
            self.frames +%= 1;
        }
        if (!self.timer_enabled) return;
        self.timer_phase += t_states;
        while (self.timer_phase >= self.config.timer_period) {
            self.timer_phase -= self.config.timer_period;
            self.timer_count +%= 1;
            self.timer_irq = true;
        }
    }

    pub fn read(self: *Devices, port: u8) u8 {
        const p = self.config.ports;
        if (port == p.input) return self.input;
        if (port == p.input_control) return @as(u8, @intFromBool(self.input_irq_enabled)) | (if (self.input_irq) @as(u8, 0x80) else 0);
        if (port == p.timer_control) return @as(u8, @intFromBool(self.timer_enabled)) | (if (self.timer_irq) @as(u8, 0x80) else 0);
        if (port == p.timer_count_low) return @truncate(self.timer_count);
        if (port == p.timer_count_high) return @truncate(self.timer_count >> 8);
        if (port == p.timer_period_low) return @truncate(self.config.timer_period);
        if (port == p.timer_period_high) return @truncate(self.config.timer_period >> 8);
        if (port == p.display_data) return self.display.read();
        return 0xff;
    }
    pub fn write(self: *Devices, port: u8, value: u8) void {
        const p = self.config.ports;
        if (port == p.input_control) {
            self.input_irq_enabled = value & 1 != 0;
            if (value & 0x80 != 0) self.input_irq = false;
        }
        if (port == p.timer_control) {
            self.timer_enabled = value & 1 != 0;
            if (!self.timer_enabled) self.timer_phase = 0;
            if (value & 0x80 != 0) self.timer_irq = false;
        }
        if (port == p.timer_period_low or port == p.timer_period_high) {
            const candidate = if (port == p.timer_period_low) (self.config.timer_period & 0xff00) | value else (self.config.timer_period & 0xff) | (@as(u16, value) << 8);
            if (candidate != 0) {
                self.config.timer_period = candidate;
                self.timer_phase %= candidate;
            }
        }
        if (port == p.display_address_low) self.display.address = (self.display.address & 0x700) | value;
        if (port == p.display_address_high) self.display.address = (self.display.address & 0xff) | (@as(u11, @truncate(value)) << 8);
        if (port == p.display_data) self.display.write(value);
        if (port == p.display_control and value & 1 != 0) {
            self.display.frame.clear();
            self.display.address = 0;
        }
    }
};
