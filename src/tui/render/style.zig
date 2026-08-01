pub const Color = enum(u8) { default = 9, black = 0, red, green, yellow, blue, magenta, cyan, white };

pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    bold: bool = false,
    reverse: bool = false,
};
