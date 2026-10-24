const trace = @import("../trace/trace.zig");

pub const PortDevice = struct {
    context: *anyopaque,
    read: *const fn (*anyopaque, u16) u8,
    write: *const fn (*anyopaque, u16, u8) void,
};

pub const Bus = struct {
    memory: [65536]u8 = @splat(0),
    port_device: ?PortDevice = null,
    trace_sink: ?trace.TraceSink = null,
    debug_trace_sink: ?trace.TraceSink = null,
    trace_sequence: u64 = 0,
    instruction_index: u64 = 0,
    instruction_t_state: u64 = 0,
    instruction_pc: u16 = 0,
    event_index_in_instruction: u8 = 0,

    pub fn beginInstruction(self: *Bus, index: u64, t_state: u64, pc: u16) void {
        self.instruction_index = index;
        self.instruction_t_state = t_state;
        self.instruction_pc = pc;
        self.event_index_in_instruction = 0;
    }

    pub fn readOpcode(self: *Bus, address: u16) u8 {
        const value = self.memory[address];
        self.record(.opcode_fetch, address, value, .{ .m1 = true, .mreq = true, .rd = true });
        return value;
    }

    pub fn readOperand8(self: *Bus, address: u16) u8 {
        const value = self.memory[address];
        self.record(.operand_read, address, value, .{ .mreq = true, .rd = true });
        return value;
    }

    pub fn readOperand16(self: *Bus, address: u16) u16 {
        return @as(u16, self.readOperand8(address)) | (@as(u16, self.readOperand8(address +% 1)) << 8);
    }

    pub fn read8(self: *const Bus, address: u16) u8 {
        // Read-only callers are inspection APIs and intentionally do not trace.
        return self.memory[address];
    }
    pub fn readData8(self: *Bus, address: u16) u8 {
        const value = self.memory[address];
        self.record(.memory_read, address, value, .{ .mreq = true, .rd = true });
        return value;
    }
    pub fn write8(self: *Bus, address: u16, value: u8) void {
        self.memory[address] = value;
        self.record(.memory_write, address, value, .{ .mreq = true, .wr = true });
    }
    pub fn read16(self: *const Bus, address: u16) u16 {
        const next = address +% 1;
        return @as(u16, self.read8(address)) | (@as(u16, self.read8(next)) << 8);
    }
    pub fn write16(self: *Bus, address: u16, value: u16) void {
        self.write8(address, @truncate(value));
        self.write8(address +% 1, @truncate(value >> 8));
    }
    pub fn input(self: *Bus, port: u16) u8 {
        const value = if (self.port_device) |device| device.read(device.context, port) else 0xff;
        self.record(.io_read, port, value, .{ .iorq = true, .rd = true });
        return value;
    }
    pub fn output(self: *Bus, port: u16, value: u8) void {
        if (self.port_device) |device| device.write(device.context, port, value);
        self.record(.io_write, port, value, .{ .iorq = true, .wr = true });
    }
    pub fn acknowledgeInterrupt(self: *Bus, value: u8) void {
        self.record(.interrupt_ack, 0, value, .{ .m1 = true, .iorq = true, .int = true });
    }

    fn record(self: *Bus, kind: trace.BusEventKind, address: u16, data: u8, signals: trace.BusSignals) void {
        const event: trace.BusEvent = .{
            .sequence = self.trace_sequence,
            .instruction_index = self.instruction_index,
            .event_index_in_instruction = self.event_index_in_instruction,
            .t_state_start = self.instruction_t_state,
            .kind = kind,
            .address = address,
            .data = data,
            .signals = signals,
            .pc = self.instruction_pc,
        };
        if (self.trace_sink) |sink| sink.record(event);
        if (self.debug_trace_sink) |sink| sink.record(event);
        if (self.trace_sink == null and self.debug_trace_sink == null) return;
        self.trace_sequence +%= 1;
        self.event_index_in_instruction +|= 1;
    }
};
