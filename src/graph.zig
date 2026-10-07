// ZigLens dependency graph — Spec Sec.11, 167-170.
// File/module/package graph, cycles (SCC/Tarjan-lite via DFS),
// fan-in/fan-out, shortest path, dependents/dependencies queries.

const std = @import("std");

pub const Edge = struct {
    from: usize, // file index
    to: usize, // file index
    raw: []u8, // original import string (owned)
    external: bool,

    pub fn deinit(self: *Edge, gpa: std.mem.Allocator) void {
        gpa.free(self.raw);
    }
};

pub const Graph = struct {
    n: usize,
    adj: std.array_list.Managed(std.array_list.Managed(usize)), // per-node outgoing file idx
    rev: std.array_list.Managed(std.array_list.Managed(usize)), // incoming
    edges: std.array_list.Managed(Edge),
    external_imports: std.array_list.Managed([]u8),
    allocator: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, n: usize) !Graph {
        var g = Graph{
            .n = n,
            .adj = std.array_list.Managed(std.array_list.Managed(usize)).init(gpa),
            .rev = std.array_list.Managed(std.array_list.Managed(usize)).init(gpa),
            .edges = std.array_list.Managed(Edge).init(gpa),
            .external_imports = std.array_list.Managed([]u8).init(gpa),
            .allocator = gpa,
        };
        var i: usize = 0;
        while (i < n) : (i += 1) {
            try g.adj.append(std.array_list.Managed(usize).init(gpa));
            try g.rev.append(std.array_list.Managed(usize).init(gpa));
        }
        return g;
    }

    pub fn deinit(self: *Graph) void {
        for (self.adj.items) |*a| a.deinit();
        self.adj.deinit();
        for (self.rev.items) |*a| a.deinit();
        self.rev.deinit();
        for (self.edges.items) |*e| e.deinit(self.allocator);
        self.edges.deinit();
        for (self.external_imports.items) |s| self.allocator.free(s);
        self.external_imports.deinit();
    }

    pub fn addEdge(self: *Graph, from: usize, to: usize, raw: []const u8) !void {
        // dedupe
        for (self.adj.items[from].items) |v| {
            if (v == to) return;
        }
        try self.adj.items[from].append(to);
        try self.rev.items[to].append(from);
        try self.edges.append(.{ .from = from, .to = to, .raw = try self.allocator.dupe(u8, raw), .external = false });
    }

    pub fn addExternal(self: *Graph, from: usize, raw: []const u8) !void {
        _ = from;
        for (self.external_imports.items) |e| {
            if (std.mem.eql(u8, e, raw)) return;
        }
        try self.external_imports.append(try self.allocator.dupe(u8, raw));
    }

    pub fn fanOut(self: *Graph, node: usize) usize {
        return self.adj.items[node].items.len;
    }

    pub fn fanIn(self: *Graph, node: usize) usize {
        return self.rev.items[node].items.len;
    }
};

