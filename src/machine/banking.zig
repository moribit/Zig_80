pub const bank_size = 0x4000;
pub const Kind = enum { rom, ram };
pub const Mapping = struct { kind: Kind, bank: u8 };
pub const Snapshot = struct { slots: [4]Mapping, rom_count: u8, ram_count: u8 };

pub const Banks = struct {
    rom: [4][bank_size]u8 = @splat(@splat(0)),
    ram: [4][bank_size]u8 = @splat(@splat(0)),
    rom_count: u8 = 4,
    ram_count: u8 = 4,
    slots: [4]Mapping = .{ .{ .kind = .rom, .bank = 0 }, .{ .kind = .rom, .bank = 1 }, .{ .kind = .ram, .bank = 0 }, .{ .kind = .ram, .bank = 1 } },

    pub fn map(self: *Banks, slot: usize, mapping: Mapping) !void {
        if (slot >= 4 or mapping.bank >= (if (mapping.kind == .rom) self.rom_count else self.ram_count)) return error.InvalidBank;
        self.slots[slot] = mapping;
    }
    pub fn read(self: *const Banks, address: u16) u8 {
        const mapping = self.slots[address / bank_size];
        return if (mapping.kind == .rom) self.rom[mapping.bank][address % bank_size] else self.ram[mapping.bank][address % bank_size];
    }
    pub fn write(self: *Banks, address: u16, value: u8) void {
        const mapping = self.slots[address / bank_size];
        if (mapping.kind == .ram) self.ram[mapping.bank][address % bank_size] = value;
    }
    pub fn snapshot(self: *const Banks) Snapshot {
        return .{ .slots = self.slots, .rom_count = self.rom_count, .ram_count = self.ram_count };
    }
    pub fn reset(self: *Banks) void {
        @memset(&self.ram, @splat(0));
        self.slots = .{ .{ .kind = .rom, .bank = 0 }, .{ .kind = .rom, .bank = 1 }, .{ .kind = .ram, .bank = 0 }, .{ .kind = .ram, .bank = 1 } };
    }
};
