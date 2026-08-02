const std = @import("std");
const instruction = @import("../cpu/instruction.zig");

pub const Decoded = struct { address: u16, size: u8, bytes: [3]u8 = .{ 0, 0, 0 }, text: [32]u8 = undefined, text_len: usize = 0 };

pub fn decode(data: []const u8, address: u16) Decoded {
    const i: usize = address;
    const op = data[i];
    var d = Decoded{ .address = address, .size = 1, .bytes = .{ op, 0, 0 } };
    const w = struct {
        fn set(x: *Decoded, comptime fmt: []const u8, args: anytype) void {
            const s = std.fmt.bufPrint(&x.text, fmt, args) catch unreachable;
            x.text_len = s.len;
        }
    }.set;
    switch (op) {
        0x00 => w(&d, "NOP", .{}),
        0x76 => w(&d, "HALT", .{}),
        0xc9 => w(&d, "RET", .{}),
        0x3e, 0x06, 0x0e, 0x16, 0x1e, 0x26, 0x2e => {
            d.size = 2;
            d.bytes[1] = byte(data, i + 1);
            const names = [_][]const u8{ "B", "C", "D", "E", "H", "L", "A" };
            const codes = [_]u8{ 0x06, 0x0e, 0x16, 0x1e, 0x26, 0x2e, 0x3e };
            var name: []const u8 = "?";
            for (codes, names) |code, n| if (op == code) {
                name = n;
                break;
            };
            w(&d, "LD {s},0x{X:0>2}", .{ name, d.bytes[1] });
        },
        0x01, 0x11, 0x21, 0x31 => {
            loadWord(&d, data, i);
            const name: []const u8 = if (op == 0x01) "BC" else if (op == 0x11) "DE" else if (op == 0x21) "HL" else "SP";
            w(&d, "LD {s},0x{X:0>4}", .{ name, word(d) });
        },
        0x40...0x75, 0x77...0x7f => {
            const destination = (op >> 3) & 7;
            const source = op & 7;
            w(&d, "LD {s},{s}", .{ instruction.register8Name(destination), instruction.register8Name(source) });
        },
        0x36 => {
            d.size = 2;
            d.bytes[1] = byte(data, i + 1);
            w(&d, "LD (HL),0x{X:0>2}", .{d.bytes[1]});
        },
        0x3a, 0x32, 0x2a, 0x22 => {
            loadWord(&d, data, i);
            if (op == 0x3a) w(&d, "LD A,(0x{X:0>4})", .{word(d)}) else if (op == 0x32) w(&d, "LD (0x{X:0>4}),A", .{word(d)}) else if (op == 0x2a) w(&d, "LD HL,(0x{X:0>4})", .{word(d)}) else w(&d, "LD (0x{X:0>4}),HL", .{word(d)});
        },
        0xc3, 0xc2, 0xca, 0xcd => {
            loadWord(&d, data, i);
            const name: []const u8 = if (op == 0xc3) "JP" else if (op == 0xc2) "JP NZ," else if (op == 0xca) "JP Z," else "CALL";
            w(&d, "{s} 0x{X:0>4}", .{ name, word(d) });
        },
        0x18, 0x20, 0x28 => {
            d.size = 2;
            d.bytes[1] = byte(data, i + 1);
            const off: i8 = @bitCast(d.bytes[1]);
            const target: u16 = address +% 2 +% @as(u16, @bitCast(@as(i16, off)));
            const name: []const u8 = if (op == 0x18) "JR" else if (op == 0x20) "JR NZ," else "JR Z,";
            w(&d, "{s} 0x{X:0>4}", .{ name, target });
        },
        0xc6, 0xd6, 0xfe => {
            d.size = 2;
            d.bytes[1] = byte(data, i + 1);
            const name: []const u8 = if (op == 0xc6) "ADD A," else if (op == 0xd6) "SUB" else "CP";
            w(&d, "{s} 0x{X:0>2}", .{ name, d.bytes[1] });
        },
        0x80...0x85, 0x87, 0x90...0x95, 0x97, 0xb8...0xbd, 0xbf => {
            const regs = [_][]const u8{ "B", "C", "D", "E", "H", "L", "?", "A" };
            const name: []const u8 = if (op < 0x90) "ADD A," else if (op < 0xb8) "SUB" else "CP";
            w(&d, "{s} {s}", .{ name, regs[op & 7] });
        },
        0xa0...0xb7 => {
            const decoded = instruction.logicByOpcode(op).?;
            w(&d, "{s} {s}", .{ decoded.family.mnemonic, instruction.register8Name(decoded.register_code.?) });
        },
        0xe6, 0xee, 0xf6 => {
            d.size = 2;
            d.bytes[1] = byte(data, i + 1);
            const decoded = instruction.logicByOpcode(op).?;
            w(&d, "{s} 0x{X:0>2}", .{ decoded.family.mnemonic, d.bytes[1] });
        },
        0x3c, 0x04, 0x0c, 0x14, 0x1c, 0x24, 0x2c, 0x23, 0x3d, 0x05, 0x0d, 0x15, 0x1d, 0x25, 0x2d, 0x2b => {
            const is_inc = op == 0x3c or op == 0x04 or op == 0x0c or op == 0x14 or op == 0x1c or op == 0x24 or op == 0x2c or op == 0x23;
            const reg: []const u8 = switch (op) {
                0x3c, 0x3d => "A",
                0x04, 0x05 => "B",
                0x0c, 0x0d => "C",
                0x14, 0x15 => "D",
                0x1c, 0x1d => "E",
                0x24, 0x25 => "H",
                0x2c, 0x2d => "L",
                else => "HL",
            };
            w(&d, "{s} {s}", .{ if (is_inc) "INC" else "DEC", reg });
        },
        0xf5, 0xc5, 0xd5, 0xe5, 0xf1, 0xc1, 0xd1, 0xe1 => {
            const push = op & 0x0f == 5;
            const reg: []const u8 = switch (op & 0xf0) {
                0xf0 => "AF",
                0xc0 => "BC",
                0xd0 => "DE",
                else => "HL",
            };
            w(&d, "{s} {s}", .{ if (push) "PUSH" else "POP", reg });
        },
        else => w(&d, "DB 0x{X:0>2}", .{op}),
    }
    return d;
}

fn byte(data: []const u8, i: usize) u8 {
    return if (i < data.len) data[i] else 0;
}
fn loadWord(d: *Decoded, data: []const u8, i: usize) void {
    d.size = 3;
    d.bytes[1] = byte(data, i + 1);
    d.bytes[2] = byte(data, i + 2);
}
fn word(d: Decoded) u16 {
    return @as(u16, d.bytes[1]) | (@as(u16, d.bytes[2]) << 8);
}
pub fn text(d: *const Decoded) []const u8 {
    return d.text[0..d.text_len];
}
