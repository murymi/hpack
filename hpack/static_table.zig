const std = @import("std");
const HeaderField = @import("header.zig");

pub const size = headers.len;

pub fn StaticTable(HashCtx: type) type {
    return struct {
        table: std.HashMap(HeaderField, usize, HashCtx, 80),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !Self {
            var table = std.HashMap(HeaderField, usize, HashCtx, 80).init(allocator);
            for (headers, 1..) |h, i| {
                try table.put(h, i);
            }
            return Self{ .table = table };
        }

        pub fn deinit(self: *Self) void {
            self.table.deinit();
        }

        pub inline fn getByValue(self: *Self, field: HeaderField) ?usize {
            return self.table.get(field);
        }
    };
}

pub inline fn getByIndex(idx: usize) HeaderField {
    return headers[idx];
}

pub const headers = [_]HeaderField{ .{ .name = ":authority" }, .{ .name = ":method", .value = "GET" }, .{ .name = ":method", .value = "POST" }, .{ .name = ":path", .value = "/" }, .{ .name = ":path", .value = "/index.html" }, .{ .name = ":scheme", .value = "http" }, .{ .name = ":scheme", .value = "https" }, .{ .name = ":status", .value = "200" }, .{ .name = ":status", .value = "204" }, .{ .name = ":status", .value = "206" }, .{ .name = ":status", .value = "304" }, .{ .name = ":status", .value = "400" }, .{ .name = ":status", .value = "404" }, .{ .name = ":status", .value = "500" }, .{ .name = "accept-charset" }, .{ .name = "accept-encoding", .value = "gzip, deflate" }, .{ .name = "accept-language" }, .{ .name = "accept-ranges" }, .{ .name = "accept" }, .{ .name = "access-control-allow-origin" }, .{ .name = "age" }, .{ .name = "allow" }, .{ .name = "authorization" }, .{ .name = "cache-control" }, .{ .name = "content-disposition" }, .{ .name = "content-encoding" }, .{ .name = "content-language" }, .{ .name = "content-length" }, .{ .name = "content-location" }, .{ .name = "content-range" }, .{ .name = "content-type" }, .{ .name = "cookie" }, .{ .name = "date" }, .{ .name = "etag" }, .{ .name = "expect" }, .{ .name = "expires" }, .{ .name = "from" }, .{ .name = "host" }, .{ .name = "if-match" }, .{ .name = "if-modified-since" }, .{ .name = "if-none-match" }, .{ .name = "if-range" }, .{ .name = "if-unmodified-since" }, .{ .name = "last-modified" }, .{ .name = "link" }, .{ .name = "location" }, .{ .name = "max-forwards" }, .{ .name = "proxy-authenticate" }, .{ .name = "proxy-authorization" }, .{ .name = "range" }, .{ .name = "referer" }, .{ .name = "refresh" }, .{ .name = "retry-after" }, .{ .name = "server" }, .{ .name = "set-cookie" }, .{ .name = "strict-transport-security" }, .{ .name = "transfer-encoding" }, .{ .name = "user-agent" }, .{ .name = "vary" }, .{ .name = "via" }, .{ .name = "www-authenticate" } };
