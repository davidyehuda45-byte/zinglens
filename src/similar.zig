// ZigLens duplicate-code detection — Spec Sec.58-60.
// Normalized line-window hashing (LOW/MEDIUM confidence, never exact-only):
// trims, skips blanks/comments, caps work per file. Explainable via locations.

const std = @import("std");

pub const DupLoc = struct {
    path: []const u8,
    line: usize,
};

pub const DupGroup = struct {
    lines: usize,
    confidence: []const u8, // "HIGH" (>=10 lines) else "MEDIUM"
    locs: std.array_list.Managed(DupLoc),

    pub fn deinit(self: *DupGroup, gpa: std.mem.Allocator) void {
        self.locs.deinit();
        _ = gpa;
    }
};

fn normHash(window: []const []const u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (window) |ln| {
        for (ln) |c| {
            h ^= c;
            h *%= 0x100000001b3;
        }
        h ^= 0xFF;
        h *%= 0x100000001b3;
    }
    return h;
}

fn isComment(t: []const u8) bool {
    return std.mem.startsWith(u8, t, "//") or std.mem.startsWith(u8, t, "#") or std.mem.startsWith(u8, t, "*") or std.mem.startsWith(u8, t, "/*");
}

pub fn findDuplicates(
    gpa: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    paths: []const []const u8,
    min_lines: usize,
) !std.array_list.Managed(DupGroup) {
    var out = std.array_list.Managed(DupGroup).init(gpa);
    errdefer {
        for (out.items) |*g| g.deinit(gpa);
        out.deinit();
    }
    var seen = std.AutoHashMap(u64, usize).init(gpa);
    defer seen.deinit();
    const cwd = std.Io.Dir.cwd();
    var dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch return out;
    defer dir.close(io);
    var norm = std.array_list.Managed([]const u8).init(gpa);
    defer norm.deinit();
    var lnos = std.array_list.Managed(usize).init(gpa);
    defer lnos.deinit();

    for (paths) |p| {
        const content = dir.readFileAlloc(io, p, gpa, .limited(2 * 1024 * 1024)) catch continue;
        defer gpa.free(content);
        norm.clearRetainingCapacity();
        lnos.clearRetainingCapacity();
        var line_no: usize = 0;
        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |raw| {
            line_no += 1;
            const t = std.mem.trim(u8, raw[0..@min(raw.len, 300)], " \t\r");
            if (t.len == 0 or isComment(t)) continue;
            norm.append(t) catch break;
            lnos.append(line_no) catch break;
            if (norm.items.len > 5000) break;
        }
        if (norm.items.len < min_lines) continue;
        var w: usize = 0;
        while (w + min_lines <= norm.items.len) : (w += 1) {
            const h = normHash(norm.items[w .. w + min_lines]);
            const e = seen.getOrPut(h) catch continue;
            if (!e.found_existing) {
                if (out.items.len >= 100) break;
                var g = DupGroup{
                    .lines = min_lines,
                    .confidence = if (min_lines >= 10) "HIGH" else "MEDIUM",
                    .locs = std.array_list.Managed(DupLoc).init(gpa),
                };
                g.locs.append(.{ .path = p, .line = lnos.items[w] }) catch continue;
                out.append(g) catch continue;
                e.value_ptr.* = out.items.len - 1;
            } else {
                var g = &out.items[e.value_ptr.*];
                // avoid same-file self hit
                var same = false;
                for (g.locs.items) |l| {
                    if (l.path.ptr == p.ptr and l.line == lnos.items[w]) {
                        same = true;
                        break;
                    }
                }
                if (!same and g.locs.items.len < 10) {
                    g.locs.append(.{ .path = p, .line = lnos.items[w] }) catch continue;
                }
            }
        }
        if (out.items.len >= 100) break;
    }
    // keep only groups with 2+ locations
    var kept = std.array_list.Managed(DupGroup).init(gpa);
    defer kept.deinit();
    for (out.items) |*g| {
        if (g.locs.items.len >= 2) {
            kept.append(g.*) catch {
                g.locs.deinit();
                continue;
            };
        } else g.locs.deinit();
    }
    out.clearRetainingCapacity();
    for (kept.items) |*g| out.append(g.*) catch continue;
    return out;
}

test "dup basics" {
    const t = std.testing;
    // unit-test normHash determinism only (no fs)
    const w = [_][]const u8{ "a", "b" };
    try t.expect(normHash(&w) == normHash(&w));
}
