const codes = @import("codes.zig");
const std = @import("std");
const math = std.math;

const hcodes = codes.huffman_codes;
const lens = codes.huffman_code_lengths;

const Self = @This();

pub const Error = error{ FailedToDecodeInteger, FailedToDecode, EosDecoded, InvalidPadding, InvalidPrefixSize };

tree: *Node = undefined,
treeHeap: [256 * @sizeOf(Node)]Node = [1]Node{.{}} ** (256 * @sizeOf(Node)),
heap_idx: usize = 0,

pub fn init() Self {
    var self = Self{};
    self.tree = self.makeNode();
    for (hcodes, lens, 0..) |code, len, sym|
        try self.tree.insert(&self, code, @truncate(sym), @intCast(len));
    return self;
}

inline fn makeNode(self: *Self) *Node {
    self.treeHeap[self.heap_idx] = .{};
    self.heap_idx += 1;
    return &self.treeHeap[self.heap_idx - 1];
}

pub fn encode(source: []const u8, buf: anytype) !usize {
    var byteoffset: u8 = 0;
    var acc: u32 = 0;
    var idx: usize = 0;
    for (source) |value| {
        const codeseq = codes.huffman_codes[value];
        const codelen = codes.huffman_code_lengths[value];
        const rem: u8 = @intCast(32 - byteoffset);
        idx += codelen;
        if (rem == 0) {
            try buf.writeInt(u32, acc, .big);
        } else if (rem == codelen) {
            acc <<= @intCast(codelen);
            acc |= codeseq;
            try buf.writeInt(u32, acc, .big);
            byteoffset = 0;
            acc = 0;
        } else if (rem > codelen) {
            acc <<= @intCast(codelen);
            acc |= codeseq;
            byteoffset += codelen;
        } else if (rem < codelen) {
            acc <<= @intCast(rem);
            acc |= (codeseq >> @intCast(codelen - rem));
            try buf.writeInt(u32, acc, .big);
            acc = codeseq & (math.pow(u32, 2, codelen - rem) - 1);
            byteoffset = codelen - rem;
        }
    }
    if (byteoffset != 0) {
        const f: u32 = 0xffffffff;
        acc <<= @intCast(32 - byteoffset);
        acc = (f >> @intCast(byteoffset)) | acc;
        const bytes = std.mem.asBytes(&acc);
        const k = std.mem.alignForward(u64, byteoffset, 8) / 8;
        var n: usize = 4;
        for (0..k) |_| {
            try buf.writeInt(u8, bytes[n - 1], .big);
            n -= 1;
        }
    }
    return std.mem.alignForward(u64, idx, 8) / 8;
}

const Node = struct {
    symbol: u16 = 0,
    bits: u8 = 0,
    left: ?*Node = null,
    right: ?*Node = null,

    fn isLeaf(self: *Node) bool {
        return self.left == null and self.left == null;
    }

    fn insert(self: *Node, codec: *Self, c: u32, symbol: u16, len: u8) !void {
        var code = c << @intCast(32 - len);
        const mask: u32 = 0x80000000;
        var current = self;
        for (0..len) |_| {
            var new_node: ?*Node = null;
            if (mask & code > 0)
                new_node = if (current.right) |n| n else blk: {
                    const n = codec.makeNode();
                    current.right = n;
                    break :blk n;
                }
            else
                new_node = if (current.left) |n| n else blk: {
                    const n = codec.makeNode();
                    current.left = n;
                    break :blk n;
                };

            new_node.?.symbol = symbol;
            new_node.?.bits = len;
            current = new_node.?;
            code <<= 1;
        }
    }

    inline fn getBranch(self: *Node, code: u8) !*Node {
        if (code == 1)
            return self.right orelse return error.FailedToDecode
        else if (code == 0)
            return self.left orelse return error.FailedToDecode;
        unreachable;
    }
};

pub fn calcEncodedLength(source: []const u8) usize {
    var idx: usize = 0;
    for (source) |value| {
        const codelen = codes.huffman_code_lengths[value];
        idx += codelen;
    }
    return std.mem.alignForward(u64, idx, 8) / 8;
}

pub fn decode(self: *Self, input: []const u8, output: anytype) !usize {
    var t = self.tree;
    var bitlen: i32 = 0;
    var last_byte = input[0];
    for (input) |v| {
        var value = v;
        for (0..8) |_| {
            t = try t.getBranch(value >> 7);
            if (t.isLeaf()) {
                if (t.symbol == hcodes[256]) return error.EosDecoded;
                try output.writeInt(u8, @truncate(t.symbol), .little);
                bitlen += t.bits;
                last_byte = v;
                t = self.tree;
            }
            value <<= 1;
        }
    }
    const k = @mod(bitlen, 8);
    if (k != 0) {
        const a = @as(u8, 255) >> @as(u3, @intCast(k));
        if (last_byte & a != a) return error.InvalidPadding;
    }
    return 0;
}

pub fn encodeInt(value: u64, n: u4, writer: anytype) !void {
    if (n <= 0 or n > 8) return error.InvalidPrefixSize;
    var v = value;
    const max_int = math.pow(usize, 2, n);
    if (value < max_int - 1)
        try writer.writeInt(u8, @intCast(value), .little)
    else {
        try writer.writeInt(u8, @intCast(max_int - 1), .little);
        v = v - (max_int - 1);
        while (v >= 128) : (v /= 128) try writer.writeInt(u8, @intCast(v % 128 + 128), .little);
        try writer.writeInt(u8, @intCast(v), .little);
    }
}

