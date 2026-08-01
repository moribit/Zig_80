pub const Definition = struct { mnemonic: []const u8, opcode: u8, size: u8, t_states: u16 };

pub const fixed = [_]Definition{
    .{ .mnemonic = "NOP", .opcode = 0x00, .size = 1, .t_states = 4 },
    .{ .mnemonic = "HALT", .opcode = 0x76, .size = 1, .t_states = 4 },
    .{ .mnemonic = "RET", .opcode = 0xc9, .size = 1, .t_states = 10 },
};
