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

pub fn add8(a: u8, b: u8) struct { value: u8, flags: u8 } {
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

pub fn sub8(a: u8, b: u8) struct { value: u8, flags: u8 } {
    const value = a -% b;
    var f: u8 = N;
    if (value & 0x80 != 0) f |= S;
    if (value == 0) f |= Z;
    if ((a & 0x0f) < (b & 0x0f)) f |= H;
    if (((a ^ b) & (a ^ value) & 0x80) != 0) f |= PV;
    if (a < b) f |= C;
    return .{ .value = value, .flags = f };
}

pub fn inc8(value: u8, old_f: u8) struct { value: u8, flags: u8 } {
    const result = value +% 1;
    var f: u8 = old_f & C;
    if (result & 0x80 != 0) f |= S;
    if (result == 0) f |= Z;
    if ((value & 0x0f) == 0x0f) f |= H;
    if (value == 0x7f) f |= PV;
    return .{ .value = result, .flags = f };
}

pub fn dec8(value: u8, old_f: u8) struct { value: u8, flags: u8 } {
    const result = value -% 1;
    var f: u8 = (old_f & C) | N;
    if (result & 0x80 != 0) f |= S;
    if (result == 0) f |= Z;
    if ((value & 0x0f) == 0) f |= H;
    if (value == 0x80) f |= PV;
    return .{ .value = result, .flags = f };
}
