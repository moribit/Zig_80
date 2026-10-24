const std = @import("std");
const Registers = @import("../cpu/registers.zig").Registers;
const flags = @import("../cpu/flags.zig");
const trace = @import("../trace/trace.zig");

pub const Compare = enum { equal, not_equal, less, less_equal, greater, greater_equal };
pub const RegisterName = enum { a, f, b, c, d, e, h, l, af, bc, de, hl, pc, sp };
pub const FlagName = enum { s, z, h, pv, n, c };

pub const Condition = union(enum) {
    register: struct { name: RegisterName, compare: Compare = .equal, value: u16 },
    flag: struct { name: FlagName, value: bool },
    value: struct { compare: Compare = .equal, value: u8 },

    pub fn matchesRegisters(self: Condition, registers: Registers) bool {
        return switch (self) {
            .register => |condition| compare16(registerValue(registers, condition.name), condition.compare, condition.value),
            .flag => |condition| flagValue(registers.f, condition.name) == condition.value,
            .value => false,
        };
    }

    pub fn matchesValue(self: Condition, value: u8) bool {
        return switch (self) {
            .value => |condition| compare16(value, condition.compare, condition.value),
            else => true,
        };
    }
};

pub fn parseCondition(lhs: []const u8, operator: []const u8, rhs: []const u8) !Condition {
    const comparison: Compare = if (std.mem.eql(u8, operator, "==")) .equal else if (std.mem.eql(u8, operator, "!=")) .not_equal else if (std.mem.eql(u8, operator, "<")) .less else if (std.mem.eql(u8, operator, "<=")) .less_equal else if (std.mem.eql(u8, operator, ">")) .greater else if (std.mem.eql(u8, operator, ">=")) .greater_equal else return error.InvalidOperator;
    const value = try parseNumber(rhs);
    if (parseFlagName(lhs)) |name| {
        if (comparison != .equal or value > 1) return error.InvalidFlagCondition;
        return .{ .flag = .{ .name = name, .value = value != 0 } };
    }
    const name = parseRegisterName(lhs) orelse return error.InvalidRegister;
    return .{ .register = .{ .name = name, .compare = comparison, .value = value } };
}

pub fn parseValueCondition(operator: []const u8, rhs: []const u8) !Condition {
    const parsed = try parseCondition("A", operator, rhs);
    const register = parsed.register;
    if (register.value > 0xff) return error.ValueOutOfRange;
    return .{ .value = .{ .compare = register.compare, .value = @truncate(register.value) } };
}

pub const Breakpoint = struct {
    address: u16,
    condition: ?Condition = null,
    hit_target: u64 = 1,
    hits: u64 = 0,
    enabled: bool = true,
    temporary: bool = false,
};

pub const BreakpointOptions = struct {
    condition: ?Condition = null,
    hit_target: u64 = 1,
    enabled: bool = true,
    temporary: bool = false,
};

pub const Breakpoints = struct {
    values: [64]Breakpoint = undefined,
    len: usize = 0,

    pub fn add(self: *Breakpoints, address: u16) bool {
        return self.addOptions(address, .{});
    }

    pub fn addOptions(self: *Breakpoints, address: u16, options: BreakpointOptions) bool {
        if (self.find(address) != null or self.len == self.values.len) return false;
        self.values[self.len] = .{ .address = address, .condition = options.condition, .hit_target = @max(1, options.hit_target), .enabled = options.enabled, .temporary = options.temporary };
        self.len += 1;
        return true;
    }

    pub fn remove(self: *Breakpoints, address: u16) bool {
        const index = self.find(address) orelse return false;
        self.removeAt(index);
        return true;
    }

    pub fn contains(self: *const Breakpoints, address: u16) bool {
        const index = self.find(address) orelse return false;
        return self.values[index].enabled;
    }

    pub fn setEnabled(self: *Breakpoints, address: u16, enabled: bool) bool {
        const index = self.find(address) orelse return false;
        self.values[index].enabled = enabled;
        return true;
    }

    pub fn shouldBreak(self: *Breakpoints, address: u16, registers: Registers) bool {
        const index = self.find(address) orelse return false;
        var breakpoint = &self.values[index];
        if (!breakpoint.enabled) return false;
        if (breakpoint.condition) |condition| if (!condition.matchesRegisters(registers)) return false;
        breakpoint.hits +|= 1;
        if (breakpoint.hits < breakpoint.hit_target) return false;
        if (breakpoint.temporary) self.removeAt(index);
        return true;
    }

    fn find(self: *const Breakpoints, address: u16) ?usize {
        for (self.values[0..self.len], 0..) |breakpoint, index| if (breakpoint.address == address) return index;
        return null;
    }

    fn removeAt(self: *Breakpoints, index: usize) void {
        self.values[index] = self.values[self.len - 1];
        self.len -= 1;
    }
};

