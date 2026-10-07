// ZigLens heuristic parser — Spec Sec.9-10.
// Offline, deterministic, no code execution. Line-based multi-language
// symbol/import/export/call/complexity extraction.
// This is v0.1 heuristic layer; tree-sitter-grade adapters plug in via
// LanguageAdapter extension point (Phase 3).

const std = @import("std");
const langmod = @import("language.zig");

pub const SymbolKind = enum {
    function,
    class,
    interface,
    @"struct",
    @"enum",
    variable,
    constant,
    method,
    unknown,

    pub fn name(self: SymbolKind) []const u8 {
        return switch (self) {
            .function => "function",
            .class => "class",
            .interface => "interface",
            .@"struct" => "struct",
            .@"enum" => "enum",
            .variable => "variable",
            .constant => "constant",
            .method => "method",
            .unknown => "unknown",
        };
    }
};

pub const Symbol = struct {
    name: []u8,
    kind: SymbolKind,
    line: usize,
    column: usize,

    pub fn deinit(self: *Symbol, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
    }
};

pub const FileFacts = struct {
    language: langmod.Language,
    symbols: std.array_list.Managed(Symbol),
    imports: std.array_list.Managed([]u8),
    exports: std.array_list.Managed([]u8),
    calls: std.array_list.Managed([]u8),
    loc: usize,
    complexity: u32,
    nesting_max: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *FileFacts) void {
        for (self.symbols.items) |*s| s.deinit(self.allocator);
        self.symbols.deinit();
        for (self.imports.items) |p| self.allocator.free(p);
        self.imports.deinit();
        for (self.exports.items) |p| self.allocator.free(p);
        self.exports.deinit();
        for (self.calls.items) |p| self.allocator.free(p);
        self.calls.deinit();
    }
};

fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '$';
}

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == '$';
}

fn dupTrimmed(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    return gpa.dupe(u8, std.mem.trim(u8, s, " \t\r;"));
}

fn extractQuoted(gpa: std.mem.Allocator, line: []const u8) !?[]u8 {
    // first '...' or "..." token
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const q = line[i];
        if (q == '\'' or q == '"') {
            var j = i + 1;
            while (j < line.len and line[j] != q) : (j += 1) {}
            if (j < line.len) {
                return try gpa.dupe(u8, line[i + 1 .. j]);
            }
            return null;
        }
    }
    return null;
}

fn extractIdentAfter(gpa: std.mem.Allocator, line: []const u8, keyword: []const u8) !?[]u8 {
    const idx = std.mem.indexOf(u8, line, keyword) orelse return null;
    var i = idx + keyword.len;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t' or line[i] == '*')) : (i += 1) {}
    const start = i;
    if (start >= line.len or !isIdentStart(line[start])) return null;
    while (i < line.len and isIdentChar(line[i])) : (i += 1) {}
    // strip generics: Foo<T> -> Foo
    const end = i;
    if (end > start and line[start..end].len > 0) {
        return try gpa.dupe(u8, line[start..end]);
    }
    return null;
}

fn lineComplexity(line: []const u8) u32 {
    var c: u32 = 0;
    const kws = [_][]const u8{ "if ", "if(", "for ", "for(", "while ", "while(", "case ", "catch ", "elif ", "else if", "&&", "||", "??", "match ", "switch " };
    for (kws) |k| {
        var idx: usize = 0;
        while (std.mem.indexOf(u8, line[idx..], k)) |off| {
            c += 1;
            idx += off + k.len;
            if (idx >= line.len) break;
        }
    }
    // ternary ? (avoid ?? double counted; rough)
    var qi: usize = 0;
    while (qi < line.len) : (qi += 1) {
        if (line[qi] == '?' and (qi + 1 >= line.len or line[qi + 1] != '?') and (qi == 0 or line[qi - 1] != '?')) c += 1;
    }
    return c;
}

