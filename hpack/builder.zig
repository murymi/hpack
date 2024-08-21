const std = @import("std");
const math = std.math;
const testing = std.testing;
const codec = @import("codec.zig");
const HpackContext = @import("tables.zig").HpackContext;
const HeaderField = @import("./header.zig");

pub fn Builder(HashFunction: type) type {
    return struct {
        const Self = @This();
        buf: std.io.FixedBufferStream([]u8),
        ctx: *HpackContext(HashFunction),
        header_list_len: u24 = 0,

        pub fn init(ctx: *HpackContext(HashFunction), buf: []u8) Self {
            return Self{ .buf = std.io.fixedBufferStream(buf), .ctx = ctx };
        }

        pub fn add(self: *Self, header: HeaderField, index: bool, never_index: bool) !void {
            self.header_list_len += @intCast(header.size());
            if (self.ctx.get(header)) |idx| {
                const pos = self.buf.pos;
                try codec.encodeInt(idx, 7, self.buf.writer());
                self.buf.buffer[pos] |= 128;
            } else if (self.ctx.get(.{ .name = header.name, .value = if (std.mem.eql(u8, ":path", header.name)) "/" else "" })) |idx| {
                var pos = self.buf.pos;
                if (never_index) {
                    try codec.encodeInt(idx, 4, self.buf.writer());
                    self.buf.buffer[pos] |= 16;
                } else if (index) {
                    try self.ctx.dynamic_table.put(header);
                    try codec.encodeInt(idx, 6, self.buf.writer());
                    self.buf.buffer[pos] |= 64;
                } else {
                    try codec.encodeInt(idx, 4, self.buf.writer());
                    self.buf.buffer[pos] &= 0xf;
                }
                pos = self.buf.pos;
                try codec.encodeInt(header.value.len, 7, self.buf.writer());
                try self.buf.writer().writeAll(header.value);
                self.buf.buffer[pos] &= 127;
            } else {
                if (never_index) {
                    try self.buf.writer().writeInt(u8, 16, .little);
                } else if (index) {
                    try self.ctx.dynamic_table.put(header);
                    try self.buf.writer().writeInt(u8, 64, .little);
                } else {
                    try self.buf.writer().writeInt(u8, 0, .little);
                }
                var pos = self.buf.pos;
                try codec.encodeInt(header.name.len, 7, self.buf.writer());
                try self.buf.writer().writeAll(header.name);
                self.buf.buffer[pos] &= 127;
                pos = self.buf.pos;
                try codec.encodeInt(header.value.len, 7, self.buf.writer());
                try self.buf.writer().writeAll(header.value);
                self.buf.buffer[pos] &= 127;
            }
        }

        pub fn addCompress(self: *Self, header: HeaderField, index: bool, never_index: bool) !void {
            if (self.ctx.get(header)) |idx| {
                const pos = self.buf.pos;
                try codec.encodeInt(idx, 7, self.buf.writer());
                self.buf.buffer[pos] |= 128;
            } else if (self.ctx.get(.{ .name = header.name, .value = if (std.mem.eql(u8, ":path", header.name)) "/" else "" })) |idx| {
                var pos = self.buf.pos;
                if (never_index) {
                    try codec.encodeInt(idx, 4, self.buf.writer());
                    self.buf.buffer[pos] |= 16;
                } else if (index) {
                    try self.ctx.dynamic_table.put(header);
                    try codec.encodeInt(idx, 6, self.buf.writer());
                    self.buf.buffer[pos] |= 64;
                } else {
                    try codec.encodeInt(idx, 4, self.buf.writer());
                    self.buf.buffer[pos] &= 0xf;
                }
                pos = self.buf.pos;
                try codec.encodeInt(codec.calcEncodedLength(header.value), 7, self.buf.writer());
                _ = try codec.encode(header.value, self.buf.writer());
                self.buf.buffer[pos] |= 128;
            } else {
                if (never_index) {
                    try self.buf.writer().writeInt(u8, 16, .little);
                } else if (index) {
                    try self.ctx.dynamic_table.put(header);
                    try self.buf.writer().writeInt(u8, 64, .little);
                } else {
                    try self.buf.writer().writeInt(u8, 0, .little);
                }
                var pos = self.buf.pos;
                try codec.encodeInt(codec.calcEncodedLength(header.name), 7, self.buf.writer());
                _ = try codec.encode(header.name, self.buf.writer());
                self.buf.buffer[pos] |= 128;
                pos = self.buf.pos;
                try codec.encodeInt(codec.calcEncodedLength(header.value), 7, self.buf.writer());
                _ = try codec.encode(header.value, self.buf.writer());
                self.buf.buffer[pos] |= 128;
            }
        }

        pub fn addDynResize(self: *Self, size: usize) !void {
            const pos = self.buf.pos;
            _ = try codec.encodeInt(size, 5, self.buf.writer());
            self.buf.buffer[pos] |= 32;
        }

        pub fn addSlice(self: *Self, headers: []HeaderField) !void {
            for (headers) |value| try self.add(value, false, false);
        }

        pub fn final(self: *Self) []const u8 {
            return self.buf.buffer[0..self.buf.pos];
        }

        pub fn clear(self: *Self) void {
            self.buf.pos = 0;
        }
    };
}

