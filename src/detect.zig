// ZigLens detection maps — Spec Sec.90-93.
// Heuristic, offline, explainable (LOW confidence where inference is weak):
// REST endpoints, external services, env/config map, model relationships.

const std = @import("std");
const parser = @import("parser.zig");

pub const Endpoint = struct {
    method: []u8,
    path: []u8,
    file: []const u8,
    line: usize,

    pub fn deinit(self: *Endpoint, gpa: std.mem.Allocator) void {
        gpa.free(self.method);
        gpa.free(self.path);
    }
};

const RoutePat = struct { needle: []const u8, method: []const u8 };

const route_pats = [_]RoutePat{
    .{ .needle = "app.get(", .method = "GET" },
    .{ .needle = "app.post(", .method = "POST" },
    .{ .needle = "app.put(", .method = "PUT" },
    .{ .needle = "app.delete(", .method = "DELETE" },
    .{ .needle = "app.patch(", .method = "PATCH" },
    .{ .needle = "router.get(", .method = "GET" },
    .{ .needle = "router.post(", .method = "POST" },
    .{ .needle = "router.put(", .method = "PUT" },
    .{ .needle = "router.delete(", .method = "DELETE" },
    .{ .needle = "router.patch(", .method = "PATCH" },
    .{ .needle = "@app.get(", .method = "GET" },
    .{ .needle = "@app.post(", .method = "POST" },
    .{ .needle = "@app.put(", .method = "PUT" },
    .{ .needle = "@app.delete(", .method = "DELETE" },
    .{ .needle = "@app.route(", .method = "ANY" },
    .{ .needle = "@router.get(", .method = "GET" },
    .{ .needle = "@router.post(", .method = "POST" },
    .{ .needle = "@router.put(", .method = "PUT" },
    .{ .needle = "@router.delete(", .method = "DELETE" },
    .{ .needle = "route::get(", .method = "GET" },
    .{ .needle = "route::post(", .method = "POST" },
    .{ .needle = "route::put(", .method = "PUT" },
    .{ .needle = "route::delete(", .method = "DELETE" },
    .{ .needle = "route::patch(", .method = "PATCH" },
    .{ .needle = "@getmapping(", .method = "GET" },
    .{ .needle = "@postmapping(", .method = "POST" },
    .{ .needle = "@putmapping(", .method = "PUT" },
    .{ .needle = "@deletemapping(", .method = "DELETE" },
    .{ .needle = "@requestmapping(", .method = "REQ" },
    .{ .needle = ".handlefunc(", .method = "HANDLE" },
    .{ .needle = "[httpget", .method = "GET" },
    .{ .needle = "[httppost", .method = "POST" },
    .{ .needle = "[httpput", .method = "PUT" },
    .{ .needle = "[httpdelete", .method = "DELETE" },
};

fn firstQuoted(gpa: std.mem.Allocator, line: []const u8) !?[]u8 {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const q = line[i];
        if (q == '\'' or q == '"') {
            var j = i + 1;
            while (j < line.len and line[j] != q) : (j += 1) {}
            if (j < line.len and j > i + 1) return try gpa.dupe(u8, line[i + 1 .. j]);
            return null;
        }
    }
    return null;
}

pub fn scanEndpoints(gpa: std.mem.Allocator, file: []const u8, content: []const u8) !std.array_list.Managed(Endpoint) {
    var out = std.array_list.Managed(Endpoint).init(gpa);
    errdefer {
        for (out.items) |*e| e.deinit(gpa);
        out.deinit();
    }
    var line_no: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    var lowbuf: [512]u8 = undefined;
    while (lines.next()) |raw| {
        line_no += 1;
        const n = @min(raw.len, 500);
        const low = std.ascii.lowerString(lowbuf[0..n], raw[0..n]);
        var method: ?[]const u8 = null;
        for (route_pats) |rp| {
            if (std.mem.indexOf(u8, low, rp.needle) != null) {
                method = rp.method;
                break;
            }
        }
        // Rails-style: `get '/path'`
        if (method == null) {
            const verbs = [_][]const u8{ "get ", "post ", "put ", "patch ", "delete " };
            for (verbs) |v| {
                if (std.mem.startsWith(u8, low, v)) {
                    const rest = std.mem.trim(u8, low[v.len..], " \t");
                    if (rest.len > 0 and (rest[0] == '\'' or rest[0] == '"' or rest[0] == '/')) {
                        method = v[0 .. v.len - 1];
                        break;
                    }
                }
            }
            if (method) |m| {
                _ = m;
                // upper-case it below via dup
            }
        }
        if (method) |m| {
            const p = (try firstQuoted(gpa, raw[0..n])) orelse try gpa.dupe(u8, "?");
            var mup: [8]u8 = undefined;
            const ml = std.ascii.upperString(mup[0..@min(m.len, 8)], m[0..@min(m.len, 8)]);
            out.append(.{
                .method = try gpa.dupe(u8, ml),
                .path = p,
                .file = file,
                .line = line_no,
            }) catch {
                gpa.free(p);
                break;
            };
            if (out.items.len > 500) break;
        }
    }
    return out;
}