pub fn parse(gpa: std.mem.Allocator, content: []const u8, language: langmod.Language) !FileFacts {
    var facts = FileFacts{
        .language = language,
        .symbols = std.array_list.Managed(Symbol).init(gpa),
        .imports = std.array_list.Managed([]u8).init(gpa),
        .exports = std.array_list.Managed([]u8).init(gpa),
        .calls = std.array_list.Managed([]u8).init(gpa),
        .loc = 0,
        .complexity = 1,
        .nesting_max = 0,
        .allocator = gpa,
    };
    errdefer facts.deinit();

    var brace_depth: u32 = 0;
    var line_no: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw[0..@min(raw.len, 500)], " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "//") or std.mem.startsWith(u8, line, "#") or std.mem.startsWith(u8, line, "*") or std.mem.startsWith(u8, line, "/*")) {
            // still count? skip
            continue;
        }
        facts.loc += 1;
        facts.complexity += lineComplexity(line);

        // nesting via braces
        for (line) |ch| {
            if (ch == '{') {
                brace_depth += 1;
                if (brace_depth > facts.nesting_max) facts.nesting_max = brace_depth;
            } else if (ch == '}') {
                if (brace_depth > 0) brace_depth -= 1;
            }
        }
        // python indent nesting approx
        if (language == .python) {
            var indent: u32 = 0;
            for (raw) |ch| {
                if (ch == ' ') indent += 1 else if (ch == '\t') indent += 4 else break;
            }
            const lvl = indent / 4;
            if (lvl > facts.nesting_max) facts.nesting_max = lvl;
        }

        // ---- imports ----
        const trimmed = line;
        if (isImportLine(trimmed, language)) {
            if (try extractQuoted(gpa, trimmed)) |q| {
                try facts.imports.append(q);
            } else {
                // python: import x.y / from x import y ; go: import "fmt" already quoted
                // bare import token fallback
                if (try bareImport(gpa, trimmed, language)) |b| {
                    try facts.imports.append(b);
                }
            }
        }
        // ---- exports / definitions ----
        try detectSymbols(gpa, &facts, trimmed, line_no, language);
        // ---- calls (identifier + '(') ----
        try detectCalls(gpa, &facts, trimmed);
    }
    return facts;
}

fn isImportLine(line: []const u8, language: langmod.Language) bool {
    switch (language) {
        .javascript, .typescript => {
            return std.mem.startsWith(u8, line, "import ") or std.mem.startsWith(u8, line, "} from ") or std.mem.indexOf(u8, line, "require(") != null or std.mem.startsWith(u8, line, "export ") and std.mem.indexOf(u8, line, " from ") != null;
        },
        .python => {
            return std.mem.startsWith(u8, line, "import ") or std.mem.startsWith(u8, line, "from ");
        },
        .go => {
            return std.mem.startsWith(u8, line, "import ") or (line.len > 0 and line[0] == '"');
        },
        .rust => {
            return std.mem.startsWith(u8, line, "use ");
        },
        .java, .kotlin => {
            return std.mem.startsWith(u8, line, "import ");
        },
        .c, .cpp => {
            return std.mem.startsWith(u8, line, "#include");
        },
        .csharp => {
            return std.mem.startsWith(u8, line, "using ");
        },
        .php => {
            return std.mem.startsWith(u8, line, "use ") or std.mem.startsWith(u8, line, "require") or std.mem.startsWith(u8, line, "include");
        },
        .ruby => {
            return std.mem.startsWith(u8, line, "require ") or std.mem.startsWith(u8, line, "require_relative ") or std.mem.startsWith(u8, line, "include ");
        },
        .swift => {
            return std.mem.startsWith(u8, line, "import ");
        },
        .dart => {
            return std.mem.startsWith(u8, line, "import ") or std.mem.startsWith(u8, line, "export ");
        },
        .elixir => {
            return std.mem.startsWith(u8, line, "alias ") or std.mem.startsWith(u8, line, "import ") or std.mem.startsWith(u8, line, "require ");
        },
        .zig => {
            return std.mem.startsWith(u8, line, "const ") and std.mem.indexOf(u8, line, "@import(") != null;
        },
        else => {
            return std.mem.startsWith(u8, line, "import ");
        },
    }
}

