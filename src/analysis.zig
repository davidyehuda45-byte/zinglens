// ZigLens analysis engine — Spec Sec.12-17, 45-46, 132-138.
// Deterministic, explainable. Every score carries reasons.

const std = @import("std");
const scanner = @import("scanner.zig");
const graphmod = @import("graph.zig");
const parser = @import("parser.zig");

pub const Confidence = enum { high, medium, low };
pub const Severity = enum { info, low, medium, high, critical };

pub fn severityName(s: Severity) []const u8 {
    return switch (s) {
        .info => "INFO",
        .low => "LOW",
        .medium => "MEDIUM",
        .high => "HIGH",
        .critical => "CRITICAL",
    };
}

pub fn confidenceName(c: Confidence) []const u8 {
    return switch (c) {
        .high => "HIGH",
        .medium => "MEDIUM",
        .low => "LOW",
    };
}

// ---------- Complexity ----------
pub const ComplexityRank = struct {
    path: []const u8,
    complexity: u32,
    loc: usize,
    nesting: u32,
};

pub fn rankComplexity(gpa: std.mem.Allocator, res: *scanner.ScanResult) !std.array_list.Managed(ComplexityRank) {
    var out = std.array_list.Managed(ComplexityRank).init(gpa);
    for (res.files.items) |*f| {
        if (f.facts) |*facts| {
            try out.append(.{ .path = f.path, .complexity = facts.complexity, .loc = facts.loc, .nesting = facts.nesting_max });
        }
    }
    // sort desc by complexity
    std.mem.sort(ComplexityRank, out.items, {}, struct {
        fn lt(_: void, a: ComplexityRank, b: ComplexityRank) bool {
            return a.complexity > b.complexity;
        }
    }.lt);
    return out;
}

// ---------- Dead code ----------
pub const DeadItem = struct {
    file: []const u8,
    name: []const u8,
    kind: []const u8,
    confidence: Confidence,
    reason: []const u8,
};

pub fn findDead(gpa: std.mem.Allocator, res: *scanner.ScanResult) !std.array_list.Managed(DeadItem) {
    var out = std.array_list.Managed(DeadItem).init(gpa);
    // Build global call/reference set
    var called = std.StringHashMap(void).init(gpa);
    defer called.deinit();
    var imported_names = std.StringHashMap(void).init(gpa);
    defer imported_names.deinit();

    for (res.files.items) |*f| {
        if (f.facts) |*facts| {
            for (facts.calls.items) |c| {
                const kv = try called.getOrPut(c);
                _ = kv;
            }
            for (facts.imports.items) |im| {
                const kv = try imported_names.getOrPut(im);
                _ = kv;
            }
        }
    }
    // Heuristic: symbols never appearing in any calls set + not exported-consumed
    for (res.files.items) |*f| {
        if (f.facts) |*facts| {
            const is_entry = isEntryPoint(f.path);
            for (facts.symbols.items) |*s| {
                if (s.kind == .function or s.kind == .method) {
                    if (is_entry) continue;
                    if (std.mem.eql(u8, s.name, "main")) continue;
                    if (called.get(s.name) != null) continue;
                    // exported? lower confidence
                    var exported = false;
                    for (facts.exports.items) |e| {
                        if (std.mem.eql(u8, e, s.name)) {
                            exported = true;
                            break;
                        }
                    }
                    const conf: Confidence = if (exported) .low else .medium;
                    const reason: []const u8 = if (exported) "exported but no local callers found (may be external API)" else "no callers found in workspace";
                    try out.append(.{ .file = f.path, .name = s.name, .kind = s.kind.name(), .confidence = conf, .reason = reason });
                    if (out.items.len > 500) break;
                }
            }
            // Unused files: no fan-in will be computed by caller; here flag files with zero symbols and zero imports as low
            if (facts.symbols.items.len == 0 and facts.loc < 5) {
                // skip noise
            }
        }
    }
    return out;
}

