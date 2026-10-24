pub const Result8 = struct { value: u8, flags: u8 };

pub const S: u8 = 0x80;
pub const Z: u8 = 0x40;
pub const H: u8 = 0x10;
pub const PV: u8 = 0x04;
pub const N: u8 = 0x02;
pub const C: u8 = 0x01;

pub fn isSet(f: u8, mask: u8) bool {
    return f & mask != 0;
}
pub fn set(f: *u8, mask: u8, value: bool) void {
    if (value) f.* |= mask else f.* &= ~mask;
}

pub fn add8(a: u8, b: u8) Result8 {
    const wide = @as(u16, a) + b;
    const value: u8 = @truncate(wide);
    var f: u8 = 0;
    if (value & 0x80 != 0) f |= S;
    if (value == 0) f |= Z;
    if ((a & 0x0f) + (b & 0x0f) > 0x0f) f |= H;
    if ((~(a ^ b) & (a ^ value) & 0x80) != 0) f |= PV;
    if (wide > 0xff) f |= C;
    return .{ .value = value, .flags = f };
}

pub fn sub8(a: u8, b: u8) Result8 {
    const value = a -% b;
    var f: u8 = N;
    if (value & 0x80 != 0) f |= S;
    if (value == 0) f |= Z;
    if ((a & 0x0f) < (b & 0x0f)) f |= H;
    if (((a ^ b) & (a ^ value) & 0x80) != 0) f |= PV;
    if (a < b) f |= C;
    return .{ .value = value, .flags = f };
}

pub fn adc8(a: u8, b: u8, carry: bool) Result8 {
    const c: u8 = @intFromBool(carry);
    const wide = @as(u16, a) + @as(u16, b) + c;
    const value: u8 = @truncate(wide);
    var f: u8 = 0;
    if (value & 0x80 != 0) f |= S;
    if (value == 0) f |= Z;
    if ((a & 0x0f) + (b & 0x0f) + c > 0x0f) f |= H;
    if (((~(a ^ b)) & (a ^ value)) & 0x80 != 0) f |= PV;
    if (wide > 0xff) f |= C;
    return .{ .value = value, .flags = f };
}

pub fn sbc8(a: u8, b: u8, carry: bool) Result8 {
    const c: u8 = @intFromBool(carry);
    const value = a -% b -% c;
    var f: u8 = N;
    if (value & 0x80 != 0) f |= S;
    if (value == 0) f |= Z;
    if ((a & 0x0f) < (b & 0x0f) + c) f |= H;
    if (((a ^ b) & (a ^ value)) & 0x80 != 0) f |= PV;
    if (@as(u16, a) < @as(u16, b) + c) f |= C;
    return .{ .value = value, .flags = f };
}

pub fn add16HL(a: u16, b: u16, old_f: u8) struct { value: u16, flags: u8 } {
    const wide = @as(u32, a) + b;
    var f = old_f & (S | Z | PV);
    if ((a & 0x0fff) + (b & 0x0fff) > 0x0fff) f |= H;
    if (wide > 0xffff) f |= C;
    return .{ .value = @truncate(wide), .flags = f };
}

pub fn rotateShift(operation: @import("instruction.zig").CbOperation, value: u8, old_f: u8) Result8 {
    const old_carry: u8 = @intFromBool(isSet(old_f, C));
    const carry = switch (operation) {
        .rlc, .rl, .sla => value >> 7,
        else => value & 1,
    };
    const result = switch (operation) {
        .rlc => (value << 1) | carry,
        .rrc => (value >> 1) | (carry << 7),
        .rl => (value << 1) | old_carry,
        .rr => (value >> 1) | (old_carry << 7),
        .sla => value << 1,
        .sra => (value >> 1) | (value & 0x80),
        .srl => value >> 1,
        else => unreachable,
    };
    var f: u8 = if (carry != 0) C else 0;
    if (result & 0x80 != 0) f |= S;
    if (result == 0) f |= Z;
    if (@popCount(result) & 1 == 0) f |= PV;
    return .{ .value = result, .flags = f };
}

pub fn bitTest(bit: u3, value: u8, old_f: u8) u8 {
    const bit_is_set = value & (@as(u8, 1) << bit) != 0;
    var f = (old_f & C) | H;
    if (!bit_is_set) f |= Z | PV;
    if (bit == 7 and bit_is_set) f |= S;
    return f;
}

pub const LogicOperation = enum { @"and", xor, @"or" };

pub fn logic8(operation: LogicOperation, a: u8, b: u8) Result8 {
    const value = switch (operation) {
        .@"and" => a & b,
        .xor => a ^ b,
        .@"or" => a | b,
    };
    var f: u8 = if (operation == .@"and") H else 0;
    if (value & 0x80 != 0) f |= S;
    if (value == 0) f |= Z;
    if (@popCount(value) & 1 == 0) f |= PV;
    return .{ .value = value, .flags = f };
}

pub fn inc8(value: u8, old_f: u8) Result8 {
    const result = value +% 1;
    var f: u8 = old_f & C;
    if (result & 0x80 != 0) f |= S;
    if (result == 0) f |= Z;
    if ((value & 0x0f) == 0x0f) f |= H;
    if (value == 0x7f) f |= PV;
    return .{ .value = result, .flags = f };
}

pub fn dec8(value: u8, old_f: u8) Result8 {
    const result = value -% 1;
    var f: u8 = (old_f & C) | N;
    if (result & 0x80 != 0) f |= S;
    if (result == 0) f |= Z;
    if ((value & 0x0f) == 0) f |= H;
    if (value == 0x80) f |= PV;
    return .{ .value = result, .flags = f };
}
