const Style = @import("style.zig").Style;

pub const Cell = struct {
    codepoint: u21 = ' ',
    style: Style = .{},
};