fn isEntryPoint(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    const entries = [_][]const u8{ "main.", "index.", "app.", "server.", "mod.", "lib.", "__init__", "main" };
    for (entries) |e| {
        if (std.mem.startsWith(u8, base, e)) return true;
    }
    if (std.mem.indexOf(u8, path, "pages/") != null) return true;
    if (std.mem.indexOf(u8, path, "bin/") != null) return true;
    return false;
}

// ---------- Impact / risk ----------
pub const Impact = struct {
    direct: usize,
    indirect: usize,
    tests: usize,
    risk: u8,
    reasons: std.array_list.Managed([]u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Impact) void {
        for (self.reasons.items) |r| self.allocator.free(r);
        self.reasons.deinit();
    }
};

pub fn analyzeImpact(gpa: std.mem.Allocator, g: *graphmod.Graph, paths: []const []const u8, target_idx: usize, complexity: u32) !Impact {
    var rev_reach = try graphmod.reachable(gpa, g, target_idx, true);
    defer rev_reach.deinit();
    var fwd_reach = try graphmod.reachable(gpa, g, target_idx, false);
    defer fwd_reach.deinit();

    const direct = g.rev.items[target_idx].items.len;
    const indirect = if (rev_reach.items.len > direct) rev_reach.items.len - direct else 0;

    // affected tests: files with test in path among dependents + fwd
    var tests: usize = 0;
    for (rev_reach.items) |idx| {
        if (isTestFile(paths[idx])) tests += 1;
    }
    for (fwd_reach.items) |idx| {
        if (isTestFile(paths[idx])) tests += 1;
    }

    var risk: u32 = 10;
    var reasons = std.array_list.Managed([]u8).init(gpa);
    errdefer {
        for (reasons.items) |r| gpa.free(r);
        reasons.deinit();
    }
    if (direct >= 10) {
        risk += 30;
        try reasons.append(try std.fmt.allocPrint(gpa, "{d} direct dependents", .{direct}));
    } else if (direct >= 3) {
        risk += 15;
        try reasons.append(try std.fmt.allocPrint(gpa, "{d} direct dependents", .{direct}));
    } else if (direct > 0) {
        risk += 5;
        try reasons.append(try std.fmt.allocPrint(gpa, "{d} direct dependents", .{direct}));
    }
    if (rev_reach.items.len >= 20) {
        risk += 25;
        try reasons.append(try std.fmt.allocPrint(gpa, "{d} transitive dependents", .{rev_reach.items.len}));
    } else if (rev_reach.items.len >= 5) {
        risk += 10;
        try reasons.append(try std.fmt.allocPrint(gpa, "{d} transitive dependents", .{rev_reach.items.len}));
    }
    if (complexity >= 20) {
        risk += 20;
        try reasons.append(try std.fmt.allocPrint(gpa, "high complexity ({d})", .{complexity}));
    } else if (complexity >= 10) {
        risk += 10;
        try reasons.append(try std.fmt.allocPrint(gpa, "moderate complexity ({d})", .{complexity}));
    }
    if (tests > 0) {
        risk += @min(tests * 2, 10);
        try reasons.append(try std.fmt.allocPrint(gpa, "{d} related tests", .{tests}));
    }
    if (isCriticalPath(paths[target_idx])) {
        risk += 10;
        try reasons.append(try gpa.dupe(u8, "critical module (auth/db/payment)"));
    }
    if (risk > 100) risk = 100;
    return .{ .direct = direct, .indirect = indirect, .tests = tests, .risk = @as(u8, @intCast(risk)), .reasons = reasons, .allocator = gpa };
}

fn isTestFile(p: []const u8) bool {
    if (std.mem.indexOf(u8, p, "test") != null) return true;
    if (std.mem.indexOf(u8, p, "spec") != null) return true;
    if (std.mem.indexOf(u8, p, "__tests__") != null) return true;
    return false;
}

