# ZigLens — Rontgen untuk codebase-mu

![Version](https://img.shields.io/badge/version-0.5.1-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Zig](https://img.shields.io/badge/zig-0.17.0-orange)

[English](./README.md) | **Indonesia**

> Arahkan ZigLens ke folder project apa pun. Dalam hitungan detik, lihat
> bagaimana kode saling terhubung, apa yang aman diubah, dan apa yang perlu
> diperbaiki — semuanya di komputermu sendiri, tanpa internet.

```powershell
ziglens .
```

```
Files             1,842
Symbols           12,941
Architecture      82/100
Security          94/100

Potential issues  31
Dashboard: http://127.0.0.1:4173
```

## Untuk siapa?

- Kamu baru mewarisi project besar tanpa dokumentasi
- Mau refactoring tapi takut merusak yang lain
- Mau menemukan kode mati, dependency kusut, dan file berisiko
- Kamu me-review kode atau onboarding developer baru

## Install (pilih satu)

**Download (Windows / Linux / macOS):** ambil zip dari GitHub Releases,
cocokkan dengan `SHA256SUMS`, ekstrak, jalankan.

```powershell
Expand-Archive ziglens-x86_64-windows.zip
.\ziglens.exe --help
```

> Peringatan SmartScreen itu normal (binary open-source tanpa tanda tangan):
> *More info → Run anyway* — atau build dari source di bawah.

**Build dari source** (butuh Zig 0.17+):

```powershell
zig build -Doptimize=ReleaseSafe
./zig-out/bin/ziglens --help
```

## Coba (2 menit)

```powershell
ziglens scan .            # ringkasan project apa pun
ziglens impact src/database.ts   # apa yang rusak kalau file ini diubah?
ziglens deadcode          # kode tak terpakai, lengkap dengan keyakinannya
ziglens top               # apa yang harus diperbaiki dulu?
ziglens serve             # buka dashboard visual di browser
```

Semua command juga bisa output JSON bersih untuk script dan CI:

```powershell
ziglens analyze --ci      # exit 2 kalau quality gate gagal
```

## Apa yang dikasih tahu (bahasa sederhana)

- **Peta** — file mana butuh file mana, dan siapa butuh file ini
- **Risiko** — apa dampak mengubah suatu file, lengkap dengan alasannya
- **Bersih-bersih** — kode mati, blok duplikat, file kebesaran
- **Keamanan** — secret bocor (disamarkan, tidak pernah disimpan), config berisiko
- **Riwayat** — file yang paling sering berubah, siapa pemiliknya, evolusinya
- **Skor kesehatan** — arsitektur, keamanan, maintainability, semua bisa dijelaskan

## Kodemu tetap milikmu

- 100% offline. Tanpa akun, tanpa API key, tanpa upload, tanpa telemetry.
- Read-only: ZigLens tidak pernah mengubah atau menjalankan kodemu.
- Dashboard hanya di `127.0.0.1` (komputermu saja, bukan orang lain).
- Satu binary kecil, tanpa installer, tanpa dependensi.

## Bahasa

Default Inggris, Indonesia tersedia di mana-mana:

```powershell
ziglens scan . --lang id        # CLI berbahasa Indonesia
```

Dashboard ada **tombol EN/ID** di bar atas.

## Dokumentasi

- `docs/CLI.md` — semua command, lengkap dengan contoh
- `docs/TROUBLESHOOTING.md` — scan lambat, false positive, port sibuk
- `docs/API.md` — JSON API lokal untuk script-mu sendiri
- `docs/ARCHITECTURE.md` — cara skor dihitung (tanpa angka sulap)
- `docs/PLUGIN.md`, `docs/CI.md`, `docs/BENCHMARKS.md`

## Penulis & lisensi

David Yehuda Surbakti — Lisensi MIT, lihat `LICENSE`.
Kontribusi dipersilakan: `docs/CONTRIBUTING.md`.
