//pub const hpack = @import("hpack/main.zig");

const std = @import("std");
pub const Codec = @import("hpack/codec.zig");
const staticTable = @import("hpack/static_table.zig");
const synamicTable = @import("hpack/dyn_table.zig");
pub const HeaderField = @import("hpack/header.zig");
const tables = @import("hpack/tables.zig");
const builder = @import("hpack/builder.zig");
const parser = @import("hpack/parser.zig");

pub const HpackContext = tables.HpackContext;
pub const Builder = builder.Builder;
pub const Parser = parser.Parser;

test {
    _ = std.testing.refAllDecls(builder);
    _ = std.testing.refAllDecls(tables);
    _ = std.testing.refAllDecls(parser);
    _ = std.testing.refAllDecls(Codec);
}
