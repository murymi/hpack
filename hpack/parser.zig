const std = @import("std");
const codec = @import("codec.zig");
const dtable = @import("dyn_table.zig");
const HpackContext = @import("tables.zig").HpackContext;
const builder = @import("builder.zig");
const Builder = builder.Builder;
const HeaderField = @import("./header.zig");

pub fn Parser(HashFunction: type) type {
    return struct {
        heap: std.io.FixedBufferStream([]u8),
        heapidx: usize = 0,
        ctx: *HpackContext(HashFunction),

        pub fn init(ctx: *HpackContext(HashFunction), heap: []u8) @This() {
            return @This(){ .heap = std.io.fixedBufferStream(heap), .ctx = ctx };
        }

        const Self = @This();

        pub const Error = error{ HeaderIndexOutOfBounds, NoSpaceLeft, OutOfMemory, DecompressionFailed } || codec.Error || dtable.DynamicTable(HpackContext(HashFunction).HashCtx(HashFunction)).Error;

        pub fn parse(self: *Self, in: []const u8, output: []HeaderField) Error![]HeaderField {
            var input = in;
            var outidx: usize = 0;
            var header: HeaderField = .{};
            while (input.len > 0) {
                var step: bool = true;
                if (input[0] & 128 == 128) {
                    //6.1. Indexed Header Field Representation
                    const idx = try decodeInt(&input, 7);
                    if (self.ctx.at(idx - 1)) |h|
                        header = h
                    else
                        return error.HeaderIndexOutOfBounds;
                } else if (input[0] & 64 == 64) {
                    //6.2.1. Literal Header Field with Incremental Indexing
                    const idx = try decodeInt(&input, 6);
                    if (idx > 0) {
                        if (self.ctx.at(idx - 1)) |h|
                            header = h
                        else
                            return error.HeaderIndexOutOfBounds;
                    } else header.name = try self.decodeString(&input);
                    header.value = try self.decodeString(&input);
                    try self.ctx.dynamic_table.put(header);
                } else if (input[0] & 32 == 32) {
                    step = false;
                    //6.3. Dynamic Table Size Update
                    const new_size = try decodeInt(&input, 5);
                    try self.ctx.dynamic_table.resize(new_size);
                } else if (input[0] & 16 == 16) {
                    //6.2.3. Literal Header Field Never Indexed
                    const idx = try decodeInt(&input, 4);
                    if (idx > 0) {
                        if (self.ctx.at(idx - 1)) |h|
                            header = h
                        else
                            return error.HeaderIndexOutOfBounds;
                    } else header.name = try self.decodeString(&input);

                    header.value = try self.decodeString(&input);
                } else if (input[0] & 240 == 0) {
                    //6.2.2. Literal Header Field without Indexing
                    const idx = try decodeInt(&input, 4);
                    if (idx > 0) {
                        if (self.ctx.at(idx - 1)) |h|
                            header = h
                        else
                            return error.HeaderIndexOutOfBounds;
                    } else header.name = try self.decodeString(&input);
                    header.value = try self.decodeString(&input);
                }
                //std.debug.print("{s} -> {s}\n", .{output[outidx].name, output[outidx].value});
                if (step and outidx < output.len) {
                    output[outidx] = header;
                    outidx += 1;
                }
            }
            return output[0..outidx];
        }

        fn decodeString(self: *@This(), input: *[]const u8) ![]const u8 {
            const compressed = input.*[0] & 128 == 128;
            const result = try codec.decodeInt(input.*, 7);
            if (result.value > input.len) return error.DecompressionFailed;
            input.* = input.*[result.size..];
            const pos = self.heap.pos;
            if (compressed)
                _ = try self.ctx.codec.decode(input.*[0..result.value], self.heap.writer())
            else
                try self.heap.writer().writeAll(input.*[0..result.value]);
            input.* = input.*[result.value..];
            return self.heap.buffer[pos..self.heap.pos];
        }

        fn decodeInt(input: *[]const u8, n: u4) !u64 {
            const res = try codec.decodeInt(input.*, n);
            input.* = input.*[res.size..];
            return res.value;
        }
    };
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const tst = std.testing;

test "plain" {
    const malloc = gpa.allocator();
    var heap = [_]u8{0} ** 4096;

    var ctx = try HpackContext(std.hash.Wyhash).init(malloc, 256);
    var p = Parser(std.hash.Wyhash).init(&ctx, heap[0..]);

    var headers = [_]HeaderField{.{}} ** 50;
    {
        const expected = [_]HeaderField{ .{ .name = ":status", .value = "302" }, .{ .name = "cache-control", .value = "private" }, .{ .name = "date", .value = "Mon, 21 Oct 2013 20:13:21 GMT" }, .{ .name = "location", .value = "https://www.example.com" } };

        const out = try p.parse(&.{
            0x48, 0x03, 0x33, 0x30, 0x32, 0x58, 0x07, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x61, 0x1d,
            0x4d, 0x6f, 0x6e, 0x2c, 0x20, 0x32, 0x31, 0x20, 0x4f, 0x63, 0x74, 0x20, 0x32, 0x30, 0x31, 0x33,
            0x20, 0x32, 0x30, 0x3a, 0x31, 0x33, 0x3a, 0x32, 0x31, 0x20, 0x47, 0x4d, 0x54, 0x6e, 0x17, 0x68,
            0x74, 0x74, 0x70, 0x73, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70,
            0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d,
        }, headers[0..]);

        for (out, expected) |a, b| try tst.expect(a.eql(b));
        try tst.expectEqual(222, ctx.dynamic_table.capacity);
    }
    {
        const expected = [_]HeaderField{ .{ .name = ":status", .value = "307" }, .{ .name = "cache-control", .value = "private" }, .{ .name = "date", .value = "Mon, 21 Oct 2013 20:13:21 GMT" }, .{ .name = "location", .value = "https://www.example.com" } };

        const out = try p.parse(&.{ 0x48, 0x03, 0x33, 0x30, 0x37, 0xc1, 0xc0, 0xbf }, headers[0..]);

        for (out, expected) |a, b| try tst.expect(a.eql(b));
        try tst.expectEqual(222, ctx.dynamic_table.capacity);
    }
    {
        const expected = [_]HeaderField{ .{ .name = ":status", .value = "200" }, .{ .name = "cache-control", .value = "private" }, .{ .name = "date", .value = "Mon, 21 Oct 2013 20:13:22 GMT" }, .{ .name = "location", .value = "https://www.example.com" }, .{ .name = "content-encoding", .value = "gzip" }, .{ .name = "set-cookie", .value = "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1" } };
        const out = try p.parse(&.{ 0x88, 0xc1, 0x61, 0x1d, 0x4d, 0x6f, 0x6e, 0x2c, 0x20, 0x32, 0x31, 0x20, 0x4f, 0x63, 0x74, 0x20, 0x32, 0x30, 0x31, 0x33, 0x20, 0x32, 0x30, 0x3a, 0x31, 0x33, 0x3a, 0x32, 0x32, 0x20, 0x47, 0x4d, 0x54, 0xc0, 0x5a, 0x04, 0x67, 0x7a, 0x69, 0x70, 0x77, 0x38, 0x66, 0x6f, 0x6f, 0x3d, 0x41, 0x53, 0x44, 0x4a, 0x4b, 0x48, 0x51, 0x4b, 0x42, 0x5a, 0x58, 0x4f, 0x51, 0x57, 0x45, 0x4f, 0x50, 0x49, 0x55, 0x41, 0x58, 0x51, 0x57, 0x45, 0x4f, 0x49, 0x55, 0x3b, 0x20, 0x6d, 0x61, 0x78, 0x2d, 0x61, 0x67, 0x65, 0x3d, 0x33, 0x36, 0x30, 0x30, 0x3b, 0x20, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6f, 0x6e, 0x3d, 0x31 }, headers[0..]);
        for (out, expected) |a, b| try tst.expect(a.eql(b));
        try tst.expectEqual(215, ctx.dynamic_table.capacity);
    }
}

test "compress" {
    const malloc = gpa.allocator();
    var heap = [_]u8{0} ** 4096;
    var ctx = try HpackContext(std.hash.Wyhash).init(malloc, 256);
    var p = Parser(std.hash.Wyhash).init(&ctx, heap[0..]);
    var headers = [_]HeaderField{.{}} ** 10;

    {
        const expected = [_]HeaderField{ .{ .name = ":status", .value = "302" }, .{ .name = "cache-control", .value = "private" }, .{ .name = "date", .value = "Mon, 21 Oct 2013 20:13:21 GMT" }, .{ .name = "location", .value = "https://www.example.com" } };

        const out = try p.parse(&.{ 0x48, 0x82, 0x64, 0x02, 0x58, 0x85, 0xae, 0xc3, 0x77, 0x1a, 0x4b, 0x61, 0x96, 0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04, 0x0b, 0x81, 0x66, 0xe0, 0x82, 0xa6, 0x2d, 0x1b, 0xff, 0x6e, 0x91, 0x9d, 0x29, 0xad, 0x17, 0x18, 0x63, 0xc7, 0x8f, 0x0b, 0x97, 0xc8, 0xe9, 0xae, 0x82, 0xae, 0x43, 0xd3 }, headers[0..]);

        for (out, expected) |a, b| try tst.expect(a.eql(b));
        try tst.expectEqual(222, ctx.dynamic_table.capacity);
    }

    {
        const expected = [_]HeaderField{ .{ .name = ":status", .value = "307" }, .{ .name = "cache-control", .value = "private" }, .{ .name = "date", .value = "Mon, 21 Oct 2013 20:13:21 GMT" }, .{ .name = "location", .value = "https://www.example.com" } };
        const out = try p.parse(&.{ 0x48, 0x83, 0x64, 0x0e, 0xff, 0xc1, 0xc0, 0xbf }, headers[0..]);
        for (out, expected) |a, b| try tst.expect(a.eql(b));
        try tst.expectEqual(222, ctx.dynamic_table.capacity);
    }

    {
        const expected = [_]HeaderField{ .{ .name = ":status", .value = "200" }, .{ .name = "cache-control", .value = "private" }, .{ .name = "date", .value = "Mon, 21 Oct 2013 20:13:22 GMT" }, .{ .name = "location", .value = "https://www.example.com" }, .{ .name = "content-encoding", .value = "gzip" }, .{ .name = "set-cookie", .value = "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1" } };
        const out = try p.parse(&.{ 0x88, 0xc1, 0x61, 0x96, 0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04, 0x0b, 0x81, 0x66, 0xe0, 0x84, 0xa6, 0x2d, 0x1b, 0xff, 0xc0, 0x5a, 0x83, 0x9b, 0xd9, 0xab, 0x77, 0xad, 0x94, 0xe7, 0x82, 0x1d, 0xd7, 0xf2, 0xe6, 0xc7, 0xb3, 0x35, 0xdf, 0xdf, 0xcd, 0x5b, 0x39, 0x60, 0xd5, 0xaf, 0x27, 0x08, 0x7f, 0x36, 0x72, 0xc1, 0xab, 0x27, 0x0f, 0xb5, 0x29, 0x1f, 0x95, 0x87, 0x31, 0x60, 0x65, 0xc0, 0x03, 0xed, 0x4e, 0xe5, 0xb1, 0x06, 0x3d, 0x50, 0x07 }, headers[0..]);
        for (out, expected) |a, b| try tst.expect(a.eql(b));
        try tst.expectEqual(215, ctx.dynamic_table.capacity);
    }

    {
        const expected = [_]HeaderField{.{ .name = "password", .value = "secret" }};
        const out = try p.parse(&.{ 0x10, 0x08, 0x70, 0x61, 0x73, 0x73, 0x77, 0x6f, 0x72, 0x64, 0x06, 0x73, 0x65, 0x63, 0x72, 0x65, 0x74 }, headers[0..]);
        for (out, expected) |a, b| try tst.expect(a.eql(b));
    }
}

test "table resize" {
    const malloc = gpa.allocator();
    var ctx = try HpackContext(std.hash.Wyhash).init(malloc, 4096);
    var heap = [_]u8{0} ** 4096;
    var buildbuf = [_]u8{0} ** 4096;
    var p = Parser(std.hash.Wyhash).init(&ctx, heap[0..]);
    var b = Builder(std.hash.Wyhash).init(&ctx, buildbuf[0..]);
    try b.addDynResize(4096);
    try b.addDynResize(405);
    try b.addDynResize(789);
    try b.addDynResize(45);
    try b.addDynResize(678);
    var headers = [_]HeaderField{.{}} ** 50;

    {
        const out = try p.parse(b.final(), headers[0..]);
        try tst.expectEqual(out.len, 0);
        try tst.expectEqual(678, ctx.dynamic_table.max_capacity);
    }
}