fn bareImport(gpa: std.mem.Allocator, line: []const u8, language: langmod.Language) !?[]u8 {
    switch (language) {
        .python => {
            if (std.mem.startsWith(u8, line, "import ")) {
                const rest = std.mem.trim(u8, line["import ".len..], " \t");
                var end: usize = 0;
                while (end < rest.len and (isIdentChar(rest[end]) or rest[end] == '.' or rest[end] == ',' or rest[end] == ' ')) : (end += 1) {}
                const tok = std.mem.trim(u8, rest[0..end], " \t");
                // take first module before comma/space
                var cend: usize = 0;
                while (cend < tok.len and (isIdentChar(tok[cend]) or tok[cend] == '.')) : (cend += 1) {}
                if (cend > 0) return try gpa.dupe(u8, tok[0..cend]);
            } else if (std.mem.startsWith(u8, line, "from ")) {
                const rest = line["from ".len..];
                var end: usize = 0;
                while (end < rest.len and (isIdentChar(rest[end]) or rest[end] == '.')) : (end += 1) {}
                if (end > 0) return try gpa.dupe(u8, rest[0..end]);
            }
            return null;
        },
        .rust, .java, .kotlin, .csharp, .swift, .ruby, .elixir => {
            // last token
            var end = std.mem.trim(u8, line, " \t;");
            // strip trailing
            if (std.mem.lastIndexOfScalar(u8, end, ' ')) |i| {
                const tok = std.mem.trim(u8, end[i + 1 ..], " \t;");
                if (tok.len > 0) return try gpa.dupe(u8, tok);
            }
            return null;
        },
        else => return null,
    }
}

fn addSymbol(gpa: std.mem.Allocator, facts: *FileFacts, name: []u8, kind: SymbolKind, line_no: usize) !void {
    // column approx 1
    try facts.symbols.append(.{ .name = name, .kind = kind, .line = line_no, .column = 1 });
    _ = gpa;
}