// Resolve import string to file index.
// Handles relative imports (./ ../) + extension probing + index files.
pub fn resolveImport(from_path: []const u8, raw: []const u8, files: []const []const u8) ?usize {
    if (raw.len == 0) return null;
    // absolute-ish or package import -> external unless matches a file suffix
    const is_relative = std.mem.startsWith(u8, raw, ".") or std.mem.startsWith(u8, raw, "/") or std.mem.indexOfScalar(u8, raw, '/') == null and std.mem.startsWith(u8, raw, "@") == false;
    if (!is_relative) {
        // try suffix match: e.g. "src/db" matches "src/db.ts"
        for (files, 0..) |f, i| {
            if (std.mem.endsWith(u8, f, raw)) return i;
            // strip extension compare
            if (stripExt(f)) |sf| {
                if (std.mem.endsWith(u8, sf, raw)) return i;
            }
        }
        return null;
    }
    // relative: join dirname(from) + raw
    const dir = std.fs.path.dirname(from_path) orelse "";
    // manual join
    // remove query/hash
    var clean = raw;
    if (std.mem.indexOfScalar(u8, clean, '?')) |qi| clean = clean[0..qi];
    if (std.mem.indexOfScalar(u8, clean, '#')) |hi| clean = clean[0..hi];
    // candidates
    // We do string-level resolution without fs access (index-based)
    var buf: [4096]u8 = undefined;
    const joined = if (dir.len == 0) clean else std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, clean }) catch return null;
    // normalize ./ and ../ lexically
    var norm: [4096]u8 = undefined;
    const nl = normalizeRel(joined, &norm);
    const npath = norm[0..nl];
    // direct match / with extensions / index files
    const exts = [_][]const u8{ "", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".py", ".go", ".rs", ".zig", ".php", ".java", ".rb", ".dart", ".swift", ".kt", ".cs", ".c", ".h", ".cpp", ".ex", ".exs" };
    for (files, 0..) |f, i| {
        if (std.mem.eql(u8, f, npath)) return i;
        for (exts) |e| {
            if (e.len == 0) continue;
            var cb: [4096]u8 = undefined;
            const cand = std.fmt.bufPrint(&cb, "{s}{s}", .{ npath, e }) catch continue;
            if (std.mem.eql(u8, f, cand)) return i;
        }
        // index.* inside dir
        var ib: [4096]u8 = undefined;
        const idxcand = std.fmt.bufPrint(&ib, "{s}/index", .{npath}) catch continue;
        for (exts) |e| {
            if (e.len == 0) continue;
            var cb2: [4096]u8 = undefined;
            const cand2 = std.fmt.bufPrint(&cb2, "{s}{s}", .{ idxcand, e }) catch continue;
            if (std.mem.eql(u8, f, cand2)) return i;
        }
    }
    return null;
}

fn stripExt(p: []const u8) ?[]const u8 {
    const base = std.fs.path.basename(p);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |di| {
        return p[0 .. p.len - (base.len - di)];
    }
    return null;
}

fn normalizeRel(p: []const u8, out: []u8) usize {
    // split by '/', handle . and ..
    var parts: [256][]const u8 = undefined;
    var nparts: usize = 0;
    var it = std.mem.splitSequence(u8, p, "/");
    while (it.next()) |seg| {
        if (seg.len == 0 or std.mem.eql(u8, seg, ".")) continue;
        if (std.mem.eql(u8, seg, "..")) {
            if (nparts > 0) nparts -= 1;
            continue;
        }
        if (nparts < parts.len) {
            parts[nparts] = seg;
            nparts += 1;
        }
    }
    var pos: usize = 0;
    for (parts[0..nparts], 0..) |seg, i| {
        if (i > 0) {
            out[pos] = '/';
            pos += 1;
        }
        @memcpy(out[pos .. pos + seg.len], seg);
        pos += seg.len;
    }
    return pos;
}

// Cycle detection — return list of cycles (each cycle = list of node idx).
pub fn findCycles(gpa: std.mem.Allocator, g: *Graph) !std.array_list.Managed(std.array_list.Managed(usize)) {
    var cycles = std.array_list.Managed(std.array_list.Managed(usize)).init(gpa);
    errdefer {
        for (cycles.items) |*c| c.deinit();
        cycles.deinit();
    }
    const n = g.n;
    const color = try gpa.alloc(u8, n); // 0 unvisited,1 in-stack,2 done
    defer gpa.free(color);
    @memset(color, 0);
    var stack = std.array_list.Managed(usize).init(gpa);
    defer stack.deinit();
    const in_stack_pos = try gpa.alloc(isize, n);
    defer gpa.free(in_stack_pos);
    for (in_stack_pos) |*v| v.* = -1;

    var s: usize = 0;
    while (s < n) : (s += 1) {
        if (color[s] == 0) try dfs(gpa, g, s, color, &stack, in_stack_pos, &cycles);
    }
    return cycles;
}

