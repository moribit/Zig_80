pub const Kind = enum { classic, handheld };

/// Provisional virtual ports, configurable until physical hardware is specified.
pub const Ports = struct {
    input: u8 = 0x10,
    input_control: u8 = 0x11,
    rom_bank: u8 = 0x20,
    ram_bank: u8 = 0x21,
    timer_control: u8 = 0x30,
    timer_count_low: u8 = 0x31,
    timer_count_high: u8 = 0x32,
    timer_period_low: u8 = 0x33,
    timer_period_high: u8 = 0x34,
    display_address_low: u8 = 0x40,
    display_address_high: u8 = 0x41,
    display_data: u8 = 0x42,
    display_control: u8 = 0x43,
};

pub const Config = struct {
    kind: Kind = .classic,
    clock_hz: u32 = 4_000_000,
    frame_hz: u16 = 60,
    timer_period: u16 = 40_000,
    rom_banks: u8 = 4,
    ram_banks: u8 = 4,
    ports: Ports = .{},

    pub fn validate(self: Config) !void {
        if (self.clock_hz == 0 or self.frame_hz == 0 or self.frame_hz > self.clock_hz or self.timer_period == 0 or self.rom_banks < 2 or self.rom_banks > 4 or self.ram_banks < 2 or self.ram_banks > 4) return error.InvalidMachineConfig;
        const std = @import("std");
        const fields = std.meta.fields(Ports);
        inline for (fields, 0..) |field, i| inline for (fields[0..i]) |previous| {
            if (@field(self.ports, field.name) == @field(self.ports, previous.name)) return error.DuplicatePort;
        };
    }
};