fn detectSymbols(gpa: std.mem.Allocator, facts: *FileFacts, line: []const u8, line_no: usize, language: langmod.Language) !void {
    // export tracking: export Praha / module.exports / pub ...
    if (std.mem.startsWith(u8, line, "export ")) {
        if (try extractIdentAfter(gpa, line, "export function")) |n| {
            try addSymbol(gpa, facts, n, .function, line_no);
            try facts.exports.append(try gpa.dupe(u8, n));
            return;
        }
        if (try extractIdentAfter(gpa, line, "export class")) |n| {
            try addSymbol(gpa, facts, n, .class, line_no);
            try facts.exports.append(try gpa.dupe(u8, n));
            return;
        }
        if (try extractIdentAfter(gpa, line, "export interface")) |n| {
            try addSymbol(gpa, facts, n, .interface, line_no);
            try facts.exports.append(try gpa.dupe(u8, n));
            return;
        }
        if (try extractIdentAfter(gpa, line, "export const")) |n| {
            try addSymbol(gpa, facts, n, .constant, line_no);
            try facts.exports.append(try gpa.dupe(u8, n));
            return;
        }
        if (try extractIdentAfter(gpa, line, "export default function")) |n| {
            try addSymbol(gpa, facts, n, .function, line_no);
            try facts.exports.append(try gpa.dupe(u8, n));
            return;
        }
    }

    switch (language) {
        .javascript, .typescript => {
            if (std.mem.startsWith(u8, line, "function ") or std.mem.indexOf(u8, line, "function ") == 0) {
                if (try extractIdentAfter(gpa, line, "function")) |n| try addSymbol(gpa, facts, n, .function, line_no);
            } else if (std.mem.startsWith(u8, line, "class ")) {
                if (try extractIdentAfter(gpa, line, "class")) |n| try addSymbol(gpa, facts, n, .class, line_no);
            } else if (std.mem.startsWith(u8, line, "interface ")) {
                if (try extractIdentAfter(gpa, line, "interface")) |n| try addSymbol(gpa, facts, n, .interface, line_no);
            } else if (std.mem.startsWith(u8, line, "enum ")) {
                if (try extractIdentAfter(gpa, line, "enum")) |n| try addSymbol(gpa, facts, n, .@"enum", line_no);
            } else if (std.mem.startsWith(u8, line, "const ") or std.mem.startsWith(u8, line, "let ") or std.mem.startsWith(u8, line, "var ")) {
                // const foo = ( or const foo =
                const kwlen: usize = if (std.mem.startsWith(u8, line, "const ")) 6 else 4;
                const rest = line[kwlen..];
                var i: usize = 0;
                while (i < rest.len and (rest[i] == ' ' or rest[i] == '\t')) : (i += 1) {}
                const s = i;
                if (s < rest.len and isIdentStart(rest[s])) {
                    while (i < rest.len and isIdentChar(rest[i])) : (i += 1) {}
                    if (i > s) {
                        const nm = try gpa.dupe(u8, rest[s..i]);
                        const is_fn = std.mem.indexOf(u8, rest, "=>") != null or std.mem.indexOf(u8, rest, "function") != null;
                        try addSymbol(gpa, facts, nm, if (is_fn) SymbolKind.function else SymbolKind.variable, line_no);
                    }
                }
            }
        },
        .python => {
            if (std.mem.startsWith(u8, line, "def ")) {
                if (try extractIdentAfter(gpa, line, "def")) |n| {
                    // trim trailing ( :
                    if (std.mem.indexOfScalar(u8, n, '(')) |pi| {
                        const clean = try gpa.dupe(u8, n[0..pi]);
                        gpa.free(n);
                        try addSymbol(gpa, facts, clean, .function, line_no);
                    } else try addSymbol(gpa, facts, n, .function, line_no);
                }
            } else if (std.mem.startsWith(u8, line, "class ")) {
                if (try extractIdentAfter(gpa, line, "class")) |n| {
                    var clean = n;
                    if (std.mem.indexOfAny(u8, n, "(: ")) |pi| {
                        const c2 = try gpa.dupe(u8, n[0..pi]);
                        gpa.free(n);
                        clean = c2;
                    }
                    try addSymbol(gpa, facts, clean, .class, line_no);
                }
            }
        },
        .go => {
            if (std.mem.startsWith(u8, line, "func ")) {
                const rest = line["func ".len..];
                // method? func (r R) Name(
                var r = rest;
                if (r.len > 0 and r[0] == '(') {
                    if (std.mem.indexOfScalar(u8, r, ')')) |ci| r = std.mem.trim(u8, r[ci + 1 ..], " \t");
                }
                var i: usize = 0;
                while (i < r.len and isIdentStart(r[i])) : (i += 1) {}
                // actually need start check
                if (r.len > 0 and isIdentStart(r[0])) {
                    var e: usize = 0;
                    while (e < r.len and isIdentChar(r[e])) : (e += 1) {}
                    if (e > 0) {
                        const nm = try gpa.dupe(u8, r[0..e]);
                        const is_method = std.mem.startsWith(u8, rest, "(");
                        try addSymbol(gpa, facts, nm, if (is_method) SymbolKind.method else SymbolKind.function, line_no);
                    }
                }
            } else if (std.mem.startsWith(u8, line, "type ") and std.mem.indexOf(u8, line, "struct") != null) {
                if (try extractIdentAfter(gpa, line, "type")) |n| try addSymbol(gpa, facts, n, .@"struct", line_no);
            } else if (std.mem.startsWith(u8, line, "type ") and std.mem.indexOf(u8, line, "interface") != null) {
                if (try extractIdentAfter(gpa, line, "type")) |n| try addSymbol(gpa, facts, n, .interface, line_no);
            }
        },
        .rust => {
            if (std.mem.startsWith(u8, line, "fn ") or std.mem.startsWith(u8, line, "pub fn ")) {
                const kw = if (std.mem.startsWith(u8, line, "pub fn ")) "pub fn" else "fn";
                if (try extractIdentAfter(gpa, line, kw)) |n| {
                    var clean = n;
                    if (std.mem.indexOfScalar(u8, n, '<')) |gi| {
                        const c2 = try gpa.dupe(u8, n[0..gi]);
                        gpa.free(n);
                        clean = c2;
                    }
                    try addSymbol(gpa, facts, clean, .function, line_no);
                }
            } else if (std.mem.startsWith(u8, line, "struct ") or std.mem.startsWith(u8, line, "pub struct ")) {
                const kw = if (std.mem.startsWith(u8, line, "pub struct ")) "pub struct" else "struct";
                if (try extractIdentAfter(gpa, line, kw)) |n| try addSymbol(gpa, facts, n, .@"struct", line_no);
            } else if (std.mem.startsWith(u8, line, "enum ") or std.mem.startsWith(u8, line, "pub enum ")) {
                const kw = if (std.mem.startsWith(u8, line, "pub enum ")) "pub enum" else "enum";
                if (try extractIdentAfter(gpa, line, kw)) |n| try addSymbol(gpa, facts, n, .@"enum", line_no);
            } else if (std.mem.startsWith(u8, line, "trait ") or std.mem.startsWith(u8, line, "pub trait ")) {
                const kw = if (std.mem.startsWith(u8, line, "pub trait ")) "pub trait" else "trait";
                if (try extractIdentAfter(gpa, line, kw)) |n| try addSymbol(gpa, facts, n, .interface, line_no);
            }
        },
        .zig => {
            if (std.mem.startsWith(u8, line, "pub fn ") or std.mem.startsWith(u8, line, "fn ")) {
                const kw = if (std.mem.startsWith(u8, line, "pub fn ")) "pub fn" else "fn";
                if (try extractIdentAfter(gpa, line, kw)) |n| {
                    var clean = n;
                    if (std.mem.indexOfScalar(u8, n, '(')) |pi| {
                        const c2 = try gpa.dupe(u8, n[0..pi]);
                        gpa.free(n);
                        clean = c2;
                    }
                    const is_pub = std.mem.startsWith(u8, line, "pub ");
                    try addSymbol(gpa, facts, clean, .function, line_no);
                    if (is_pub) try facts.exports.append(try gpa.dupe(u8, clean));
                }
            } else if (std.mem.startsWith(u8, line, "pub const ") or std.mem.startsWith(u8, line, "const ")) {
                // struct/enum detection: const Foo = struct {
                if (std.mem.indexOf(u8, line, "struct") != null or std.mem.indexOf(u8, line, "enum") != null or std.mem.indexOf(u8, line, "union") != null) {
                    const kw = if (std.mem.startsWith(u8, line, "pub const ")) "pub const" else "const";
                    if (try extractIdentAfter(gpa, line, kw)) |n| {
                        var clean = n;
                        if (std.mem.indexOfScalar(u8, n, ' ') != null or std.mem.indexOfScalar(u8, n, '=') != null) {
                            // trim
                            var e: usize = 0;
                            while (e < n.len and isIdentChar(n[e])) : (e += 1) {}
                            const c2 = try gpa.dupe(u8, n[0..e]);
                            gpa.free(n);
                            clean = c2;
                        }
                        const kind: SymbolKind = if (std.mem.indexOf(u8, line, "enum") != null) .@"enum" else .@"struct";
                        try addSymbol(gpa, facts, clean, kind, line_no);
                    }
                }
            }
        },
        .java, .kotlin, .csharp, .swift, .dart, .php, .ruby, .elixir, .c, .cpp => {
            // generic class/struct/enum/function patterns
            if (std.mem.indexOf(u8, line, "class ") != null) {
                if (try extractIdentAfter(gpa, line, "class")) |n| try addSymbol(gpa, facts, n, .class, line_no);
            } else if (std.mem.indexOf(u8, line, "interface ") != null) {
                if (try extractIdentAfter(gpa, line, "interface")) |n| try addSymbol(gpa, facts, n, .interface, line_no);
            } else if (std.mem.indexOf(u8, line, "struct ") != null) {
                if (try extractIdentAfter(gpa, line, "struct")) |n| try addSymbol(gpa, facts, n, .@"struct", line_no);
            } else if (std.mem.indexOf(u8, line, "enum ") != null) {
                if (try extractIdentAfter(gpa, line, "enum")) |n| try addSymbol(gpa, facts, n, .@"enum", line_no);
            }
            // function: def / function / fn / func variants + C-style: "type name("
            if (language == .python) {} else if (language == .ruby) {
                if (std.mem.startsWith(u8, line, "def ")) {
                    if (try extractIdentAfter(gpa, line, "def")) |n| try addSymbol(gpa, facts, n, .function, line_no);
                }
            } else if (language == .elixir) {
                if (std.mem.startsWith(u8, line, "def ") or std.mem.startsWith(u8, line, "defp ") or std.mem.startsWith(u8, line, "defmodule ")) {
                    const kw = if (std.mem.startsWith(u8, line, "defmodule ")) "defmodule" else if (std.mem.startsWith(u8, line, "defp ")) "defp" else "def";
                    const kind: SymbolKind = if (std.mem.eql(u8, kw, "defmodule")) SymbolKind.class else SymbolKind.function;
                    if (try extractIdentAfter(gpa, line, kw)) |n| try addSymbol(gpa, facts, n, kind, line_no);
                }
            } else if (language == .php) {
                if (std.mem.indexOf(u8, line, "function ") != null) {
                    if (try extractIdentAfter(gpa, line, "function")) |n| try addSymbol(gpa, facts, n, .function, line_no);
                }
            } else {
                // C-like: look for "name(" at line start-ish, skip control keywords
                const controls = [_][]const u8{ "if", "for", "while", "switch", "catch", "return", "sizeof" };
                var s = line;
                // strip visibility modifiers
                for ([_][]const u8{ "public ", "private ", "protected ", "static ", "final ", "virtual ", "override ", "inline " }) |mod| {
                    if (std.mem.startsWith(u8, s, mod)) s = s[mod.len..];
                }
                if (std.mem.indexOfScalar(u8, s, '(')) |pi| {
                    // find identifier before (
                    var e = pi;
                    while (e > 0 and s[e - 1] == ' ') : (e -= 1) {}
                    var st = e;
                    while (st > 0 and isIdentChar(s[st - 1])) : (st -= 1) {}
                    if (e > st) {
                        const nm = s[st..e];
                        var is_ctrl = false;
                        for (controls) |c| {
                            if (std.mem.eql(u8, nm, c)) {
                                is_ctrl = true;
                                break;
                            }
                        }
                        if (!is_ctrl and nm.len >= 2) {
                            const dup = try gpa.dupe(u8, nm);
                            try addSymbol(gpa, facts, dup, .function, line_no);
                        }
                    }
                }
            }
        },
        else => {},
    }
}

