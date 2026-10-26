//! Test-only functional 8251 and existing Cpu/Bus, not a new emulator.
const std = @import("std");
const assembler = @import("../assembler/assembler.zig");
const wire = @import("loader_protocol.zig");
pub const Harness = struct {
    cpu: @import("../cpu/cpu.zig").Cpu = .{},
    bus: @import("../machine/bus.zig").Bus = .{},
    rx: [8192]u8 = undefined,
    rx_head: usize = 0,
    rx_len: usize = 0,
    tx: [8192]u8 = undefined,
    tx_len: usize = 0,
    controls: [128]u8 = @splat(0),
    control_len: usize = 0,
    mode: u8 = 0,
    command: u8 = 0,
    expects_mode: bool = false,
    port30: u8 = 0,
    cts: bool = true,
    errors: u8 = 0,
    tx_delay: u8 = 0,
    protected_write: bool = false,
    application_entries: usize = 0,

    pub fn assemble(io: std.Io, allocator: std.mem.Allocator, name: []const u8, fast_timeout: bool) !assembler.Result {
        var path: [160]u8 = undefined;
        const file = try std.fmt.bufPrint(&path, "examples/pc8001/loader/{s}.asm", .{name});
        const source = try std.Io.Dir.cwd().readFileAlloc(io, file, allocator, .limited(65536));
        defer allocator.free(source);
        const text = try std.mem.replaceOwned(u8, allocator, source, "POLL_LIMIT equ 0", if (fast_timeout) "POLL_LIMIT equ 16" else "POLL_LIMIT equ 0");
        defer allocator.free(text);
        var failure: assembler.FailureLocation = .{};
        return assembler.assembleSourceFile(io, allocator, file, text, &failure);
    }
    pub fn init(self: *Harness, io: std.Io, allocator: std.mem.Allocator, boot: bool, fast_timeout: bool) !void {
        self.* = .{};
        @memset(&self.bus.memory, 0xa5);
        @memset(self.bus.memory[wire.stage1_address..][0..wire.stage1_size], 0);
        var image = try assemble(io, allocator, if (boot) "stage0" else "stage1", fast_timeout);
        defer image.deinit();
        const address: u16 = if (boot) wire.stage0_address else wire.stage1_address;
        @memcpy(self.bus.memory[address..][0..image.bytes.items.len], image.bytes.items);
        self.bus.port_device = .{ .context = self, .read = read, .write = write };
        self.bus.memory[0xea66] = 0x2a;
        self.bus.write16(0xcf00, 0xbeef);
        self.cpu.registers.pc = address;
        self.cpu.registers.sp = 0xcf00;
        self.cpu.registers.setAF(0x1234);
        self.cpu.registers.setBC(0x5678);
        self.cpu.registers.setDE(0x9abc);
        self.cpu.registers.setHL(0xdef0);
    }
    pub fn feed(self: *Harness, bytes: []const u8) !void {
        if (bytes.len + self.rx_len > self.rx.len) return error.MockRxOverflow;
        for (bytes) |byte| {
            self.rx[(self.rx_head + self.rx_len) % self.rx.len] = byte;
            self.rx_len += 1;
        }
    }
    pub fn steps(self: *Harness, count: usize) !void {
        for (0..count) |_| {
            if (self.cpu.registers.pc == 0xbeef) return;
            if (self.cpu.registers.pc == wire.app_min) {
                if (self.tx_delay != 0) return error.ApplicationEnteredBeforeAckDrained;
                self.application_entries += 1;
            }
            _ = try self.cpu.step(&self.bus);
        }
    }
    pub fn transact(self: *Harness, kind: u8, sequence: u8, payload: []const u8) !wire.Frame {
        var buffer: [wire.max_frame]u8 = undefined;
        return self.exchange(try wire.encode(&buffer, kind, sequence, payload));
    }
    pub fn exchange(self: *Harness, bytes: []const u8) !wire.Frame {
        self.tx_len = 0;
        try self.feed(bytes);
        var parser: wire.Parser = .{};
        var cursor: usize = 0;
        for (0..3_000_000) |_| {
            try self.steps(1);
            while (cursor < self.tx_len) {
                const byte = self.tx[cursor];
                cursor += 1;
                if (try parser.feed(byte)) |frame| {
                    if (frame.kind != 0x82) return frame;
                }
            }
        }
        return error.MockResponseTimeout;
    }
    fn read(context: *anyopaque, port: u16) u8 {
        const self: *Harness = @ptrCast(@alignCast(context));
        if (@as(u8, @truncate(port)) == 0x20) {
            if (self.rx_len == 0 or self.command & 4 == 0) return 0xff;
            const byte = self.rx[self.rx_head];
            self.rx_head = (self.rx_head + 1) % self.rx.len;
            self.rx_len -= 1;
            return byte;
        }
        if (@as(u8, @truncate(port)) != 0x21) return 0xff;
        if (self.tx_delay > 0 and self.cts) self.tx_delay -= 1;
        return self.errors | @as(u8, if (self.cts) 1 else 0) | @as(u8, if (self.tx_delay == 0) 4 else 0) | @as(u8, if (self.rx_len > 0 and self.command & 4 != 0) 2 else 0);
    }
    fn write(context: *anyopaque, port: u16, value: u8) void {
        const self: *Harness = @ptrCast(@alignCast(context));
        switch (@as(u8, @truncate(port))) {
            0x20 => {
                if (self.command & 1 == 0 or !self.cts or self.port30 & 0x30 != 0x20) return;
                if (self.tx_len < self.tx.len) {
                    self.tx[self.tx_len] = value;
                    self.tx_len += 1;
                }
                self.tx_delay = 3;
            },
            0x21 => {
                if (self.control_len < self.controls.len) {
                    self.controls[self.control_len] = value;
                    self.control_len += 1;
                }
                if (self.expects_mode) {
                    self.mode = value;
                    self.expects_mode = false;
                } else if (value & 0x40 != 0) {
                    self.expects_mode = true;
                    self.command = 0;
                } else {
                    self.command = value;
                    if (value & 0x10 != 0) self.errors = 0;
                }
            },
            0x30 => self.port30 = value,
            else => {},
        }
    }
};