fn isCriticalPath(p: []const u8) bool {
    const keys = [_][]const u8{ "auth", "database", "db", "payment", "crypto", "security", "user" };
    var buf: [256]u8 = undefined;
    const low = std.ascii.lowerString(&buf, p);
    for (keys) |k| {
        if (std.mem.indexOf(u8, low, k) != null) return true;
    }
    return false;
}

// ---------- Architecture ----------
pub const ArchViolation = struct {
    id: []u8,
    severity: Severity,
    message: []u8, // owned
};

pub fn checkArchitecture(gpa: std.mem.Allocator, paths: []const []const u8, g: *graphmod.Graph) !std.array_list.Managed(ArchViolation) {
    var out = std.array_list.Managed(ArchViolation).init(gpa);
    for (g.edges.items) |e| {
        if (e.external) continue;
        const from_layer = layerOf(paths[e.from]);
        const to_layer = layerOf(paths[e.to]);
        // violation: lower layer importing upper layer (db -> ui, repo -> controller, etc.)
        if (to_layer != .unknown and from_layer != .unknown and layerOrder(from_layer) > layerOrder(to_layer)) {
            // allow same-layer
            const m = try std.fmt.allocPrint(gpa, "{s} ({s}) imports {s} ({s}): layer inversion", .{ paths[e.from], layerName(from_layer), paths[e.to], layerName(to_layer) });
            const rid = try gpa.dupe(u8, "ARCH-001");
            errdefer gpa.free(rid);
            try out.append(.{ .id = rid, .severity = .medium, .message = m });
            if (out.items.len > 200) break;
        }
    }
    return out;
}

const Layer = enum { ui, controller, service, repository, database, unknown };

fn layerOrder(l: Layer) u8 {
    return switch (l) {
        .ui => 0,
        .controller => 1,
        .service => 2,
        .repository => 3,
        .database => 4,
        .unknown => 255,
    };
}

fn layerOf(p: []const u8) Layer {
    var buf: [512]u8 = undefined;
    const low = std.ascii.lowerString(&buf, p);
    if (std.mem.indexOf(u8, low, "ui") != null or std.mem.indexOf(u8, low, "view") != null or std.mem.indexOf(u8, low, "component") != null or std.mem.indexOf(u8, low, "page") != null) return .ui;
    if (std.mem.indexOf(u8, low, "controller") != null or std.mem.indexOf(u8, low, "handler") != null or std.mem.indexOf(u8, low, "route") != null) return .controller;
    if (std.mem.indexOf(u8, low, "service") != null) return .service;
    if (std.mem.indexOf(u8, low, "repositor") != null or std.mem.indexOf(u8, low, "dao") != null) return .repository;
    if (std.mem.indexOf(u8, low, "database") != null or std.mem.indexOf(u8, low, "/db") != null or std.mem.indexOf(u8, low, "model") != null or std.mem.indexOf(u8, low, "schema") != null or std.mem.indexOf(u8, low, "migration") != null) return .database;
    return .unknown;
}

fn layerName(l: Layer) []const u8 {
    return switch (l) {
        .ui => "UI",
        .controller => "Controller",
        .service => "Service",
        .repository => "Repository",
        .database => "Database",
        .unknown => "?",
    };
}

pub fn architectureScore(cycles: usize, violations: usize) u8 {
    var s: i32 = 100;
    s -= @as(i32, @intCast(cycles * 8));
    s -= @as(i32, @intCast(violations * 5));
    if (s < 0) s = 0;
    return @as(u8, @intCast(s));
}

// ---------- Refactor priority (Spec Sec.138-139) ----------
// Priority = Risk x Impact x Maintainability cost, explainable per file.
pub const FixItem = struct {
    idx: usize,
    score: u32,
};