pub const WatchKind = enum { memory_read, memory_write, io_read, io_write };
pub const Watchpoint = struct {
    kind: WatchKind,
    start: u16,
    end: u16,
    condition: ?Condition = null,
    hits: u64 = 0,
    enabled: bool = true,
};

pub const Watchpoints = struct {
    values: [64]Watchpoint = undefined,
    len: usize = 0,

    pub fn add(self: *Watchpoints, watchpoint: Watchpoint) bool {
        if (self.len == self.values.len or watchpoint.end < watchpoint.start) return false;
        self.values[self.len] = watchpoint;
        self.len += 1;
        return true;
    }

    pub fn remove(self: *Watchpoints, index: usize) bool {
        if (index >= self.len) return false;
        self.values[index] = self.values[self.len - 1];
        self.len -= 1;
        return true;
    }

    pub fn match(self: *Watchpoints, event: trace.BusEvent) ?usize {
        for (self.values[0..self.len], 0..) |*watchpoint, index| {
            if (!watchpoint.enabled or event.address < watchpoint.start or event.address > watchpoint.end) continue;
            const kind_matches = switch (watchpoint.kind) {
                .memory_read => event.kind == .memory_read,
                .memory_write => event.kind == .memory_write,
                .io_read => event.kind == .io_read,
                .io_write => event.kind == .io_write,
            };
            if (!kind_matches) continue;
            if (watchpoint.condition) |condition| if (!condition.matchesValue(event.data)) continue;
            watchpoint.hits +|= 1;
            return index;
        }
        return null;
    }
};

fn compare16(lhs: u16, operation: Compare, rhs: u16) bool {
    return switch (operation) {
        .equal => lhs == rhs,
        .not_equal => lhs != rhs,
        .less => lhs < rhs,
        .less_equal => lhs <= rhs,
        .greater => lhs > rhs,
        .greater_equal => lhs >= rhs,
    };
}

fn registerValue(registers: Registers, name: RegisterName) u16 {
    return switch (name) {
        .a => registers.a,
        .f => registers.f,
        .b => registers.b,
        .c => registers.c,
        .d => registers.d,
        .e => registers.e,
        .h => registers.h,
        .l => registers.l,
        .af => registers.af(),
        .bc => registers.bc(),
        .de => registers.de(),
        .hl => registers.hl(),
        .pc => registers.pc,
        .sp => registers.sp,
    };
}

fn flagValue(value: u8, name: FlagName) bool {
    return flags.isSet(value, switch (name) {
        .s => flags.S,
        .z => flags.Z,
        .h => flags.H,
        .pv => flags.PV,
        .n => flags.N,
        .c => flags.C,
    });
}

fn parseRegisterName(text: []const u8) ?RegisterName {
    inline for (std.enums.values(RegisterName)) |value| if (std.ascii.eqlIgnoreCase(text, @tagName(value))) return value;
    return null;
}

fn parseFlagName(text: []const u8) ?FlagName {
    inline for (std.enums.values(FlagName)) |value| if (std.ascii.eqlIgnoreCase(text, @tagName(value))) return value;
    return null;
}

fn parseNumber(text: []const u8) !u16 {
    return if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) std.fmt.parseInt(u16, text[2..], 16) else std.fmt.parseInt(u16, text, 10);
}
