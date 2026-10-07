// ZigLens -- Local Codebase Intelligence & Architecture Analysis Platform.
// v0.1: Zig CLI + scanner + 16-language heuristic parser + symbol index +
// dependency graph + deadcode + complexity + impact + security + dashboard.
// Spec: local-first, offline, read-only, single binary, JSON API, localhost only.

const std = @import("std");
const i18n = @import("i18n.zig");
const langmod = @import("language.zig");
const parser = @import("parser.zig");
const scanner = @import("scanner.zig");
const graphmod = @import("graph.zig");
const analysis = @import("analysis.zig");
const report_util = @import("report_util.zig");
const dashboard = @import("dashboard.zig");
const store = @import("store.zig");
const configmod = @import("config.zig");
const gitmod = @import("git.zig");
const rulesmod = @import("rules.zig");
const pluginmod = @import("plugin.zig");
const detectmod = @import("detect.zig");
const similarmod = @import("similar.zig");

const VERSION = "0.7.0";

const Cmd = enum {
    scan, analyze, search, symbol, refs, deps, graph, impact, deadcode,
    complexity, architecture, security, git, report, export_data, serve,
    watch, doctor, config, version, help, completion, path, why,
    baseline, snapshot, compare, cache, plugin, map, top, diff, evolution,
    unknown,
};

fn parseCmd(s: []const u8) Cmd {
    if (std.mem.eql(u8, s, "scan")) return .scan;
    if (std.mem.eql(u8, s, "analyze")) return .analyze;
    if (std.mem.eql(u8, s, "search")) return .search;
    if (std.mem.eql(u8, s, "symbol")) return .symbol;
    if (std.mem.eql(u8, s, "refs")) return .refs;
    if (std.mem.eql(u8, s, "deps")) return .deps;
    if (std.mem.eql(u8, s, "graph")) return .graph;
    if (std.mem.eql(u8, s, "impact")) return .impact;
    if (std.mem.eql(u8, s, "deadcode")) return .deadcode;
    if (std.mem.eql(u8, s, "complexity")) return .complexity;
    if (std.mem.eql(u8, s, "architecture") or std.mem.eql(u8, s, "arch")) return .architecture;
    if (std.mem.eql(u8, s, "security") or std.mem.eql(u8, s, "sec")) return .security;
    if (std.mem.eql(u8, s, "git")) return .git;
    if (std.mem.eql(u8, s, "report")) return .report;
    if (std.mem.eql(u8, s, "export")) return .export_data;
    if (std.mem.eql(u8, s, "serve")) return .serve;
    if (std.mem.eql(u8, s, "watch")) return .watch;
    if (std.mem.eql(u8, s, "doctor")) return .doctor;
    if (std.mem.eql(u8, s, "config")) return .config;
    if (std.mem.eql(u8, s, "version") or std.mem.eql(u8, s, "--version") or std.mem.eql(u8, s, "-V")) return .version;
    if (std.mem.eql(u8, s, "help") or std.mem.eql(u8, s, "--help") or std.mem.eql(u8, s, "-h")) return .help;
    if (std.mem.eql(u8, s, "completion")) return .completion;
    if (std.mem.eql(u8, s, "path")) return .path;
    if (std.mem.eql(u8, s, "why")) return .why;
    if (std.mem.eql(u8, s, "baseline")) return .baseline;
    if (std.mem.eql(u8, s, "snapshot")) return .snapshot;
    if (std.mem.eql(u8, s, "compare")) return .compare;
    if (std.mem.eql(u8, s, "cache")) return .cache;
    if (std.mem.eql(u8, s, "plugin")) return .plugin;
    if (std.mem.eql(u8, s, "map")) return .map;
    if (std.mem.eql(u8, s, "top")) return .top;
    if (std.mem.eql(u8, s, "diff")) return .diff;
    if (std.mem.eql(u8, s, "evolution")) return .evolution;
    return .unknown;
}

// Normal result output -> stdout (pipable: --json > file works).
// Diagnostics/errors -> stderr. Exit codes carry failure.
fn printOut(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    var w = std.Io.File.stdout().writer(io, &buf);
    w.interface.print(fmt, args) catch {};
    w.interface.flush() catch {};
}

fn printErr(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var w = std.Io.File.stderr().writer(io, &buf);
    w.interface.print(fmt, args) catch {};
    w.interface.flush() catch {};
}

const Flags = struct {
    json: bool = false,
    quiet: bool = false,
    verbose: bool = false,
    no_color: bool = false,
    root: []const u8 = ".",
    format: []const u8 = "terminal",
    template: []const u8 = "default",
    output: ?[]const u8 = null,
    lang: i18n.Lang = .en,
    port: u16 = 4173,
    top: usize = 20,
    ci: bool = false,
    staged: bool = false,
    threads: usize = 0,
};

const Snapshot = struct {
    res: scanner.ScanResult,
    paths: [][]const u8, // owned dupes? borrow from res paths
    graph: graphmod.Graph,
    cycles: std.array_list.Managed(std.array_list.Managed(usize)),
    arch: std.array_list.Managed(analysis.ArchViolation),
    dead: std.array_list.Managed(analysis.DeadItem),
    complexity: std.array_list.Managed(analysis.ComplexityRank),
    total_symbols: usize,
    lang_counts: [17]usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Snapshot) void {
        self.res.deinit();
        self.allocator.free(self.paths);
        self.graph.deinit();
        for (self.cycles.items) |*c| c.deinit();
        self.cycles.deinit();
        for (self.arch.items) |*a| {
            self.allocator.free(a.id);
            self.allocator.free(a.message);
        }
        self.arch.deinit();
        self.dead.deinit();
        self.complexity.deinit();
    }
};

fn buildSnapshot(gpa: std.mem.Allocator, io: std.Io, root: []const u8, quiet: bool) !Snapshot {
    if (!quiet) printErr(io, "Scanning project...\n", .{});
    var cfg_opt: ?configmod.Config = if (configmod.load(gpa, io, root)) |c| c else |_| null;
    defer if (cfg_opt) |*c| c.deinit();
    var limits = scanner.Limits{};
    if (cfg_opt) |*c| {
        limits.max_file_size = c.max_file_mb * 1024 * 1024;
        limits.max_files = c.max_files;
    }
    var res = try scanner.scan(gpa, io, root, limits);
    errdefer res.deinit();
    // apply custom ignores from .ziglens.toml / .ziglensignore
    if (cfg_opt) |*c| {
        var i = res.files.items.len;
        while (i > 0) {
            i -= 1;
            var skip = false;
            for (c.ignore_paths.items) |pat| {
                if (std.mem.indexOf(u8, res.files.items[i].path, pat) != null) {
                    skip = true;
                    break;
                }
            }
            if (skip) {
                res.files.items[i].deinit(gpa);
                _ = res.files.orderedRemove(i);
            }
        }
    }

    const n = res.files.items.len;
    var paths = try gpa.alloc([]const u8, n);
    errdefer gpa.free(paths);
    for (res.files.items, 0..) |*f, idx| paths[idx] = f.path;

    var g = try graphmod.Graph.init(gpa, n);
    errdefer g.deinit();

    // resolve imports -> edges
    for (res.files.items, 0..) |*f, idx| {
        if (f.facts) |*facts| {
            for (facts.imports.items) |imp| {
                if (graphmod.resolveImport(f.path, imp, paths)) |to| {
                    g.addEdge(idx, to, imp) catch continue;
                } else {
                    g.addExternal(idx, imp) catch continue;
                }
            }
        }
    }

    var cycles = try graphmod.findCycles(gpa, &g);
    errdefer {
        for (cycles.items) |*c| c.deinit();
        cycles.deinit();
    }
    var arch = try analysis.checkArchitecture(gpa, paths, &g);
    errdefer {
        for (arch.items) |*a| {
            gpa.free(a.id);
            gpa.free(a.message);
        }
        arch.deinit();
    }
    // custom rules from .ziglens.toml [[rules]]
    if (cfg_opt) |*c| {
        _ = c;
        const cwd2 = std.Io.Dir.cwd();
        if (std.Io.Dir.openDir(cwd2, io, root, .{ .iterate = true })) |rd| {
            var rdir = rd;
            defer rdir.close(io);
            if (rdir.readFileAlloc(io, ".ziglens.toml", gpa, .limited(64 * 1024))) |raw| {
                defer gpa.free(raw);
                if (rulesmod.parseRules(gpa, raw)) |rules| {
                    defer {
                        for (rules.items) |*r| {
                            gpa.free(r.id);
                            gpa.free(r.from);
                            gpa.free(r.to);
                            gpa.free(r.message);
                        }
                        var mrules = rules;
                        mrules.deinit();
                    }
                    for (rules.items) |*r| {
                        for (g.edges.items) |e| {
                            if (e.external) continue;
                            if (rulesmod.matchRule(paths[e.from], r.from) and rulesmod.matchRule(paths[e.to], r.to)) {
                                const rid = gpa.dupe(u8, r.id) catch continue;
                                const m = std.fmt.allocPrint(gpa, "{s}: {s} -> {s} ({s})", .{ r.message, paths[e.from], paths[e.to], r.id }) catch {
                                    gpa.free(rid);
                                    continue;
                                };
                                arch.append(.{ .id = rid, .severity = .high, .message = m }) catch {
                                    gpa.free(rid);
                                    gpa.free(m);
                                    continue;
                                };
                                if (arch.items.len > 200) break;
                            }
                        }
                    }
                } else |_| {}
            } else |_| {}
        } else |_| {}
    }
    var dead = try analysis.findDead(gpa, &res);
    errdefer dead.deinit();
    var complexity = try analysis.rankComplexity(gpa, &res);
    errdefer complexity.deinit();

    var total_symbols: usize = 0;
    var lang_counts: [17]usize = undefined;
    for (&lang_counts) |*c| c.* = 0;
    for (res.files.items) |*f| {
        if (f.facts) |*facts| total_symbols += facts.symbols.items.len;
        const li = @as(usize, @intFromEnum(f.language));
        if (li < lang_counts.len) lang_counts[li] += 1;
    }

    return .{
        .res = res,
        .paths = paths,
        .graph = g,
        .cycles = cycles,
        .arch = arch,
        .dead = dead,
        .complexity = complexity,
        .total_symbols = total_symbols,
        .lang_counts = lang_counts,
        .allocator = gpa,
    };
}

fn healthScores(snap: *Snapshot) struct { arch: u8, maint: u8, sec: u8, overall: u8 } {
    const arch = analysis.architectureScore(snap.cycles.items.len, snap.arch.items.len);
    var high_cx: usize = 0;
    for (snap.complexity.items) |c| {
        if (c.complexity > 20) high_cx += 1;
    }
    var maint: i32 = 100;
    maint -= @as(i32, @intCast(high_cx * 2));
    maint -= @as(i32, @intCast(snap.dead.items.len / 10));
    if (maint < 0) maint = 0;
    const sec: u8 = 90; // refined by security command; base
    const overall = @as(u8, @intCast((@as(u32, arch) + @as(u32, @as(u8, @intCast(maint))) + sec) / 3));
    return .{ .arch = arch, .maint = @as(u8, @intCast(maint)), .sec = sec, .overall = overall };
}

fn findFileIdx(snap: *Snapshot, query: []const u8) ?usize {
    for (snap.paths, 0..) |p, idx| {
        if (std.mem.eql(u8, p, query)) return idx;
        // suffix match
        if (std.mem.endsWith(u8, p, query)) return idx;
        const base = std.fs.path.basename(p);
        if (std.mem.eql(u8, base, query)) return idx;
    }
    return null;
}

fn printHelp(io: std.Io) void {
    printOut(io,
        \\ZigLens v{s} -- X-ray for your codebase (local-first, offline).
        \\
        \\Usage: ziglens [command] [args] [flags]
        \\
        \\Commands:
        \\  scan [root]              Scan project, show summary
        \\  analyze [root]           Full analysis + health scores
        \\  search <query>           Global symbol/file search
        \\  symbol <name>            Symbol detail
        \\  refs <name>              References to symbol
        \\  deps <file>              What file needs / who needs it
        \\  graph [--format json]    Dependency graph dump
        \\  path <A> <B>             Shortest dependency path A -> B
        \\  why <A> <B>              Explain dependency path
        \\  impact <file>            Change blast radius + risk
        \\  deadcode                 Unused code (HIGH/MEDIUM/LOW)
        \\  complexity [--top N]     Complexity ranking
        \\  architecture             Layers, violations, cycles
        \\  security                 Secret/config/unsafe scan (masked)
        \\  git [hotspots]           Git-aware hotspots (Phase2: full history)
        \\  report --format html     Project/security/arch/tech-debt report
        \\  export --format json     Machine-readable export
        \\  serve [--port 4173]      Local dashboard (127.0.0.1 only)
        \\  watch                    Re-scan on change (polling)
        \\  baseline create          Save violation baseline (CI regression)
        \\  snapshot create          Save project snapshot JSON
        \\  compare                  Compare current vs baseline
        \\  cache clean              Remove .ziglens/ index
        \\  plugin <list|install|remove> Local plugins (untrusted)
        \\  map <api|services|config|models> Detection maps
        \\  top [--top N]            Refactor priority ranking
        \\  diff [base head|--cached] Changed files + affected modules
        \\  evolution [--commits N]  History timeline (churn/ownership)
        \\  doctor                   Environment & config checks
        \\  config                   Show effective config
        \\  completion <shell>       Shell completion (bash/zsh/fish/powershell)
        \\  version                  Version
        \\  help                     This help
        \\
        \\Global flags: --json --quiet --verbose --no-color --root <dir>
        \\  --format <terminal|json|md|html|csv> --output <file> --lang <en|id>
        \\  --port <n> --top <n> --ci --staged --threads <n>
        \\
        \\Examples:
        \\  ziglens scan .
        \\  ziglens impact src/database.ts
        \\  ziglens deps src/database.ts --json
        \\  ziglens serve --port 4173
        \\
        \\Exit codes: 0 pass · 1 analysis failure · 2 quality-gate failure · 3 config error
        \\
    , .{VERSION});
}

fn writeOutputFile(io: std.Io, path: []const u8, content: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var f = try cwd.createFile(io, path, .{});
    defer f.close(io);
    var buf: [8192]u8 = undefined;
    var w = f.writer(io, &buf);
    try w.interface.writeAll(content);
    try w.interface.flush();
}

