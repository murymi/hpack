const std = @import("std");

pub const HeaderField = @This();

name: []const u8 = "",
value: []const u8 = "",
hash: u64 = 0,

pub fn size(self: *const HeaderField) usize {
    return self.name.len + self.value.len + 32;
}

/// for testing only
pub fn eql(self: *const HeaderField, h: HeaderField) bool {
    return std.mem.eql(u8, self.name, h.name) and
        std.mem.eql(u8, self.value, h.value);
}
