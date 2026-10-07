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
    // fix-first plain language
    lvl_very_high: []const u8,
    lvl_high: []const u8,
    lvl_moderate: []const u8,
    lvl_low: []const u8,
    wx_complex: []const u8, // "very hard to understand (complexity {d})"
    wx_fairly: []const u8, // "hard to understand (complexity {d})"
    wx_growing: []const u8, // "getting complex ({d})"
    wx_deps: []const u8, // "{d} files depend on it"
    wx_viol: []const u8, // "breaks {d} architecture rule(s)"
    wx_dead: []const u8, // "{d} unused piece(s) inside"
    wx_small: []const u8, // fallback
    do_split: []const u8,
    do_careful: []const u8,
    do_layer: []const u8,
    do_delete: []const u8,
    do_review: []const u8,
    fix_title: []const u8,
    why_label: []const u8,
    do_label: []const u8,
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
            .lvl_very_high = "VERY HIGH",
            .lvl_high = "HIGH",
            .lvl_moderate = "MODERATE",
            .lvl_low = "low",
            .wx_complex = "very hard to understand (complexity {d})",
            .wx_fairly = "hard to understand (complexity {d})",
            .wx_growing = "getting complex ({d})",
            .wx_deps = "{d} files depend on it",
            .wx_viol = "breaks {d} architecture rule(s)",
            .wx_dead = "{d} unused piece(s) inside",
            .wx_small = "no single big problem, general cleanup candidate",
            .do_split = "Split into smaller functions",
            .do_careful = "Change carefully and run related tests",
            .do_layer = "Move the dependency to the correct layer",
            .do_delete = "Delete after confirming nothing uses it",
            .do_review = "Review when you next touch this file",
            .fix_title = "What should I fix first? (higher score = fix sooner)",
            .why_label = "Why",
            .do_label = "Do",
        },
        .id => .{
            .scanning = "Memindai project...",
            .parsing = "Mengurai...",
            .indexing = "Mengindeks...",
            .analyzing = "Menganalisis...",
            .done = "Selesai.",
            .no_violations = "Tidak ada pelanggaran arsitektur terdeteksi.",
            .use_doctor = "Jalankan: ziglens doctor",
            .lvl_very_high = "SANGAT TINGGI",
            .lvl_high = "TINGGI",
            .lvl_moderate = "SEDANG",
            .lvl_low = "rendah",
            .wx_complex = "sangat sulit dipahami (kompleksitas {d})",
            .wx_fairly = "sulit dipahami (kompleksitas {d})",
            .wx_growing = "mulai kompleks ({d})",
            .wx_deps = "{d} file bergantung padanya",
            .wx_viol = "melanggar {d} aturan arsitektur",
            .wx_dead = "{d} bagian tak terpakai di dalamnya",
            .wx_small = "tidak ada masalah besar, kandidat bersih-bersih umum",
            .do_split = "Pecah menjadi fungsi-fungsi kecil",
            .do_careful = "Ubah hati-hati dan jalankan tes terkait",
            .do_layer = "Pindahkan dependency ke layer yang benar",
            .do_delete = "Hapus setelah pastikan tak ada yang memakai",
            .do_review = "Review saat kamu menyentuh file ini",
            .fix_title = "Apa yang harus diperbaiki dulu? (skor besar = kerjakan duluan)",
            .why_label = "Kenapa",
            .do_label = "Lakukan",
        },
    };
}

test "parse lang" {
    try std.testing.expect(parseLang("id") == .id);
    try std.testing.expect(parseLang("en") == .en);
    try std.testing.expect(parseLang("xx") == .en);
}
