const std = @import("std");
const Codec = @import("codec.zig");
const stable = @import("static_table.zig");
const dtable = @import("dyn_table.zig");
const Allocator = std.mem.Allocator;
const HeaderField = @import("./header.zig");

pub fn HpackContext(comptime HashFunction: type) type {
    return struct {
        dynamic_table: dtable.DynamicTable(HashCtx(HashFunction)),
        static_table: stable.StaticTable(HashCtx(HashFunction)),
        allocator: Allocator,
        codec: Codec,

        pub fn init(allocator: Allocator, dynamic_table_capacity: usize) !@This() {
            return @This(){ .allocator = allocator, .dynamic_table = dtable.DynamicTable(HashCtx(HashFunction)).init(allocator, dynamic_table_capacity, dynamic_table_capacity), .static_table = try stable.StaticTable(HashCtx(HashFunction)).init(allocator), .codec = Codec.init() };
        }

        pub fn get(self: *@This(), header: HeaderField) ?usize {
            if (self.dynamic_table.getByValue(header)) |h|
                return h;
            if (self.static_table.getByValue(header)) |h|
                return h;
            return null;
        }

        pub fn at(self: *@This(), idx: usize) ?HeaderField {
            if (idx >= stable.size + self.dynamic_table.table.items.len) return null;
            if (idx < stable.size) return stable.getByIndex(idx);
            return self.dynamic_table.table.items[idx - stable.size];
        }

        pub fn deinit(self: *@This()) void {
            self.dynamic_table.deinit();
            self.static_table.deinit();
        }

        pub fn clear(self: *@This()) void {
            self.dynamic_table.clear();
        }

        pub fn HashCtx(HashFunc: type) type {
            return struct {
                pub fn hash(_: @This(), header: HeaderField) u64 {
                    var hashfn = HashFunc.init(0);
                    hashfn.update(header.name);
                    hashfn.update(header.value);
                    return hashfn.final();
                }

                pub fn eql(_: @This(), a: HeaderField, b: HeaderField) bool {
                    var hashfn = HashFunc.init(0);
                    hashfn.update(a.name);
                    hashfn.update(a.value);
                    const ha = hashfn.final();
                    hashfn = HashFunc.init(0);
                    hashfn.update(b.name);
                    hashfn.update(b.value);
                    return ha == hashfn.final();
                }
            };
        }
    };
}

test "resize table" {
    const malloc = std.testing.allocator;
    var ctx = try HpackContext(std.hash.Wyhash).init(malloc, 500);
    defer ctx.deinit();
    try std.testing.expectError(dtable.DynamicTable(HpackContext(std.hash.Wyhash).HashCtx(std.hash.Wyhash)).Error.TooBigResize, ctx.dynamic_table.resize(501));

    try ctx.dynamic_table.resize(50);
    try std.testing.expectEqual(
        50,
        ctx.dynamic_table.max_capacity,
    );
}

test "add large header" {
    const malloc = std.testing.allocator;
    var ctx = try HpackContext(std.hash.Wyhash).init(malloc, 50);
    defer ctx.deinit();

    try ctx.dynamic_table.put(.{ .name = "hello0000", .value = "world0000000000000" });
    try std.testing.expectEqual(
        0,
        ctx.dynamic_table.capacity,
    );
}

test "eviction" {
    const malloc = std.testing.allocator;
    var ctx = try HpackContext(std.hash.Wyhash).init(malloc, 1000);
    defer ctx.deinit();
    try ctx.dynamic_table.resize(60);
    try ctx.dynamic_table.put(.{ .name = "hello0000", .value = "world0000000000000" });
    try std.testing.expectEqualStrings(ctx.dynamic_table.get(0).name, "hello0000");
    try ctx.dynamic_table.put(.{ .name = "hello0001", .value = "world0000000000000" });
    try std.testing.expectEqualStrings(ctx.dynamic_table.get(0).name, "hello0001");

    ctx.dynamic_table.clear();
    try ctx.dynamic_table.resize(0);

    for (0..10) |i| {
        const header = HeaderField{ .name = try malloc.dupe(u8, &std.mem.toBytes(i)), .value = try malloc.dupe(u8, &std.mem.toBytes(i)) };
        try ctx.dynamic_table.resize(header.size() + ctx.dynamic_table.capacity);
        try ctx.dynamic_table.put(header);
        try std.testing.expectEqual((8 + 8 + 32) * (i + 1), ctx.dynamic_table.capacity);
    }

    for (0..10) |i| {
        const a: usize = 0;
        const header = HeaderField{ .name = &std.mem.toBytes(a), .value = &std.mem.toBytes(a) };
        const last_header = ctx.dynamic_table.table.getLast();
        try std.testing.expectEqual(std.mem.bytesToValue(usize, last_header.name), i);
        try ctx.dynamic_table.put(header);
        malloc.free(last_header.name);
        malloc.free(last_header.value);
    }
}
