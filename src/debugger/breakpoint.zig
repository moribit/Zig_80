pub const Breakpoints = struct {
    values: [32]u16 = undefined,
    len: usize = 0,
    pub fn add(self: *Breakpoints, address: u16) bool {
        if (self.contains(address) or self.len == self.values.len) return false;
        self.values[self.len] = address;
        self.len += 1;
        return true;
    }
    pub fn remove(self: *Breakpoints, address: u16) bool {
        for (self.values[0..self.len], 0..) |v, i| if (v == address) {
            self.values[i] = self.values[self.len - 1];
            self.len -= 1;
            return true;
        };
        return false;
    }
    pub fn contains(self: *const Breakpoints, address: u16) bool {
        for (self.values[0..self.len]) |v| if (v == address) return true;
        return false;
    }
};