const CallSkip = [_][]const u8{ "if", "for", "while", "switch", "catch", "return", "import", "export", "class", "function", "def", "fn", "func", "require", "print", "sizeof" };

fn detectCalls(gpa: std.mem.Allocator, facts: *FileFacts, line: []const u8) !void {
    var i: usize = 0;
    while (i < line.len) {
        // find ident
        while (i < line.len and !isIdentStart(line[i])) : (i += 1) {}
        if (i >= line.len) break;
        const s = i;
        while (i < line.len and isIdentChar(line[i])) : (i += 1) {}
        const ident = line[s..i];
        // skip whitespace then '(' ?
        var j = i;
        while (j < line.len and (line[j] == ' ' or line[j] == '\t')) : (j += 1) {}
        if (j < line.len and line[j] == '(' and ident.len >= 2) {
            var skip = false;
            for (CallSkip) |k| {
                if (std.mem.eql(u8, ident, k)) {
                    skip = true;
                    break;
                }
            }
            if (!skip) {
                // cap calls per file to avoid blowup
                if (facts.calls.items.len < 500) {
                    const dup = try gpa.dupe(u8, ident);
                    // avoid duplicate consecutive? keep all but bounded
                    var exists = false;
                    for (facts.calls.items) |c| {
                        if (std.mem.eql(u8, c, dup)) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) try facts.calls.append(dup) else gpa.free(dup);
                }
            }
        }
    }
}

