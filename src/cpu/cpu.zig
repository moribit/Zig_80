const Registers = @import("registers.zig").Registers;
const flags = @import("flags.zig");
const Bus = @import("../machine/bus.zig").Bus;

pub const CpuError = error{UnknownOpcode};
pub const StepResult = struct { pc_before: u16, pc_after: u16, opcode: u8, t_states: u16, halted: bool };

pub const Cpu = struct {
    registers: Registers = .{},
    halted: bool = false,
    last_unknown_pc: u16 = 0,
    last_unknown_opcode: u8 = 0,
    instruction_index: u64 = 0,
    total_t_states: u64 = 0,

    pub fn reset(self: *Cpu) void {
        self.* = .{};
    }

    pub fn step(self: *Cpu, bus: *Bus) CpuError!StepResult {
        const before = self.registers.pc;
        if (self.halted) return result(self, before, 0x76, 4);
        bus.beginInstruction(self.instruction_index, self.total_t_states, before);
        const op = bus.readOpcode(self.registers.pc);
        self.registers.pc +%= 1;
        const cycles: u16 = switch (op) {
            0x00 => 4,
            0x76 => blk: {
                self.halted = true;
                break :blk 4;
            },
            0x3e => self.ld8(bus, &self.registers.a),
            0x06 => self.ld8(bus, &self.registers.b),
            0x0e => self.ld8(bus, &self.registers.c),
            0x16 => self.ld8(bus, &self.registers.d),
            0x1e => self.ld8(bus, &self.registers.e),
            0x26 => self.ld8(bus, &self.registers.h),
            0x2e => self.ld8(bus, &self.registers.l),
            0x01 => self.ld16(bus, .bc),
            0x11 => self.ld16(bus, .de),
            0x21 => self.ld16(bus, .hl),
            0x31 => self.ld16(bus, .sp),
            0x7e => blk: {
                self.registers.a = bus.readData8(self.registers.hl());
                break :blk 7;
            },
            0x77 => blk: {
                bus.write8(self.registers.hl(), self.registers.a);
                break :blk 7;
            },
            0x36 => blk: {
                bus.write8(self.registers.hl(), self.fetch8(bus));
                break :blk 10;
            },
            0x3a => blk: {
                const address = self.fetch16(bus);
                self.registers.a = bus.readData8(address);
                break :blk 13;
            },
            0x32 => blk: {
                const address = self.fetch16(bus);
                bus.write8(address, self.registers.a);
                break :blk 13;
            },
            0x2a => blk: {
                const address = self.fetch16(bus);
                const value = @as(u16, bus.readData8(address)) | (@as(u16, bus.readData8(address +% 1)) << 8);
                self.registers.setHL(value);
                break :blk 16;
            },
            0x22 => blk: {
                const address = self.fetch16(bus);
                bus.write16(address, self.registers.hl());
                break :blk 16;
            },
            0x3c => self.inc(&self.registers.a),
            0x04 => self.inc(&self.registers.b),
            0x0c => self.inc(&self.registers.c),
            0x14 => self.inc(&self.registers.d),
            0x1c => self.inc(&self.registers.e),
            0x24 => self.inc(&self.registers.h),
            0x2c => self.inc(&self.registers.l),
            0x23 => blk: {
                self.registers.setHL(self.registers.hl() +% 1);
                break :blk 6;
            },
            0x3d => self.dec(&self.registers.a),
            0x05 => self.dec(&self.registers.b),
            0x0d => self.dec(&self.registers.c),
            0x15 => self.dec(&self.registers.d),
            0x1d => self.dec(&self.registers.e),
            0x25 => self.dec(&self.registers.h),
            0x2d => self.dec(&self.registers.l),
            0x2b => blk: {
                self.registers.setHL(self.registers.hl() -% 1);
                break :blk 6;
            },
            0xc6 => self.add(self.fetch8(bus), 7),
            0x80...0x85, 0x87 => self.add(self.regValue(op & 7), 4),
            0xd6 => self.sub(self.fetch8(bus), 7, false),
            0x90...0x95, 0x97 => self.sub(self.regValue(op & 7), 4, false),
            0xfe => self.sub(self.fetch8(bus), 7, true),
            0xb8...0xbd, 0xbf => self.sub(self.regValue(op & 7), 4, true),
            0xc3 => blk: {
                self.registers.pc = self.fetch16(bus);
                break :blk 10;
            },
            0xc2 => self.jpConditional(bus, !flags.isSet(self.registers.f, flags.Z)),
            0xca => self.jpConditional(bus, flags.isSet(self.registers.f, flags.Z)),
            0x18 => self.jr(bus, true),
            0x20 => self.jr(bus, !flags.isSet(self.registers.f, flags.Z)),
            0x28 => self.jr(bus, flags.isSet(self.registers.f, flags.Z)),
            0xcd => blk: {
                const target = self.fetch16(bus);
                self.push(bus, self.registers.pc);
                self.registers.pc = target;
                break :blk 17;
            },
            0xc9 => blk: {
                self.registers.pc = self.pop(bus);
                break :blk 10;
            },
            0xf5 => self.pushPair(bus, self.registers.af()),
            0xc5 => self.pushPair(bus, self.registers.bc()),
            0xd5 => self.pushPair(bus, self.registers.de()),
            0xe5 => self.pushPair(bus, self.registers.hl()),
            0xf1 => self.popPair(bus, .af),
            0xc1 => self.popPair(bus, .bc),
            0xd1 => self.popPair(bus, .de),
            0xe1 => self.popPair(bus, .hl),
            else => {
                self.last_unknown_pc = before;
                self.last_unknown_opcode = op;
                self.registers.pc = before;
                return error.UnknownOpcode;
            },
        };
        self.instruction_index +%= 1;
        self.total_t_states +%= cycles;
        return result(self, before, op, cycles);
    }

    const Pair = enum { af, bc, de, hl, sp };
    fn result(self: *Cpu, before: u16, op: u8, cycles: u16) StepResult {
        return .{ .pc_before = before, .pc_after = self.registers.pc, .opcode = op, .t_states = cycles, .halted = self.halted };
    }
    fn fetch8(self: *Cpu, bus: *Bus) u8 {
        const v = bus.readOperand8(self.registers.pc);
        self.registers.pc +%= 1;
        return v;
    }
    fn fetch16(self: *Cpu, bus: *Bus) u16 {
        const v = bus.readOperand16(self.registers.pc);
        self.registers.pc +%= 2;
        return v;
    }
    fn ld8(self: *Cpu, bus: *Bus, dst: *u8) u16 {
        dst.* = self.fetch8(bus);
        return 7;
    }
    fn ld16(self: *Cpu, bus: *Bus, p: Pair) u16 {
        const v = self.fetch16(bus);
        switch (p) {
            .bc => self.registers.setBC(v),
            .de => self.registers.setDE(v),
            .hl => self.registers.setHL(v),
            .sp => self.registers.sp = v,
            .af => unreachable,
        }
        return 10;
    }
    fn inc(self: *Cpu, dst: *u8) u16 {
        const x = flags.inc8(dst.*, self.registers.f);
        dst.* = x.value;
        self.registers.f = x.flags;
        return 4;
    }
    fn dec(self: *Cpu, dst: *u8) u16 {
        const x = flags.dec8(dst.*, self.registers.f);
        dst.* = x.value;
        self.registers.f = x.flags;
        return 4;
    }
    fn regValue(self: *Cpu, code: u8) u8 {
        return switch (code) {
            0 => self.registers.b,
            1 => self.registers.c,
            2 => self.registers.d,
            3 => self.registers.e,
            4 => self.registers.h,
            5 => self.registers.l,
            7 => self.registers.a,
            else => unreachable,
        };
    }
    fn add(self: *Cpu, v: u8, cycles: u16) u16 {
        const x = flags.add8(self.registers.a, v);
        self.registers.a = x.value;
        self.registers.f = x.flags;
        return cycles;
    }
    fn sub(self: *Cpu, v: u8, cycles: u16, compare: bool) u16 {
        const x = flags.sub8(self.registers.a, v);
        if (!compare) self.registers.a = x.value;
        self.registers.f = x.flags;
        return cycles;
    }
    fn jpConditional(self: *Cpu, bus: *Bus, condition: bool) u16 {
        const target = self.fetch16(bus);
        if (condition) self.registers.pc = target;
        return 10;
    }
    fn jr(self: *Cpu, bus: *Bus, condition: bool) u16 {
        const raw = self.fetch8(bus);
        if (condition) {
            const offset: i8 = @bitCast(raw);
            self.registers.pc +%= @bitCast(@as(i16, offset));
            return 12;
        }
        return 7;
    }
    fn push(self: *Cpu, bus: *Bus, v: u16) void {
        self.registers.sp -%= 2;
        bus.write16(self.registers.sp, v);
    }
    fn pop(self: *Cpu, bus: *Bus) u16 {
        const v = @as(u16, bus.readData8(self.registers.sp)) | (@as(u16, bus.readData8(self.registers.sp +% 1)) << 8);
        self.registers.sp +%= 2;
        return v;
    }
    fn pushPair(self: *Cpu, bus: *Bus, v: u16) u16 {
        self.push(bus, v);
        return 11;
    }
    fn popPair(self: *Cpu, bus: *Bus, p: Pair) u16 {
        const v = self.pop(bus);
        switch (p) {
            .af => self.registers.setAF(v),
            .bc => self.registers.setBC(v),
            .de => self.registers.setDE(v),
            .hl => self.registers.setHL(v),
            .sp => unreachable,
        }
        return 10;
    }
};
