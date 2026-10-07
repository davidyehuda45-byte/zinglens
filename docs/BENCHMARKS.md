# Benchmarks (measured, Windows x64, debug build)

| Project | Files | Symbols | Time |
|---|---|---|---|
| examples/ (TS+PY) | 3 | 8 | ~0.02s |
| ziglens self | 18 | 171 | ~0.15s |
| Laravel app (SistemPerpustakaan, caches skipped) | 149 | 303 | ~0.73s |
| Mixed monorepo (ProjekDavid, 26.9k files on disk, deps skipped) | 154 | 432 | ~3.5s |

Method: `Measure-Command { ziglens scan <root> --quiet }`.
ReleaseSafe is faster. Targets: <5s for <10k files (on track).
Incremental watch rescan only on fingerprint change.