test "parse typescript" {
    const t = std.testing;
    const src =
        \\import { db } from "./database";
        \\export class UserService {
        \\  authenticate() {
        \\    if (true) { db.query(); }
        \\  }
        \\}
        \\export function login() { authenticate(); }
    ;
    var f = try parse(t.allocator, src, .typescript);
    defer f.deinit();
    try t.expect(f.symbols.items.len >= 2);
    try t.expect(f.imports.items.len == 1);
    try t.expect(f.complexity >= 2);
}

test "parse python" {
    const t = std.testing;
    const src = "import os\nfrom . import db\ndef login():\n    if True:\n        print('x')\nclass User:\n    pass\n";
    var f = try parse(t.allocator, src, .python);
    defer f.deinit();
    try t.expect(f.symbols.items.len >= 2);
    try t.expect(f.imports.items.len >= 1);
}

test "parse zig" {
    const t = std.testing;
    const src = "const std = @import(\"std\");\npub fn main() void {}\nfn helper() void {}\n";
    var f = try parse(t.allocator, src, .zig);
    defer f.deinit();
    try t.expect(f.symbols.items.len >= 2);
}

test "fuzz malformed inputs" {
    const t = std.testing;
    // NUL bytes, unmatched delimiters, unterminated strings
    const cases = [_][]const u8{
        "\x00\x00\x00",
        "{{{{{{{{{{",
        "}}}}}}}}}}",
        "\"\"\"\"\"''''",
        "function ((((((",
        "import ",
        "\xff\xfe\xfd\xfc",
    };
    for (cases) |c| {
        var f = try parse(t.allocator, c, .javascript);
        defer f.deinit();
        try t.expect(f.symbols.items.len <= 500);
        try t.expect(f.calls.items.len <= 500);
    }
    // 100KB single line (minified): must not blow up
    const big = try t.allocator.alloc(u8, 100_000);
    defer t.allocator.free(big);
    @memset(big, 'x');
    @memcpy(big[0..8], "function");
    var fb = try parse(t.allocator, big, .javascript);
    defer fb.deinit();
    try t.expect(fb.complexity < 100000);
}