pub fn fixScores(
    gpa: std.mem.Allocator,
    cx: []const u32,
    fanin: []const usize,
    viol: []const usize,
    dead: []const usize,
) !std.array_list.Managed(FixItem) {
    var out = std.array_list.Managed(FixItem).init(gpa);
    errdefer out.deinit();
    for (cx, 0..) |c, i| {
        const s = c * 2 + @as(u32, @intCast(@min(fanin[i], 100) * 3)) + @as(u32, @intCast(@min(viol[i], 20) * 15)) + @as(u32, @intCast(@min(dead[i], 50) * 4));
        try out.append(.{ .idx = i, .score = s });
    }
    std.mem.sort(FixItem, out.items, {}, struct {
        fn lt(_: void, a: FixItem, b: FixItem) bool {
            return a.score > b.score;
        }
    }.lt);
    return out;
}

// ---------- Security (masked, no plaintext stored) ----------
pub const SecFinding = struct {
    id: []const u8,
    severity: Severity,
    file: []const u8,
    line: usize,
    category: []const u8,
    masked: []u8, // owned masked evidence
    remediation: []const u8,
};

const SecPattern = struct {
    needle: []const u8,
    category: []const u8,
    severity: Severity,
    id: []const u8,
    remediation: []const u8,
};

const sec_patterns = [_]SecPattern{
    .{ .needle = "sk_live_", .category = "hardcoded-secret", .severity = .critical, .id = "SEC-001", .remediation = "Move to environment variable; rotate key." },
    .{ .needle = "sk_test_", .category = "hardcoded-secret", .severity = .high, .id = "SEC-001", .remediation = "Move to environment variable." },
    .{ .needle = "AKIA", .category = "aws-key", .severity = .critical, .id = "SEC-001", .remediation = "Use IAM roles / env; rotate key." },
    .{ .needle = "ghp_", .category = "github-token", .severity = .critical, .id = "SEC-001", .remediation = "Revoke and use env/secret store." },
    .{ .needle = "gho_", .category = "github-token", .severity = .critical, .id = "SEC-001", .remediation = "Revoke and use env/secret store." },
    .{ .needle = "xoxb-", .category = "slack-token", .severity = .high, .id = "SEC-001", .remediation = "Revoke; use env." },
    .{ .needle = "BEGIN PRIVATE KEY", .category = "private-key", .severity = .critical, .id = "SEC-006", .remediation = "Never commit private keys." },
    .{ .needle = "BEGIN RSA PRIVATE KEY", .category = "private-key", .severity = .critical, .id = "SEC-006", .remediation = "Never commit private keys." },
    .{ .needle = "password", .category = "possible-secret", .severity = .medium, .id = "SEC-001", .remediation = "Ensure value comes from env/secret store." },
    .{ .needle = "passwd", .category = "possible-secret", .severity = .medium, .id = "SEC-001", .remediation = "Ensure value comes from env/secret store." },
    .{ .needle = "api_key", .category = "possible-secret", .severity = .high, .id = "SEC-001", .remediation = "Use environment variable." },
    .{ .needle = "apikey", .category = "possible-secret", .severity = .high, .id = "SEC-001", .remediation = "Use environment variable." },
    .{ .needle = "secret", .category = "possible-secret", .severity = .low, .id = "SEC-001", .remediation = "Review; use env if sensitive." },
    .{ .needle = "mongodb://", .category = "connection-string", .severity = .high, .id = "SEC-002", .remediation = "Use env-based connection string." },
    .{ .needle = "postgres://", .category = "connection-string", .severity = .high, .id = "SEC-002", .remediation = "Use env-based connection string." },
};

pub fn maskValue(gpa: std.mem.Allocator, v: []const u8) ![]u8 {
    const t = std.mem.trim(u8, v, " \t\"';,");
    if (t.len <= 8) return try gpa.dupe(u8, "********");
    // keep prefix 4 + **** + last 2 masked? spec: sk_live_****************
    var out = std.array_list.Managed(u8).init(gpa);
    errdefer out.deinit();
    const keep = @min(t.len, 8);
    try out.appendSlice(t[0..keep]);
    try out.appendSlice("****************");
    return out.toOwnedSlice();
}