fn dfs(gpa: std.mem.Allocator, g: *Graph, u: usize, color: []u8, stack: *std.array_list.Managed(usize), pos: []isize, cycles: *std.array_list.Managed(std.array_list.Managed(usize))) !void {
    color[u] = 1;
    pos[u] = @as(isize, @intCast(stack.items.len));
    try stack.append(u);
    for (g.adj.items[u].items) |v| {
        if (color[v] == 0) {
            try dfs(gpa, g, v, color, stack, pos, cycles);
        } else if (color[v] == 1) {
            // found cycle from v..u
            var cyc = std.array_list.Managed(usize).init(gpa);
            errdefer cyc.deinit();
            const start: usize = @as(usize, @intCast(pos[v]));
            for (stack.items[start..]) |node| try cyc.append(node);
            try cyc.append(v);
            // cap cycles
            if (cycles.items.len < 100) try cycles.append(cyc) else cyc.deinit();
        }
    }
    _ = stack.pop();
    pos[u] = -1;
    color[u] = 2;
}

// BFS shortest path from a to b (dependency direction). Returns path or null.
pub fn shortestPath(gpa: std.mem.Allocator, g: *Graph, a: usize, b: usize) !?std.array_list.Managed(usize) {
    if (a == b) {
        var p = std.array_list.Managed(usize).init(gpa);
        try p.append(a);
        return p;
    }
    var prev = try gpa.alloc(isize, g.n);
    defer gpa.free(prev);
    for (prev) |*v| v.* = -1;
    var q = std.array_list.Managed(usize).init(gpa);
    defer q.deinit();
    try q.append(a);
    prev[a] = @as(isize, @intCast(a));
    var head: usize = 0;
    while (head < q.items.len) {
        const u = q.items[head];
        head += 1;
        for (g.adj.items[u].items) |v| {
            if (prev[v] == -1) {
                prev[v] = @as(isize, @intCast(u));
                if (v == b) {
                    // reconstruct
                    var path = std.array_list.Managed(usize).init(gpa);
                    var cur: usize = b;
                    try path.append(cur);
                    while (cur != a) {
                        cur = @as(usize, @intCast(prev[cur]));
                        try path.append(cur);
                    }
                    // reverse
                    var i: usize = 0;
                    var j: usize = path.items.len - 1;
                    while (i < j) {
                        const t = path.items[i];
                        path.items[i] = path.items[j];
                        path.items[j] = t;
                        i += 1;
                        j -= 1;
                    }
                    return path;
                }
                try q.append(v);
            }
        }
    }
    return null;
}

// Reachable set (transitive deps or dependents).
pub fn reachable(gpa: std.mem.Allocator, g: *Graph, start: usize, reverse: bool) !std.array_list.Managed(usize) {
    var seen = try gpa.alloc(bool, g.n);
    defer gpa.free(seen);
    @memset(seen, false);
    var out = std.array_list.Managed(usize).init(gpa);
    var q = std.array_list.Managed(usize).init(gpa);
    defer q.deinit();
    try q.append(start);
    seen[start] = true;
    var head: usize = 0;
    while (head < q.items.len) {
        const u = q.items[head];
        head += 1;
        const next = if (reverse) g.rev.items[u].items else g.adj.items[u].items;
        for (next) |v| {
            if (!seen[v]) {
                seen[v] = true;
                try out.append(v);
                try q.append(v);
            }
        }
    }
    return out;
}

test "resolve + cycle" {
    const t = std.testing;
    const files = [_][]const u8{ "src/a.ts", "src/b.ts", "src/c.ts" };
    try t.expect(resolveImport("src/a.ts", "./b", &files) == 1);
    try t.expect(resolveImport("src/a.ts", "./missing", &files) == null);

    var g = try Graph.init(t.allocator, 3);
    defer g.deinit();
    try g.addEdge(0, 1, "./b");
    try g.addEdge(1, 2, "./c");
    try g.addEdge(2, 0, "./a");
    var cycles = try findCycles(t.allocator, &g);
    defer {
        for (cycles.items) |*c| c.deinit();
        cycles.deinit();
    }
    try t.expect(cycles.items.len == 1);

    var p = try shortestPath(t.allocator, &g, 0, 2);
    defer if (p) |*pp| pp.deinit();
    try t.expect(p != null);
}
