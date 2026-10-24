const Registers = @import("registers.zig").Registers;
const flags = @import("flags.zig");
const instruction = @import("instruction.zig");
const Bus = @import("../machine/bus.zig").Bus;

pub const CpuError = error{UnknownOpcode};
pub const InstructionFault = struct { pc: u16, prefix: ?u8 = null, opcode: u8 };
pub const StepResult = struct { pc_before: u16, pc_after: u16, opcode: u8, t_states: u16, halted: bool };

pub const Cpu = struct {
    registers: Registers = .{},
    halted: bool = false,
    last_unknown_pc: u16 = 0,
    last_unknown_opcode: u8 = 0,
    fault: ?InstructionFault = null,
    iff1: bool = false,
    iff2: bool = false,
    ei_delay: u2 = 0,
    interrupt_mode: u2 = 0,
    int_line: bool = false,
    int_data: u8 = 0xff,
    nmi_pending: bool = false,
    instruction_index: u64 = 0,
    total_t_states: u64 = 0,

    pub fn reset(self: *Cpu) void {
        self.* = .{};
    }

    pub fn step(self: *Cpu, bus: *Bus) CpuError!StepResult {
        const before = self.registers.pc;
        if (self.nmi_pending or (self.int_line and self.iff1 and self.ei_delay == 0)) return self.acceptInterrupt(bus);
        if (self.halted) {
            self.incrementR();
            self.total_t_states +%= 4;
            return result(self, before, 0x76, 4);
        }
        const registers_before = self.registers;
        errdefer self.registers = registers_before;
        self.fault = null;
        bus.beginInstruction(self.instruction_index, self.total_t_states, before);
        const op = bus.readOpcode(self.registers.pc);
        self.registers.pc +%= 1;
        self.incrementR();
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
            0x40...0x75, 0x77...0x7f => self.ldRegister(bus, (op >> 3) & 7, op & 7),
            0x36 => blk: {
                bus.write8(self.registers.hl(), self.fetch8(bus));
                break :blk 10;
            },
            0x34 => self.incMemory(bus),
            0x35 => self.decMemory(bus),
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
            0xa0...0xa7 => self.logic(bus, .@"and", op & 7),
            0xa8...0xaf => self.logic(bus, .xor, op & 7),
            0xb0...0xb7 => self.logic(bus, .@"or", op & 7),
            0xe6 => self.logicImmediate(bus, .@"and"),
            0xee => self.logicImmediate(bus, .xor),
            0xf6 => self.logicImmediate(bus, .@"or"),
            0x88...0x8f => self.adc(bus, op & 7),
            0xce => self.adcImmediate(bus),
            0x98...0x9f => self.sbc(bus, op & 7),
            0xde => self.sbcImmediate(bus),
            0x09, 0x19, 0x29, 0x39 => self.addHL(op),
            0x10 => self.djnz(bus),
            0xcb => try self.cb(bus),
            0xed => try self.ed(bus),
            0xdd, 0xfd => try self.indexed(bus, op),
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
            else => self.extendedBase(bus, op) orelse {
                self.last_unknown_pc = before;
                self.last_unknown_opcode = op;
                self.fault = .{ .pc = before, .opcode = op };
                self.registers.pc = before;
                return error.UnknownOpcode;
            },
        };
        self.instruction_index +%= 1;
        self.total_t_states +%= cycles;
        if (self.ei_delay > 0) self.ei_delay -= 1;
        return result(self, before, op, cycles);
    }

    pub fn setInt(self: *Cpu, asserted: bool, data: u8) void {
        self.int_line = asserted;
        self.int_data = data;
    }

    pub fn requestNmi(self: *Cpu) void {
        self.nmi_pending = true;
    }

    fn incrementR(self: *Cpu) void {
        self.registers.r = (self.registers.r & 0x80) | ((self.registers.r +% 1) & 0x7f);
    }

    fn acceptInterrupt(self: *Cpu, bus: *Bus) CpuError!StepResult {
        const pc = self.registers.pc;
        // IM0 accepts the documented single-byte RST vectors. Other injected
        // instructions are deliberately rejected before architectural changes.
        if (!self.nmi_pending and self.interrupt_mode == 0 and self.int_data & 0xc7 != 0xc7) {
            self.fault = .{ .pc = pc, .opcode = self.int_data };
            self.last_unknown_pc = pc;
            self.last_unknown_opcode = self.int_data;
            return error.UnknownOpcode;
        }
        bus.beginInstruction(self.instruction_index, self.total_t_states, pc);
        self.incrementR();
        self.halted = false;
        var cycles: u16 = 13;
        var target: u16 = 0x38;
        if (self.nmi_pending) {
            self.nmi_pending = false;
            self.iff2 = self.iff1;
            self.iff1 = false;
            target = 0x66;
            cycles = 11;
        } else {
            self.iff1 = false;
            self.iff2 = false;
            bus.acknowledgeInterrupt(self.int_data);
            if (self.interrupt_mode == 0) target = self.int_data & 0x38;
        }
        self.push(bus, pc);
        if (self.interrupt_mode == 2 and cycles != 11) {
            const vector = (@as(u16, self.registers.i) << 8) | self.int_data;
            target = @as(u16, bus.readData8(vector)) | (@as(u16, bus.readData8(vector +% 1)) << 8);
            cycles = 19;
        }
        self.registers.pc = target;
        self.instruction_index +%= 1;
        self.total_t_states +%= cycles;
        return result(self, pc, self.int_data, cycles);
    }

    fn ed(self: *Cpu, bus: *Bus) CpuError!u16 {
        const op = bus.readOpcode(self.registers.pc);
        self.registers.pc +%= 1;
        const definition = @import("extended_metadata.zig").lookup(0xed, op) orelse {
            self.last_unknown_pc = self.registers.pc -% 2;
            self.last_unknown_opcode = op;
            self.fault = .{ .pc = self.last_unknown_pc, .prefix = 0xed, .opcode = op };
            return error.UnknownOpcode;
        };
        self.incrementR();
        if (op & 0xc7 == 0x40) {
            const value = bus.input(self.registers.bc());
            self.setRegValue((op >> 3) & 7, value);
            self.registers.f = (self.registers.f & flags.C) | flags.logic8(.@"or", value, 0).flags;
        } else if (op & 0xc7 == 0x41) {
            bus.output(self.registers.bc(), self.regValue((op >> 3) & 7));
        } else if (op & 0xcf == 0x42 or op & 0xcf == 0x4a) {
            const lhs = self.registers.hl();
            const rhs = self.pairValue((op >> 4) & 3);
            const carry: u32 = @intFromBool(flags.isSet(self.registers.f, flags.C));
            const subtract = op & 8 == 0;
            const wide = if (subtract) @as(u32, lhs) -% rhs -% carry else @as(u32, lhs) + rhs + carry;
            const value: u16 = @truncate(wide);
            const signed_lhs: i32 = @as(i16, @bitCast(lhs));
            const signed_rhs: i32 = @as(i16, @bitCast(rhs));
            const signed = if (subtract) signed_lhs - signed_rhs - @as(i32, @intCast(carry)) else signed_lhs + signed_rhs + @as(i32, @intCast(carry));
            var f: u8 = if (subtract) flags.N else 0;
            if (value == 0) f |= flags.Z;
            if (value & 0x8000 != 0) f |= flags.S;
            if ((lhs ^ rhs ^ value) & 0x1000 != 0) f |= flags.H;
            if (signed < -32768 or signed > 32767) f |= flags.PV;
            if (wide > 65535) f |= flags.C;
            self.registers.setHL(value);
            self.registers.f = f;
        } else if (op & 0xcf == 0x43 or op & 0xcf == 0x4b) {
            const address = self.fetch16(bus);
            if (op & 8 == 0) bus.write16(address, self.pairValue((op >> 4) & 3)) else {
                const value = @as(u16, bus.readData8(address)) | (@as(u16, bus.readData8(address +% 1)) << 8);
                self.setPair((op >> 4) & 3, value);
            }
        } else if (op & 0xe4 == 0xa0) {
            const decrement = op & 8 != 0;
            const delta: u16 = if (decrement) 0xffff else 1;
            const kind = op & 3;
            var repeat = false;
            switch (kind) {
                0 => {
                    bus.write8(self.registers.de(), bus.readData8(self.registers.hl()));
                    self.registers.setHL(self.registers.hl() +% delta);
                    self.registers.setDE(self.registers.de() +% delta);
                    self.registers.setBC(self.registers.bc() -% 1);
                    self.registers.f = (self.registers.f & (flags.S | flags.Z | flags.C)) | (if (self.registers.bc() != 0) flags.PV else @as(u8, 0));
                    repeat = self.registers.bc() != 0;
                },
                1 => {
                    const compared = flags.sub8(self.registers.a, bus.readData8(self.registers.hl()));
                    self.registers.setHL(self.registers.hl() +% delta);
                    self.registers.setBC(self.registers.bc() -% 1);
                    self.registers.f = (compared.flags & ~@as(u8, flags.C | flags.PV)) | (self.registers.f & flags.C) | (if (self.registers.bc() != 0) flags.PV else @as(u8, 0));
                    repeat = self.registers.bc() != 0 and compared.value != 0;
                },
                2, 3 => {
                    const value = if (kind == 2) bus.input(self.registers.bc()) else bus.readData8(self.registers.hl());
                    self.registers.b -%= 1;
                    if (kind == 2) bus.write8(self.registers.hl(), value) else bus.output(self.registers.bc(), value);
                    self.registers.setHL(self.registers.hl() +% delta);
                    const rhs: u8 = if (kind == 2) self.registers.c +% @as(u8, if (decrement) 0xff else 1) else self.registers.l;
                    const sum = @as(u16, value) + rhs;
                    var f = flags.logic8(.@"or", self.registers.b, 0).flags & (flags.S | flags.Z);
                    if (value & 0x80 != 0) f |= flags.N;
                    if (sum > 255) f |= flags.H | flags.C;
                    if (@popCount(@as(u8, @truncate(sum & 7)) ^ self.registers.b) & 1 == 0) f |= flags.PV;
                    self.registers.f = f;
                    repeat = self.registers.b != 0;
                },
                else => unreachable,
            }
            if (op & 0x10 != 0 and repeat) {
                self.registers.pc -%= 2;
                return definition.taken_t_states;
            }
        } else switch (op) {
            0x44 => {
                const changed = flags.sub8(0, self.registers.a);
                self.registers.a = changed.value;
                self.registers.f = changed.flags;
            },
            0x45, 0x4d => {
                self.registers.pc = self.pop(bus);
                self.iff1 = self.iff2;
            },
            0x46 => self.interrupt_mode = 0,
            0x56 => self.interrupt_mode = 1,
            0x5e => self.interrupt_mode = 2,
            0x47 => self.registers.i = self.registers.a,
            0x4f => self.registers.r = self.registers.a,
            0x57, 0x5f => {
                self.registers.a = if (op == 0x57) self.registers.i else self.registers.r;
                self.registers.f = (self.registers.f & flags.C) | (flags.logic8(.@"or", self.registers.a, 0).flags & ~flags.PV) | (if (self.iff2) flags.PV else @as(u8, 0));
            },
            0x67, 0x6f => {
                const value = bus.readData8(self.registers.hl());
                const low = self.registers.a & 15;
                const changed: u8 = if (op == 0x67) (low << 4) | (value >> 4) else (value << 4) | low;
                self.registers.a = (self.registers.a & 0xf0) | (if (op == 0x67) value & 15 else value >> 4);
                bus.write8(self.registers.hl(), changed);
                self.registers.f = (self.registers.f & flags.C) | flags.logic8(.@"or", self.registers.a, 0).flags;
            },
            else => unreachable,
        }
        return definition.t_states;
    }

    fn pairValue(self: *const Cpu, code: u8) u16 {
        return switch (code) {
            0 => self.registers.bc(),
            1 => self.registers.de(),
            2 => self.registers.hl(),
            else => self.registers.sp,
        };
    }

    fn indexed(self: *Cpu, bus: *Bus, prefix: u8) CpuError!u16 {
        const start = self.registers.pc -% 1;
        const op = bus.readOpcode(self.registers.pc);
        self.registers.pc +%= 1;
        const metadata = @import("extended_metadata.zig");
        const index = if (prefix == 0xdd) &self.registers.ix else &self.registers.iy;
        if (op == 0xcb) {
            const displacement: i8 = @bitCast(self.fetch8(bus));
            const cb_op = self.fetch8(bus); // DD/FD CB final opcode is not M1.
            const definition = metadata.lookupIndexedCb(prefix, cb_op) orelse {
                self.last_unknown_pc = start;
                self.last_unknown_opcode = cb_op;
                self.fault = .{ .pc = start, .prefix = prefix, .opcode = cb_op };
                return error.UnknownOpcode;
            };
            self.incrementR();
            const address = index.* +% @as(u16, @bitCast(@as(i16, displacement)));
            const value = bus.readData8(address);
            const group = cb_op >> 6;
            if (group == 1) self.registers.f = flags.bitTest(@truncate((cb_op >> 3) & 7), value, self.registers.f) else if (group >= 2) {
                const mask = @as(u8, 1) << @as(u3, @truncate((cb_op >> 3) & 7));
                bus.write8(address, if (group == 2) value & ~mask else value | mask);
            } else {
                const operation: instruction.CbOperation = @enumFromInt(cb_op & 0x38);
                const changed = flags.rotateShift(operation, value, self.registers.f);
                bus.write8(address, changed.value);
                self.registers.f = changed.flags;
            }
            return definition.t_states;
        }
        const definition = metadata.lookup(prefix, op) orelse {
            self.last_unknown_pc = start;
            self.last_unknown_opcode = op;
            self.fault = .{ .pc = start, .prefix = prefix, .opcode = op };
            return error.UnknownOpcode;
        };
        self.incrementR();
        switch (op) {
            0x21 => index.* = self.fetch16(bus),
            0x22 => bus.write16(self.fetch16(bus), index.*),
            0x2a => {
                const address = self.fetch16(bus);
                index.* = @as(u16, bus.readData8(address)) | (@as(u16, bus.readData8(address +% 1)) << 8);
            },
            0x23 => index.* +%= 1,
            0x2b => index.* -%= 1,
            0x09, 0x19, 0x29, 0x39 => {
                const rhs = if (op == 0x29) index.* else self.pairValue((op >> 4) & 3);
                const changed = flags.add16HL(index.*, rhs, self.registers.f);
                index.* = changed.value;
                self.registers.f = changed.flags;
            },
            0xe1 => index.* = self.pop(bus),
            0xe5 => self.push(bus, index.*),
            0xe3 => {
                const value = @as(u16, bus.readData8(self.registers.sp)) | (@as(u16, bus.readData8(self.registers.sp +% 1)) << 8);
                bus.write8(self.registers.sp +% 1, @truncate(index.* >> 8));
                bus.write8(self.registers.sp, @truncate(index.*));
                index.* = value;
            },
            0xe9 => self.registers.pc = index.*,
            0xf9 => self.registers.sp = index.*,
            else => {
                const displacement: i8 = @bitCast(self.fetch8(bus));
                const address = index.* +% @as(u16, @bitCast(@as(i16, displacement)));
                switch (op) {
                    0x34, 0x35 => {
                        const value = bus.readData8(address);
                        const changed = if (op == 0x34) flags.inc8(value, self.registers.f) else flags.dec8(value, self.registers.f);
                        bus.write8(address, changed.value);
                        self.registers.f = changed.flags;
                    },
                    0x36 => bus.write8(address, self.fetch8(bus)),
                    0x46, 0x4e, 0x56, 0x5e, 0x66, 0x6e, 0x7e => self.setRegValue((op >> 3) & 7, bus.readData8(address)),
                    0x70...0x75, 0x77 => bus.write8(address, self.regValue(op & 7)),
                    else => {
                        const value = bus.readData8(address);
                        switch (op) {
                            0x86 => _ = self.add(value, 19),
                            0x8e => _ = self.adcValue(value),
                            0x96 => _ = self.sub(value, 19, false),
                            0x9e => {
                                const changed = flags.sbc8(self.registers.a, value, flags.isSet(self.registers.f, flags.C));
                                self.registers.a = changed.value;
                                self.registers.f = changed.flags;
                            },
                            0xbe => _ = self.sub(value, 19, true),
                            0xa6, 0xae, 0xb6 => {
                                const operation: flags.LogicOperation = if (op == 0xa6) .@"and" else if (op == 0xae) .xor else .@"or";
                                const changed = flags.logic8(operation, self.registers.a, value);
                                self.registers.a = changed.value;
                                self.registers.f = changed.flags;
                            },
                            else => unreachable,
                        }
                    },
                }
            },
        }
        return definition.t_states;
    }
    fn setPair(self: *Cpu, code: u8, value: u16) void {
        switch (code) {
            0 => self.registers.setBC(value),
            1 => self.registers.setDE(value),
            2 => self.registers.setHL(value),
            else => self.registers.sp = value,
        }
    }

    fn conditionHolds(self: *const Cpu, code: u8) bool {
        const mask: u8 = switch ((code >> 1) & 3) {
            0 => flags.Z,
            1 => flags.C,
            2 => flags.PV,
            else => flags.S,
        };
        return flags.isSet(self.registers.f, mask) == (code & 1 != 0);
    }

    fn extendedBase(self: *Cpu, bus: *Bus, op: u8) ?u16 {
        const definition = @import("extended_metadata.zig").lookup(0, op) orelse return null;
        if (op & 0xc7 == 0xc4) {
            const target = self.fetch16(bus);
            if (!self.conditionHolds((op >> 3) & 7)) return definition.t_states;
            self.push(bus, self.registers.pc);
            self.registers.pc = target;
            return definition.taken_t_states;
        }
        if (op & 0xc7 == 0xc0) {
            if (!self.conditionHolds((op >> 3) & 7)) return definition.t_states;
            self.registers.pc = self.pop(bus);
            return definition.taken_t_states;
        }
        if (op & 0xc7 == 0xc2) return self.jpConditional(bus, self.conditionHolds((op >> 3) & 7));
        if (op & 0xc7 == 0xc7) {
            self.push(bus, self.registers.pc);
            self.registers.pc = op & 0x38;
            return definition.t_states;
        }
        switch (op) {
            0x02 => bus.write8(self.registers.bc(), self.registers.a),
            0x12 => bus.write8(self.registers.de(), self.registers.a),
            0x0a => self.registers.a = bus.readData8(self.registers.bc()),
            0x1a => self.registers.a = bus.readData8(self.registers.de()),
            0x03 => self.registers.setBC(self.registers.bc() +% 1),
            0x13 => self.registers.setDE(self.registers.de() +% 1),
            0x33 => self.registers.sp +%= 1,
            0x0b => self.registers.setBC(self.registers.bc() -% 1),
            0x1b => self.registers.setDE(self.registers.de() -% 1),
            0x3b => self.registers.sp -%= 1,
            0x86 => return self.add(bus.readData8(self.registers.hl()), 7),
            0x96 => return self.sub(bus.readData8(self.registers.hl()), 7, false),
            0xbe => return self.sub(bus.readData8(self.registers.hl()), 7, true),
            0x30 => return self.jr(bus, !flags.isSet(self.registers.f, flags.C)),
            0x38 => return self.jr(bus, flags.isSet(self.registers.f, flags.C)),
            0xe9 => self.registers.pc = self.registers.hl(),
            0xf9 => self.registers.sp = self.registers.hl(),
            0x08 => {
                const old = self.registers.af();
                self.registers.setAF(self.registers.af_alt);
                self.registers.af_alt = old;
            },
            0xd9 => {
                const bc = self.registers.bc();
                const de = self.registers.de();
                const hl = self.registers.hl();
                self.registers.setBC(self.registers.bc_alt);
                self.registers.setDE(self.registers.de_alt);
                self.registers.setHL(self.registers.hl_alt);
                self.registers.bc_alt = bc;
                self.registers.de_alt = de;
                self.registers.hl_alt = hl;
            },
            0xeb => {
                const old = self.registers.hl();
                self.registers.setHL(self.registers.de());
                self.registers.setDE(old);
            },
            0xe3 => {
                const low = bus.readData8(self.registers.sp);
                const high = bus.readData8(self.registers.sp +% 1);
                bus.write8(self.registers.sp +% 1, self.registers.h);
                bus.write8(self.registers.sp, self.registers.l);
                self.registers.setHL(@as(u16, low) | (@as(u16, high) << 8));
            },
            0x07, 0x0f, 0x17, 0x1f => {
                const operation: instruction.CbOperation = switch (op) {
                    0x07 => .rlc,
                    0x0f => .rrc,
                    0x17 => .rl,
                    else => .rr,
                };
                const changed = flags.rotateShift(operation, self.registers.a, self.registers.f);
                self.registers.a = changed.value;
                self.registers.f = (self.registers.f & (flags.S | flags.Z | flags.PV)) | (changed.flags & flags.C);
            },
            0x27 => {
                const old = self.registers.a;
                const subtract = flags.isSet(self.registers.f, flags.N);
                const carry = flags.isSet(self.registers.f, flags.C) or old > 0x99;
                var correction: u8 = if (flags.isSet(self.registers.f, flags.H) or old & 15 > 9) 6 else 0;
                if (carry) correction |= 0x60;
                self.registers.a = if (subtract) old -% correction else old +% correction;
                self.registers.f = (self.registers.f & flags.N) | (flags.logic8(.@"or", self.registers.a, 0).flags) | (if (carry) flags.C else @as(u8, 0)) | ((old ^ self.registers.a) & flags.H);
            },
            0x2f => {
                self.registers.a = ~self.registers.a;
                self.registers.f |= flags.H | flags.N;
            },
            0x37 => self.registers.f = (self.registers.f & (flags.S | flags.Z | flags.PV)) | flags.C,
            0x3f => self.registers.f = (self.registers.f & (flags.S | flags.Z | flags.PV)) | (if (flags.isSet(self.registers.f, flags.C)) flags.H else flags.C),
            0xf3 => {
                self.iff1 = false;
                self.iff2 = false;
                self.ei_delay = 0;
            },
            0xfb => {
                self.iff1 = true;
                self.iff2 = true;
                self.ei_delay = 2;
            },
            0xdb => {
                const port = (@as(u16, self.registers.a) << 8) | self.fetch8(bus);
                self.registers.a = bus.input(port);
            },
            0xd3 => {
                const port = (@as(u16, self.registers.a) << 8) | self.fetch8(bus);
                bus.output(port, self.registers.a);
            },
            else => unreachable,
        }
        return definition.t_states;
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
    fn incMemory(self: *Cpu, bus: *Bus) u16 {
        const address = self.registers.hl();
        const x = flags.inc8(bus.readData8(address), self.registers.f);
        bus.write8(address, x.value);
        self.registers.f = x.flags;
        return 11;
    }
    fn decMemory(self: *Cpu, bus: *Bus) u16 {
        const address = self.registers.hl();
        const x = flags.dec8(bus.readData8(address), self.registers.f);
        bus.write8(address, x.value);
        self.registers.f = x.flags;
        return 11;
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
    fn setRegValue(self: *Cpu, code: u8, value: u8) void {
        switch (code) {
            0 => self.registers.b = value,
            1 => self.registers.c = value,
            2 => self.registers.d = value,
            3 => self.registers.e = value,
            4 => self.registers.h = value,
            5 => self.registers.l = value,
            7 => self.registers.a = value,
            else => unreachable,
        }
    }
    fn ldRegister(self: *Cpu, bus: *Bus, destination: u8, source: u8) u16 {
        const value = if (source == 6) bus.readData8(self.registers.hl()) else self.regValue(source);
        if (destination == 6) bus.write8(self.registers.hl(), value) else self.setRegValue(destination, value);
        return instruction.ldRegisterTStates(destination, source);
    }
    fn logic(self: *Cpu, bus: *Bus, operation: flags.LogicOperation, source: u8) u16 {
        const value = if (source == 6) bus.readData8(self.registers.hl()) else self.regValue(source);
        const result_value = flags.logic8(operation, self.registers.a, value);
        self.registers.a = result_value.value;
        self.registers.f = result_value.flags;
        return if (source == 6) 7 else 4;
    }
    fn logicImmediate(self: *Cpu, bus: *Bus, operation: flags.LogicOperation) u16 {
        const result_value = flags.logic8(operation, self.registers.a, self.fetch8(bus));
        self.registers.a = result_value.value;
        self.registers.f = result_value.flags;
        return 7;
    }
    fn adc(self: *Cpu, bus: *Bus, source: u8) u16 {
        const value = if (source == 6) bus.readData8(self.registers.hl()) else self.regValue(source);
        const x = flags.adc8(self.registers.a, value, flags.isSet(self.registers.f, flags.C));
        self.registers.a = x.value;
        self.registers.f = x.flags;
        return if (source == 6) 7 else 4;
    }
    fn adcImmediate(self: *Cpu, bus: *Bus) u16 {
        return self.adcValue(self.fetch8(bus));
    }
    fn adcValue(self: *Cpu, value: u8) u16 {
        const x = flags.adc8(self.registers.a, value, flags.isSet(self.registers.f, flags.C));
        self.registers.a = x.value;
        self.registers.f = x.flags;
        return 7;
    }
    fn sbc(self: *Cpu, bus: *Bus, source: u8) u16 {
        const value = if (source == 6) bus.readData8(self.registers.hl()) else self.regValue(source);
        const x = flags.sbc8(self.registers.a, value, flags.isSet(self.registers.f, flags.C));
        self.registers.a = x.value;
        self.registers.f = x.flags;
        return if (source == 6) 7 else 4;
    }
    fn sbcImmediate(self: *Cpu, bus: *Bus) u16 {
        const x = flags.sbc8(self.registers.a, self.fetch8(bus), flags.isSet(self.registers.f, flags.C));
        self.registers.a = x.value;
        self.registers.f = x.flags;
        return 7;
    }
    fn addHL(self: *Cpu, opcode: u8) u16 {
        const rhs = switch (opcode) {
            0x09 => self.registers.bc(),
            0x19 => self.registers.de(),
            0x29 => self.registers.hl(),
            0x39 => self.registers.sp,
            else => unreachable,
        };
        const x = flags.add16HL(self.registers.hl(), rhs, self.registers.f);
        self.registers.setHL(x.value);
        self.registers.f = x.flags;
        return 11;
    }
    fn djnz(self: *Cpu, bus: *Bus) u16 {
        const raw = self.fetch8(bus);
        self.registers.b -%= 1;
        if (self.registers.b == 0) return 8;
        const offset: i8 = @bitCast(raw);
        self.registers.pc +%= @bitCast(@as(i16, offset));
        return 13;
    }
    fn cb(self: *Cpu, bus: *Bus) CpuError!u16 {
        const opcode = bus.readOpcode(self.registers.pc);
        self.registers.pc +%= 1;
        // Reject before reading a data operand or changing architectural state.
        if (opcode >= 0x30 and opcode <= 0x37) {
            self.last_unknown_pc = self.registers.pc -% 2;
            self.last_unknown_opcode = opcode;
            self.fault = .{ .pc = self.last_unknown_pc, .prefix = 0xcb, .opcode = opcode };
            self.registers.pc = self.last_unknown_pc;
            return error.UnknownOpcode;
        }
        self.incrementR();
        const register = opcode & 7;
        const value = if (register == 6) bus.readData8(self.registers.hl()) else self.regValue(register);
        const group = opcode >> 6;
        if (group == 1) {
            self.registers.f = flags.bitTest(@truncate((opcode >> 3) & 7), value, self.registers.f);
            return instruction.cbTStates(.bit, register);
        }
        if (group == 2 or group == 3) {
            const mask = @as(u8, 1) << @truncate((opcode >> 3) & 7);
            const changed = if (group == 2) value & ~mask else value | mask;
            if (register == 6) bus.write8(self.registers.hl(), changed) else self.setRegValue(register, changed);
            return instruction.cbTStates(if (group == 2) .res else .set, register);
        }
        const operation: instruction.CbOperation = switch ((opcode >> 3) & 7) {
            0 => .rlc,
            1 => .rrc,
            2 => .rl,
            3 => .rr,
            4 => .sla,
            5 => .sra,
            7 => .srl,
            else => unreachable,
        };
        const changed = flags.rotateShift(operation, value, self.registers.f);
        if (register == 6) bus.write8(self.registers.hl(), changed.value) else self.setRegValue(register, changed.value);
        self.registers.f = changed.flags;
        return instruction.cbTStates(operation, register);
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
        self.registers.sp -%= 1;
        bus.write8(self.registers.sp, @truncate(v >> 8));
        self.registers.sp -%= 1;
        bus.write8(self.registers.sp, @truncate(v));
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