pub const Result = struct {
    value: u64,
    // size in encoded form
    size: usize,
};

pub fn decodeInt(value: []const u8, n: u4) !Result {
    var end: usize = 1;
    const max_int = math.pow(usize, 2, n);
    var result = value[0] & (max_int - 1);
    if (result < max_int - 1) return .{ .value = result, .size = end };
    var m: usize = 0;
    while (true) {
        if (end >= value.len) return error.FailedToDecodeInteger;
        const b = value[end];
        result = result + (b & 127) * math.pow(usize, 2, m);
        m = m + 7;
        end += 1;
        if (b & 128 != 128) break;
    }
    return .{ .value = result, .size = end };
}

test "tree" {
    const tv1 = [_]u8{ '>', 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1 };
    const tv2 = [_]u8{ '?', 1, 1, 1, 1, 1, 1, 1, 1, 0, 0 };
    const tv3 = [_]u8{ '@', 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0 };
    const tv4 = [_]u8{ 'A', 1, 0, 0, 0, 0, 1 };
    const tv5 = [_]u8{ 'D', 1, 0, 1, 1, 1, 1, 1 };
    const tv6 = [_]u8{ 'Q', 1, 1, 0, 1, 1, 0, 0 };
    const tv7 = [_]u8{ 'm', 1, 0, 1, 0, 0, 1 };
    const tv8 = [_]u8{ ']', 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0 };
    const tvs = [_][]const u8{ tv1[0..], tv2[0..], tv3[0..], tv4[0..], tv5[0..], tv6[0..], tv7[0..], tv8[0..] };
    const codec = Self.init();
    for (tvs) |value| {
        var t = codec.tree;
        for (value[1..]) |bit| {
            t = try t.getBranch(bit);
        }
        try std.testing.expectEqual(value[0], t.symbol);
        try std.testing.expect(t.isLeaf());
    }
}

test "enc dec" {
    var bufs: [255][200]u8 = undefined;
    for (&bufs) |*value| {
        std.crypto.random.bytes(value[0..]);
    }
    var ctx = Self.init();
    var enc = [_]u8{0} ** 1000;
    var dec = [_]u8{0} ** 1000;
    var encstream = std.io.fixedBufferStream(enc[0..]);
    var decstream = std.io.fixedBufferStream(dec[0..]);
    for (bufs[0..]) |buf| {
        defer {
            encstream.reset();
            decstream.reset();
        }
        const l = calcEncodedLength(buf[0..]);
        const out = try encode(buf[0..], encstream.writer());
        try std.testing.expectEqual(out, l);
        _ = try decode(&ctx, enc[0..out], decstream.writer());
        try std.testing.expectEqualSlices(u8, buf[0..], dec[0..buf.len]);
    }
}

test "integer" {
    var buf = [_]u8{0} ** 10;
    var stream = std.io.fixedBufferStream(buf[0..]);

    var a = try encodeInt(500, 3, stream.writer());
    var out = try decodeInt(buf[0..stream.pos], 3);
    try std.testing.expect(out.value == 500);
    stream.reset();

    a = try encodeInt(500, 1, stream.writer());
    out = try decodeInt(buf[0..stream.pos], 1);
    try std.testing.expect(out.value == 500);
    stream.reset();

    a = try encodeInt(500, 8, stream.writer());
    out = try decodeInt(buf[0..stream.pos], 8);
    try std.testing.expect(out.value == 500);
    stream.reset();

    a = try encodeInt(50000000000, 8, stream.writer());
    out = try decodeInt(buf[0..stream.pos], 8);
    try std.testing.expect(out.value == 50000000000);
    stream.reset();

    for (1..9) |j| {
        for (0..10000) |i| {
            //var i: usize = 0;
            a = try encodeInt(i, @truncate(j), stream.writer());
            out = try decodeInt(buf[0..stream.pos], @truncate(j));
            try std.testing.expectEqual(out.value, i);
            stream.reset();
        }
    }
}

test "invalid padding" {
    var ctx = Self.init();
    var out = [_]u8{0} ** 5;
    var outstream = std.io.fixedBufferStream(out[0..]);
    try std.testing.expectError(Error.InvalidPadding, ctx.decode(&.{ 255, 0 }, outstream.writer()));
    outstream.pos = 0;
    const Tester = packed struct(u8) {
        a: bool = false,
        b: bool = false,
        c: bool = false,
        d: bool = false,
        e: bool = false,
        f: bool = false,
        g: bool = false,
        h: bool = false,
    };

    try std.testing.expectError(Error.InvalidPadding, ctx.decode(&.{@as(u8, @bitCast(Tester{ .a = true, .f = true }))}, outstream.writer()));
    try std.testing.expectError(Error.InvalidPadding, ctx.decode(&.{@as(u8, @bitCast(Tester{ .a = true, .c = true, .f = true }))}, outstream.writer()));
    try std.testing.expectError(Error.InvalidPadding, ctx.decode(&.{@as(u8, @bitCast(Tester{ .a = true, .b = true, .d = true, .e = true }))}, outstream.writer()));
}
