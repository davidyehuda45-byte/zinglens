// ZigLens project scanner — Spec Sec.8.1, 67-70, 102.
// Read-only by default, symlink-safe, size-limited, .gitignore aware.

const std = @import("std");
const langmod = @import("language.zig");
const parser = @import("parser.zig");

pub const Limits = struct {
    max_file_size: usize = 50 * 1024 * 1024,
    warn_file_size: usize = 10 * 1024 * 1024,
    max_depth: usize = 64,
    max_files: usize = 200_000,
};

pub const ScannedFile = struct {
    path: []u8, // relative, slash-separated
    language: langmod.Language,
    size: u64,
    facts: ?parser.FileFacts, // owned; null if skipped/binary/too large
    skipped_reason: ?[]const u8,

    pub fn deinit(self: *ScannedFile, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        if (self.facts) |*f| f.deinit();
    }
};

pub const ScanResult = struct {
    files: std.array_list.Managed(ScannedFile),
    root: []u8,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn deinit(self: *ScanResult) void {
        for (self.files.items) |*f| f.deinit(self.allocator);
        self.files.deinit();
        self.allocator.free(self.root);
    }
};

fn normalizePath(gpa: std.mem.Allocator, p: []const u8) ![]u8 {
    const dup = try gpa.dupe(u8, p);
    for (dup) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return dup;
}

fn hasNul(content: []const u8) bool {
    const n = @min(content.len, 8000);
    for (content[0..n]) |c| {
        if (c == 0) return true;
    }
    return false;
}

const BinExts = [_][]const u8{ ".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".zip", ".tar", ".gz", ".exe", ".dll", ".so", ".dylib", ".bin", ".mp4", ".mp3", ".woff", ".woff2", ".ttf", ".eot", ".ogg", ".mov", ".avi", ".psd", ".sketch" };

fn isBinaryExt(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |di| {
        const ext = base[di..];
        for (BinExts) |b| {
            if (std.ascii.eqlIgnoreCase(ext, b)) return true;
        }
    }
    return false;
}

pub fn scan(gpa: std.mem.Allocator, io: std.Io, root_path: []const u8, limits: Limits) !ScanResult {
    var res = ScanResult{
        .files = std.array_list.Managed(ScannedFile).init(gpa),
        .root = try gpa.dupe(u8, root_path),
        .allocator = gpa,
        .io = io,
    };
    errdefer res.deinit();

    // Open root with iterate permission
    var root_dir = try std.Io.Dir.openDir(std.Io.Dir.cwd(), io, root_path, .{ .iterate = true });
    defer root_dir.close(io);
    try walkDir(gpa, io, root_dir, "", limits, &res);
    return res;
}

fn scanWithDir(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, root_path: []const u8, limits: Limits, res: *ScanResult) !ScanResult {
    _ = root_path;
    try walkDir(gpa, io, dir, "", limits, res);
    return res.*;
}

fn walkDir(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, prefix: []const u8, limits: Limits, res: *ScanResult) !void {
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (res.files.items.len >= limits.max_files) break;
        const rel = entry.path; // [:0]const u8
        const rel_slice: []const u8 = rel[0..rel.len];
        if (rel_slice.len == 0) continue;
        if (entry.depth() > limits.max_depth) continue;

        const norm = try normalizePath(gpa, rel_slice);
        defer gpa.free(norm);
        // prefix handling (walker path already relative to opened dir)
        const display = if (prefix.len == 0) norm else blk: {
            const j = try std.fs.path.join(gpa, &[_][]const u8{ prefix, norm });
            defer gpa.free(j);
            break :blk try normalizePath(gpa, j);
        };
        defer if (prefix.len != 0) gpa.free(display);

        const show: []const u8 = if (prefix.len == 0) norm else display;

        if (langmod.isDefaultIgnored(show)) continue;
        if (std.mem.startsWith(u8, show, ".git/") or std.mem.eql(u8, show, ".git")) continue;

        if (entry.kind == .sym_link) {
            // Spec Sec.67: do not follow symlinks outside root by default
            continue;
        }
        if (entry.kind == .directory) continue;
        if (entry.kind != .file) continue;

        // Only keep source-ish + config files; skip obvious binaries by ext
        const language = langmod.detectLanguage(show);
        const is_cfg = isConfigFile(show);
        if (language == .unknown and !is_cfg) {
            // still index as unknown? skip non-source to keep index lean,
            // but keep counts for overview via lightweight stat
            continue;
        }
        if (isBinaryExt(show)) continue;

        // stat size
        var size: u64 = 0;
        if (entry.dir.statFile(io, entry.basename, .{})) |st| {
            size = st.size;
        } else |_| {}

        if (size > limits.max_file_size) {
            const p = try gpa.dupe(u8, show);
            errdefer gpa.free(p);
            try res.files.append(.{ .path = p, .language = language, .size = size, .facts = null, .skipped_reason = "too-large" });
            continue;
        }

        // read content (limit)
        const content = entry.dir.readFileAlloc(io, entry.basename, gpa, .limited(limits.max_file_size)) catch {
            const p = try gpa.dupe(u8, show);
            try res.files.append(.{ .path = p, .language = language, .size = size, .facts = null, .skipped_reason = "read-error" });
            continue;
        };
        defer gpa.free(content);
        if (hasNul(content)) continue; // binary

        const facts = parser.parse(gpa, content, language) catch {
            const p = try gpa.dupe(u8, show);
            try res.files.append(.{ .path = p, .language = language, .size = size, .facts = null, .skipped_reason = "parse-error" });
            continue;
        };
        const p = try gpa.dupe(u8, show);
        try res.files.append(.{ .path = p, .language = language, .size = size, .facts = facts, .skipped_reason = null });
    }
}

fn isConfigFile(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    if (std.mem.eql(u8, base, "package.json")) return true;
    if (std.mem.eql(u8, base, "go.mod")) return true;
    if (std.mem.eql(u8, base, "Cargo.toml")) return true;
    if (std.mem.eql(u8, base, "composer.json")) return true;
    if (std.mem.eql(u8, base, "requirements.txt")) return true;
    if (std.mem.eql(u8, base, "pyproject.toml")) return true;
    if (std.mem.eql(u8, base, ".env")) return true;
    if (std.mem.eql(u8, base, "pubspec.yaml")) return true;
    if (std.mem.eql(u8, base, "mix.exs")) return true;
    if (std.mem.eql(u8, base, "pom.xml")) return true;
    return false;
}

test "normalize" {
    const t = std.testing;
    const p = try normalizePath(t.allocator, "a\\b\\c.ts");
    defer t.allocator.free(p);
    try t.expectEqualStrings("a/b/c.ts", p);
}