test "all languages smoke" {
    const t = std.testing;
    const samples = [_]struct { lang: @import("language.zig").Language, src: []const u8 }{
        .{ .lang = .javascript, .src = "import x from 'y';\nfunction f() { if (a) g(); }\n" },
        .{ .lang = .typescript, .src = "export class A {}\nexport function f() {}\n" },
        .{ .lang = .python, .src = "import os\ndef f():\n    pass\n" },
        .{ .lang = .php, .src = "<?php\nfunction f() {}\nclass A {}\n" },
        .{ .lang = .rust, .src = "use std::io;\nfn main() {}\nstruct S {}\n" },
        .{ .lang = .go, .src = "package m\nimport \"fmt\"\nfunc Run() {}\n" },
        .{ .lang = .java, .src = "import java.util.*;\nclass A { void m() {} }\n" },
        .{ .lang = .c, .src = "#include <stdio.h>\nint main() { return 0; }\n" },
        .{ .lang = .cpp, .src = "#include <vector>\nclass A {};\nint f() { return 1; }\n" },
        .{ .lang = .csharp, .src = "using System;\nclass A { void M() {} }\n" },
        .{ .lang = .kotlin, .src = "import kotlin.*\nclass A\nfun f() {}\n" },
        .{ .lang = .swift, .src = "import Foundation\nclass A {}\nfunc f() {}\n" },
        .{ .lang = .dart, .src = "import 'a.dart';\nclass A {}\n" },
        .{ .lang = .ruby, .src = "require 'x'\ndef f\nend\n" },
        .{ .lang = .elixir, .src = "defmodule M do\ndef f do\nend\nend\n" },
        .{ .lang = .zig, .src = "const x = @import(\"y\");\npub fn f() void {}\n" },
    };
    for (samples) |s| {
        var f = try parse(t.allocator, s.src, s.lang);
        defer f.deinit();
        try t.expect(f.loc >= 1);
    }
}