pub const ServiceUse = struct {
    service: []const u8,
    file: []const u8,
    line: usize,
};

const SvcPat = struct { service: []const u8, needles: []const []const u8 };

const svc_pats = [_]SvcPat{
    .{ .service = "PostgreSQL", .needles = &[_][]const u8{ "postgres", "pg-pool", "typeorm", "sequelize", "diesel", "psycopg", "database_url" } },
    .{ .service = "MySQL", .needles = &[_][]const u8{ "mysql", "mysqli", "pymysql" } },
    .{ .service = "Redis", .needles = &[_][]const u8{ "redis", "RQ", "bullmq" } },
    .{ .service = "MongoDB", .needles = &[_][]const u8{ "mongo", "mongoose" } },
    .{ .service = "Stripe", .needles = &[_][]const u8{"stripe"} },
    .{ .service = "AWS", .needles = &[_][]const u8{ "aws-sdk", "amazonaws", "boto3", "s3client" } },
    .{ .service = "RabbitMQ", .needles = &[_][]const u8{ "amqp", "rabbitmq" } },
    .{ .service = "Kafka", .needles = &[_][]const u8{"kafka"} },
    .{ .service = "SMTP", .needles = &[_][]const u8{ "smtp", "nodemailer", "sendgrid", "mailgun", "phpmailer" } },
    .{ .service = "Firebase", .needles = &[_][]const u8{"firebase"} },
    .{ .service = "GraphQL", .needles = &[_][]const u8{ "graphql", "apollo" } },
    .{ .service = "OpenAI", .needles = &[_][]const u8{ "openai", "anthropic" } },
};

pub fn scanServices(gpa: std.mem.Allocator, file: []const u8, content: []const u8) !std.array_list.Managed(ServiceUse) {
    var out = std.array_list.Managed(ServiceUse).init(gpa);
    var line_no: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    var lowbuf: [512]u8 = undefined;
    while (lines.next()) |raw| {
        line_no += 1;
        const n = @min(raw.len, 500);
        const low = std.ascii.lowerString(lowbuf[0..n], raw[0..n]);
        for (svc_pats) |sp| {
            for (sp.needles) |nd| {
                if (std.mem.indexOf(u8, low, nd) != null) {
                    // one hit per service per line
                    var dup = false;
                    for (out.items) |*o| {
                        if (o.line == line_no and o.service.ptr == sp.service.ptr) {
                            dup = true;
                            break;
                        }
                    }
                    if (!dup) try out.append(.{ .service = sp.service, .file = file, .line = line_no });
                    break;
                }
            }
            if (out.items.len > 500) break;
        }
    }
    return out;
}

pub const EnvUse = struct {
    name: []u8,
    file: []const u8,
    line: usize,

    pub fn deinit(self: *EnvUse, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
    }
};

fn identAfter(gpa: std.mem.Allocator, line: []const u8, needle: []const u8) !?[]u8 {
    const idx = std.mem.indexOf(u8, line, needle) orelse return null;
    var i = idx + needle.len;
    const start = i;
    while (i < line.len and ((line[i] >= 'A' and line[i] <= 'Z') or (line[i] >= '0' and line[i] <= '9') or line[i] == '_')) : (i += 1) {}
    if (i == start) return null;
    return try gpa.dupe(u8, line[start..i]);
}

