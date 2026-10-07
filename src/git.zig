// ZigLens git history — Spec Sec.16, 142-144.
// `git log --name-only` via child process (Io), fallback to reflog.
// Provides churn, ownership, evolution signals. Read-only; never mutates repo.

const std = @import("std");

pub const Commit = struct {
    hash: []u8,
    author: []u8,
    date: []u8,
    files: std.array_list.Managed([]u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Commit, gpa: std.mem.Allocator) void {
        gpa.free(self.hash);
        gpa.free(self.author);
        gpa.free(self.date);
        for (self.files.items) |f| gpa.free(f);
        self.files.deinit();
        _ = self.allocator;
    }
};

pub fn getLog(gpa: std.mem.Allocator, io: std.Io, root: []const u8, max_commits: usize) !std.array_list.Managed(Commit) {
    var out = std.array_list.Managed(Commit).init(gpa);
    errdefer {
        for (out.items) |*c| c.deinit(gpa);
        out.deinit();
    }
    // Redirect to temp file instead of pipe: avoids Windows pipe-reader hangs.
    const cwd = std.Io.Dir.cwd();
    var root_dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch return out;
    defer root_dir.close(io);
    root_dir.createDirPath(io, ".ziglens") catch {};
    var tmp = root_dir.createFile(io, ".ziglens/gitlog.tmp", .{}) catch return out;
    var child = std.process.spawn(io, .{
        .argv = &[_][]const u8{ "git", "--no-pager", "log", "--name-only", "--pretty=format:HASH:%H AUTHOR:%ae", "--no-merges" },
        .cwd = .{ .path = root },
        .stdout = .{ .file = tmp },
        .stderr = .ignore,
    }) catch {
        tmp.close(io);
        return out;
    };
    _ = child.wait(io) catch {};
    tmp.close(io);
    const data = root_dir.readFileAlloc(io, ".ziglens/gitlog.tmp", gpa, .limited(10 * 1024 * 1024)) catch return out;
    defer gpa.free(data);
    root_dir.deleteFile(io, ".ziglens/gitlog.tmp") catch {};
    var current: ?Commit = null;
    var count: usize = 0;
    var lines = std.mem.splitSequence(u8, data, "\n");
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "HASH:")) {
            if (current) |*c| {
                try out.append(c.*);
                current = null;
            }
            if (count >= max_commits) break;
            count += 1;
            // HASH:<hash> AUTHOR:<email>
            var hash: []const u8 = "";
            var author: []const u8 = "unknown";
            if (std.mem.indexOf(u8, t, "AUTHOR:")) |ai| {
                if (t.len > 5) hash = std.mem.trim(u8, t[5..ai], " \t");
                author = std.mem.trim(u8, t[ai + 7 ..], " \t");
            }
            current = .{
                .hash = try gpa.dupe(u8, hash),
                .author = try gpa.dupe(u8, author),
                .date = try gpa.dupe(u8, ""),
                .files = std.array_list.Managed([]u8).init(gpa),
                .allocator = gpa,
            };
        } else if (t.len > 0) {
            if (current) |*c| {
                if (c.files.items.len < 200) {
                    c.files.append(try gpa.dupe(u8, t)) catch continue;
                }
            }
        }
    }
    if (current) |*c| {
        try out.append(c.*);
    }
    return out;
}

pub const Churn = struct {
    path: []u8,
    commits: usize,
    authors: usize,
};pub fn churnByFile(gpa: std.mem.Allocator, commits: []Commit) !std.array_list.Managed(Churn) {
    var map = std.StringHashMap(struct { commits: usize, authors: std.array_list.Managed([]u8) }).init(gpa);
    defer {
        var it = map.iterator();
        while (it.next()) |e| e.value_ptr.authors.deinit();
        map.deinit();
    }
    for (commits) |*c| {
        for (c.files.items) |f| {
            const e = try map.getOrPut(f);
            if (!e.found_existing) {
                e.value_ptr.* = .{ .commits = 0, .authors = std.array_list.Managed([]u8).init(gpa) };
            }
            e.value_ptr.commits += 1;
            var known = false;
            for (e.value_ptr.authors.items) |a| {
                if (std.mem.eql(u8, a, c.author)) {
                    known = true;
                    break;
                }
            }
            if (!known) try e.value_ptr.authors.append(c.author);
        }
    }
    var out = std.array_list.Managed(Churn).init(gpa);
    var it = map.iterator();
    while (it.next()) |e| {
        try out.append(.{ .path = try gpa.dupe(u8, e.key_ptr.*), .commits = e.value_ptr.commits, .authors = e.value_ptr.authors.items.len });
    }
    std.mem.sort(Churn, out.items, {}, struct {
        fn lt(_: void, a: Churn, b: Churn) bool {
            return a.commits > b.commits;
        }
    }.lt);
    return out;
}

