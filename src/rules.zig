// ZigLens custom architecture rules — Spec Sec.43-44.
// Rules from .ziglens.toml [[rules]]: {id, from, to, deny, message}.
// Layer names: ui, controller, service, repository, database.
// Example: controllers must not import database.

const std = @import("std");

pub const Rule = struct {
    id: []u8,
    from: []u8, // layer substring, lowercase
    to: []u8,
    message: []u8,
};

pub fn parseRules(gpa: std.mem.Allocator, raw: []const u8) !std.array_list.Managed(Rule) {
    var out = std.array_list.Managed(Rule).init(gpa);
    errdefer {
        for (out.items) |*r| {
            gpa.free(r.id);
            gpa.free(r.from);
            gpa.free(r.to);
            gpa.free(r.message);
        }
        out.deinit();
    }
    // minimal [[rules]] parser: key = "value" lines within block
    var in_rules = false;
    var cur_id: ?[]u8 = null;
    var cur_from: ?[]u8 = null;
    var cur_to: ?[]u8 = null;
    var cur_msg: ?[]u8 = null;
    var lines = std.mem.splitSequence(u8, raw, "\n");
    while (lines.next()) |ln| {
        const t = std.mem.trim(u8, ln, " \t\r");
        if (std.mem.eql(u8, t, "[[rules]]")) {
            if (in_rules and cur_from != null and cur_to != null) {
                try out.append(.{
                    .id = cur_id orelse try gpa.dupe(u8, "ARCH-101"),
                    .from = cur_from.?,
                    .to = cur_to.?,
                    .message = cur_msg orelse try gpa.dupe(u8, "custom rule violation"),
                });
                cur_id = null;
                cur_from = null;
                cur_to = null;
                cur_msg = null;
            }
            in_rules = true;
            continue;
        }
        if (!in_rules) continue;
        if (t.len > 0 and t[0] == '[' and !std.mem.startsWith(u8, t, "[[rules]]")) {
            break; // next section
        }
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = std.mem.trim(u8, t[0..eq], " \t");
        var val = std.mem.trim(u8, t[eq + 1 ..], " \t\"'");
        if (val.len > 0 and (val[val.len - 1] == '"' or val[val.len - 1] == '\'')) val = val[0 .. val.len - 1];
        if (std.mem.eql(u8, key, "id")) {
            if (cur_id) |p| gpa.free(p);
            cur_id = try gpa.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "from")) {
            if (cur_from) |p| gpa.free(p);
            var low: [256]u8 = undefined;
            const n = @min(val.len, 255);
            cur_from = try gpa.dupe(u8, std.ascii.lowerString(low[0..n], val[0..n]));
        } else if (std.mem.eql(u8, key, "to")) {
            if (cur_to) |p| gpa.free(p);
            var low2: [256]u8 = undefined;
            const n2 = @min(val.len, 255);
            cur_to = try gpa.dupe(u8, std.ascii.lowerString(low2[0..n2], val[0..n2]));
        } else if (std.mem.eql(u8, key, "message")) {
            if (cur_msg) |p| gpa.free(p);
            cur_msg = try gpa.dupe(u8, val);
        }
    }
    if (in_rules and cur_from != null and cur_to != null) {
        try out.append(.{
            .id = cur_id orelse try gpa.dupe(u8, "ARCH-101"),
            .from = cur_from.?,
            .to = cur_to.?,
            .message = cur_msg orelse try gpa.dupe(u8, "custom rule violation"),
        });
    } else {
        if (cur_id) |p| gpa.free(p);
        if (cur_from) |p| gpa.free(p);
        if (cur_to) |p| gpa.free(p);
        if (cur_msg) |p| gpa.free(p);
    }
    return out;
}

pub fn matchRule(path: []const u8, layer_sub: []const u8) bool {
    var buf: [1024]u8 = undefined;
    const n = @min(path.len, 1024);
    const low = std.ascii.lowerString(buf[0..n], path[0..n]);
    return std.mem.indexOf(u8, low, layer_sub) != null;
}

test "parse rules" {
    const t = std.testing;
    const raw = "[[rules]]\nid = \"ARCH-101\"\nfrom = \"controller\"\nto = \"database\"\nmessage = \"no direct db\"\n";
    var r = try parseRules(t.allocator, raw);
    defer {
        for (r.items) |*x| {
            t.allocator.free(x.id);
            t.allocator.free(x.from);
            t.allocator.free(x.to);
            t.allocator.free(x.message);
        }
        r.deinit();
    }
    try t.expect(r.items.len == 1);
    try t.expect(matchRule("src/controllers/a.ts", "controller"));
    try t.expect(!matchRule("src/services/a.ts", "controller"));
}
