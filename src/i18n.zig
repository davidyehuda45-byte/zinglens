// ZigLens i18n — EN default, ID optional via --lang id.
// Spec Sec.111: Core English + Indonesian, extensible.

const std = @import("std");

pub const Lang = enum { en, id };

pub fn parseLang(s: []const u8) Lang {
    if (std.mem.eql(u8, s, "id") or std.mem.eql(u8, s, "indonesian") or std.mem.eql(u8, s, "id-ID")) return .id;
    return .en;
}

pub const Msg = struct {
    scanning: []const u8,
    parsing: []const u8,
    indexing: []const u8,
    analyzing: []const u8,
    done: []const u8,
    no_violations: []const u8,
    use_doctor: []const u8,
};

pub fn msg(lang: Lang) Msg {
    return switch (lang) {
        .en => .{
            .scanning = "Scanning project...",
            .parsing = "Parsing...",
            .indexing = "Indexing...",
            .analyzing = "Analyzing...",
            .done = "Done.",
            .no_violations = "No architecture violations detected.",
            .use_doctor = "Run: ziglens doctor",
        },
        .id => .{
            .scanning = "Memindai project...",
            .parsing = "Mengurai...",
            .indexing = "Mengindeks...",
            .analyzing = "Menganalisis...",
            .done = "Selesai.",
            .no_violations = "Tidak ada pelanggaran arsitektur terdeteksi.",
            .use_doctor = "Jalankan: ziglens doctor",
        },
    };
}

test "parse lang" {
    try std.testing.expect(parseLang("id") == .id);
    try std.testing.expect(parseLang("en") == .en);
    try std.testing.expect(parseLang("xx") == .en);
}