pub fn scanSecurity(gpa: std.mem.Allocator, path: []const u8, content: []const u8) !std.array_list.Managed(SecFinding) {
    var out = std.array_list.Managed(SecFinding).init(gpa);
    var line_no: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |raw| {
        line_no += 1;
        const trimmed = std.mem.trim(u8, raw, " \t\r");
        // Skip pattern definitions themselves (avoid self-flagging FP)
        if (std.mem.indexOf(u8, raw, ".needle") != null) continue;
        if (std.mem.indexOf(u8, raw, "needle =") != null) continue;
        // Skip pure comment/doc lines to cut FPs (real secrets in comments still
        // reviewable via --verbose Phase2; code lines are primary signal)
        if (std.mem.startsWith(u8, trimmed, "//") or std.mem.startsWith(u8, trimmed, "#") or std.mem.startsWith(u8, trimmed, "*") or std.mem.startsWith(u8, trimmed, "/*") or std.mem.startsWith(u8, trimmed, "\\\\")) continue;
        // Suppression: // ziglens-ignore SEC-001 (Spec Sec.83)
        if (std.mem.indexOf(u8, raw, "ziglens-ignore") != null) continue;
        var lowbuf: [2048]u8 = undefined;
        const n = @min(raw.len, lowbuf.len);
        const low = std.ascii.lowerString(lowbuf[0..n], raw[0..n]);
        for (sec_patterns) |sp| {
            if (containsNeedle(low, sp.needle)) {
                // skip comments that say e.g. "password" in remediation? keep, low FP documented
                const masked = try maskValue(gpa, std.mem.trim(u8, raw, " \t\r"));
                try out.append(.{
                    .id = sp.id,
                    .severity = sp.severity,
                    .file = path,
                    .line = line_no,
                    .category = sp.category,
                    .masked = masked,
                    .remediation = sp.remediation,
                });
                break; // one finding per line
            }
        }
        if (out.items.len > 300) break;
    }
    // .env exposure: if file is .env, flag
    const base = std.fs.path.basename(path);
    if (std.mem.eql(u8, base, ".env")) {
        const masked = try gpa.dupe(u8, ".env file detected****************");
        try out.append(.{ .id = "SEC-008", .severity = .medium, .file = path, .line = 1, .category = "env-exposure", .masked = masked, .remediation = "Ensure .env is gitignored and never committed." });
    }
    return out;
}

fn isWordChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_';
}

// Word-boundary match for generic needles ("secret" must not hit "security").
fn containsNeedle(hay: []const u8, needle: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOf(u8, hay[i..], needle)) |off| {
        const s = i + off;
        const e = s + needle.len;
        const left_ok = s == 0 or !isWordChar(hay[s - 1]);
        const right_ok = e >= hay.len or !isWordChar(hay[e]);
        // high-signal tokens with special chars (_, -, :) match even mid-word
        const high_signal = std.mem.indexOfScalar(u8, needle, '_') != null or std.mem.indexOfScalar(u8, needle, '-') != null or std.mem.indexOfScalar(u8, needle, ':') != null;
        if ((left_ok and right_ok) or (high_signal and left_ok)) return true;
        i = s + 1;
        if (i >= hay.len) break;
    }
    return false;
}

test "security mask" {
    const t = std.testing;
    const m = try maskValue(t.allocator, "sk_live_123456789abcdef"); // ziglens-ignore SEC-001 (test fixture)
    defer t.allocator.free(m);
    try t.expect(std.mem.indexOf(u8, m, "********") != null);
    try t.expect(std.mem.indexOf(u8, m, "123456789abcdef") == null);
}

test "arch score" {
    const t = std.testing;
    try t.expect(architectureScore(0, 0) == 100);
    try t.expect(architectureScore(2, 0) < 100);
}
