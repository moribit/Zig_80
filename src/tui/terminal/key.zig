pub const KeyCode = union(enum) {
    character: u21,
    enter,
    escape,
    backspace,
    delete,
    tab,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    function: u8,
};

pub const KeyEvent = struct {
    code: KeyCode,
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};
