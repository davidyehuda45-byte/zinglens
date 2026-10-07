// ZigLens persistent store — Spec Sec.30, 33, 101, 122-123.
// v0.1: in-memory only. Phase 2: .ziglens/ JSON index with hashes,
// incremental detection, snapshots, baseline, cache management.
// SQLite migration path documented; JSON keeps zero-dep single binary.

const std = @import("std");

pub const INDEX_DIR = ".ziglens";
pub const INDEX_FILE = ".ziglens/index.json";
pub const BASELINE_FILE = ".ziglens/baseline.json";

pub fn ensureDir(io: std.Io) !void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, INDEX_DIR) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

// FNV-1a 64 hash for change detection (fast, deterministic).
pub fn hashContent(content: []const u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (content) |c| {
        h ^= c;
        h *%= 0x100000001b3;
    }
    return h;
}

pub const FileState = struct {
    path: []u8,
    hash: u64,
    size: u64,
};

pub fn computeStates(gpa: std.mem.Allocator, io: std.Io, root: []const u8, paths: []const []const u8) !std.array_list.Managed(FileState) {
    var out = std.array_list.Managed(FileState).init(gpa);
    errdefer {
        for (out.items) |*s| gpa.free(s.path);
        out.deinit();
    }
    const cwd = std.Io.Dir.cwd();
    var dir = try std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true });
    defer dir.close(io);
    for (paths) |p| {
        const content = dir.readFileAlloc(io, p, gpa, .limited(50 * 1024 * 1024)) catch continue;
        defer gpa.free(content);
        try out.append(.{ .path = try gpa.dupe(u8, p), .hash = hashContent(content), .size = content.len });
    }
    return out;
}

pub fn saveBaseline(gpa: std.mem.Allocator, io: std.Io, root: []const u8, cycles: usize, violations: usize, dead: usize, files: usize, deps: usize, msgs: []const []const u8) !void {
    try ensureDir(io);
    const cwd = std.Io.Dir.cwd();
    var f = try cwd.createFile(io, BASELINE_FILE, .{});
    defer f.close(io);
    var buf: [4096]u8 = undefined;
    var w = f.writer(io, &buf);
    try w.interface.print("{{\"root\":\"{s}\",\"cycles\":{d},\"violations\":{d},\"dead\":{d},\"files\":{d},\"deps\":{d},\"msgs\":[", .{ root, cycles, violations, dead, files, deps });
    const cap = @min(msgs.len, 100);
    var i: usize = 0;
    while (i < cap) : (i += 1) {
        if (i > 0) try w.interface.writeAll(",");
        try w.interface.writeAll("\"");
        for (msgs[i]) |c| {
            if (c == '"') try w.interface.writeAll("\\\"") else if (c == '\\') try w.interface.writeAll("\\\\") else try w.interface.writeAll(&[_]u8{c});
        }
        try w.interface.writeAll("\"");
    }
    try w.interface.writeAll("]}");
    try w.interface.flush();
    _ = gpa;
}

pub const Baseline = struct {
    cycles: usize,
    violations: usize,
    dead: usize,
    files: usize,
    deps: usize,
    msgs: std.array_list.Managed([]u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Baseline) void {
        for (self.msgs.items) |m| self.allocator.free(m);
        self.msgs.deinit();
    }
};

pub fn loadBaseline(gpa: std.mem.Allocator, io: std.Io) !?Baseline {
    const cwd = std.Io.Dir.cwd();
    const raw = cwd.readFileAlloc(io, BASELINE_FILE, gpa, .limited(2 * 1024 * 1024)) catch return null;
    defer gpa.free(raw);
    const c = parseNum(raw, "\"cycles\"") orelse 0;
    const v = parseNum(raw, "\"violations\"") orelse 0;
    const d = parseNum(raw, "\"dead\"") orelse 0;
    const fc = parseNum(raw, "\"files\"") orelse 0;
    const dc = parseNum(raw, "\"deps\"") orelse 0;
    var msgs = std.array_list.Managed([]u8).init(gpa);
    errdefer {
        for (msgs.items) |m| gpa.free(m);
        msgs.deinit();
    }
    if (std.mem.indexOf(u8, raw, "\"msgs\"")) |mi| {
        var i = mi;
        // find '['
        while (i < raw.len and raw[i] != '[') : (i += 1) {}
        i += 1;
        while (i < raw.len and msgs.items.len < 100) {
            while (i < raw.len and raw[i] != '"' and raw[i] != ']') : (i += 1) {}
            if (i >= raw.len or raw[i] == ']') break;
            i += 1; // past opening quote
            var out = std.array_list.Managed(u8).init(gpa);
            errdefer out.deinit();
            while (i < raw.len and raw[i] != '"') {
                if (raw[i] == '\\' and i + 1 < raw.len) {
                    i += 1;
                    try out.append(raw[i]);
                } else try out.append(raw[i]);
                i += 1;
            }
            if (i < raw.len) i += 1; // past closing quote
            msgs.append(try out.toOwnedSlice()) catch {
                out.deinit();
                break;
            };
            // skip comma/space
            while (i < raw.len and (raw[i] == ',' or raw[i] == ' ')) : (i += 1) {}
        }
    }
    return .{ .cycles = c, .violations = v, .dead = d, .files = fc, .deps = dc, .msgs = msgs, .allocator = gpa };
}

fn parseNum(raw: []const u8, key: []const u8) ?usize {
    const ki = std.mem.indexOf(u8, raw, key) orelse return null;
    var i = ki + key.len;
    while (i < raw.len and (raw[i] < '0' or raw[i] > '9')) : (i += 1) {}
    var j = i;
    while (j < raw.len and raw[j] >= '0' and raw[j] <= '9') : (j += 1) {}
    if (j == i) return null;
    return std.fmt.parseInt(usize, raw[i..j], 10) catch null;
}

pub fn cleanCache(io: std.Io) !void {
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, INDEX_DIR) catch {};
}

test "hash deterministic" {
    const t = std.testing;
    try t.expect(hashContent("abc") == hashContent("abc"));
    try t.expect(hashContent("abc") != hashContent("abd"));
}
