const std = @import("std");
const static = @import("static_table.zig");
const List = std.ArrayList(HeaderField);
const HeaderField = @import("./header.zig");

pub fn DynamicTable(HashContext: type) type {
    return struct {
        settings_capacity: usize = 4096,
        capacity: usize = 0,
        max_capacity: usize,
        table: List,
        hash_ctx: HashContext,

        const Self = @This();

        pub const Error = error{TooBigResize};

        pub fn init(allocator: std.mem.Allocator, settings_capacity: usize, max_capacity: usize) Self {
            return Self{ .max_capacity = max_capacity, .table = List.init(allocator), .settings_capacity = settings_capacity, .hash_ctx = HashContext{} };
        }

        pub fn deinit(self: *Self) void {
            self.table.deinit();
        }

        pub fn put(self: *Self, header: HeaderField) !void {
            const header_size = header.size();
            var gap = self.max_capacity - self.capacity;
            if (header_size > self.max_capacity) {
                self.capacity = 0;
                return self.table.clearRetainingCapacity();
            } else if (header_size > gap) {
                while (header_size > gap) {
                    const s = self.pop().size();
                    gap += s;
                }
            }
            var h = header;
            h.hash = self.hash_ctx.hash(h);
            try self.table.insert(0, h);
            self.capacity += header_size;
        }

        pub fn get(self: *Self, idx: usize) HeaderField {
            return self.table.items[idx];
        }

        pub fn pop(self: *Self) HeaderField {
            var s = self.table.pop();
            self.capacity -= s.size();
            return s;
        }

        pub fn getByValue(self: *Self, field: HeaderField) ?usize {
            const hash = self.hash_ctx.hash(field);
            for (self.table.items, static.size + 1..) |h, i| {
                if (hash == h.hash)
                    return i;
            }
            return null;
        }

        pub fn resize(self: *Self, new_size: u64) Error!void {
            if (new_size > self.settings_capacity) return error.TooBigResize;
            self.max_capacity = new_size;
            while (self.capacity > self.max_capacity) self.max_capacity -= self.pop().size();
        }

        pub fn clear(self: *Self) void {
            self.capacity = 0;
            self.table.clearAndFree();
        }
    };
}
