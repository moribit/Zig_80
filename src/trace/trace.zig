pub const BusEventKind = enum {
    opcode_fetch,
    operand_read,
    memory_read,
    memory_write,
    io_read,
    io_write,
    refresh,
    interrupt_ack,
};

pub const BusSignals = packed struct {
    m1: bool = false,
    mreq: bool = false,
    iorq: bool = false,
    rd: bool = false,
    wr: bool = false,
    rfsh: bool = false,
    halt: bool = false,
    wait: bool = false,
    int: bool = false,
    nmi: bool = false,
};

pub const BusEvent = struct {
    sequence: u64,
    instruction_index: u64,
    t_state_start: u64,
    /// Zero means that this access is logically modeled, not cycle-accurate.
    t_state_count: u16 = 0,
    kind: BusEventKind,
    address: u16,
    data: u8,
    signals: BusSignals,
    pc: u16,
};

pub const TraceSink = struct {
    context: *anyopaque,
    record_fn: *const fn (context: *anyopaque, event: BusEvent) void,

    pub fn record(self: TraceSink, event: BusEvent) void {
        self.record_fn(self.context, event);
    }
};

pub fn RingBuffer(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        events: [capacity]BusEvent = undefined,
        start: usize = 0,
        len: usize = 0,

        pub fn clear(self: *Self) void {
            self.start = 0;
            self.len = 0;
        }

        pub fn record(self: *Self, event: BusEvent) void {
            if (capacity == 0) return;
            const index = (self.start + self.len) % capacity;
            self.events[index] = event;
            if (self.len < capacity) {
                self.len += 1;
            } else {
                self.start = (self.start + 1) % capacity;
            }
        }

        pub fn get(self: *const Self, index: usize) ?BusEvent {
            if (index >= self.len or capacity == 0) return null;
            return self.events[(self.start + index) % capacity];
        }

        pub fn latest(self: *const Self) ?BusEvent {
            if (self.len == 0) return null;
            return self.get(self.len - 1);
        }

        pub fn sink(self: *Self) TraceSink {
            return .{ .context = self, .record_fn = sinkRecord };
        }

        fn sinkRecord(context: *anyopaque, event: BusEvent) void {
            const self: *Self = @ptrCast(@alignCast(context));
            self.record(event);
        }
    };
}

pub const TraceBuffer = RingBuffer(4096);

pub fn kindName(kind: BusEventKind) []const u8 {
    return switch (kind) {
        .opcode_fetch => "Opcode Fetch",
        .operand_read => "Operand Read",
        .memory_read => "Memory Read",
        .memory_write => "Memory Write",
        .io_read => "I/O Read",
        .io_write => "I/O Write",
        .refresh => "Refresh",
        .interrupt_ack => "Interrupt Ack",
    };
}
