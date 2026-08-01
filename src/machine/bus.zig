pub const Bus = struct {
    memory: [65536]u8 = [_]u8{0} ** 65536,

    pub fn read8(self: *const Bus, address: u16) u8 {
        return self.memory[address];
    }
    pub fn write8(self: *Bus, address: u16, value: u8) void {
        self.memory[address] = value;
    }
    pub fn read16(self: *const Bus, address: u16) u16 {
        const next = address +% 1;
        return @as(u16, self.read8(address)) | (@as(u16, self.read8(next)) << 8);
    }
    pub fn write16(self: *Bus, address: u16, value: u16) void {
        self.write8(address, @truncate(value));
        self.write8(address +% 1, @truncate(value >> 8));
    }
    pub fn input(_: *Bus, _: u16) u8 {
        return 0xff;
    }
    pub fn output(_: *Bus, _: u16, _: u8) void {}
};
