//! Functional original-PC-8001 port adapter for tests, not a full PC-8001 target.
//! One holding register + shift register; time advances on status polls, not bits.
const Bus = @import("../machine/bus.zig").Bus;
pub const Usart = struct {
    receive: []const u8 = "",
    receive_index: usize = 0,
    transmitted: [256]u8 = @splat(0),
    transmitted_len: usize = 0,
    controls: [16]u8 = @splat(0),
    control_len: usize = 0,
    port30: u8 = 0,
    mode: u8 = 0,
    command: u8 = 0,
    expects_mode: bool = false,
    cts: bool = true,
    errors: u8 = 0,
    holding: ?u8 = null,
    shifting: ?u8 = null,
    shift_polls: u8 = 0,
    rx_delay: u8 = 0,
    status_reads: usize = 0,
    upper_port_seen: bool = false,

    pub fn attach(self: *Usart, bus: *Bus) void {
        bus.port_device = .{ .context = self, .read = read, .write = write };
    }
    fn external(self: *const Usart) bool {
        return self.port30 & 0x30 == 0x20;
    }
    fn read(context: *anyopaque, port: u16) u8 {
        const self: *Usart = @ptrCast(@alignCast(context));
        if (port > 255) self.upper_port_seen = true;
        const low: u8 = @truncate(port);
        if (low == 0x20) {
            if (!self.external() or self.command & 4 == 0 or self.receive_index >= self.receive.len) return 0xff;
            const value = self.receive[self.receive_index];
            self.receive_index += 1;
            self.rx_delay = 6;
            return value;
        }
        if (low != 0x21) return 0xff;
        self.status_reads += 1;
        if (self.external() and self.command & 1 != 0 and self.cts) {
            if (self.shifting) |byte| {
                if (self.shift_polls > 0) self.shift_polls -= 1;
                if (self.shift_polls == 0) {
                    if (self.transmitted_len < self.transmitted.len) {
                        self.transmitted[self.transmitted_len] = byte;
                        self.transmitted_len += 1;
                    }
                    self.shifting = null;
                }
            }
            if (self.shifting == null and self.holding != null) {
                self.shifting = self.holding;
                self.holding = null;
                self.shift_polls = 5;
            }
        }
        if (self.rx_delay > 0) self.rx_delay -= 1;
        const rx_ready = self.external() and self.command & 4 != 0 and self.receive_index < self.receive.len and self.rx_delay == 0;
        return self.errors | @as(u8, if (self.holding == null) 1 else 0) | @as(u8, if (rx_ready) 2 else 0) | @as(u8, if (self.holding == null and self.shifting == null) 4 else 0);
    }
    fn write(context: *anyopaque, port: u16, value: u8) void {
        const self: *Usart = @ptrCast(@alignCast(context));
        if (port > 255) self.upper_port_seen = true;
        switch (@as(u8, @truncate(port))) {
            0x20 => {
                if (self.holding == null) self.holding = value;
            },
            0x21 => {
                if (self.control_len < self.controls.len) {
                    self.controls[self.control_len] = value;
                    self.control_len += 1;
                }
                if (self.expects_mode) {
                    self.mode = value;
                    self.expects_mode = false;
                } else if (value & 0x40 != 0) {
                    self.expects_mode = true;
                    self.command = 0;
                    self.holding = null;
                    self.shifting = null;
                } else self.command = value;
            },
            0x30 => self.port30 = value,
            else => {},
        }
    }
};
