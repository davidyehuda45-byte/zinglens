// ZigLens language intelligence — Spec Sec.9, 94, 95.
// 16 languages, framework + package-manager detection, offline heuristic.

const std = @import("std");

pub const Language = enum {
    javascript,
    typescript,
    python,
    php,
    rust,
    go,
    java,
    c,
    cpp,
    csharp,
    kotlin,
    swift,
    dart,
    ruby,
    elixir,
    zig,
    unknown,

    pub fn name(self: Language) []const u8 {
        return switch (self) {
            .javascript => "javascript",
            .typescript => "typescript",
            .python => "python",
            .php => "php",
            .rust => "rust",
            .go => "go",
            .java => "java",
            .c => "c",
            .cpp => "cpp",
            .csharp => "csharp",
            .kotlin => "kotlin",
            .swift => "swift",
            .dart => "dart",
            .ruby => "ruby",
            .elixir => "elixir",
            .zig => "zig",
            .unknown => "unknown",
        };
    }
};

pub fn detectLanguage(path: []const u8) Language {
    const base = std.fs.path.basename(path);
    // Exact filenames first
    if (std.mem.eql(u8, base, "go.mod") or std.mem.eql(u8, base, "go.sum")) return .go;
    if (std.mem.eql(u8, base, "Cargo.toml") or std.mem.eql(u8, base, "Cargo.lock")) return .rust;
    if (std.mem.eql(u8, base, "composer.json")) return .php;
    if (std.mem.eql(u8, base, "requirements.txt") or std.mem.eql(u8, base, "pyproject.toml")) return .python;
    if (std.mem.eql(u8, base, "pubspec.yaml")) return .dart;
    if (std.mem.eql(u8, base, "mix.exs")) return .elixir;
    if (std.mem.eql(u8, base, "Gemfile")) return .ruby;

    // Extension map
    const i = std.mem.lastIndexOfScalar(u8, base, '.') orelse return .unknown;
    const ext = base[i..];
    if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".jsx") or std.mem.eql(u8, ext, ".mjs") or std.mem.eql(u8, ext, ".cjs")) return .javascript;
    if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx") or std.mem.eql(u8, ext, ".mts") or std.mem.eql(u8, ext, ".cts")) return .typescript;
    if (std.mem.eql(u8, ext, ".py") or std.mem.eql(u8, ext, ".pyi")) return .python;
    if (std.mem.eql(u8, ext, ".php")) return .php;
    if (std.mem.eql(u8, ext, ".rs")) return .rust;
    if (std.mem.eql(u8, ext, ".go")) return .go;
    if (std.mem.eql(u8, ext, ".java")) return .java;
    if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .c;
    if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".hpp") or std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".hh")) return .cpp;
    if (std.mem.eql(u8, ext, ".cs")) return .csharp;
    if (std.mem.eql(u8, ext, ".kt") or std.mem.eql(u8, ext, ".kts")) return .kotlin;
    if (std.mem.eql(u8, ext, ".swift")) return .swift;
    if (std.mem.eql(u8, ext, ".dart")) return .dart;
    if (std.mem.eql(u8, ext, ".rb")) return .ruby;
    if (std.mem.eql(u8, ext, ".ex") or std.mem.eql(u8, ext, ".exs")) return .elixir;
    if (std.mem.eql(u8, ext, ".zig")) return .zig;
    return .unknown;
}

pub fn isSourceFile(path: []const u8) bool {
    return detectLanguage(path) != .unknown;
}

pub const Framework = enum {
    nextjs, react, vue, laravel, django, fastapi, spring, rails, phoenix, flutter,
    unknown, none,
};

pub fn detectFrameworkFile(path: []const u8) ?Framework {
    const base = std.fs.path.basename(path);
    if (std.mem.eql(u8, base, "next.config.js") or std.mem.eql(u8, base, "next.config.ts")) return .nextjs;
    if (std.mem.eql(u8, base, "artisan")) return .laravel;
    if (std.mem.eql(u8, base, "manage.py")) return .django;
    if (std.mem.eql(u8, base, "pubspec.yaml")) return .flutter;
    if (std.mem.eql(u8, base, "mix.exs")) return .phoenix;
    return null;
}

pub const PackageManager = enum {
    npm, pnpm, yarn, bun, pip, poetry, cargo, composer, gomodules, maven, gradle, dart_pub,
    unknown,
};

pub fn detectPackageManagerFile(path: []const u8) ?PackageManager {
    const base = std.fs.path.basename(path);
    if (std.mem.eql(u8, base, "package-lock.json")) return .npm;
    if (std.mem.eql(u8, base, "pnpm-lock.yaml")) return .pnpm;
    if (std.mem.eql(u8, base, "yarn.lock")) return .yarn;
    if (std.mem.eql(u8, base, "bun.lockb")) return .bun;
    if (std.mem.eql(u8, base, "package.json")) return .npm;
    if (std.mem.eql(u8, base, "requirements.txt") or std.mem.eql(u8, base, "pyproject.toml")) return .pip;
    if (std.mem.eql(u8, base, "Cargo.toml") or std.mem.eql(u8, base, "Cargo.lock")) return .cargo;
    if (std.mem.eql(u8, base, "composer.json") or std.mem.eql(u8, base, "composer.lock")) return .composer;
    if (std.mem.eql(u8, base, "go.mod") or std.mem.eql(u8, base, "go.sum")) return .gomodules;
    if (std.mem.eql(u8, base, "pom.xml")) return .maven;
    if (std.mem.eql(u8, base, "build.gradle")) return .gradle;
    if (std.mem.eql(u8, base, "pubspec.yaml")) return .dart_pub;
    return null;
}

// Default ignore dirs — Spec Sec.68
pub fn isDefaultIgnored(path: []const u8) bool {
    const ignored = [_][]const u8{
        ".git", "node_modules", "vendor", "dist", "build", "target",
        "coverage", ".cache", ".tmp", ".ziglens", "__pycache__",
        ".venv", "venv", ".idea", ".vscode", ".zig-cache", "zig-out",
        ".zig", "zig-cache", ".next", "out",
    };
    // check any path segment
    var it = std.mem.splitSequence(u8, path, "/");
    while (it.next()) |seg| {
        // also handle windows sep
        var wit = std.mem.splitSequence(u8, seg, "\\");
        while (wit.next()) |s| {
            for (ignored) |ig| {
                if (std.mem.eql(u8, s, ig)) return true;
            }
        }
    }
    // generated framework caches (keep source dirs like bootstrap/app.php)
    if (std.mem.indexOf(u8, path, "storage/framework/views") != null) return true;
    if (std.mem.indexOf(u8, path, "bootstrap/cache") != null) return true;
    if (std.mem.indexOf(u8, path, "public/build") != null) return true;
    if (std.mem.indexOf(u8, path, "public/hot") != null) return true;
    return false;
}

test "detect language" {
    const t = std.testing;
    try t.expect(detectLanguage("src/a.ts") == .typescript);
    try t.expect(detectLanguage("src/a.js") == .javascript);
    try t.expect(detectLanguage("main.py") == .python);
    try t.expect(detectLanguage("main.zig") == .zig);
    try t.expect(detectLanguage("main.go") == .go);
    try t.expect(detectLanguage("lib.rs") == .rust);
    try t.expect(detectLanguage("App.java") == .java);
    try t.expect(detectLanguage("a.php") == .php);
    try t.expect(detectLanguage("README.md") == .unknown);
    try t.expect(isDefaultIgnored("node_modules/foo/bar.js"));
    try t.expect(!isDefaultIgnored("src/app.ts"));
}
