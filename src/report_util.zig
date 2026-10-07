// ZigLens reports — Spec Sec.36-37. JSON stable for automation,
// plus Markdown / HTML standalone / CSV.

const std = @import("std");

pub fn escapeJsonInto(out: *std.array_list.Managed(u8), s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            else => {
                if (c < 0x20) {
                    try out.appendSlice("\\u00");
                    const hex = "0123456789abcdef";
                    try out.append(hex[c >> 4]);
                    try out.append(hex[c & 0xF]);
                } else try out.append(c);
            },
        }
    }
}

pub fn jsonString(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    try out.append('"');
    try escapeJsonInto(&out, s);
    try out.append('"');
    return out.toOwnedSlice();
}

test "escape json" {
    const t = std.testing;
    var out = std.array_list.Managed(u8).init(t.allocator);
    defer out.deinit();
    try escapeJsonInto(&out, "a\"b\nc");
    try t.expectEqualStrings("a\\\"b\\nc", out.items);
}
