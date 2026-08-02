pub const Definition = struct { mnemonic: []const u8, opcode: u8, size: u8, t_states: u16 };

/// Mnemonics currently accepted by the assembler. Operand forms remain family-specific.
pub const assembler_mnemonics = [_][]const u8{
    "NOP", "HALT", "RET", "JP",  "CALL", "JR",  "PUSH", "POP", "INC",
    "DEC", "ADD",  "ADC", "SUB", "SBC",  "CP",  "AND",  "OR",  "XOR",
    "LD",  "DJNZ", "BIT", "SET", "RES",  "RLC", "RRC",  "RL",  "RR",
    "SLA", "SRA",  "SRL",
};

pub fn isAssemblerMnemonic(name: []const u8) bool {
    for (assembler_mnemonics) |candidate| {
        if (@import("std").ascii.eqlIgnoreCase(name, candidate)) return true;
    }
    return false;
}

/// Z80's three-bit register encoding. Code 6 denotes memory addressed by HL.
pub const register8_names = [_][]const u8{ "B", "C", "D", "E", "H", "L", "(HL)", "A" };

pub fn register8Code(name: []const u8) ?u8 {
    for (register8_names, 0..) |candidate, code| {
        if (@import("std").ascii.eqlIgnoreCase(name, candidate)) return @intCast(code);
    }
    return null;
}

pub fn register8Name(code: u8) []const u8 {
    return register8_names[code & 7];
}

pub const LogicFamily = struct {
    mnemonic: []const u8,
    register_base: u8,
    immediate_opcode: u8,
    register_size: u8 = 1,
    indirect_size: u8 = 1,
    immediate_size: u8 = 2,
    register_t_states: u16 = 4,
    indirect_t_states: u16 = 7,
    immediate_t_states: u16 = 7,
    flags: []const u8,
};

/// Documented flags only. Undocumented flag bits are outside the current model.
pub const logic_families = [_]LogicFamily{
    .{ .mnemonic = "AND", .register_base = 0xa0, .immediate_opcode = 0xe6, .flags = "S Z 1 P/V 0 0" },
    .{ .mnemonic = "XOR", .register_base = 0xa8, .immediate_opcode = 0xee, .flags = "S Z 0 P/V 0 0" },
    .{ .mnemonic = "OR", .register_base = 0xb0, .immediate_opcode = 0xf6, .flags = "S Z 0 P/V 0 0" },
};

pub fn logicByMnemonic(mnemonic: []const u8) ?LogicFamily {
    for (logic_families) |family| if (@import("std").ascii.eqlIgnoreCase(mnemonic, family.mnemonic)) return family;
    return null;
}

pub fn logicByOpcode(opcode: u8) ?struct { family: LogicFamily, register_code: ?u8 } {
    for (logic_families) |family| {
        if (opcode == family.immediate_opcode) return .{ .family = family, .register_code = null };
        if (opcode >= family.register_base and opcode < family.register_base + 8) return .{ .family = family, .register_code = opcode & 7 };
    }
    return null;
}

pub fn ldRegisterOpcode(destination: u8, source: u8) ?u8 {
    const opcode: u8 = 0x40 | ((destination & 7) << 3) | (source & 7);
    return if (opcode == 0x76) null else opcode;
}

pub fn ldRegisterTStates(destination: u8, source: u8) u16 {
    return if (destination == 6 or source == 6) 7 else 4;
}

pub fn ldRegisterSize(_: u8, _: u8) u8 {
    return 1;
}

pub const CbOperation = enum(u8) { rlc = 0x00, rrc = 0x08, rl = 0x10, rr = 0x18, sla = 0x20, sra = 0x28, srl = 0x38, bit = 0x40, res = 0x80, set = 0xc0 };

pub fn cbOpcode(operation: CbOperation, bit: u3, register: u8) u8 {
    return @intFromEnum(operation) + (if (operation == .bit or operation == .res or operation == .set) @as(u8, bit) << 3 else 0) + (register & 7);
}

pub fn cbTStates(operation: CbOperation, register: u8) u16 {
    if (register != 6) return 8;
    return if (operation == .bit) 12 else 15;
}

pub const fixed = [_]Definition{
    .{ .mnemonic = "NOP", .opcode = 0x00, .size = 1, .t_states = 4 },
    .{ .mnemonic = "HALT", .opcode = 0x76, .size = 1, .t_states = 4 },
    .{ .mnemonic = "RET", .opcode = 0xc9, .size = 1, .t_states = 10 },
};