// ---------- JSON builders (manual, stable) ----------
fn buildProjectJson(gpa: std.mem.Allocator, io: std.Io, snap: *Snapshot, root: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    const h = healthScores(snap);
    try out.appendSlice("{\"project\":");
    const pj = try report_util.jsonString(gpa, root);
    defer gpa.free(pj);
    try out.appendSlice(pj);
    try out.appendSlice(",\"version\":\"" ++ VERSION ++ "\"");
    var buf: [128]u8 = undefined;
    const hc = try std.fmt.bufPrint(&buf, ",\"health\":{{\"architecture\":{d},\"maintainability\":{d},\"security\":{d},\"overall\":{d}}},\"files\":[", .{ h.arch, h.maint, h.sec, h.overall });
    try out.appendSlice(hc);
    for (snap.res.files.items, 0..) |*f, i| {
        if (i > 0) try out.append(',');
        try out.append('{');
        const pq = try report_util.jsonString(gpa, f.path);
        defer gpa.free(pq);
        try out.appendSlice("\"path\":");
        try out.appendSlice(pq);
        const lb = try std.fmt.bufPrint(&buf, ",\"language\":\"{s}\",\"size\":{d}", .{ f.language.name(), f.size });
        try out.appendSlice(lb);
        if (f.facts) |*facts| {
            const cb = try std.fmt.bufPrint(&buf, ",\"loc\":{d},\"complexity\":{d},\"symbols\":{d}", .{ facts.loc, facts.complexity, facts.symbols.items.len });
            try out.appendSlice(cb);
        }
        try out.append('}');
    }
    try out.appendSlice("],\"dependencies\":[");
    for (snap.graph.edges.items, 0..) |*e, i| {
        if (i > 0) try out.append(',');
        const rq = try report_util.jsonString(gpa, e.raw);
        defer gpa.free(rq);
        const eb = try std.fmt.bufPrint(&buf, "{{\"from\":{d},\"to\":{d},\"raw\":", .{ e.from, e.to });
        try out.appendSlice(eb);
        try out.appendSlice(rq);
        try out.append('}');
    }
    try out.appendSlice("],\"cycles\":[");
    for (snap.cycles.items, 0..) |*c, i| {
        if (i > 0) try out.append(',');
        try out.append('[');
        for (c.items, 0..) |node, j| {
            if (j > 0) try out.append(',');
            const nb = try std.fmt.bufPrint(&buf, "{d}", .{node});
            try out.appendSlice(nb);
        }
        try out.append(']');
    }
    // top complexity (dashboard Overview needs real rows, not empty tables)
    try out.appendSlice("],\"top_complexity\":[");
    const tcn = @min(snap.complexity.items.len, 10);
    for (snap.complexity.items[0..tcn], 0..) |*c, i| {
        if (i > 0) try out.append(',');
        const pq = try report_util.jsonString(gpa, c.path);
        defer gpa.free(pq);
        try out.appendSlice("{\"path\":");
        try out.appendSlice(pq);
        var b2: [64]u8 = undefined;
        const s2 = try std.fmt.bufPrint(&b2, ",\"complexity\":{d},\"loc\":{d}}}", .{ c.complexity, c.loc });
        try out.appendSlice(s2);
    }
    // recommendations (shared scorer with `top` / analyze)
    try out.appendSlice("],\"recommendations\":[");
    if (scoredFixes(gpa, snap)) |fixes| {
        defer {
            var mf = fixes;
            mf.deinit();
        }
        const rn = @min(fixes.items.len, 5);
        for (fixes.items[0..rn], 0..) |*fx, i| {
            if (fx.score == 0) break;
            if (i > 0) try out.append(',');
            const det = fixDetail(gpa, snap, fx.idx) catch "?";
            const owned_det = det.len > 1 or (det.len == 1 and det[0] != '?');
            defer if (owned_det) gpa.free(det);
            var tmp: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&tmp, "{s} ({s})", .{ snap.paths[fx.idx], det }) catch continue;
            const mq = try report_util.jsonString(gpa, msg);
            defer gpa.free(mq);
            try out.appendSlice(mq);
        }
    } else |_| {}
    // security count (capped sample; values never stored, only counted)
    const sec = countSecurity(gpa, io, snap, root);
    var b3: [128]u8 = undefined;
    const tail = try std.fmt.bufPrint(&b3, "],\"symbols\":{d},\"deadcode_count\":{d},\"security_count\":{d},\"security_truncated\":{s}}}", .{ snap.total_symbols, snap.dead.items.len, sec.count, if (sec.truncated) "true" else "false" });
    try out.appendSlice(tail);
    return out.toOwnedSlice();
}

