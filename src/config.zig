// ZigLens config — Spec Sec.35, 83, 102 (.ziglens.toml + .ziglensignore).
// Minimal TOML-subset parser (no dependency): [section], key = value,
// string/bool/int, string arrays. Unknown keys ignored.

const std = @import("std");

pub const Config = struct {
    dead_code: bool = true,
    complexity: bool = true,
    security: bool = true,
    git: bool = true,
    max_file_mb: usize = 50,
    max_files: usize = 200_000,
    ignore_paths: std.array_list.Managed([]u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        for (self.ignore_paths.items) |p| self.allocator.free(p);
        self.ignore_paths.deinit();
    }
};

pub fn load(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !Config {
    var cfg = Config{ .ignore_paths = std.array_list.Managed([]u8).init(gpa), .allocator = gpa };
    errdefer cfg.deinit();
    const cwd = std.Io.Dir.cwd();
    var dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch return cfg;
    defer dir.close(io);
    // .ziglens.toml
    if (dir.readFileAlloc(io, ".ziglens.toml", gpa, .limited(64 * 1024))) |raw| {
        defer gpa.free(raw);
        parseToml(gpa, raw, &cfg) catch {};
    } else |_| {}
    // .ziglensignore (one pattern per line, # comments)
    if (dir.readFileAlloc(io, ".ziglensignore", gpa, .limited(64 * 1024))) |raw| {
        defer gpa.free(raw);
        var lines = std.mem.splitSequence(u8, raw, "\n");
        while (lines.next()) |ln| {
            const t = std.mem.trim(u8, ln, " \t\r");
            if (t.len == 0 or t[0] == '#') continue;
            cfg.ignore_paths.append(gpa.dupe(u8, t) catch continue) catch continue;
        }
    } else |_| {}
    return cfg;
}

fn parseToml(gpa: std.mem.Allocator, raw: []const u8, cfg: *Config) !void {
    var section: []const u8 = "";
    var lines = std.mem.splitSequence(u8, raw, "\n");
    while (lines.next()) |ln| {
        const t = std.mem.trim(u8, ln, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        if (t[0] == '[') {
            if (std.mem.indexOfScalar(u8, t, ']')) |e| section = t[1..e];
            continue;
        }
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = std.mem.trim(u8, t[0..eq], " \t");
        var val = std.mem.trim(u8, t[eq + 1 ..], " \t");
        // strip quotes
        if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') val = val[1 .. val.len - 1];
        if (std.mem.eql(u8, section, "analysis")) {
            if (std.mem.eql(u8, key, "dead_code")) cfg.dead_code = parseBool(val);
            if (std.mem.eql(u8, key, "complexity")) cfg.complexity = parseBool(val);
            if (std.mem.eql(u8, key, "security")) cfg.security = parseBool(val);
            if (std.mem.eql(u8, key, "git")) cfg.git = parseBool(val);
        } else if (std.mem.eql(u8, section, "limits")) {
            if (std.mem.eql(u8, key, "max_file_mb")) cfg.max_file_mb = std.fmt.parseInt(usize, val, 10) catch cfg.max_file_mb;
            if (std.mem.eql(u8, key, "max_files")) cfg.max_files = std.fmt.parseInt(usize, val, 10) catch cfg.max_files;
        } else if (std.mem.eql(u8, section, "ignore")) {
            // paths = ["a", "b"] single-line
            if (std.mem.indexOf(u8, val, "\"")) |_| {
                var i: usize = 0;
                while (i < val.len) {
                    if (val[i] == '"') {
                        var j = i + 1;
                        while (j < val.len and val[j] != '"') : (j += 1) {}
                        if (j < val.len) {
                            cfg.ignore_paths.append(try gpa.dupe(u8, val[i + 1 .. j])) catch break;
                            i = j + 1;
                        } else break;
                    } else i += 1;
                }
            }
        }
    }
}

fn parseBool(s: []const u8) bool {
    return std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "yes") or std.mem.eql(u8, s, "1");
}

test "toml" {
    const t = std.testing;
    const raw = "[analysis]\ndead_code = false\n[limits]\nmax_file_mb = 10\n";
    var cfg = Config{ .ignore_paths = std.array_list.Managed([]u8).init(t.allocator), .allocator = t.allocator };
    defer cfg.deinit();
    try parseToml(t.allocator, raw, &cfg);
    try t.expect(!cfg.dead_code);
    try t.expect(cfg.max_file_mb == 10);
}