test "plain" {
    const malloc = std.testing.allocator;
    var ctx = try HpackContext(std.hash.Wyhash).init(malloc, 4096);
    defer ctx.deinit();
    var header_buf = [_]u8{0} ** 4096;
    var b = Builder(std.hash.Wyhash).init(&ctx, header_buf[0..]);
    {
        defer b.clear();
        try b.add(.{ .name = "custom-key", .value = "custom-header" }, true, false);
        try std.testing.expectEqualSlices(u8, &.{ 0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0d, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x68, 0x65, 0x61, 0x64, 0x65, 0x72 }, b.final());
    }
    {
        defer b.clear();
        try b.add(.{ .name = ":path", .value = "/sample/path" }, false, false);
        try std.testing.expectEqualSlices(u8, &.{ 0x04, 0x0c, 0x2f, 0x73, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2f, 0x70, 0x61, 0x74, 0x68 }, b.final());
    }
    {
        defer b.clear();
        try b.add(.{ .name = "password", .value = "secret" }, false, true);
        try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x08, 0x70, 0x61, 0x73, 0x73, 0x77, 0x6f, 0x72, 0x64, 0x06, 0x73, 0x65, 0x63, 0x72, 0x65, 0x74 }, b.final());
    }
    {
        defer b.clear();
        defer ctx.clear();
        try b.add(.{ .name = ":method", .value = "GET" }, false, false);
        try std.testing.expectEqualSlices(u8, &.{0x82}, b.final());
    }
    {
        defer b.clear();
        //defer ctx.clear();
        try b.add(.{ .name = ":method", .value = "GET" }, false, true);
        try b.add(.{ .name = ":scheme", .value = "http" }, false, true);
        try b.add(.{ .name = ":path", .value = "/" }, false, true);
        try b.add(.{ .name = ":authority", .value = "www.example.com" }, true, false);
        try std.testing.expectEqualSlices(u8, &.{ 0x82, 0x86, 0x84, 0x41, 0x0f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d }, b.final());
        try testing.expectEqual(57, ctx.dynamic_table.capacity);
    }
    {
        defer b.clear();
        //defer ctx.clear();
        try b.add(.{ .name = ":method", .value = "GET" }, false, true);
        try b.add(.{ .name = ":scheme", .value = "http" }, false, true);
        try b.add(.{ .name = ":path", .value = "/" }, false, true);
        try b.add(.{ .name = ":authority", .value = "www.example.com" }, true, false);
        try b.add(.{ .name = "cache-control", .value = "no-cache" }, true, false);
        try std.testing.expectEqualSlices(u8, &.{ 0x82, 0x86, 0x84, 0xbe, 0x58, 0x08, 0x6e, 0x6f, 0x2d, 0x63, 0x61, 0x63, 0x68, 0x65 }, b.final());
        try testing.expectEqual(110, ctx.dynamic_table.capacity);
    }
    {
        defer b.clear();
        //defer ctx.clear();
        try b.add(.{ .name = ":method", .value = "GET" }, false, true);
        try b.add(.{ .name = ":scheme", .value = "https" }, false, true);
        try b.add(.{ .name = ":path", .value = "/index.html" }, false, true);
        try b.add(.{ .name = ":authority", .value = "www.example.com" }, true, false);
        try b.add(.{ .name = "custom-key", .value = "custom-value" }, true, false);
        try std.testing.expectEqualSlices(u8, &.{ 0x82, 0x87, 0x85, 0xbf, 0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0c, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x76, 0x61, 0x6c, 0x75, 0x65 }, b.final());
        try testing.expectEqual(164, ctx.dynamic_table.capacity);
    }
}

test "compress" {
    const malloc = std.testing.allocator;
    var ctx = try HpackContext(std.hash.Wyhash).init(malloc, 4096);
    var header_buf = [_]u8{0} ** 4096;
    defer ctx.deinit();
    var b = Builder(std.hash.Wyhash).init(&ctx, header_buf[0..]);
    {
        defer b.clear();
        //defer ctx.clear();
        try b.addCompress(.{ .name = ":method", .value = "GET" }, false, true);
        try b.addCompress(.{ .name = ":scheme", .value = "http" }, false, true);
        try b.addCompress(.{ .name = ":path", .value = "/" }, false, true);
        try b.addCompress(.{ .name = ":authority", .value = "www.example.com" }, true, false);
        try std.testing.expectEqualSlices(u8, &.{ 0x82, 0x86, 0x84, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff }, b.final());
        try testing.expectEqual(57, ctx.dynamic_table.capacity);
    }
    {
        defer b.clear();
        //defer ctx.clear();
        try b.addCompress(.{ .name = ":method", .value = "GET" }, false, true);
        try b.addCompress(.{ .name = ":scheme", .value = "http" }, false, true);
        try b.addCompress(.{ .name = ":path", .value = "/" }, false, true);
        try b.addCompress(.{ .name = ":authority", .value = "www.example.com" }, true, false);
        try b.addCompress(.{ .name = "cache-control", .value = "no-cache" }, true, false);
        try std.testing.expectEqualSlices(u8, &.{ 0x82, 0x86, 0x84, 0xbe, 0x58, 0x86, 0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf }, b.final());
        try testing.expectEqual(110, ctx.dynamic_table.capacity);
    }
    {
        defer b.clear();
        //defer ctx.clear();
        try b.addCompress(.{ .name = ":method", .value = "GET" }, false, true);
        try b.addCompress(.{ .name = ":scheme", .value = "https" }, false, true);
        try b.addCompress(.{ .name = ":path", .value = "/index.html" }, false, true);
        try b.addCompress(.{ .name = ":authority", .value = "www.example.com" }, true, false);
        try b.addCompress(.{ .name = "custom-key", .value = "custom-value" }, true, false);
        try std.testing.expectEqualSlices(u8, &.{ 0x82, 0x87, 0x85, 0xbf, 0x40, 0x88, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xa9, 0x7d, 0x7f, 0x89, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xb8, 0xe8, 0xb4, 0xbf }, b.final());
        try testing.expectEqual(164, ctx.dynamic_table.capacity);
    }
}
