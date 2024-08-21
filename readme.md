### HPACK Protocal in Ziglang
 - passing all tests in <a href="https://datatracker.ietf.org/doc/html/rfc7541">RFC7541</a>
 - zig 0.13

```zig
test {
    const allocator = std.testing.allocator;
    var ctx = try hpack.HpackContext(std.hash.Wyhash).init(allocator, 256);
    var heap = [_]u8{0} ** 4096;
    var parser = hpack.Parser(std.hash.Wyhash).init(&ctx, heap[0..]);
    var headers = [_]HeaderField{.{}} ** 4;

    const expected = [_]HeaderField{ 
        .{ .name = ":status", .value = "302" },
        .{ .name = "cache-control", .value = "private" },
        .{ .name = "date", .value = "Mon, 21 Oct 2013 20:13:21 GMT" },
        .{ .name = "location", .value = "https://www.example.com" }
    };

    const out = try p.parse(&.{ 
        0x48, 0x82, 0x64, 0x02, 0x58, 0x85, 0xae,
        0xc3, 0x77, 0x1a, 0x4b, 0x61, 0x96, 0xd0, 
        0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44,
        0xa8, 0x20, 0x05, 0x95, 0x04, 0x0b, 0x81,
        0x66, 0xe0, 0x82, 0xa6, 0x2d, 0x1b, 0xff,
        0x6e, 0x91, 0x9d, 0x29, 0xad, 0x17, 0x18,
        0x63, 0xc7, 0x8f, 0x0b, 0x97, 0xc8, 0xe9,
        0xae, 0x82, 0xae, 0x43, 0xd3 
    }, headers[0..]);

    for (out, expected) |a, b| try tst.expect(a.eql(b));
    try testing.expectEqual(222, ctx.dynamic_table.capacity);
}
```