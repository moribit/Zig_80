pub const Registers = struct {
    a: u8 = 0,
    f: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
    d: u8 = 0,
    e: u8 = 0,
    h: u8 = 0,
    l: u8 = 0,
    pc: u16 = 0,
    sp: u16 = 0xffff,

    pub fn af(self: Registers) u16 {
        return pair(self.a, self.f);
    }
    pub fn bc(self: Registers) u16 {
        return pair(self.b, self.c);
    }
    pub fn de(self: Registers) u16 {
        return pair(self.d, self.e);
    }
    pub fn hl(self: Registers) u16 {
        return pair(self.h, self.l);
    }
    pub fn setAF(self: *Registers, v: u16) void {
        split(v, &self.a, &self.f);
    }
    pub fn setBC(self: *Registers, v: u16) void {
        split(v, &self.b, &self.c);
    }
    pub fn setDE(self: *Registers, v: u16) void {
        split(v, &self.d, &self.e);
    }
    pub fn setHL(self: *Registers, v: u16) void {
        split(v, &self.h, &self.l);
    }
};

fn pair(hi: u8, lo: u8) u16 {
    return (@as(u16, hi) << 8) | lo;
}
fn split(v: u16, hi: *u8, lo: *u8) void {
    hi.* = @truncate(v >> 8);
    lo.* = @truncate(v);
}