// Capped security count for dashboards/JSON (masked evidence freed immediately).
fn countSecurity(gpa: std.mem.Allocator, io: std.Io, snap: *Snapshot, root: []const u8) struct { count: usize, truncated: bool } {
    const cwd = std.Io.Dir.cwd();
    var dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch return .{ .count = 0, .truncated = true };
    defer dir.close(io);
    var count: usize = 0;
    var scanned: usize = 0;
    for (snap.paths) |p| {
        if (scanned >= 150) return .{ .count = count, .truncated = true };
        const content = dir.readFileAlloc(io, p, gpa, .limited(1024 * 1024)) catch continue;
        defer gpa.free(content);
        scanned += 1;
        var found = analysis.scanSecurity(gpa, p, content) catch continue;
        defer {
            for (found.items) |*f| gpa.free(f.masked);
            found.deinit();
        }
        count += found.items.len;
    }
    return .{ .count = count, .truncated = false };
}

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;

    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer it.deinit();
    _ = it.next(); // argv0

    var cmd: Cmd = .help;
    var cmd_seen = false;
    var dashdash = false;
    var positional = std.array_list.Managed([]const u8).init(gpa);
    defer positional.deinit();
    var flags = Flags{};
    var fmt_explicit = false;

    while (it.next()) |a| {
        const s: []const u8 = a;
        if (dashdash) {
            try positional.append(s);
        } else if (std.mem.eql(u8, s, "--")) {
            dashdash = true;
        } else if (std.mem.eql(u8, s, "--json")) {
            flags.json = true;
        } else if (std.mem.eql(u8, s, "--quiet")) {
            flags.quiet = true;
        } else if (std.mem.eql(u8, s, "--verbose")) {
            flags.verbose = true;
        } else if (std.mem.eql(u8, s, "--no-color")) {
            flags.no_color = true;
        } else if (std.mem.eql(u8, s, "--ci")) {
            flags.ci = true;
        } else if (std.mem.eql(u8, s, "--root")) {
            if (it.next()) |v| flags.root = v else {
                printErr(io, "error: --root needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.startsWith(u8, s, "--root=")) {
            flags.root = s["--root=".len..];
        } else if (std.mem.eql(u8, s, "--format")) {
            if (it.next()) |v| {
                flags.format = v;
                fmt_explicit = true;
            } else {
                printErr(io, "error: --format needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.startsWith(u8, s, "--format=")) {
            flags.format = s["--format=".len..];
            fmt_explicit = true;
        } else if (std.mem.eql(u8, s, "--output") or std.mem.eql(u8, s, "-o")) {
            if (it.next()) |v| flags.output = v else {
                printErr(io, "error: --output needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.eql(u8, s, "--lang")) {
            if (it.next()) |v| flags.lang = i18n.parseLang(v) else {
                printErr(io, "error: --lang needs en|id\n", .{});
                return 3;
            }
        } else if (std.mem.startsWith(u8, s, "--lang=")) {
            flags.lang = i18n.parseLang(s["--lang=".len..]);
        } else if (std.mem.eql(u8, s, "--port")) {
            if (it.next()) |v| flags.port = std.fmt.parseInt(u16, v, 10) catch {
                printErr(io, "error: --port must be 1..65535\n", .{});
                return 3;
            } else {
                printErr(io, "error: --port needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.eql(u8, s, "--top")) {
            if (it.next()) |v| flags.top = std.fmt.parseInt(usize, v, 10) catch 20 else {
                printErr(io, "error: --top needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.eql(u8, s, "--threads")) {
            if (it.next()) |_| {} else {
                printErr(io, "error: --threads needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.eql(u8, s, "--ignore")) {
            if (it.next()) |_| {} else {
                printErr(io, "error: --ignore needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.eql(u8, s, "--include")) {
            if (it.next()) |_| {} else {
                printErr(io, "error: --include needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.eql(u8, s, "--config")) {
            if (it.next()) |_| {} else {
                printErr(io, "error: --config needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.eql(u8, s, "--template")) {
            if (it.next()) |v| flags.template = v else {
                printErr(io, "error: --template needs a value\n", .{});
                return 3;
            }
        } else if (std.mem.eql(u8, s, "--staged")) {
            flags.staged = true;
        } else if (std.mem.startsWith(u8, s, "--template=")) {
            flags.template = s["--template=".len..];
        } else if (!cmd_seen and !std.mem.startsWith(u8, s, "-")) {
            cmd = parseCmd(s);
            cmd_seen = true;
            if (cmd == .unknown) {
                // maybe a path shorthand: `ziglens .` => scan
                if (std.mem.eql(u8, s, ".") or isPathLike(s)) {
                    cmd = .scan;
                    try positional.append(s);
                } else {
                    printErr(io, "Unknown command '{s}'. Run: ziglens help\n", .{s});
                    return 3;
                }
            }
        } else if (std.mem.startsWith(u8, s, "-") and !cmd_seen) {
            // global flag like --version handled as command already; -h etc.
            if (std.mem.eql(u8, s, "-h") or std.mem.eql(u8, s, "--help")) {
                printHelp(io);
                return 0;
            }
            printErr(io, "Unknown flag '{s}'. Run: ziglens help\n", .{s});
            return 3;
        } else if (std.mem.startsWith(u8, s, "-")) {
            printErr(io, "Unknown flag '{s}'. Run: ziglens help\n", .{s});
            return 3;
        } else {
            try positional.append(s);
        }
    }
    if (!cmd_seen) cmd = .scan; // `ziglens .` / bare => scan (Zero-config UX)
    if (flags.json) flags.format = "json";
    if (fmt_explicit and std.mem.eql(u8, flags.format, "json")) flags.json = true;

    switch (cmd) {
        .version => {
            if (flags.json) {
                printOut(io, "{{\"name\":\"ziglens\",\"version\":\"{s}\"}}\n", .{VERSION});
            } else {
                printOut(io, "ziglens {s}\n", .{VERSION});
            }
            return 0;
        },
        .help => {
            printHelp(io);
            return 0;
        },
        .completion => {
            const shell: []const u8 = if (positional.items.len > 0) positional.items[0] else "powershell";
            if (std.mem.eql(u8, shell, "powershell")) {
                printOut(io, "$c=@('scan','analyze','search','symbol','refs','deps','graph','impact','deadcode','complexity','architecture','security','git','report','export','serve','watch','baseline','snapshot','compare','cache','plugin','map','top','diff','evolution','doctor','config','version','help'); Register-ArgumentCompleter -CommandName ziglens -ScriptBlock {{ param($w,$p,$l) $c | Where-Object {{ $_ -like \"$p*\" }} | ForEach-Object {{ [CompletionResult]::new($_,$_, 'ParameterValue', $_) }} }}\n", .{});
            } else if (std.mem.eql(u8, shell, "bash")) {
                printOut(io, "_ziglens() {{ COMPREPLY=($(compgen -W 'scan analyze search symbol refs deps graph impact deadcode complexity architecture security git report export serve watch baseline snapshot compare cache plugin map top diff evolution doctor config version help' -- \"${{COMP_WORDS[COMP_CWORD]}}\")); }}; complete -F _ziglens ziglens\n", .{});
            } else if (std.mem.eql(u8, shell, "zsh")) {
                printOut(io, "#compdef ziglens\n_arguments '1: :((scan analyze search symbol refs deps graph impact deadcode complexity architecture security git report export serve watch baseline snapshot compare cache plugin map top diff evolution doctor config version help))'\n", .{});
            } else if (std.mem.eql(u8, shell, "fish")) {
                printOut(io, "complete -c ziglens -f -n '__fish_use_subcommand' -a 'scan analyze search symbol refs deps graph impact deadcode complexity architecture security git report export serve watch baseline snapshot compare cache plugin map top diff evolution doctor config version help'\n", .{});
            } else {
                printErr(io, "Unknown shell '{s}'. Use: bash|zsh|fish|powershell\n", .{shell});
                return 3;
            }
            return 0;
        },
        .doctor => return cmdDoctor(io, flags),
        .config => return cmdConfig(io, flags),
        else => {},
    }

    // Commands needing a snapshot
    const root: []const u8 = if (positional.items.len > 0 and (cmd == .scan or cmd == .analyze or cmd == .serve or cmd == .watch or cmd == .report or cmd == .export_data)) positional.items[0] else flags.root;

    switch (cmd) {
        .scan => return cmdScan(gpa, io, root, flags),
        .analyze => return cmdAnalyze(gpa, io, root, flags),
        .search, .symbol, .refs => return cmdSearch(gpa, io, root, flags, positional.items, cmd),
        .deps, .graph => return cmdDeps(gpa, io, root, flags, positional.items),
        .path, .why => return cmdPath(gpa, io, root, flags, positional.items),
        .impact => return cmdImpact(gpa, io, root, flags, positional.items),
        .deadcode => return cmdDeadcode(gpa, io, root, flags),
        .complexity => return cmdComplexity(gpa, io, root, flags),
        .architecture => return cmdArchitecture(gpa, io, root, flags),
        .security => return cmdSecurity(gpa, io, root, flags),
        .git => return cmdGit(gpa, io, root, flags, positional.items),
        .report, .export_data => return cmdReport(gpa, io, root, flags, positional.items),
        .serve => return cmdServe(gpa, io, root, flags),
        .watch => return cmdWatch(gpa, io, root, flags),
        .baseline => return cmdBaseline(gpa, io, root, flags, positional.items),
        .snapshot => return cmdSnapshot(gpa, io, root, flags, positional.items),
        .compare => return cmdCompare(gpa, io, root, flags),
        .cache => return cmdCache(gpa, io, flags, positional.items),
        .plugin => return cmdPlugin(gpa, io, flags, positional.items),
        .map => return cmdMap(gpa, io, root, flags, positional.items),
        .top => return cmdTop(gpa, io, root, flags),
        .diff => return cmdDiff(gpa, io, root, flags, positional.items),
        .evolution => return cmdEvolution(gpa, io, root, flags, positional.items),
        else => {
            printHelp(io);
            return 3;
        },
    }
}

fn isPathLike(s: []const u8) bool {
    return std.mem.indexOfScalar(u8, s, '/') != null or std.mem.indexOfScalar(u8, s, '\\') != null or std.mem.eql(u8, s, ".") or std.mem.eql(u8, s, "..");
}

// ---------------- scan ----------------
fn cmdScan(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    var snap = buildSnapshot(gpa, io, root, flags.quiet) catch |err| {
        printErr(io, "Unable to scan '{s}'\nReason: {t}\nRun: ziglens doctor\n", .{ root, err });
        return 1;
    };
    defer snap.deinit();
    const h = healthScores(&snap);

    if (flags.json) {
        const js = buildProjectJson(gpa, io, &snap, root) catch {
            printErr(io, "{{\"error\":\"json-build-failed\"}}\n", .{});
            return 1;
        };
        defer gpa.free(js);
        emitOutput(io, flags, js) catch return 1;
        return 0;
    }

    if (!flags.quiet) {
        const m = i18n.msg(flags.lang);
        printOut(io, "\nZigLens\n\n{s}\n\n", .{m.done});
        printOut(io, "Files             {d}\n", .{snap.res.files.items.len});
        printOut(io, "Symbols           {d}\n", .{snap.total_symbols});
        // languages
        printOut(io, "Languages         ", .{});
        var first = true;
        for (0..snap.lang_counts.len) |li| {
            if (snap.lang_counts[li] == 0) continue;
            const l: langmod.Language = @enumFromInt(li);
            if (l == .unknown) continue;
            if (!first) printOut(io, ", ", .{});
            printOut(io, "{s}({d})", .{ l.name(), snap.lang_counts[li] });
            first = false;
        }
        printOut(io, "\nDependencies      {d}\n", .{snap.graph.edges.items.len});
        printOut(io, "\nArchitecture      {d}/100\n", .{h.arch});
        printOut(io, "Security          {d}/100\n", .{h.sec});
        printOut(io, "Maintainability   {d}/100\n", .{h.maint});
        printOut(io, "\nPotential issues  {d}\n", .{snap.cycles.items.len + snap.arch.items.len + snap.dead.items.len});
        printOut(io, "\nDashboard:\nhttp://127.0.0.1:{d}\n      (run: ziglens serve {s})\n", .{ flags.port, root });
    }
    return 0;
}

fn emitOutput(io: std.Io, flags: Flags, content: []const u8) !void {
    if (flags.output) |op| {
        try writeOutputFile(io, op, content);
        if (!flags.quiet) printErr(io, "Wrote {s}\n", .{op});
    } else {
        printOut(io, "{s}\n", .{content});
    }
}

// ---------------- analyze ----------------
fn cmdAnalyze(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    var snap = buildSnapshot(gpa, io, root, flags.quiet) catch |err| {
        printErr(io, "Analysis failed: {t}\n", .{err});
        return 1;
    };
    defer snap.deinit();
    const h = healthScores(&snap);

    // --staged: restrict scope to staged files + their affected modules
    if (flags.staged) {
        const extra = [_][]const u8{ "diff", "--cached", "--name-only" };
        var changed = gitmod.getChanged(gpa, io, root, &extra) catch return 1;
        defer {
            for (changed.items) |p| gpa.free(p);
            changed.deinit();
        }
        if (changed.items.len == 0) {
            printErr(io, "No staged changes.\n", .{});
            return 0;
        }
        var matched = matchChanged(&snap, changed.items);
        defer matched.deinit();
        var affected = diffAffected(gpa, &snap, matched.items) catch return 1;
        defer affected.deinit();
        const level: []const u8 = if (affected.items.len >= 30) "HIGH" else if (affected.items.len >= 10) "MEDIUM" else "LOW";
        if (flags.json) {
            printOut(io, "{{\"staged\":{d},\"matched\":{d},\"affected\":{d},\"level\":\"{s}\"}}\n", .{ changed.items.len, matched.items.len, affected.items.len, level });
            return 0;
        }
        printOut(io, "\nSTAGED analysis\nStaged files: {d} (in index: {d})\nAffected modules: {d}\nRisk: {s}\n", .{ changed.items.len, matched.items.len, affected.items.len, level });
        for (matched.items) |m| printOut(io, "  ~ {s}\n", .{snap.paths[m]});
        return 0;
    }

    if (flags.json) {
        const js = buildProjectJson(gpa, io, &snap, root) catch return 1;
        defer gpa.free(js);
        emitOutput(io, flags, js) catch return 1;
        if (flags.ci) {
            // CI quality gates (defaults; configurable via .ziglens.toml Phase2)
            if (snap.cycles.items.len > 0 or snap.arch.items.len > 0) return 2;
        }
        return 0;
    }

    printOut(io, "\nPROJECT HEALTH\n", .{});
    printOut(io, "Architecture       {d}\n", .{h.arch});
    printOut(io, "Security            {d}\n", .{h.sec});
    printOut(io, "Maintainability     {d}\n", .{h.maint});
    printOut(io, "Overall             {d}\n", .{h.overall});
    printOut(io, "\nFILES              {d}\n", .{snap.res.files.items.len});
    printOut(io, "SYMBOLS             {d}\n", .{snap.total_symbols});
    printOut(io, "DEPENDENCIES         {d}\n", .{snap.graph.edges.items.len});
    printOut(io, "\nDEAD CODE             {d}\n", .{snap.dead.items.len});
    printOut(io, "ARCH VIOLATIONS         {d}\n", .{snap.arch.items.len});
    printOut(io, "CYCLES                  {d}\n", .{snap.cycles.items.len});
    // top risk: single plain-language fix list (no raw formulas, no duplicates)
    if (scoredFixes(gpa, &snap)) |fixes| {
        defer {
            var mf = fixes;
            mf.deinit();
        }
        renderFixes(gpa, io, &snap, fixes.items, 5, i18n.msg(flags.lang));
    } else |_| {}

    if (flags.ci and (snap.cycles.items.len > 0 or snap.arch.items.len > 0)) {
        printErr(io, "\nCI: FAILED (quality gate)\n", .{});
        return 2;
    }
    return 0;
}

// ---------------- search/symbol/refs ----------------
fn cmdSearch(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8, cmd: Cmd) u8 {
    if (positional.len == 0) {
        printErr(io, "Usage: ziglens {s} <query>\n", .{@tagName(cmd)});
        return 3;
    }
    const q = positional[0];
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();

    var out = std.array_list.Managed(u8).init(gpa);
    defer out.deinit();
    const is_json = flags.json;
    if (is_json) out.appendSlice("{\"query\":") catch return 1;
    if (is_json) {
        const qq = report_util.jsonString(gpa, q) catch return 1;
        defer gpa.free(qq);
        out.appendSlice(qq) catch return 1;
        out.appendSlice(",\"results\":[") catch return 1;
    }
    var count: usize = 0;
    var first = true;
    // files
    for (snap.paths, 0..) |p, idx| {
        if (std.mem.indexOf(u8, p, q) != null) {
            if (is_json) {
                if (!first) out.append(',') catch return 1;
                first = false;
                const pq = report_util.jsonString(gpa, p) catch return 1;
                defer gpa.free(pq);
                var b: [64]u8 = undefined;
                const pre = std.fmt.bufPrint(&b, "{{\"type\":\"file\",\"path\":", .{}) catch return 1;
                out.appendSlice(pre) catch return 1;
                out.appendSlice(pq) catch return 1;
                const suf = std.fmt.bufPrint(&b, ",\"file_idx\":{d}}}", .{idx}) catch return 1;
                out.appendSlice(suf) catch return 1;
            } else {
                printOut(io, "{s}\n", .{p});
            }
            count += 1;
            if (count >= 50) break;
        }
    }
    // symbols
    for (snap.res.files.items) |*f| {
        if (f.facts) |*facts| {
            for (facts.symbols.items) |*s| {
                if (std.mem.indexOf(u8, s.name, q) != null) {
                    if (cmd == .refs) {
                        // refs: show callers containing this name in calls
                        continue;
                    }
                    if (is_json) {
                        if (!first) out.append(',') catch return 1;
                        first = false;
                        const nq = report_util.jsonString(gpa, s.name) catch return 1;
                        defer gpa.free(nq);
                        const pq = report_util.jsonString(gpa, f.path) catch return 1;
                        defer gpa.free(pq);
                        var b: [128]u8 = undefined;
                        const pre = std.fmt.bufPrint(&b, "{{\"type\":\"symbol\",\"name\":", .{}) catch return 1;
                        out.appendSlice(pre) catch return 1;
                        out.appendSlice(nq) catch return 1;
                        out.appendSlice(",\"file\":") catch return 1;
                        out.appendSlice(pq) catch return 1;
                        const suf = std.fmt.bufPrint(&b, ",\"kind\":\"{s}\",\"line\":{d}}}", .{ s.kind.name(), s.line }) catch return 1;
                        out.appendSlice(suf) catch return 1;
                    } else {
                        printOut(io, "{s}\n  {s}:{d} [{s}]\n", .{ s.name, f.path, s.line, s.kind.name() });
                    }
                    count += 1;
                    if (count >= 50) break;
                }
            }
        }
        if (count >= 50) break;
    }
    if (cmd == .refs) {
        // who calls q?
        for (snap.res.files.items) |*f| {
            if (f.facts) |*facts| {
                for (facts.calls.items) |c| {
                    if (std.mem.eql(u8, c, q)) {
                        if (!is_json) printOut(io, "called in {s}\n", .{f.path});
                        count += 1;
                        break;
                    }
                }
            }
        }
    }
    if (is_json) {
        out.appendSlice("]}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
    } else if (count == 0) {
        printOut(io, "No results for '{s}'\n", .{q});
    }
    return 0;
}

// ---------------- deps/graph ----------------
fn cmdDeps(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    if (positional.len == 0) {
        // dump all deps summary
        if (flags.json) {
            const js = buildProjectJson(gpa, io, &snap, root) catch return 1;
            defer gpa.free(js);
            emitOutput(io, flags, js) catch return 1;
            return 0;
        }
        printOut(io, "Files: {d}, edges: {d}, cycles: {d}\n", .{ snap.paths.len, snap.graph.edges.items.len, snap.cycles.items.len });
        return 0;
    }
    const q = positional[0];
    const idx = findFileIdx(&snap, q) orelse {
        printErr(io, "File '{s}' not found in index. Try: ziglens search {s}\n", .{ q, q });
        return 1;
    };
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        const pq = report_util.jsonString(gpa, snap.paths[idx]) catch return 1;
        defer gpa.free(pq);
        out.appendSlice("{\"file\":") catch return 1;
        out.appendSlice(pq) catch return 1;
        out.appendSlice(",\"depends_on\":[") catch return 1;
        for (snap.graph.adj.items[idx].items, 0..) |to, i| {
            if (i > 0) out.append(',') catch return 1;
            const tq = report_util.jsonString(gpa, snap.paths[to]) catch return 1;
            defer gpa.free(tq);
            out.appendSlice(tq) catch return 1;
        }
        out.appendSlice("],\"dependents\":[") catch return 1;
        for (snap.graph.rev.items[idx].items, 0..) |from, i| {
            if (i > 0) out.append(',') catch return 1;
            const fq = report_util.jsonString(gpa, snap.paths[from]) catch return 1;
            defer gpa.free(fq);
            out.appendSlice(fq) catch return 1;
        }
        out.appendSlice("]}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    printOut(io, "{s}\n", .{snap.paths[idx]});
    printOut(io, "Needs ({d}):\n", .{snap.graph.adj.items[idx].items.len});
    for (snap.graph.adj.items[idx].items) |to| printOut(io, "  -> {s}\n", .{snap.paths[to]});
    printOut(io, "Needed by ({d}):\n", .{snap.graph.rev.items[idx].items.len});
    for (snap.graph.rev.items[idx].items) |from| printOut(io, "  <- {s}\n", .{snap.paths[from]});
    return 0;
}

fn cmdPath(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    if (positional.len < 2) {
        printErr(io, "Usage: ziglens path <A> <B>\n", .{});
        return 3;
    }
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    const a = findFileIdx(&snap, positional[0]) orelse {
        printErr(io, "File '{s}' not found\n", .{positional[0]});
        return 1;
    };
    const b = findFileIdx(&snap, positional[1]) orelse {
        printErr(io, "File '{s}' not found\n", .{positional[1]});
        return 1;
    };
    var p = graphmod.shortestPath(gpa, &snap.graph, a, b) catch return 1;
    defer if (p) |*pp| pp.deinit();
    if (p == null) {
        if (flags.json) {
            printOut(io, "{{\"from\":\"{s}\",\"to\":\"{s}\",\"path\":null}}\n", .{ positional[0], positional[1] });
        } else {
            printOut(io, "No dependency path {s} -> {s}\n", .{ snap.paths[a], snap.paths[b] });
        }
        return 0;
    }
    if (flags.json) {
        printOut(io, "{{\"path\":[", .{});
        for (p.?.items, 0..) |node, i| {
            if (i > 0) printOut(io, ",", .{});
            printOut(io, "\"{s}\"", .{snap.paths[node]});
        }
        printOut(io, "]}}\n", .{});
    } else {
        for (p.?.items, 0..) |node, i| {
            if (i > 0) printOut(io, "  ↓\n", .{});
            printOut(io, "{s}\n", .{snap.paths[node]});
        }
    }
    return 0;
}

// ---------------- impact ----------------
fn cmdImpact(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    if (positional.len == 0) {
        printErr(io, "Usage: ziglens impact <file>\n", .{});
        return 3;
    }
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    const idx = findFileIdx(&snap, positional[0]) orelse {
        printErr(io, "File '{s}' not found\n", .{positional[0]});
        return 1;
    };
    var cx: u32 = 1;
    if (snap.res.files.items[idx].facts) |*f| cx = f.complexity;
    var imp = analysis.analyzeImpact(gpa, &snap.graph, snap.paths, idx, cx) catch return 1;
    defer imp.deinit();
    const level: []const u8 = if (imp.risk >= 75) "HIGH" else if (imp.risk >= 40) "MEDIUM" else "LOW";
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        const pq = report_util.jsonString(gpa, snap.paths[idx]) catch return 1;
        defer gpa.free(pq);
        var b: [256]u8 = undefined;
        const pre = std.fmt.bufPrint(&b, "{{\"file\":{s},\"risk\":{d},\"level\":\"{s}\",\"direct\":{d},\"indirect\":{d},\"tests\":{d},\"reasons\":[", .{ pq, imp.risk, level, imp.direct, imp.indirect, imp.tests }) catch return 1;
        // pq borrowed into pre? need copy: rebuild safely
        _ = pre;
        // simpler emit via debug lines
        printOut(io, "{{\"file\":\"{s}\",\"risk\":{d},\"level\":\"{s}\",\"direct\":{d},\"indirect\":{d},\"tests\":{d}}}\n", .{ snap.paths[idx], imp.risk, level, imp.direct, imp.indirect, imp.tests });
        return 0;
    }
    printOut(io, "\nPotential impact: {s}\n\n", .{level});
    printOut(io, "Direct dependents: {d}\n", .{imp.direct});
    printOut(io, "Indirect dependents: {d}\n", .{imp.indirect});
    printOut(io, "Affected tests: {d}\n", .{imp.tests});
    printOut(io, "Risk score: {d}/100\n", .{imp.risk});
    if (imp.reasons.items.len > 0) {
        printOut(io, "\nReasons:\n", .{});
        for (imp.reasons.items) |r| printOut(io, "+ {s}\n", .{r});
    }
    return 0;
}

// ---------------- deadcode ----------------
fn cmdDeadcode(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        out.appendSlice("{\"deadcode\":[") catch return 1;
        for (snap.dead.items, 0..) |*d, i| {
            if (i > 0) out.append(',') catch return 1;
            const fq = report_util.jsonString(gpa, d.file) catch return 1;
            defer gpa.free(fq);
            const nq = report_util.jsonString(gpa, d.name) catch return 1;
            defer gpa.free(nq);
            var b: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&b, "{{\"file\":{s},\"name\":{s},\"confidence\":\"{s}\"}}", .{ fq, nq, analysis.confidenceName(d.confidence) }) catch return 1;
            // fq/nq are JSON strings; embedding via {s} duplicates quotes correctly? need raw
            _ = s;
            out.appendSlice("{\"file\":") catch return 1;
            out.appendSlice(fq) catch return 1;
            out.appendSlice(",\"name\":") catch return 1;
            out.appendSlice(nq) catch return 1;
            var b2: [128]u8 = undefined;
            const tail = std.fmt.bufPrint(&b2, ",\"confidence\":\"{s}\"}}", .{analysis.confidenceName(d.confidence)}) catch return 1;
            out.appendSlice(tail) catch return 1;
        }
        out.appendSlice("]}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    if (snap.dead.items.len == 0) {
        printOut(io, "No dead code candidates found.\n", .{});
        return 0;
    }
    for (snap.dead.items) |*d| {
        printOut(io, "[{s}] {s} :: {s} ({s}) -- {s}\n", .{ analysis.confidenceName(d.confidence), d.file, d.name, d.kind, d.reason });
    }
    return 0;
}

// ---------------- complexity ----------------
fn cmdComplexity(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    const n = @min(flags.top, snap.complexity.items.len);
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        out.appendSlice("{\"complexity\":[") catch return 1;
        for (snap.complexity.items[0..n], 0..) |*c, i| {
            if (i > 0) out.append(',') catch return 1;
            const pq = report_util.jsonString(gpa, c.path) catch return 1;
            defer gpa.free(pq);
            var b: [128]u8 = undefined;
            const pre = std.fmt.bufPrint(&b, "{{\"path\":", .{}) catch return 1;
            out.appendSlice(pre) catch return 1;
            out.appendSlice(pq) catch return 1;
            const suf = std.fmt.bufPrint(&b, ",\"complexity\":{d},\"loc\":{d}}}", .{ c.complexity, c.loc }) catch return 1;
            out.appendSlice(suf) catch return 1;
        }
        out.appendSlice("]}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    printOut(io, "Top {d} complexity:\n", .{n});
    const ml = i18n.msg(flags.lang);
    for (snap.complexity.items[0..n]) |*c| {
        printOut(io, "  [{s}] {d}\t{s} (loc {d})\n", .{ cxLevel(ml, c.complexity), c.complexity, c.path, c.loc });
    }
    return 0;
}

// ---------------- architecture ----------------
fn cmdArchitecture(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        var b: [64]u8 = undefined;
        const pre = std.fmt.bufPrint(&b, "{{\"cycles\":{d},\"violations\":[", .{snap.cycles.items.len}) catch return 1;
        out.appendSlice(pre) catch return 1;
        for (snap.arch.items, 0..) |*v, i| {
            if (i > 0) out.append(',') catch return 1;
            const mq = report_util.jsonString(gpa, v.message) catch return 1;
            defer gpa.free(mq);
            out.appendSlice("{\"id\":\"") catch return 1;
            out.appendSlice(v.id) catch return 1;
            out.appendSlice("\",\"message\":") catch return 1;
            out.appendSlice(mq) catch return 1;
            out.append('}') catch return 1;
        }
        out.appendSlice("]}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    if (snap.cycles.items.len == 0 and snap.arch.items.len == 0) {
        printOut(io, "{s}\n\nThis is either good architecture,\nor your analyzer needs improvement.\n", .{i18n.msg(flags.lang).no_violations});
        return 0;
    }
    if (snap.cycles.items.len > 0) {
        printOut(io, "Circular dependencies ({d}):\n", .{snap.cycles.items.len});
        for (snap.cycles.items, 0..) |*c, i| {
            printOut(io, "  cycle {d}: ", .{i + 1});
            for (c.items, 0..) |node, j| {
                if (j > 0) printOut(io, " -> ", .{});
                printOut(io, "{s}", .{snap.paths[node]});
            }
            printOut(io, "\n", .{});
        }
    }
    for (snap.arch.items) |*v| {
        printOut(io, "[{s}] {s}: {s}\n", .{ v.id, analysis.severityName(v.severity), v.message });
    }
    return 0;
}

// ---------------- security ----------------
fn cmdSecurity(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    var all = std.array_list.Managed(analysis.SecFinding).init(gpa);
    defer {
        for (all.items) |*f| gpa.free(f.masked);
        all.deinit();
    }
    for (snap.res.files.items) |*f| {
        if (f.facts == null) continue;
        // re-read content for security scan (facts don't store content)
        const cwd = std.Io.Dir.cwd();
        var dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch continue;
        const content = dir.readFileAlloc(io, f.path, gpa, .limited(5 * 1024 * 1024)) catch {
            dir.close(io);
            continue;
        };
        dir.close(io);
        defer gpa.free(content);
        var found = analysis.scanSecurity(gpa, f.path, content) catch continue;
        defer {
            // move ownership of masked into all; free on error paths
            for (found.items) |*ff| {
                all.append(ff.*) catch {
                    gpa.free(ff.masked);
                };
            }
            found.deinit();
        }
        if (all.items.len > 500) break;
    }
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        out.appendSlice("{\"findings\":[") catch return 1;
        for (all.items, 0..) |*fd, i| {
            if (i > 0) out.append(',') catch return 1;
            const fq = report_util.jsonString(gpa, fd.file) catch return 1;
            defer gpa.free(fq);
            const mq = report_util.jsonString(gpa, fd.masked) catch return 1;
            defer gpa.free(mq);
            out.appendSlice("{\"id\":\"") catch return 1;
            out.appendSlice(fd.id) catch return 1;
            out.appendSlice("\",\"file\":") catch return 1;
            out.appendSlice(fq) catch return 1;
            var b: [128]u8 = undefined;
            const mid = std.fmt.bufPrint(&b, ",\"line\":{d},\"severity\":\"{s}\",\"evidence\":", .{ fd.line, analysis.severityName(fd.severity) }) catch return 1;
            out.appendSlice(mid) catch return 1;
            out.appendSlice(mq) catch return 1;
            out.append('}') catch return 1;
        }
        out.appendSlice("]}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    if (all.items.len == 0) {
        printOut(io, "No security findings.\n", .{});
        return 0;
    }
    for (all.items) |*fd| {
        printOut(io, "[{s}] {s} {s}:{d}\n  {s}\n  fix: {s}\n", .{ fd.id, analysis.severityName(fd.severity), fd.file, fd.line, fd.masked, fd.remediation });
    }
    return 0;
}

// ---------------- git ----------------
fn cmdGit(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    _ = positional;
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    // Phase1: branch from .git/HEAD + hotspot proxy (fan-in x complexity).
    const cwd = std.Io.Dir.cwd();
    var branch: []const u8 = "unknown";
    var branch_buf: ?[]u8 = null;
    defer if (branch_buf) |b| gpa.free(b);
    if (std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true })) |gitdir| {
        var gd = gitdir;
        defer gd.close(io);
        if (gd.readFileAlloc(io, ".git/HEAD", gpa, .limited(1024))) |head| {
            defer gpa.free(head);
            const t = std.mem.trim(u8, head, " \t\r\n");
            if (std.mem.startsWith(u8, t, "ref: ")) {
                const ref = t["ref: ".len..];
                if (std.mem.lastIndexOfScalar(u8, ref, '/')) |li| {
                    branch_buf = gpa.dupe(u8, ref[li + 1 ..]) catch null;
                    if (branch_buf) |bb| branch = bb;
                }
            } else if (t.len >= 7) {
                branch_buf = gpa.dupe(u8, t[0..7]) catch null;
                if (branch_buf) |bb| branch = bb;
            }
        } else |_| {}
    } else |_| {}

    // hotspot = top rev-count
    var order = std.array_list.Managed(usize).init(gpa);
    defer order.deinit();
    for (0..snap.paths.len) |i| order.append(i) catch return 1;
    std.mem.sort(usize, order.items, &snap, struct {
        fn lt(s: *Snapshot, a: usize, b: usize) bool {
            return s.graph.rev.items[a].items.len > s.graph.rev.items[b].items.len;
        }
    }.lt);

    // reflog history: .git/logs/HEAD -> commit count + contributors
    var commits: usize = 0;
    var contributors: usize = 0;
    if (std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true })) |gdir| {
        var gd2 = gdir;
        defer gd2.close(io);
        if (gd2.readFileAlloc(io, ".git/logs/HEAD", gpa, .limited(10 * 1024 * 1024))) |log| {
            defer gpa.free(log);
            var emails = std.array_list.Managed([]const u8).init(gpa);
            defer emails.deinit();
            var lines = std.mem.splitSequence(u8, log, "\n");
            while (lines.next()) |ln| {
                if (ln.len < 10) continue;
                commits += 1;
                if (std.mem.indexOfScalar(u8, ln, '<')) |li| {
                    if (std.mem.indexOfScalar(u8, ln[li..], '>')) |ri| {
                        const em = ln[li + 1 .. li + ri];
                        var known = false;
                        for (emails.items) |e| {
                            if (std.mem.eql(u8, e, em)) {
                                known = true;
                                break;
                            }
                        }
                        if (!known and emails.items.len < 50) emails.append(em) catch {};
                    }
                }
            }
            contributors = emails.items.len;
        } else |_| {}
    } else |_| {}

    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        const bq = report_util.jsonString(gpa, branch) catch return 1;
        defer gpa.free(bq);
        out.appendSlice("{\"branch\":") catch return 1;
        out.appendSlice(bq) catch return 1;
        out.appendSlice(",\"hotspots\":[") catch return 1;
        const n = @min(order.items.len, 10);
        for (order.items[0..n], 0..) |idx, i| {
            if (i > 0) out.append(',') catch return 1;
            const pq = report_util.jsonString(gpa, snap.paths[idx]) catch return 1;
            defer gpa.free(pq);
            var b: [64]u8 = undefined;
            const pre = std.fmt.bufPrint(&b, "{{\"path\":", .{}) catch return 1;
            out.appendSlice(pre) catch return 1;
            out.appendSlice(pq) catch return 1;
            const suf = std.fmt.bufPrint(&b, ",\"dependents\":{d}}}", .{snap.graph.rev.items[idx].items.len}) catch return 1;
            out.appendSlice(suf) catch return 1;
        }
        out.appendSlice("],\"commits\":") catch return 1;
        var cb: [32]u8 = undefined;
        const cs = std.fmt.bufPrint(&cb, "{d}", .{commits}) catch return 1;
        out.appendSlice(cs) catch return 1;
        out.appendSlice(",\"contributors\":") catch return 1;
        const ds = std.fmt.bufPrint(&cb, "{d}", .{contributors}) catch return 1;
        out.appendSlice(ds) catch return 1;
        out.appendSlice("}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    printOut(io, "Branch: {s} | Commits: {d} | Contributors: {d}\nHotspots (by dependents):\n", .{ branch, commits, contributors });
    const n = @min(order.items.len, 10);
    for (order.items[0..n]) |idx| {
        printOut(io, "  {s} -- {d} dependents\n", .{ snap.paths[idx], snap.graph.rev.items[idx].items.len });
    }
    // git log churn (needs git binary + repo; silent fallback)
    if (gitmod.getLog(gpa, io, root, 200)) |logcommits| {
        var lc = logcommits;
        defer {
            for (lc.items) |*c| c.deinit(gpa);
            lc.deinit();
        }
        if (lc.items.len > 0) {
            var churn = gitmod.churnByFile(gpa, lc.items) catch null;
            if (churn) |*ch| {
                defer {
                    for (ch.items) |*x| gpa.free(x.path);
                    ch.deinit();
                }
                printOut(io, "\nChurn (top changed files, {d} commits scanned):\n", .{lc.items.len});
                const cn = @min(ch.items.len, 10);
                for (ch.items[0..cn]) |*x| {
                    printOut(io, "  {s} -- {d} commits, {d} authors\n", .{ x.path, x.commits, x.authors });
                }
            }
        }
    } else |_| {}
    return 0;
}

// ---------------- report/export ----------------
fn cmdReport(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    _ = positional;
    var snap = buildSnapshot(gpa, io, root, flags.quiet) catch return 1;
    defer snap.deinit();
    const h = healthScores(&snap);
    const fmt = flags.format;

    if (std.mem.eql(u8, fmt, "json") or flags.json) {
        const js = buildProjectJson(gpa, io, &snap, root) catch return 1;
        defer gpa.free(js);
        emitOutput(io, flags, js) catch return 1;
        return 0;
    }
    // templates apply to md/html/terminal (not raw json/csv dumps)
    if (!std.mem.eql(u8, flags.template, "default") and !std.mem.eql(u8, fmt, "csv")) {
        return cmdReportTemplate(gpa, io, &snap, root, flags, h);
    } else if (std.mem.eql(u8, fmt, "md") or std.mem.eql(u8, fmt, "markdown")) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        var b: [256]u8 = undefined;
        const head = std.fmt.bufPrint(&b, "# ZigLens Report -- {s}\n\nHealth: {d}/100 (arch {d}, maint {d})\n\nFiles: {d}, Symbols: {d}, Deps: {d}, Cycles: {d}\n\n## Top complexity\n", .{ root, h.overall, h.arch, h.maint, snap.paths.len, snap.total_symbols, snap.graph.edges.items.len, snap.cycles.items.len }) catch return 1;
        out.appendSlice(head) catch return 1;
        const n = @min(snap.complexity.items.len, 20);
        for (snap.complexity.items[0..n]) |*c| {
            const line = std.fmt.bufPrint(&b, "- {s} -- complexity {d}, loc {d}\n", .{ c.path, c.complexity, c.loc }) catch return 1;
            out.appendSlice(line) catch return 1;
        }
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    } else if (std.mem.eql(u8, fmt, "html")) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        out.appendSlice("<!DOCTYPE html><html><head><meta charset=utf-8><title>ZigLens Report</title><style>body{font-family:monospace;background:#0d1117;color:#e6edf3;padding:24px}table{border-collapse:collapse}td,th{border:1px solid #21262d;padding:4px 8px}</style></head><body>") catch return 1;
        var b: [256]u8 = undefined;
        const head = std.fmt.bufPrint(&b, "<h1>ZigLens Report -- {s}</h1><p>Health {d}/100 · Files {d} · Symbols {d}</p><table><tr><th>file</th><th>complexity</th></tr>", .{ root, h.overall, snap.paths.len, snap.total_symbols }) catch return 1;
        out.appendSlice(head) catch return 1;
        const n = @min(snap.complexity.items.len, 50);
        for (snap.complexity.items[0..n]) |*c| {
            const row = std.fmt.bufPrint(&b, "<tr><td>{s}</td><td>{d}</td></tr>", .{ c.path, c.complexity }) catch return 1;
            out.appendSlice(row) catch return 1;
        }
        out.appendSlice("</table></body></html>") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    } else if (std.mem.eql(u8, fmt, "csv")) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        out.appendSlice("path,language,loc,complexity,symbols\n") catch return 1;
        for (snap.res.files.items) |*f| {
            var b: [512]u8 = undefined;
            if (f.facts) |*facts| {
                const line = std.fmt.bufPrint(&b, "{s},{s},{d},{d},{d}\n", .{ f.path, f.language.name(), facts.loc, facts.complexity, facts.symbols.items.len }) catch continue;
                out.appendSlice(line) catch return 1;
            }
        }
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    // terminal
    return cmdAnalyze(gpa, io, root, flags);
}

fn cmdReportTemplate(gpa: std.mem.Allocator, io: std.Io, snap: *Snapshot, root: []const u8, flags: Flags, h: @TypeOf(healthScores(snap))) u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    defer out.deinit();
    var b: [256]u8 = undefined;
    if (std.mem.eql(u8, flags.template, "executive")) {
        const s = std.fmt.bufPrint(&b, "# Executive Summary -- {s}\n\nProject Health: {d}\n\nMajor risks: {d}\nArchitecture issues: {d}\nTechnical debt: {s}\n", .{ root, h.overall, snap.cycles.items.len, snap.arch.items.len, if (h.maint < 60) "High" else if (h.maint < 80) "Medium" else "Low" }) catch return 1;
        out.appendSlice(s) catch return 1;
    } else if (std.mem.eql(u8, flags.template, "architecture")) {
        const s = std.fmt.bufPrint(&b, "# Architecture Report -- {s}\n\nScore: {d}/100\nCycles: {d}\nViolations: {d}\n\n", .{ root, h.arch, snap.cycles.items.len, snap.arch.items.len }) catch return 1;
        out.appendSlice(s) catch return 1;
        for (snap.arch.items) |*v| {
            const l = std.fmt.bufPrint(&b, "- [{s}] {s}\n", .{ v.id, v.message }) catch break;
            out.appendSlice(l) catch return 1;
        }
    } else if (std.mem.eql(u8, flags.template, "technical-debt")) {
        const s = std.fmt.bufPrint(&b, "# Technical Debt -- {s}\n\nDead code: {d}\nHigh-complexity files: ", .{ root, snap.dead.items.len }) catch return 1;
        out.appendSlice(s) catch return 1;
        var hc: usize = 0;
        for (snap.complexity.items) |*c| {
            if (c.complexity > 20) hc += 1;
        }
        const s2 = std.fmt.bufPrint(&b, "{d}\nCycles: {d}\n", .{ hc, snap.cycles.items.len }) catch return 1;
        out.appendSlice(s2) catch return 1;
    } else if (std.mem.eql(u8, flags.template, "security")) {
        out.appendSlice("# Security Report\n\nRun `ziglens security --json` for masked findings.\n") catch return 1;
        const s = std.fmt.bufPrint(&b, "Files scanned: {d}\n", .{snap.paths.len}) catch return 1;
        out.appendSlice(s) catch return 1;
    } else if (std.mem.eql(u8, flags.template, "ci")) {
        const level: []const u8 = if (snap.cycles.items.len > 0) "High" else if (snap.arch.items.len > 0) "Medium" else "Low";
        const s = std.fmt.bufPrint(&b, "## ZigLens Analysis\n\nRisk: {s}\n\n", .{level}) catch return 1;
        out.appendSlice(s) catch return 1;
        const s2 = std.fmt.bufPrint(&b, "+ {d} files scanned\n+ {d} dependencies\n+ {d} architecture warnings\n", .{ snap.paths.len, snap.graph.edges.items.len, snap.arch.items.len + snap.cycles.items.len }) catch return 1;
        out.appendSlice(s2) catch return 1;
    } else {
        printErr(io, "Unknown template '{s}'. Use: default|security|architecture|technical-debt|executive|ci\n", .{flags.template});
        return 3;
    }
    emitOutput(io, flags, out.items) catch return 1;
    return 0;
}

// ---------------- serve ----------------
fn cmdServe(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    var snap = buildSnapshot(gpa, io, root, flags.quiet) catch return 1;
    defer snap.deinit();
    const js = buildProjectJson(gpa, io, &snap, root) catch return 1;
    defer gpa.free(js);

    // localhost only (Spec Sec.28). Refuse --host != localhost.
    const addr = std.Io.net.IpAddress{ .ip4 = .loopback(flags.port) };
    var server = addr.listen(io, .{ .reuse_address = true }) catch |err| {
        printErr(io, "Cannot bind 127.0.0.1:{d}: {t}\n", .{ flags.port, err });
        return 1;
    };
    defer server.deinit(io);
    printOut(io, "ZigLens dashboard: http://127.0.0.1:{d}  (root: {s}, Ctrl+C to stop)\n", .{ flags.port, root });

    while (true) {
        const stream = server.accept(io) catch |err| {
            if (flags.verbose) printErr(io, "accept: {t}\n", .{err});
            continue;
        };
        handleHttp(gpa, io, stream, &snap, root, js) catch |err| {
            if (flags.verbose) printErr(io, "http: {t}\n", .{err});
        };
        stream.close(io);
    }
}

fn groupOf(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |li| {
        if (li == 0) return ".";
        // top-level dir only for clustering
        if (std.mem.indexOfScalar(u8, path, '/')) |fi| return path[0..fi];
        return path[0..li];
    }
    return ".";
}

// Clustered graph JSON: directory groups + capped nodes/edges + table rows.
// Large-graph policy: cap nodes 500 / edges 1000, client lazy-expands.
fn buildGraphJson(gpa: std.mem.Allocator, snap: *Snapshot) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    // groups
    var groups = std.StringHashMap(struct { files: usize, out_e: usize }).init(gpa);
    defer groups.deinit();
    for (snap.paths) |p| {
        const g = groupOf(p);
        const e = try groups.getOrPut(g);
        if (!e.found_existing) e.value_ptr.* = .{ .files = 0, .out_e = 0 };
        e.value_ptr.files += 1;
    }
    // inter-group edges (dedup via map "a\x00b")
    var gedges = std.StringHashMap(void).init(gpa);
    defer gedges.deinit();
    var tmp: [1024]u8 = undefined;
    for (snap.graph.edges.items) |e| {
        if (e.external) continue;
        const ga = groupOf(snap.paths[e.from]);
        const gb = groupOf(snap.paths[e.to]);
        if (std.mem.eql(u8, ga, gb)) continue;
        const k = std.fmt.bufPrint(&tmp, "{s}\x00{s}", .{ ga, gb }) catch continue;
        _ = gedges.getOrPut(k) catch continue;
    }
    try out.appendSlice("{\"groups\":[");
    var git = groups.iterator();
    var gi: usize = 0;
    while (git.next()) |e| {
        if (gi > 0) try out.append(',');
        gi += 1;
        const nq = try report_util.jsonString(gpa, e.key_ptr.*);
        defer gpa.free(nq);
        var b: [96]u8 = undefined;
        const s = try std.fmt.bufPrint(&b, "{{\"name\":{s},\"files\":{d}}}", .{ nq, e.value_ptr.files });
        // nq embedded via {s} would double-escape; rebuild manually:
        _ = s;
        try out.appendSlice("{\"name\":");
        try out.appendSlice(nq);
        const s2 = try std.fmt.bufPrint(&b, ",\"files\":{d}}}", .{e.value_ptr.files});
        try out.appendSlice(s2);
    }
    try out.appendSlice("],\"group_edges\":[");
    var geit = gedges.iterator();
    var gei: usize = 0;
    while (geit.next()) |e| {
        if (gei > 0) try out.append(',');
        gei += 1;
        const k = e.key_ptr.*;
        const sep = std.mem.indexOfScalar(u8, k, 0) orelse continue;
        const a = try report_util.jsonString(gpa, k[0..sep]);
        defer gpa.free(a);
        const bb = try report_util.jsonString(gpa, k[sep + 1 ..]);
        defer gpa.free(bb);
        try out.appendSlice("{\"from\":");
        try out.appendSlice(a);
        try out.appendSlice(",\"to\":");
        try out.appendSlice(bb);
        try out.append('}');
    }
    // capped nodes + table rows (accessibility alternative)
    const ncap = @min(snap.paths.len, 500);
    try out.appendSlice("],\"nodes\":[");
    var i: usize = 0;
    while (i < ncap) : (i += 1) {
        if (i > 0) try out.append(',');
        const pq = try report_util.jsonString(gpa, snap.paths[i]);
        defer gpa.free(pq);
        const gq = try report_util.jsonString(gpa, groupOf(snap.paths[i]));
        defer gpa.free(gq);
        try out.appendSlice("{\"id\":");
        var b2: [32]u8 = undefined;
        const ids = try std.fmt.bufPrint(&b2, "{d}", .{i});
        try out.appendSlice(ids);
        try out.appendSlice(",\"path\":");
        try out.appendSlice(pq);
        try out.appendSlice(",\"group\":");
        try out.appendSlice(gq);
        try out.append('}');
    }
    const ecap = @min(snap.graph.edges.items.len, 1000);
    try out.appendSlice("],\"edges\":[");
    var j: usize = 0;
    while (j < ecap) : (j += 1) {
        if (j > 0) try out.append(',');
        const e = snap.graph.edges.items[j];
        var b3: [64]u8 = undefined;
        const s3 = try std.fmt.bufPrint(&b3, "{{\"from\":{d},\"to\":{d}}}", .{ e.from, e.to });
        try out.appendSlice(s3);
    }
    var b4: [128]u8 = undefined;
    const tail = try std.fmt.bufPrint(&b4, "],\"truncated\":{s}}}", .{if (snap.paths.len > ncap or snap.graph.edges.items.len > ecap) "true" else "false"});
    try out.appendSlice(tail);
    return out.toOwnedSlice();
}

// Treemap/heatmap data: size = LOC, heat = complexity. Capped 1000 files.
fn buildTreemapJson(gpa: std.mem.Allocator, snap: *Snapshot) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    var gloc = std.StringHashMap(usize).init(gpa);
    defer gloc.deinit();
    var gcx = std.StringHashMap(u64).init(gpa);
    defer gcx.deinit();
    var gfiles = std.StringHashMap(usize).init(gpa);
    defer gfiles.deinit();
    for (snap.res.files.items) |*f| {
        const g = groupOf(f.path);
        const le = try gloc.getOrPut(g);
        if (!le.found_existing) le.value_ptr.* = 0;
        const ce = try gcx.getOrPut(g);
        if (!ce.found_existing) ce.value_ptr.* = 0;
        const fe = try gfiles.getOrPut(g);
        if (!fe.found_existing) fe.value_ptr.* = 0;
        if (f.facts) |*facts| {
            le.value_ptr.* += facts.loc;
            ce.value_ptr.* += facts.complexity;
        }
        fe.value_ptr.* += 1;
    }
    try out.appendSlice("{\"groups\":[");
    var it = gloc.iterator();
    var gi: usize = 0;
    while (it.next()) |e| {
        if (gi > 0) try out.append(',');
        gi += 1;
        const nq = try report_util.jsonString(gpa, e.key_ptr.*);
        defer gpa.free(nq);
        try out.appendSlice("{\"name\":");
        try out.appendSlice(nq);
        var b: [96]u8 = undefined;
        const s = try std.fmt.bufPrint(&b, ",\"loc\":{d},\"cx\":{d},\"files\":{d}}}", .{ e.value_ptr.*, gcx.get(e.key_ptr.*) orelse 0, gfiles.get(e.key_ptr.*) orelse 0 });
        try out.appendSlice(s);
    }
    const fcap = @min(snap.res.files.items.len, 1000);
    try out.appendSlice("],\"files\":[");
    var i: usize = 0;
    while (i < fcap) : (i += 1) {
        if (i > 0) try out.append(',');
        const f = &snap.res.files.items[i];
        const pq = try report_util.jsonString(gpa, f.path);
        defer gpa.free(pq);
        const gq = try report_util.jsonString(gpa, groupOf(f.path));
        defer gpa.free(gq);
        var loc: usize = 0;
        var cx: u64 = 0;
        if (f.facts) |*facts| {
            loc = facts.loc;
            cx = facts.complexity;
        }
        try out.appendSlice("{\"path\":");
        try out.appendSlice(pq);
        try out.appendSlice(",\"group\":");
        try out.appendSlice(gq);
        var b2: [64]u8 = undefined;
        const s2 = try std.fmt.bufPrint(&b2, ",\"loc\":{d},\"cx\":{d}}}", .{ loc, cx });
        try out.appendSlice(s2);
    }
    try out.appendSlice("]}");
    return out.toOwnedSlice();
}

fn queryParam(target: []const u8, key: []const u8) ?[]const u8 {
    const qi = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    const qs = target[qi + 1 ..];
    var pairs = std.mem.splitSequence(u8, qs, "&");
    while (pairs.next()) |pr| {
        if (pr.len <= key.len) continue;
        if (std.mem.startsWith(u8, pr, key) and pr[key.len] == '=') return pr[key.len + 1 ..];
    }
    return null;
}

fn pctDecode(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hex = s[i + 1 .. i + 3];
            const v = std.fmt.parseInt(u8, hex, 16) catch {
                try out.append(s[i]);
                i += 1;
                continue;
            };
            try out.append(v);
            i += 3;
        } else if (s[i] == '+') {
            try out.append(' ');
            i += 1;
        } else {
            try out.append(s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

fn buildSymbolsJson(gpa: std.mem.Allocator, snap: *Snapshot) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    try out.appendSlice("{\"symbols\":[");
    var n: usize = 0;
    for (snap.res.files.items) |*f| {
        if (f.facts) |*facts| {
            for (facts.symbols.items) |*s| {
                if (n > 0) try out.append(',');
                const nq = try report_util.jsonString(gpa, s.name);
                defer gpa.free(nq);
                const fq = try report_util.jsonString(gpa, f.path);
                defer gpa.free(fq);
                try out.appendSlice("{\"name\":");
                try out.appendSlice(nq);
                try out.appendSlice(",\"kind\":\"");
                try out.appendSlice(s.kind.name());
                try out.appendSlice("\",\"file\":");
                try out.appendSlice(fq);
                var b: [32]u8 = undefined;
                const ln = try std.fmt.bufPrint(&b, ",\"line\":{d}}}", .{s.line});
                try out.appendSlice(ln);
                n += 1;
                if (n >= 500) break;
            }
        }
        if (n >= 500) break;
    }
    try out.appendSlice("]}");
    return out.toOwnedSlice();
}

fn buildDeadcodeJson(gpa: std.mem.Allocator, snap: *Snapshot) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    try out.appendSlice("{\"deadcode\":[");
    for (snap.dead.items, 0..) |*d, i| {
        if (i > 0) try out.append(',');
        const fq = try report_util.jsonString(gpa, d.file);
        defer gpa.free(fq);
        const nq = try report_util.jsonString(gpa, d.name);
        defer gpa.free(nq);
        const rq = try report_util.jsonString(gpa, d.reason);
        defer gpa.free(rq);
        try out.appendSlice("{\"file\":");
        try out.appendSlice(fq);
        try out.appendSlice(",\"name\":");
        try out.appendSlice(nq);
        var b: [128]u8 = undefined;
        const mid = try std.fmt.bufPrint(&b, ",\"kind\":\"{s}\",\"confidence\":\"{s}\",\"reason\":", .{ d.kind, analysis.confidenceName(d.confidence) });
        try out.appendSlice(mid);
        try out.appendSlice(rq);
        try out.append('}');
    }
    try out.appendSlice("]}");
    return out.toOwnedSlice();
}

fn buildComplexityJson(gpa: std.mem.Allocator, snap: *Snapshot) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    try out.appendSlice("{\"ranking\":[");
    const n = @min(snap.complexity.items.len, 100);
    for (snap.complexity.items[0..n], 0..) |*c, i| {
        if (i > 0) try out.append(',');
        const pq = try report_util.jsonString(gpa, c.path);
        defer gpa.free(pq);
        try out.appendSlice("{\"path\":");
        try out.appendSlice(pq);
        var b: [64]u8 = undefined;
        const s = try std.fmt.bufPrint(&b, ",\"complexity\":{d},\"loc\":{d},\"nesting\":{d}}}", .{ c.complexity, c.loc, c.nesting });
        try out.appendSlice(s);
    }
    try out.appendSlice("]}");
    return out.toOwnedSlice();
}

fn buildArchitectureJson(gpa: std.mem.Allocator, snap: *Snapshot) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    try out.appendSlice("{\"cycles\":[");
    for (snap.cycles.items, 0..) |*c, i| {
        if (i > 0) try out.append(',');
        try out.appendSlice("{\"path\":[");
        for (c.items, 0..) |node, j| {
            if (j > 0) try out.append(',');
            const pq = try report_util.jsonString(gpa, snap.paths[node]);
            defer gpa.free(pq);
            try out.appendSlice(pq);
        }
        try out.appendSlice("]}");
    }
    try out.appendSlice("],\"violations\":[");
    for (snap.arch.items, 0..) |*v, i| {
        if (i > 0) try out.append(',');
        const iq = try report_util.jsonString(gpa, v.id);
        defer gpa.free(iq);
        const mq = try report_util.jsonString(gpa, v.message);
        defer gpa.free(mq);
        try out.appendSlice("{\"id\":");
        try out.appendSlice(iq);
        var b: [32]u8 = undefined;
        const sev = try std.fmt.bufPrint(&b, ",\"severity\":\"{s}\",\"message\":", .{analysis.severityName(v.severity)});
        try out.appendSlice(sev);
        try out.appendSlice(mq);
        try out.append('}');
    }
    try out.appendSlice("]}");
    return out.toOwnedSlice();
}

fn buildSecurityJson(gpa: std.mem.Allocator, io: std.Io, snap: *Snapshot, root: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    try out.appendSlice("{\"findings\":[");
    const cwd = std.Io.Dir.cwd();
    var dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch {
        try out.appendSlice("]}");
        return out.toOwnedSlice();
    };
    defer dir.close(io);
    var n: usize = 0;
    var scanned: usize = 0;
    for (snap.paths) |p| {
        if (scanned >= 100) break;
        const content = dir.readFileAlloc(io, p, gpa, .limited(1024 * 1024)) catch continue;
        defer gpa.free(content);
        scanned += 1;
        var found = analysis.scanSecurity(gpa, p, content) catch continue;
        defer {
            for (found.items) |*f| gpa.free(f.masked);
            found.deinit();
        }
        for (found.items) |*fd| {
            if (n > 0) try out.append(',');
            const fq = try report_util.jsonString(gpa, fd.file);
            defer gpa.free(fq);
            const mq = try report_util.jsonString(gpa, fd.masked);
            defer gpa.free(mq);
            const iq = try report_util.jsonString(gpa, fd.id);
            defer gpa.free(iq);
            try out.appendSlice("{\"id\":");
            try out.appendSlice(iq);
            try out.appendSlice(",\"file\":");
            try out.appendSlice(fq);
            var b: [128]u8 = undefined;
            const mid = try std.fmt.bufPrint(&b, ",\"line\":{d},\"severity\":\"{s}\",\"evidence\":", .{ fd.line, analysis.severityName(fd.severity) });
            try out.appendSlice(mid);
            try out.appendSlice(mq);
            try out.append('}');
            n += 1;
            if (n >= 200) break;
        }
        if (n >= 200) break;
    }
    try out.appendSlice("]}");
    return out.toOwnedSlice();
}

fn buildGitJson(gpa: std.mem.Allocator, io: std.Io, snap: *Snapshot, root: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    var branch: []const u8 = "unknown";
    var branch_buf: ?[]u8 = null;
    defer if (branch_buf) |b| gpa.free(b);
    var commits: usize = 0;
    const cwd = std.Io.Dir.cwd();
    if (std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true })) |gd| {
        var gdir = gd;
        defer gdir.close(io);
        if (gdir.readFileAlloc(io, ".git/HEAD", gpa, .limited(1024))) |head| {
            defer gpa.free(head);
            const t = std.mem.trim(u8, head, " \t\r\n");
            if (std.mem.startsWith(u8, t, "ref: ")) {
                if (std.mem.lastIndexOfScalar(u8, t, '/')) |li| {
                    branch_buf = gpa.dupe(u8, t[li + 1 ..]) catch null;
                    if (branch_buf) |bb| branch = bb;
                }
            }
        } else |_| {}
        if (gdir.readFileAlloc(io, ".git/logs/HEAD", gpa, .limited(10 * 1024 * 1024))) |log| {
            defer gpa.free(log);
            var lines = std.mem.splitSequence(u8, log, "\n");
            while (lines.next()) |ln| {
                if (ln.len >= 10) commits += 1;
            }
        } else |_| {}
    } else |_| {}
    const bq = try report_util.jsonString(gpa, branch);
    defer gpa.free(bq);
    try out.appendSlice("{\"branch\":");
    try out.appendSlice(bq);
    var b: [64]u8 = undefined;
    const pre = try std.fmt.bufPrint(&b, ",\"commits\":{d},\"hotspots\":[", .{commits});
    try out.appendSlice(pre);
    // top-10 by dependents (insertion-ranked)
    var order = std.array_list.Managed(usize).init(gpa);
    defer order.deinit();
    for (0..snap.paths.len) |i| order.append(i) catch break;
    var shown: usize = 0;
    while (shown < order.items.len and shown < 10) {
        var best: usize = 0;
        var best_v: usize = 0;
        var first = true;
        for (order.items) |idx| {
            const v = snap.graph.rev.items[idx].items.len;
            if (first or v > best_v) {
                best = idx;
                best_v = v;
                first = false;
            }
        }
        // remove best
        var k: usize = 0;
        while (k < order.items.len) : (k += 1) {
            if (order.items[k] == best) {
                _ = order.orderedRemove(k);
                break;
            }
        }
        if (shown > 0) try out.append(',');
        const pq = try report_util.jsonString(gpa, snap.paths[best]);
        defer gpa.free(pq);
        try out.appendSlice("{\"path\":");
        try out.appendSlice(pq);
        const suf = try std.fmt.bufPrint(&b, ",\"dependents\":{d}}}", .{best_v});
        try out.appendSlice(suf);
        shown += 1;
        if (shown >= 10) break;
    }
    try out.appendSlice("]}");
    return out.toOwnedSlice();
}

fn buildImpactJson(gpa: std.mem.Allocator, snap: *Snapshot, fname: []const u8) ![]u8 {
    const idx = findFileIdx(snap, fname) orelse return try gpa.dupe(u8, "{\"error\":\"file not found in index\"}");
    var cx: u32 = 1;
    if (snap.res.files.items[idx].facts) |*f| cx = f.complexity;
    var imp = analysis.analyzeImpact(gpa, &snap.graph, snap.paths, idx, cx) catch return try gpa.dupe(u8, "{\"error\":\"impact failed\"}");
    defer imp.deinit();
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    const fq = try report_util.jsonString(gpa, snap.paths[idx]);
    defer gpa.free(fq);
    try out.appendSlice("{\"file\":");
    try out.appendSlice(fq);
    var b: [128]u8 = undefined;
    const pre = try std.fmt.bufPrint(&b, ",\"risk\":{d},\"direct\":{d},\"indirect\":{d},\"tests\":{d},\"reasons\":[", .{ imp.risk, imp.direct, imp.indirect, imp.tests });
    try out.appendSlice(pre);
    for (imp.reasons.items, 0..) |r, i| {
        if (i > 0) try out.append(',');
        const rq = try report_util.jsonString(gpa, r);
        defer gpa.free(rq);
        try out.appendSlice(rq);
    }
    try out.appendSlice("]}");
    return out.toOwnedSlice();
}

const ReportBody = struct { body: []u8, ctype: []const u8 };

fn buildReportBody(gpa: std.mem.Allocator, snap: *Snapshot, root: []const u8, fmt: []const u8) !ReportBody {
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    var b: [256]u8 = undefined;
    if (std.mem.eql(u8, fmt, "html")) {
        try out.appendSlice("<!DOCTYPE html><html><head><meta charset=utf-8><title>ZigLens Report</title></head><body>");
        const head = try std.fmt.bufPrint(&b, "<h1>ZigLens Report -- {s}</h1><p>Files {d} · Symbols {d}</p>", .{ root, snap.paths.len, snap.total_symbols });
        try out.appendSlice(head);
        try out.appendSlice("</body></html>");
        return .{ .body = try out.toOwnedSlice(), .ctype = "text/html; charset=utf-8" };
    }
    if (std.mem.eql(u8, fmt, "csv")) {
        try out.appendSlice("path,complexity,loc\n");
        for (snap.complexity.items) |*c| {
            const line = try std.fmt.bufPrint(&b, "{s},{d},{d}\n", .{ c.path, c.complexity, c.loc });
            try out.appendSlice(line);
        }
        return .{ .body = try out.toOwnedSlice(), .ctype = "text/csv; charset=utf-8" };
    }
    // default md
    const head = try std.fmt.bufPrint(&b, "# ZigLens Report -- {s}\n\nFiles: {d}, Symbols: {d}, Deps: {d}\n", .{ root, snap.paths.len, snap.total_symbols, snap.graph.edges.items.len });
    try out.appendSlice(head);
    return .{ .body = try out.toOwnedSlice(), .ctype = "text/markdown; charset=utf-8" };
}

fn handleHttp(gpa: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, snap: *Snapshot, root: []const u8, project_json: []const u8) !void {
    var rbuf: [8192]u8 = undefined;
    var wbuf: [8192]u8 = undefined;
    var reader = stream.reader(io, &rbuf);
    var writer = stream.writer(io, &wbuf);
    // read request head (first line)
    const line = try reader.interface.takeDelimiterExclusive('\n');
    const req_line = std.mem.trim(u8, line, " \t\r\n");
    var parts = std.mem.splitSequence(u8, req_line, " ");
    const method = parts.next() orelse "GET";
    const target = parts.next() orelse "/";
    _ = method;
    // route
    var body: []const u8 = "";
    var ctype: []const u8 = "application/json";
    var owned: ?[]u8 = null;
    defer if (owned) |b| gpa.free(b);

    if (std.mem.eql(u8, target, "/") or std.mem.eql(u8, target, "/index.html")) {
        body = dashboard.html();
        ctype = "text/html; charset=utf-8";
    } else if (std.mem.eql(u8, target, "/api/v1/project")) {
        body = project_json;
    } else if (std.mem.startsWith(u8, target, "/api/v1/search")) {
        // ?q=
        var q: []const u8 = "";
        if (std.mem.indexOfScalar(u8, target, '?')) |qi| {
            const qs = target[qi + 1 ..];
            if (std.mem.indexOf(u8, qs, "q=")) |qii| {
                q = qs[qii + 2 ..];
                if (std.mem.indexOfScalar(u8, q, '&')) |ai| q = q[0..ai];
            }
        }
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        out.appendSlice("{\"results\":[") catch return error.WriteFailed;
        var n: usize = 0;
        for (snap.paths) |p| {
            if (q.len == 0 or std.mem.indexOf(u8, p, q) != null) {
                if (n > 0) out.append(',') catch return error.WriteFailed;
                const pq = try report_util.jsonString(gpa, p);
                defer gpa.free(pq);
                out.appendSlice("{\"type\":\"file\",\"path\":") catch return error.WriteFailed;
                out.appendSlice(pq) catch return error.WriteFailed;
                out.append('}') catch return error.WriteFailed;
                n += 1;
                if (n >= 20) break;
            }
        }
        out.appendSlice("]}") catch return error.WriteFailed;
        owned = try out.toOwnedSlice();
        body = owned.?;
    } else if (std.mem.startsWith(u8, target, "/api/v1/graph")) {
        const gj = buildGraphJson(gpa, snap) catch return error.WriteFailed;
        owned = gj;
        body = owned.?;
    } else if (std.mem.eql(u8, target, "/api/v1/treemap")) {
        const tj = buildTreemapJson(gpa, snap) catch return error.WriteFailed;
        owned = tj;
        body = owned.?;
    } else if (std.mem.eql(u8, target, "/api/v1/symbols")) {
        const sj = buildSymbolsJson(gpa, snap) catch return error.WriteFailed;
        owned = sj;
        body = owned.?;
    } else if (std.mem.eql(u8, target, "/api/v1/deadcode")) {
        const dj = buildDeadcodeJson(gpa, snap) catch return error.WriteFailed;
        owned = dj;
        body = owned.?;
    } else if (std.mem.eql(u8, target, "/api/v1/complexity")) {
        const cj = buildComplexityJson(gpa, snap) catch return error.WriteFailed;
        owned = cj;
        body = owned.?;
    } else if (std.mem.eql(u8, target, "/api/v1/architecture")) {
        const aj = buildArchitectureJson(gpa, snap) catch return error.WriteFailed;
        owned = aj;
        body = owned.?;
    } else if (std.mem.eql(u8, target, "/api/v1/security")) {
        const sj = buildSecurityJson(gpa, io, snap, root) catch return error.WriteFailed;
        owned = sj;
        body = owned.?;
    } else if (std.mem.eql(u8, target, "/api/v1/git")) {
        const gj = buildGitJson(gpa, io, snap, root) catch return error.WriteFailed;
        owned = gj;
        body = owned.?;
    } else if (std.mem.startsWith(u8, target, "/api/v1/impact")) {
        const q = queryParam(target, "file");
        if (q == null) {
            const be = "{\"error\":\"missing ?file= parameter\"}";
            try writer.interface.print("HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ be.len, be });
            try writer.interface.flush();
            return;
        }
        const fname = pctDecode(gpa, q.?) catch return error.WriteFailed;
        defer gpa.free(fname);
        const ij = buildImpactJson(gpa, snap, fname) catch return error.WriteFailed;
        owned = ij;
        body = owned.?;
    } else if (std.mem.startsWith(u8, target, "/api/v1/report")) {
        const fmt = queryParam(target, "format") orelse "md";
        const rj = buildReportBody(gpa, snap, root, fmt) catch return error.WriteFailed;
        owned = rj.body;
        body = owned.?;
        ctype = rj.ctype;
    } else if (std.mem.eql(u8, target, "/api/v1/files") or std.mem.eql(u8, target, "/api/v1/dependencies")) {
        body = project_json; // backward-compat aliases
    } else {
        const nf = "{\"error\":\"not-found\"}";
        try writer.interface.print("HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ nf.len, nf });
        try writer.interface.flush();
        return;
    }
    try writer.interface.print("HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ ctype, body.len });
    try writer.interface.writeAll(body);
    try writer.interface.flush();
}

// ---------------- watch ----------------
fn cmdWatch(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    printOut(io, "Watching {s} (poll every 2s, incremental, Ctrl+C to stop)...\n", .{root});
    var prev_fp: u64 = 0;
    var iter: usize = 0;
    while (true) {
        const fp = quickFingerprint(gpa, io, root) catch 0;
        if (iter == 0 or fp != prev_fp) {
            var snap = buildSnapshot(gpa, io, root, true) catch {
                printErr(io, "scan failed\n", .{});
                return 1;
            };
            defer snap.deinit();
            printOut(io, "[{d}] files={d} symbols={d} deps={d}{s}\n", .{ iter, snap.paths.len, snap.total_symbols, snap.graph.edges.items.len, if (iter > 0) " (changed)" else "" });
            prev_fp = fp;
        }
        iter += 1;
        if (iter >= 3 and flags.json) break; // CI-friendly bound when --json
        io.sleep(.fromSeconds(2), .awake) catch {};
        if (iter > 1000000) break;
    }
    return 0;
}

// Cheap change fingerprint: walk + stat (size+mtime), no content reads.
fn quickFingerprint(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !u64 {
    const cwd = std.Io.Dir.cwd();
    var dir = try std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    var h: u64 = 0xcbf29ce484222325;
    var count: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const p: []const u8 = entry.path[0..entry.path.len];
        for (p) |c| {
            h ^= c;
            h *%= 0x100000001b3;
        }
        if (entry.dir.statFile(io, entry.basename, .{})) |st| {
            h ^= st.size;
            h *%= 0x100000001b3;
            const ns: u64 = @as(u64, @intCast(@max(st.mtime.nanoseconds, 0)));
            h ^= ns;
            h *%= 0x100000001b3;
        } else |_| {}
        count += 1;
        if (count > 200_000) break;
    }
    h ^= count;
    return h;
}

// ---------------- doctor/config ----------------
fn cmdDoctor(io: std.Io, flags: Flags) u8 {
    _ = flags;
    printOut(io, "ZigLens doctor\n", .{});
    printOut(io, "  zig: {s}\n", .{VERSION});
    // cwd
    var buf: [1024]u8 = undefined;
    if (std.process.currentPath(io, &buf)) |n| {
        printOut(io, "  cwd: {s}\n", .{buf[0..n]});
    } else |err| {
        printOut(io, "  cwd: ERROR {t}\n", .{err});
    }
    // .git
    const cwd = std.Io.Dir.cwd();
    if (cwd.access(io, ".git", .{})) {
        printOut(io, "  git: found .git\n", .{});
    } else |_| {
        printOut(io, "  git: no .git (git features limited)\n", .{});
    }
    // port
    printOut(io, "  dashboard default: http://127.0.0.1:4173 (localhost only: OK)\n", .{});
    printOut(io, "  network: OFF by default (serve binds 127.0.0.1)\n", .{});
    printOut(io, "  fs: read-only (no project files modified)\n", .{});
    printOut(io, "OK\n", .{});
    return 0;
}

fn cmdConfig(io: std.Io, flags: Flags) u8 {
    if (flags.json) {
        printOut(io, "{{\"lang\":\"{s}\",\"port\":{d},\"format\":\"{s}\"}}\n", .{ if (flags.lang == .id) "id" else "en", flags.port, flags.format });
    } else {
        printOut(io, "lang={s}\nport={d}\nformat={s}\nroot={s}\n", .{ if (flags.lang == .id) "id" else "en", flags.port, flags.format, flags.root });
        printOut(io, "# config file: .ziglens.toml (.ziglensignore supported)\n", .{});
    }
    return 0;
}

// ---------------- baseline / snapshot / compare / cache (Phase 2) ----------------
fn cmdBaseline(gpa: std.mem.Allocator, io: std.Io, def_root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    // usage: baseline create [root] | baseline [root]
    var target = def_root;
    if (positional.len >= 2) target = positional[1]
    else if (positional.len == 1 and !std.mem.eql(u8, positional[0], "create")) target = positional[0];
    var snap = buildSnapshot(gpa, io, target, flags.quiet) catch return 1;
    defer snap.deinit();
    var msgs = std.array_list.Managed([]const u8).init(gpa);
    defer msgs.deinit();
    for (snap.arch.items) |*a| msgs.append(a.message) catch {};
    store.saveBaseline(gpa, io, target, snap.cycles.items.len, snap.arch.items.len, snap.dead.items.len, snap.paths.len, snap.graph.edges.items.len, msgs.items) catch {
        printErr(io, "Failed to write .ziglens/baseline.json\n", .{});
        return 1;
    };
    if (!flags.quiet) printOut(io, "Baseline created: cycles={d} violations={d} dead={d} files={d} deps={d}\n", .{ snap.cycles.items.len, snap.arch.items.len, snap.dead.items.len, snap.paths.len, snap.graph.edges.items.len });
    return 0;
}

fn cmdSnapshot(gpa: std.mem.Allocator, io: std.Io, def_root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    var target = def_root;
    if (positional.len >= 2) target = positional[1]
    else if (positional.len == 1 and !std.mem.eql(u8, positional[0], "create")) target = positional[0];
    var snap = buildSnapshot(gpa, io, target, flags.quiet) catch return 1;
    defer snap.deinit();
    const js = buildProjectJson(gpa, io, &snap, target) catch return 1;
    defer gpa.free(js);
    const out = if (flags.output) |o| o else ".ziglens/snapshot.json";
    store.ensureDir(io) catch return 1;
    writeOutputFile(io, out, js) catch return 1;
    return 0;
}

fn cmdCompare(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    const base_opt = store.loadBaseline(gpa, io) catch null;    if (base_opt == null) {
        printErr(io, "No baseline. Run: ziglens baseline create {s}\n", .{root});
        return 1;
    }
    var b = base_opt.?;
    defer b.deinit();
    var snap = buildSnapshot(gpa, io, root, flags.quiet) catch return 1;
    defer snap.deinit();
    const new_v = snap.arch.items.len + snap.cycles.items.len;
    const old_v = b.violations + b.cycles;
    // drift: messages present now but absent in baseline
    var new_msgs = std.array_list.Managed([]const u8).init(gpa);
    defer new_msgs.deinit();
    for (snap.arch.items) |*a| {
        var known = false;
        for (b.msgs.items) |m| {
            if (std.mem.eql(u8, m, a.message)) {
                known = true;
                break;
            }
        }
        if (!known) new_msgs.append(a.message) catch {};
    }
    var removed: usize = 0;
    for (b.msgs.items) |m| {
        var still = false;
        for (snap.arch.items) |*a| {
            if (std.mem.eql(u8, m, a.message)) {
                still = true;
                break;
            }
        }
        if (!still) removed += 1;
    }
    if (flags.json) {
        printOut(io, "{{\"baseline\":{{\"violations\":{d},\"files\":{d},\"deps\":{d}}},\"current\":{{\"violations\":{d},\"files\":{d},\"deps\":{d}}},\"new\":{d},\"removed\":{d}}}\n", .{ old_v, b.files, b.deps, new_v, snap.paths.len, snap.graph.edges.items.len, new_msgs.items.len, removed });
    } else {
        printOut(io, "Baseline: violations={d} files={d} deps={d}\nCurrent:  violations={d} files={d} deps={d}\n", .{ old_v, b.files, b.deps, new_v, snap.paths.len, snap.graph.edges.items.len });
        if (new_msgs.items.len > 0) {
            printOut(io, "\nNew violations ({d}):\n", .{new_msgs.items.len});
            for (new_msgs.items) |m| printOut(io, "  + {s}\n", .{m});
        }
        if (removed > 0) printOut(io, "\nResolved since baseline: {d}\n", .{removed});
        if (new_msgs.items.len > 0) {
            printErr(io, "\nCI would FAIL (regression)\n", .{});
            return 2;
        }
        printOut(io, "No regression.\n", .{});
    }
    return 0;
}

// Scored refactor ranking shared by `analyze` and `top`.
fn scoredFixes(gpa: std.mem.Allocator, snap: *Snapshot) !std.array_list.Managed(analysis.FixItem) {
    const n = snap.paths.len;
    var cx = try gpa.alloc(u32, n);
    defer gpa.free(cx);
    var fanin = try gpa.alloc(usize, n);
    defer gpa.free(fanin);
    var viol = try gpa.alloc(usize, n);
    defer gpa.free(viol);
    var deadc = try gpa.alloc(usize, n);
    defer gpa.free(deadc);
    for (snap.paths, 0..) |_, i| {
        viol[i] = 0;
        deadc[i] = 0;
        fanin[i] = snap.graph.rev.items[i].items.len;
        if (snap.res.files.items[i].facts) |*f| cx[i] = f.complexity else cx[i] = 1;
    }
    var idxmap = std.StringHashMap(usize).init(gpa);
    defer idxmap.deinit();
    for (snap.paths, 0..) |p, i| idxmap.put(p, i) catch {};
    for (snap.arch.items) |*a| {
        for (snap.paths, 0..) |p, i| {
            if (std.mem.indexOf(u8, a.message, p) != null) {
                viol[i] += 1;
                break;
            }
        }
    }
    for (snap.dead.items) |*d| {
        if (idxmap.get(d.file)) |i| deadc[i] += 1;
    }
    return analysis.fixScores(gpa, cx, fanin, viol, deadc);
}

fn cxLevel(m: i18n.Msg, c: u32) []const u8 {
    if (c >= 50) return m.lvl_very_high;
    if (c >= 20) return m.lvl_high;
    if (c >= 10) return m.lvl_moderate;
    return m.lvl_low;
}

fn appendWhy(gpa: std.mem.Allocator, why: *std.array_list.Managed(u8), pattern: []const u8, value: usize, first: *bool) void {
    if (!first.*) why.appendSlice("; ") catch return;
    first.* = false;
    // patterns contain one {d}
    var buf: [160]u8 = undefined;
    var out_i: usize = 0;
    var i: usize = 0;
    while (i < pattern.len and out_i + 20 < buf.len) {
        if (pattern[i] == '{' and i + 2 < pattern.len and pattern[i + 1] == 'd' and pattern[i + 2] == '}') {
            const num = std.fmt.bufPrint(buf[out_i..], "{d}", .{value}) catch break;
            out_i += num.len;
            i += 3;
        } else {
            buf[out_i] = pattern[i];
            out_i += 1;
            i += 1;
        }
    }
    why.appendSlice(buf[0..out_i]) catch {};
    _ = gpa;
}

// Plain-language fix list: why it matters + what to do. No raw formulas.
fn renderFixes(gpa: std.mem.Allocator, io: std.Io, snap: *Snapshot, fixes: []const analysis.FixItem, n: usize, m: i18n.Msg) void {
    printOut(io, "\n{s}\n", .{m.fix_title});
    const count = @min(n, fixes.len);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const fx = fixes[i];
        if (fx.score == 0) break;
        const path = snap.paths[fx.idx];
        var c: u32 = 1;
        if (snap.res.files.items[fx.idx].facts) |*f| c = f.complexity;
        const deps = snap.graph.rev.items[fx.idx].items.len;
        var v: usize = 0;
        for (snap.arch.items) |*a| {
            if (std.mem.indexOf(u8, a.message, path) != null) v += 1;
        }
        var d: usize = 0;
        for (snap.dead.items) |*x| {
            if (std.mem.eql(u8, x.file, path)) d += 1;
        }
        var why = std.array_list.Managed(u8).init(gpa);
        defer why.deinit();
        var first = true;
        if (c >= 50) appendWhy(gpa, &why, m.wx_complex, c, &first) else if (c >= 20) appendWhy(gpa, &why, m.wx_fairly, c, &first) else if (c >= 10) appendWhy(gpa, &why, m.wx_growing, c, &first);
        if (deps > 0) appendWhy(gpa, &why, m.wx_deps, deps, &first);
        if (v > 0) appendWhy(gpa, &why, m.wx_viol, v, &first);
        if (d > 0) appendWhy(gpa, &why, m.wx_dead, d, &first);
        if (first) why.appendSlice(m.wx_small) catch {};
        const action: []const u8 = if (v > 0) m.do_layer else if (d > 0) m.do_delete else if (deps >= 5) m.do_careful else if (c >= 20) m.do_split else m.do_review;
        printOut(io, "{d}. {s} [{s}]\n   {s}: {s}\n   {s}: {s}\n", .{ i + 1, path, cxLevel(m, c), m.why_label, why.items, m.do_label, action });
    }
}

fn fixDetail(gpa: std.mem.Allocator, snap: *Snapshot, idx: usize) ![]u8 {
    var c: u32 = 1;
    if (snap.res.files.items[idx].facts) |*f| c = f.complexity;
    var v: usize = 0;
    for (snap.arch.items) |*a| {
        if (std.mem.indexOf(u8, a.message, snap.paths[idx]) != null) v += 1;
    }
    var d: usize = 0;
    for (snap.dead.items) |*x| {
        if (std.mem.eql(u8, x.file, snap.paths[idx])) d += 1;
    }
    return std.fmt.allocPrint(gpa, "cx {d}, dependents {d}, violations {d}, dead {d}", .{ c, snap.graph.rev.items[idx].items.len, v, d });
}

// Match changed repo-relative paths to snapshot indices (suffix match).
fn matchChanged(snap: *Snapshot, changed: []const []const u8) std.array_list.Managed(usize) {
    var out = std.array_list.Managed(usize).init(snap.allocator);
    for (changed) |c| {
        for (snap.paths, 0..) |p, i| {
            if (std.mem.eql(u8, p, c) or std.mem.endsWith(u8, p, c) or std.mem.endsWith(u8, c, p)) {
                var dup = false;
                for (out.items) |o| {
                    if (o == i) {
                        dup = true;
                        break;
                    }
                }
                if (!dup) out.append(i) catch break;
                break;
            }
        }
    }
    return out;
}

// Union of matched files + all transitive dependents.
fn diffAffected(gpa: std.mem.Allocator, snap: *Snapshot, matched: []const usize) !std.array_list.Managed(usize) {
    var seen = try gpa.alloc(bool, snap.paths.len);
    defer gpa.free(seen);
    @memset(seen, false);
    var out = std.array_list.Managed(usize).init(gpa);
    errdefer out.deinit();
    for (matched) |m| {
        if (!seen[m]) {
            seen[m] = true;
            try out.append(m);
        }
        var reach = try graphmod.reachable(gpa, &snap.graph, m, true);
        defer reach.deinit();
        for (reach.items) |r| {
            if (!seen[r]) {
                seen[r] = true;
                try out.append(r);
            }
        }
    }
    return out;
}

fn readFileCapped(gpa: std.mem.Allocator, io: std.Io, root: []const u8, dir: *std.Io.Dir, path: []const u8, cap: usize) ?[]u8 {
    _ = root;
    return dir.readFileAlloc(io, path, gpa, .limited(cap)) catch null;
}

fn cmdMap(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    const sub: []const u8 = if (positional.len > 0) positional[0] else "";
    if (!std.mem.eql(u8, sub, "api") and !std.mem.eql(u8, sub, "services") and !std.mem.eql(u8, sub, "config") and !std.mem.eql(u8, sub, "models")) {
        printErr(io, "Usage: ziglens map <api|services|config|models> [--json]\n", .{});
        return 3;
    }
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    const cwd = std.Io.Dir.cwd();
    var dir = std.Io.Dir.openDir(cwd, io, root, .{ .iterate = true }) catch return 1;
    defer dir.close(io);

    if (std.mem.eql(u8, sub, "api")) {
        var all = std.array_list.Managed(detectmod.Endpoint).init(gpa);
        defer {
            for (all.items) |*e| e.deinit(gpa);
            all.deinit();
        }
        for (snap.paths) |p| {
            const content = readFileCapped(gpa, io, root, &dir, p, 2 * 1024 * 1024) orelse continue;
            defer gpa.free(content);
            var eps = detectmod.scanEndpoints(gpa, p, content) catch continue;
            defer eps.deinit();
            for (eps.items) |*e| all.append(e.*) catch {
                gpa.free(e.method);
                gpa.free(e.path);
            };
            if (all.items.len > 500) break;
        }
        if (flags.json) {
            var out = std.array_list.Managed(u8).init(gpa);
            defer out.deinit();
            out.appendSlice("{\"endpoints\":[") catch return 1;
            for (all.items, 0..) |*e, i| {
                if (i > 0) out.append(',') catch return 1;
                const mq = report_util.jsonString(gpa, e.method) catch return 1;
                defer gpa.free(mq);
                const pq = report_util.jsonString(gpa, e.path) catch return 1;
                defer gpa.free(pq);
                const fq = report_util.jsonString(gpa, e.file) catch return 1;
                defer gpa.free(fq);
                out.appendSlice("{\"method\":") catch return 1;
                out.appendSlice(mq) catch return 1;
                out.appendSlice(",\"path\":") catch return 1;
                out.appendSlice(pq) catch return 1;
                out.appendSlice(",\"file\":") catch return 1;
                out.appendSlice(fq) catch return 1;
                var b: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&b, ",\"line\":{d}}}", .{e.line}) catch return 1;
                out.appendSlice(s) catch return 1;
            }
            out.appendSlice("]}") catch return 1;
            emitOutput(io, flags, out.items) catch return 1;
            return 0;
        }
        if (all.items.len == 0) printOut(io, "No API endpoints detected.\n", .{});
        for (all.items) |*e| printOut(io, "{s} {s}  ({s}:{d})\n", .{ e.method, e.path, e.file, e.line });
        return 0;
    }

    if (std.mem.eql(u8, sub, "services")) {
        var seen_svc = std.StringHashMap(void).init(gpa);
        defer seen_svc.deinit();
        if (flags.json) printOut(io, "{{\"services\":[", .{});
        var first = true;
        for (snap.paths) |p| {
            const content = readFileCapped(gpa, io, root, &dir, p, 2 * 1024 * 1024) orelse continue;
            defer gpa.free(content);
            var uses = detectmod.scanServices(gpa, p, content) catch continue;
            defer uses.deinit();
            for (uses.items) |*u| {
                if (flags.json) {
                    if (!first) printOut(io, ",", .{});
                    first = false;
                    printOut(io, "{{\"service\":\"{s}\",\"file\":\"{s}\",\"line\":{d}}}", .{ u.service, u.file, u.line });
                } else {
                    printOut(io, "{s} <- {s}:{d}\n", .{ u.service, u.file, u.line });
                }
                _ = seen_svc.getOrPut(u.service) catch {};
            }
        }
        if (flags.json) printOut(io, "]}}\n", .{});
        if (!flags.json and seen_svc.count() == 0) printOut(io, "No external services detected.\n", .{});
        return 0;
    }

    if (std.mem.eql(u8, sub, "config")) {
        var defined = std.array_list.Managed(detectmod.DotEnvKey).init(gpa);
        defer {
            for (defined.items) |*k| k.deinit(gpa);
            defined.deinit();
        }
        var uses = std.array_list.Managed(detectmod.EnvUse).init(gpa);
        defer {
            for (uses.items) |*u| u.deinit(gpa);
            uses.deinit();
        }
        for (snap.paths) |p| {
            const base = std.fs.path.basename(p);
            const is_env = std.mem.eql(u8, base, ".env") or std.mem.startsWith(u8, base, ".env.");
            const content = readFileCapped(gpa, io, root, &dir, p, 2 * 1024 * 1024) orelse continue;
            defer gpa.free(content);
            if (is_env) {
                var ks = detectmod.parseDotEnv(gpa, content) catch continue;
                defer ks.deinit();
                for (ks.items) |*k| defined.append(k.*) catch {
                    gpa.free(k.name);
                };
            } else {
                var us = detectmod.scanEnvUses(gpa, p, content) catch continue;
                defer us.deinit();
                for (us.items) |*u| uses.append(u.*) catch {
                    gpa.free(u.name);
                };
            }
            if (defined.items.len > 200 or uses.items.len > 500) break;
        }
        if (flags.json) {
            var out = std.array_list.Managed(u8).init(gpa);
            defer out.deinit();
            out.appendSlice("{\"defined\":[") catch return 1;
            for (defined.items, 0..) |*k, i| {
                if (i > 0) out.append(',') catch return 1;
                const nq = report_util.jsonString(gpa, k.name) catch return 1;
                defer gpa.free(nq);
                out.appendSlice("{\"name\":") catch return 1;
                out.appendSlice(nq) catch return 1;
                var b: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&b, ",\"line\":{d}}}", .{k.line}) catch return 1;
                out.appendSlice(s) catch return 1;
            }
            out.appendSlice("],\"uses\":[") catch return 1;
            for (uses.items, 0..) |*u, i| {
                if (i > 0) out.append(',') catch return 1;
                const nq = report_util.jsonString(gpa, u.name) catch return 1;
                defer gpa.free(nq);
                const fq = report_util.jsonString(gpa, u.file) catch return 1;
                defer gpa.free(fq);
                out.appendSlice("{\"name\":") catch return 1;
                out.appendSlice(nq) catch return 1;
                out.appendSlice(",\"file\":") catch return 1;
                out.appendSlice(fq) catch return 1;
                var b2: [32]u8 = undefined;
                const s2 = std.fmt.bufPrint(&b2, ",\"line\":{d}}}", .{u.line}) catch return 1;
                out.appendSlice(s2) catch return 1;
            }
            out.appendSlice("]}") catch return 1;
            emitOutput(io, flags, out.items) catch return 1;
            return 0;
        }
        printOut(io, "Defined (.env keys, values never shown): {d}\n", .{defined.items.len});
        for (defined.items) |*k| printOut(io, "  {s} (line {d})\n", .{ k.name, k.line });
        printOut(io, "Used in code: {d}\n", .{uses.items.len});
        for (uses.items) |*u| {
            var isdef = false;
            for (defined.items) |*k| {
                if (std.mem.eql(u8, k.name, u.name)) {
                    isdef = true;
                    break;
                }
            }
            printOut(io, "  {s} <- {s}:{d}{s}\n", .{ u.name, u.file, u.line, if (isdef) "" else " (UNDEFINED)" });
        }
        return 0;
    }

    // models
    var per_file = gpa.alloc(std.array_list.Managed([]u8), snap.paths.len) catch return 1;
    defer {
        for (per_file) |*l| {
            for (l.items) |n| gpa.free(n);
            l.deinit();
        }
        gpa.free(per_file);
    }
    for (per_file) |*l| l.* = std.array_list.Managed([]u8).init(gpa);
    for (snap.res.files.items, 0..) |*f, i| {
        if (f.facts) |*facts| {
            for (facts.symbols.items) |*s| {
                if (detectmod.isModelKind(s.kind)) {
                    per_file[i].append(gpa.dupe(u8, s.name) catch continue) catch continue;
                }
            }
        }
    }
    var einput = std.array_list.Managed(detectmod.Edge).init(gpa);
    defer einput.deinit();
    for (snap.graph.edges.items) |e| {
        if (!e.external) einput.append(.{ .from = e.from, .to = e.to }) catch break;
    }
    var rels = detectmod.findModelRels(gpa, snap.paths, per_file, einput.items) catch return 1;
    defer {
        for (rels.items) |*r| r.deinit(gpa);
        rels.deinit();
    }
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        out.appendSlice("{\"models\":[") catch return 1;
        var first = true;
        for (per_file, 0..) |*l, i| {
            for (l.items) |n| {
                if (!first) out.append(',') catch return 1;
                first = false;
                const nq = report_util.jsonString(gpa, n) catch return 1;
                defer gpa.free(nq);
                const fq = report_util.jsonString(gpa, snap.paths[i]) catch return 1;
                defer gpa.free(fq);
                out.appendSlice("{\"name\":") catch return 1;
                out.appendSlice(nq) catch return 1;
                out.appendSlice(",\"file\":") catch return 1;
                out.appendSlice(fq) catch return 1;
                out.append('}') catch return 1;
            }
        }
        out.appendSlice("],\"relations\":[") catch return 1;
        for (rels.items, 0..) |*r, i| {
            if (i > 0) out.append(',') catch return 1;
            const aq = report_util.jsonString(gpa, r.from_model) catch return 1;
            defer gpa.free(aq);
            const bq = report_util.jsonString(gpa, r.to_model) catch return 1;
            defer gpa.free(bq);
            out.appendSlice("{\"from\":") catch return 1;
            out.appendSlice(aq) catch return 1;
            out.appendSlice(",\"to\":") catch return 1;
            out.appendSlice(bq) catch return 1;
            out.appendSlice(",\"confidence\":\"LOW\"}") catch return 1;
        }
        out.appendSlice("]}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    printOut(io, "Models (class/struct/interface):\n", .{});
    for (per_file, 0..) |*l, i| {
        for (l.items) |n| printOut(io, "  {s} ({s})\n", .{ n, snap.paths[i] });
    }
    printOut(io, "\nRelations (LOW confidence, file-level):\n", .{});
    for (rels.items) |*r| printOut(io, "  {s} -> {s}  ({s} -> {s})\n", .{ r.from_model, r.to_model, r.from_file, r.to_file });
    return 0;
}

fn cmdTop(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags) u8 {
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    var fixes = scoredFixes(gpa, &snap) catch return 1;
    defer fixes.deinit();
    const n = @min(flags.top, fixes.items.len);
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        out.appendSlice("{\"ranking\":[") catch return 1;
        for (fixes.items[0..n], 0..) |*fx, i| {
            if (i > 0) out.append(',') catch return 1;
            const pq = report_util.jsonString(gpa, snap.paths[fx.idx]) catch return 1;
            defer gpa.free(pq);
            const det = fixDetail(gpa, &snap, fx.idx) catch "?";
            defer if (det.len > 1 or (det.len == 1 and det[0] != '?')) gpa.free(det);
            const dq = report_util.jsonString(gpa, det) catch return 1;
            defer gpa.free(dq);
            var b: [64]u8 = undefined;
            const pre = std.fmt.bufPrint(&b, "{{\"path\":", .{}) catch return 1;
            out.appendSlice(pre) catch return 1;
            out.appendSlice(pq) catch return 1;
            const mid = std.fmt.bufPrint(&b, ",\"score\":{d},\"detail\":", .{fx.score}) catch return 1;
            out.appendSlice(mid) catch return 1;
            out.appendSlice(dq) catch return 1;
            out.append('}') catch return 1;
        }
        out.appendSlice("]}") catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    renderFixes(gpa, io, &snap, fixes.items, n, i18n.msg(flags.lang));
    // duplicate-code hint
    var dups = similarmod.findDuplicates(gpa, io, root, snap.paths, 5) catch return 0;
    defer {
        for (dups.items) |*g| g.deinit(gpa);
        dups.deinit();
    }
    if (dups.items.len > 0) {
        printOut(io, "\nDuplicate blocks: {d} group(s) -- run full detail in roadmap; top:\n", .{dups.items.len});
        const m = @min(dups.items.len, 3);
        for (dups.items[0..m]) |*g| {
            printOut(io, "  [{s}] {d} lines x {d} locations, e.g. {s}:{d}\n", .{ g.confidence, g.lines, g.locs.items.len, g.locs.items[0].path, g.locs.items[0].line });
        }
    }
    return 0;
}

fn cmdDiff(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    var extra = std.array_list.Managed([]const u8).init(gpa);
    defer extra.deinit();
    var is_staged = false;
    for (positional) |p| {
        if (std.mem.eql(u8, p, "--cached") or std.mem.eql(u8, p, "cached") or std.mem.eql(u8, p, "--staged")) is_staged = true;
    }
    if (is_staged) {
        extra.append("diff") catch return 1;
        extra.append("--cached") catch return 1;
        extra.append("--name-only") catch return 1;
    } else if (positional.len >= 2) {
        extra.append("diff") catch return 1;
        extra.append("--name-only") catch return 1;
        extra.append(positional[0]) catch return 1;
        extra.append(positional[1]) catch return 1;
    } else {
        extra.append("diff") catch return 1;
        extra.append("--name-only") catch return 1;
        extra.append("HEAD") catch return 1;
    }
    var changed = gitmod.getChanged(gpa, io, root, extra.items) catch return 1;
    defer {
        for (changed.items) |p| gpa.free(p);
        changed.deinit();
    }
    if (changed.items.len == 0) {
        if (!flags.quiet) printErr(io, "No changed files.\n", .{});
        return 0;
    }
    var snap = buildSnapshot(gpa, io, root, true) catch return 1;
    defer snap.deinit();
    var matched = matchChanged(&snap, changed.items);
    defer matched.deinit();
    var affected = diffAffected(gpa, &snap, matched.items) catch return 1;
    defer affected.deinit();
    const level: []const u8 = if (affected.items.len >= 30) "HIGH" else if (affected.items.len >= 10) "MEDIUM" else "LOW";
    if (flags.json) {
        printOut(io, "{{\"changed\":{d},\"matched\":{d},\"affected\":{d},\"level\":\"{s}\"}}\n", .{ changed.items.len, matched.items.len, affected.items.len, level });
        return 0;
    }
    printOut(io, "Changed files: {d} (matched in index: {d})\n", .{ changed.items.len, matched.items.len });
    for (matched.items) |m| printOut(io, "  ~ {s}\n", .{snap.paths[m]});
    printOut(io, "Affected modules: {d}\nRisk: {s}\n", .{ affected.items.len, level });
    return 0;
}

fn cmdEvolution(gpa: std.mem.Allocator, io: std.Io, root: []const u8, flags: Flags, positional: [][]const u8) u8 {
    var max_n: usize = 200;
    for (positional, 0..) |p, i| {
        if ((std.mem.eql(u8, p, "--commits") or std.mem.eql(u8, p, "-n")) and i + 1 < positional.len) {
            max_n = std.fmt.parseInt(usize, positional[i + 1], 10) catch 200;
        }
    }
    if (flags.top != 20) max_n = flags.top * 10;
    var hist = gitmod.getHistory(gpa, io, root, @min(max_n, 500)) catch return 1;
    defer {
        for (hist.items) |*c| c.deinit(gpa);
        hist.deinit();
    }
    if (hist.items.len == 0) {
        printOut(io, "No git history found.\n", .{});
        return 0;
    }
    // authors
    var authors = std.StringHashMap(usize).init(gpa);
    defer authors.deinit();
    var months = std.StringHashMap(usize).init(gpa);
    defer months.deinit();
    for (hist.items) |*c| {
        const ae = authors.getOrPut(c.author) catch continue;
        if (!ae.found_existing) ae.value_ptr.* = 0;
        ae.value_ptr.* += 1;
        if (c.date.len >= 7) {
            const mk = c.date[0..7];
            const me = months.getOrPut(mk) catch continue;
            if (!me.found_existing) me.value_ptr.* = 0;
            me.value_ptr.* += 1;
        }
    }
    var churn = gitmod.churnByFile(gpa, hist.items) catch null;
    defer if (churn) |*ch| {
        for (ch.items) |*x| gpa.free(x.path);
        ch.deinit();
    };
    if (flags.json) {
        var out = std.array_list.Managed(u8).init(gpa);
        defer out.deinit();
        var b: [64]u8 = undefined;
        const pre = std.fmt.bufPrint(&b, "{{\"commits\":{d},\"authors\":{d}}}", .{ hist.items.len, authors.count() }) catch return 1;
        out.appendSlice(pre) catch return 1;
        emitOutput(io, flags, out.items) catch return 1;
        return 0;
    }
    printOut(io, "Evolution: {d} commits, {d} authors\n\nPer-month:\n", .{ hist.items.len, authors.count() });
    // sorted months
    var mkeys = std.array_list.Managed([]const u8).init(gpa);
    defer mkeys.deinit();
    var mit = months.iterator();
    while (mit.next()) |e| mkeys.append(e.key_ptr.*) catch break;
    std.mem.sort([]const u8, mkeys.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    var mmax: usize = 1;
    for (mkeys.items) |k| {
        const v = months.get(k) orelse 0;
        if (v > mmax) mmax = v;
    }
    for (mkeys.items) |k| {
        const v = months.get(k) orelse 0;
        const bars = v * 20 / mmax;
        printOut(io, "  {s} {d:4} ", .{ k, v });
        var bi: usize = 0;
        while (bi < bars) : (bi += 1) printOut(io, "#", .{});
        printOut(io, "\n", .{});
    }
    if (churn) |*ch| {
        printOut(io, "\nTop churned files:\n", .{});
        const n = @min(ch.items.len, 10);
        for (ch.items[0..n]) |*x| {
            // first(newest)/last(oldest) seen
            var first: []const u8 = "?";
            var last: []const u8 = "?";
            for (hist.items) |*c| {
                for (c.files.items) |f| {
                    if (std.mem.eql(u8, f, x.path)) {
                        if (std.mem.eql(u8, first, "?")) first = if (c.date.len >= 10) c.date[0..10] else c.date;
                        last = if (c.date.len >= 10) c.date[0..10] else c.date;
                    }
                }
            }
            printOut(io, "  {s} -- {d} commits ({s}..{s})\n", .{ x.path, x.commits, last, first });
        }
    }
    return 0;
}

fn cmdCache(gpa: std.mem.Allocator, io: std.Io, flags: Flags, positional: [][]const u8) u8 {
    _ = gpa;
    const sub: []const u8 = if (positional.len > 0) positional[0] else "clean";
    if (std.mem.eql(u8, sub, "clean")) {
        store.cleanCache(io) catch {
            printErr(io, "Cache clean failed\n", .{});
            return 1;
        };
        if (!flags.quiet) printOut(io, "Cache cleaned (.ziglens/ removed)\n", .{});
        return 0;
    }
    printErr(io, "Usage: ziglens cache clean\n", .{});
    return 3;
}

fn cmdPlugin(gpa: std.mem.Allocator, io: std.Io, flags: Flags, positional: [][]const u8) u8 {
    const sub: []const u8 = if (positional.len > 0) positional[0] else "list";
    if (std.mem.eql(u8, sub, "list")) {
        var reg = pluginmod.loadRegistry(gpa, io) catch return 1;
        defer {
            for (reg.items) |p| gpa.free(p);
            reg.deinit();
        }
        if (flags.json) {
            printOut(io, "{{\"plugins\":[", .{});
            for (reg.items, 0..) |p, i| {
                if (i > 0) printOut(io, ",", .{});
                printOut(io, "\"{s}\"", .{p});
            }
            printOut(io, "]}}\n", .{});
            return 0;
        }
        if (reg.items.len == 0) {
            printOut(io, "No plugins installed. (local only -- no registry; see docs for manifest format)\n", .{});
            return 0;
        }
        for (reg.items) |p| {
            // try manifest
            const cwd = std.Io.Dir.cwd();
            if (std.Io.Dir.openDir(cwd, io, p, .{ .iterate = true })) |pd| {
                var pdir = pd;
                defer pdir.close(io);
                if (pdir.readFileAlloc(io, "plugin.manifest", gpa, .limited(16 * 1024))) |raw| {
                    defer gpa.free(raw);
                    if (pluginmod.parseManifest(gpa, raw, p)) |m| {
                        var mm = m;
                        defer mm.deinit(gpa);
                        printOut(io, "{s} {s} by {s} [{s}] ({s})\n", .{ mm.name, mm.version, mm.author, mm.capabilities, mm.path });
                    } else |_| printErr(io, "{s} (manifest unreadable)\n", .{p});
                } else |_| printOut(io, "{s} (no plugin.manifest)\n", .{p});
            } else |_| printErr(io, "{s} (path not found)\n", .{p});
        }
        return 0;
    } else if (std.mem.eql(u8, sub, "install")) {
        if (positional.len < 2) {
            printErr(io, "Usage: ziglens plugin install <dir>\n", .{});
            return 3;
        }
        var reg = pluginmod.loadRegistry(gpa, io) catch return 1;
        defer {
            for (reg.items) |p| gpa.free(p);
            reg.deinit();
        }
        for (reg.items) |p| {
            if (std.mem.eql(u8, p, positional[1])) {
                printOut(io, "Already installed.\n", .{});
                return 0;
            }
        }
        reg.append(gpa.dupe(u8, positional[1]) catch return 1) catch return 1;
        // NOTE: reg owns dupes; saveRegistry borrows -- then free after save
        pluginmod.saveRegistry(gpa, io, reg.items) catch return 1;
        printOut(io, "Installed {s} (untrusted: review manifest permissions before use)\n", .{positional[1]});
        return 0;
    } else if (std.mem.eql(u8, sub, "remove")) {
        if (positional.len < 2) {
            printErr(io, "Usage: ziglens plugin remove <dir|name>\n", .{});
            return 3;
        }
        var reg = pluginmod.loadRegistry(gpa, io) catch return 1;
        defer {
            for (reg.items) |p| gpa.free(p);
            reg.deinit();
        }
        var kept = std.array_list.Managed([]const u8).init(gpa);
        defer kept.deinit();
        for (reg.items) |p| {
            if (!std.mem.eql(u8, p, positional[1])) kept.append(p) catch continue;
        }
        pluginmod.saveRegistry(gpa, io, kept.items) catch return 1;
        printOut(io, "Removed {s}\n", .{positional[1]});
        return 0;
    }
    printErr(io, "Usage: ziglens plugin <list|install|remove>\n", .{});
    return 3;
}

test {
    _ = @import("i18n.zig");
    _ = @import("language.zig");
    _ = @import("parser.zig");
    _ = @import("scanner.zig");
    _ = @import("graph.zig");
    _ = @import("analysis.zig");
    _ = @import("report_util.zig");
    _ = @import("dashboard.zig");
    _ = @import("store.zig");
    _ = @import("config.zig");
    _ = @import("git.zig");
    _ = @import("rules.zig");
    _ = @import("plugin.zig");
    _ = @import("detect.zig");
    _ = @import("similar.zig");
}
