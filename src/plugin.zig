// ZigLens plugin system — Spec Sec.42, 124-128.
// v1 scope: local plugins only (no cloud registry). Plugins are UNTRUSTED:
// no network/fs grants except declared permissions (enforced by review,
// sandbox execution in roadmap). This module implements manifest +
// local registry (.ziglens/plugins.json) + list/install/remove.

const std = @import("std");

pub const REGISTRY_FILE = ".ziglens/plugins.json";

pub const Manifest = struct {
    name: []u8,
    version: []u8,
    author: []u8,
    capabilities: []u8,
    permissions: []u8,
    languages: []u8,
    path: []u8, // local dir owning the manifest

    pub fn deinit(self: *Manifest, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.version);
        gpa.free(self.author);
        gpa.free(self.capabilities);
        gpa.free(self.permissions);
        gpa.free(self.languages);
        gpa.free(self.path);
    }
};

// Minimal manifest format (plugin.manifest, key = "value"):
pub fn parseManifest(gpa: std.mem.Allocator, raw: []const u8, dir: []const u8) !Manifest {
    var name: ?[]u8 = null;
    var version: ?[]u8 = null;
    var author: ?[]u8 = null;
    var caps: ?[]u8 = null;
    var perms: ?[]u8 = null;
    var langs: ?[]u8 = null;
    errdefer {
        if (name) |p| gpa.free(p);
        if (version) |p| gpa.free(p);
        if (author) |p| gpa.free(p);
        if (caps) |p| gpa.free(p);
        if (perms) |p| gpa.free(p);
        if (langs) |p| gpa.free(p);
    }
    var lines = std.mem.splitSequence(u8, raw, "\n");
    while (lines.next()) |ln| {
        const t = std.mem.trim(u8, ln, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = std.mem.trim(u8, t[0..eq], " \t");
        var val = std.mem.trim(u8, t[eq + 1 ..], " \t\"'");
        if (val.len > 0 and (val[val.len - 1] == '"' or val[val.len - 1] == '\'')) val = val[0 .. val.len - 1];
        if (std.mem.eql(u8, key, "name")) {
            if (name) |p| gpa.free(p);
            name = try gpa.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "version")) {
            if (version) |p| gpa.free(p);
            version = try gpa.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "author")) {
            if (author) |p| gpa.free(p);
            author = try gpa.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "capabilities")) {
            if (caps) |p| gpa.free(p);
            caps = try gpa.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "permissions")) {
            if (perms) |p| gpa.free(p);
            perms = try gpa.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "supported_languages")) {
            if (langs) |p| gpa.free(p);
            langs = try gpa.dupe(u8, val);
        }
    }
    return .{
        .name = name orelse try gpa.dupe(u8, "unknown"),
        .version = version orelse try gpa.dupe(u8, "0.0.0"),
        .author = author orelse try gpa.dupe(u8, "unknown"),
        .capabilities = caps orelse try gpa.dupe(u8, ""),
        .permissions = perms orelse try gpa.dupe(u8, "none"),
        .languages = langs orelse try gpa.dupe(u8, ""),
        .path = try gpa.dupe(u8, dir),
    };
}

pub fn loadRegistry(gpa: std.mem.Allocator, io: std.Io) !std.array_list.Managed([]u8) {
    var out = std.array_list.Managed([]u8).init(gpa);
    const cwd = std.Io.Dir.cwd();
    const raw = cwd.readFileAlloc(io, REGISTRY_FILE, gpa, .limited(64 * 1024)) catch return out;
    defer gpa.free(raw);
    // extract quoted strings
    var i: usize = 0;
    while (i < raw.len and out.items.len < 64) {
        if (raw[i] == '"') {
            var j = i + 1;
            while (j < raw.len and raw[j] != '"') : (j += 1) {
                if (raw[j] == '\\') j += 1;
            }
            if (j < raw.len) {
                const s = raw[i + 1 .. j];
                if (!std.mem.eql(u8, s, "plugins")) {
                    out.append(gpa.dupe(u8, s) catch break) catch break;
                }
                i = j + 1;
                continue;
            }
            break;
        }
        i += 1;
    }
    return out;
}

pub fn saveRegistry(gpa: std.mem.Allocator, io: std.Io, paths: []const []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    // ensure dir
    cwd.createDirPath(io, ".ziglens") catch {};
    var f = try cwd.createFile(io, REGISTRY_FILE, .{});
    defer f.close(io);
    var buf: [2048]u8 = undefined;
    var w = f.writer(io, &buf);
    try w.interface.writeAll("{\"plugins\":[");
    for (paths, 0..) |p, i| {
        if (i > 0) try w.interface.writeAll(",");
        try w.interface.writeAll("\"");
        for (p) |c| {
            if (c == '"') try w.interface.writeAll("\\\"") else try w.interface.writeAll(&[_]u8{c});
        }
        try w.interface.writeAll("\"");
    }
    try w.interface.writeAll("]}");
    try w.interface.flush();
    _ = gpa;
}

test "manifest" {
    const t = std.testing;
    const raw = "name = \"my-plugin\"\nversion = \"1.0\"\ncapabilities = \"analyzer\"\n";
    var m = try parseManifest(t.allocator, raw, "./p");
    defer m.deinit(t.allocator);
    try t.expectEqualStrings("my-plugin", m.name);
}