pub fn scanEnvUses(gpa: std.mem.Allocator, file: []const u8, content: []const u8) !std.array_list.Managed(EnvUse) {
    var out = std.array_list.Managed(EnvUse).init(gpa);
    errdefer {
        for (out.items) |*e| e.deinit(gpa);
        out.deinit();
    }
    var line_no: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |raw| {
        line_no += 1;
        const line = raw[0..@min(raw.len, 500)];
        var got: ?[]u8 = null;
        if (try identAfter(gpa, line, "process.env.")) |v| {
            got = v;
        } else if (std.mem.indexOf(u8, line, "os.environ") != null or std.mem.indexOf(u8, line, "os.getenv(") != null or std.mem.indexOf(u8, line, "getenv(") != null or std.mem.indexOf(u8, line, "getEnvironmentVariable(") != null) {
            got = try firstQuoted(gpa, line);
        } else if (std.mem.indexOf(u8, line, "ENV[") != null) {
            got = try firstQuoted(gpa, line);
        } else if ((std.mem.indexOf(u8, line, "env(") != null or std.mem.indexOf(u8, line, "env!") != null) and std.mem.indexOf(u8, line, "envelope") == null) {
            got = try firstQuoted(gpa, line);
        }
        if (got) |v| {
            // validate KEY shape
            var ok = v.len > 0 and v.len <= 64 and (v[0] == '_' or (v[0] >= 'A' and v[0] <= 'Z'));
            var k: usize = 0;
            while (ok and k < v.len) : (k += 1) {
                const c = v[k];
                if (!((c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_')) ok = false;
            }
            if (ok) {
                out.append(.{ .name = v, .file = file, .line = line_no }) catch {
                    gpa.free(v);
                    break;
                };
            } else gpa.free(v);
            if (out.items.len > 500) break;
        }
    }
    return out;
}

pub const DotEnvKey = struct {
    name: []u8,
    line: usize,

    pub fn deinit(self: *DotEnvKey, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
    }
};

// Only keys + line numbers are stored. Values are NEVER kept (secret safety).
pub fn parseDotEnv(gpa: std.mem.Allocator, content: []const u8) !std.array_list.Managed(DotEnvKey) {
    var out = std.array_list.Managed(DotEnvKey).init(gpa);
    errdefer {
        for (out.items) |*e| e.deinit(gpa);
        out.deinit();
    }
    var line_no: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |raw| {
        line_no += 1;
        var t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        if (std.mem.startsWith(u8, t, "export ")) t = std.mem.trim(u8, t[7..], " \t");
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = std.mem.trim(u8, t[0..eq], " \t\"'");
        if (key.len == 0 or key.len > 64) continue;
        var ok = key[0] == '_' or (key[0] >= 'A' and key[0] <= 'Z') or (key[0] >= 'a' and key[0] <= 'z');
        var k: usize = 0;
        while (ok and k < key.len) : (k += 1) {
            const c = key[k];
            if (!((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_')) ok = false;
        }
        if (!ok) continue;
        try out.append(.{ .name = try gpa.dupe(u8, key), .line = line_no });
        if (out.items.len > 200) break;
    }
    return out;
}

pub const ModelRel = struct {
    from_file: []const u8,
    to_file: []const u8,
    from_model: []u8,
    to_model: []u8,

    pub fn deinit(self: *ModelRel, gpa: std.mem.Allocator) void {
        gpa.free(self.from_model);
        gpa.free(self.to_model);
    }
};

// File-level model relations (LOW confidence): model A's file depends on
// model B's file. Explainable via the import edge, not a proven FK.
pub const Edge = struct { from: usize, to: usize };

pub fn findModelRels(
    gpa: std.mem.Allocator,
    paths: []const []const u8,
    models_per_file: []const std.array_list.Managed([]u8),
    edges: []const Edge,
) !std.array_list.Managed(ModelRel) {
    var out = std.array_list.Managed(ModelRel).init(gpa);
    errdefer {
        for (out.items) |*r| r.deinit(gpa);
        out.deinit();
    }
    for (edges) |e| {
        if (e.from >= models_per_file.len or e.to >= models_per_file.len) continue;
        const a = models_per_file[e.from].items;
        const b = models_per_file[e.to].items;
        if (a.len == 0 or b.len == 0) continue;
        try out.append(.{
            .from_file = paths[e.from],
            .to_file = paths[e.to],
            .from_model = try gpa.dupe(u8, a[0]),
            .to_model = try gpa.dupe(u8, b[0]),
        });
        if (out.items.len > 200) break;
    }
    return out;
}

pub fn isModelKind(kind: parser.SymbolKind) bool {
    return kind == .class or kind == .@"struct" or kind == .interface;
}

test "endpoints" {
    const t = std.testing;
    const src = "app.get('/users', h);\napp.post(\"/users\", h);\n";
    var e = try scanEndpoints(t.allocator, "a.ts", src);
    defer {
        for (e.items) |*x| x.deinit(t.allocator);
        e.deinit();
    }
    try t.expect(e.items.len == 2);
    try t.expectEqualStrings("GET", e.items[0].method);
}

test "dotenv keys only" {
    const t = std.testing;
    const src = "# c\nSTRIPE_KEY=sk_live_abc\nPORT=3000\n";
    var k = try parseDotEnv(t.allocator, src);
    defer {
        for (k.items) |*x| x.deinit(t.allocator);
        k.deinit();
    }
    try t.expect(k.items.len == 2);
    try t.expect(std.mem.indexOf(u8, k.items[0].name, "sk_live") == null);
}