// Changed paths via `git diff` (staged / range / HEAD). Temp-file redirect
// (same Windows pipe-hang avoidance as getLog). Returns raw path lines.
pub fn getChanged(gpa: std.mem.Allocator, io: std.Io, root: []const u8, extra: []const []const u8) !std.array_list.Managed([]u8) {
    var out = std.array_list.Managed([]u8).init(gpa);
    errdefer {
        for (out.items) |p| gpa.free(p);
        out.deinit();
    }
    var argv = std.array_list.Managed([]const u8).init(gpa);
    defer argv.deinit();
    try argv.append("git");
    try argv.append("--no-pager");
    for (extra) |a| try argv.append(a);
    const cwd = std.Io.Dir.cwd();
    var root_dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch return out;
    defer root_dir.close(io);
    root_dir.createDirPath(io, ".ziglens") catch {};
    var tmp = root_dir.createFile(io, ".ziglens/gitchg.tmp", .{}) catch return out;
    var child = std.process.spawn(io, .{
        .argv = argv.items,
        .cwd = .{ .path = root },
        .stdout = .{ .file = tmp },
        .stderr = .ignore,
    }) catch {
        tmp.close(io);
        return out;
    };
    _ = child.wait(io) catch {};
    tmp.close(io);
    const data = root_dir.readFileAlloc(io, ".ziglens/gitchg.tmp", gpa, .limited(2 * 1024 * 1024)) catch return out;
    defer gpa.free(data);
    root_dir.deleteFile(io, ".ziglens/gitchg.tmp") catch {};
    var lines = std.mem.splitSequence(u8, data, "\n");
    while (lines.next()) |ln| {
        const t = std.mem.trim(u8, ln, " \t\r\"'");
        if (t.len == 0) continue;
        out.append(try gpa.dupe(u8, t)) catch break;
        if (out.items.len > 2000) break;
    }
    return out;
}

// Full history with dates for evolution timelines. Format:
// HIST:<hash>|<author>|<date> then file lines.
pub fn getHistory(gpa: std.mem.Allocator, io: std.Io, root: []const u8, max_commits: usize) !std.array_list.Managed(Commit) {
    var out = std.array_list.Managed(Commit).init(gpa);
    errdefer {
        for (out.items) |*c| c.deinit(gpa);
        out.deinit();
    }
    const cwd = std.Io.Dir.cwd();
    var root_dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch return out;
    defer root_dir.close(io);
    root_dir.createDirPath(io, ".ziglens") catch {};
    var tmp = root_dir.createFile(io, ".ziglens/githist.tmp", .{}) catch return out;
    var child = std.process.spawn(io, .{
        .argv = &[_][]const u8{ "git", "--no-pager", "log", "--pretty=format:HIST:%H|%ae|%aI", "--name-only", "--no-merges" },
        .cwd = .{ .path = root },
        .stdout = .{ .file = tmp },
        .stderr = .ignore,
    }) catch {
        tmp.close(io);
        return out;
    };
    _ = child.wait(io) catch {};
    tmp.close(io);
    const data = root_dir.readFileAlloc(io, ".ziglens/githist.tmp", gpa, .limited(10 * 1024 * 1024)) catch return out;
    defer gpa.free(data);
    root_dir.deleteFile(io, ".ziglens/githist.tmp") catch {};
    var current: ?Commit = null;
    var count: usize = 0;
    var lines = std.mem.splitSequence(u8, data, "\n");
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "HIST:")) {
            if (current) |*c| {
                try out.append(c.*);
                current = null;
            }
            if (count >= max_commits) break;
            count += 1;
            const rest = t[5..];
            var it = std.mem.splitSequence(u8, rest, "|");
            const h = it.next() orelse "";
            const a = it.next() orelse "unknown";
            const d = it.next() orelse "";
            current = .{
                .hash = try gpa.dupe(u8, h),
                .author = try gpa.dupe(u8, a),
                .date = try gpa.dupe(u8, d),
                .files = std.array_list.Managed([]u8).init(gpa),
                .allocator = gpa,
            };
        } else if (t.len > 0) {
            if (current) |*c| {
                if (c.files.items.len < 300) {
                    c.files.append(try gpa.dupe(u8, t)) catch continue;
                }
            }
        }
    }
    if (current) |*c| {
        try out.append(c.*);
    }
    return out;
}

test "churn empty" {
    const t = std.testing;
    var commits = std.array_list.Managed(Commit).init(t.allocator);
    defer commits.deinit();
    var ch = try churnByFile(t.allocator, commits.items);
    defer {
        for (ch.items) |*c| t.allocator.free(c.path);
        ch.deinit();
    }
    try t.expect(ch.items.len == 0);
}
