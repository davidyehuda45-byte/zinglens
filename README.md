# ZigLens — X-ray for your codebase

![Version](https://img.shields.io/badge/version-0.5.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Zig](https://img.shields.io/badge/zig-0.17.0-orange)
<!-- Ganti USERNAME dengan akun GitHub-mu setelah push:
![CI](https://github.com/USERNAME/ziglens/actions/workflows/ziglens.yml/badge.svg)
-->

> Scan any codebase. Understand its architecture. Find risks before changing code. All locally.

**Local-first, offline-first codebase intelligence platform in Zig.** Single binary, no API key, no cloud, no AI subscription, no database server.

```powershell
ziglens .
```

```
ZigLens

Scanning project...

Files             1,842
Symbols           12,941
Languages         4
Dependencies      387

Architecture      82/100
Security          94/100
Maintainability   76/100

Potential issues  31

Dashboard:
http://127.0.0.1:4173
```

## Install

**Windows (x64/ARM64):**
```powershell
# from GitHub Releases — verify first:
#   Get-FileHash ziglens-x86_64-windows.zip -Algorithm SHA256  (compare with SHA256SUMS)
Expand-Archive ziglens-x86_64-windows.zip
.\ziglens.exe --help
```

> SmartScreen warning is expected (unsigned open-source binary):
> *More info → Run anyway*, or build from source below.

**Linux / macOS:** single binary, same CLI. Check `SHA256SUMS` likewise.

**From source (Zig 0.17+):**
```powershell
zig build -Doptimize=ReleaseSafe
./zig-out/bin/ziglens --help
```

## Author

David Yehuda Surbakti — MIT License (see `LICENSE`).

## Quick start

```powershell
ziglens scan .
ziglens analyze .
ziglens deps src/database.ts
ziglens impact src/database.ts
ziglens deadcode
ziglens complexity --top 20
ziglens top --top 10
ziglens map api
ziglens diff --cached
ziglens evolution
ziglens security
ziglens serve --port 4173
```

All commands support `--json` for automation:
```powershell
ziglens deps --json > deps.json
ziglens analyze --ci   # exit 2 on quality-gate failure
```

## Features (v0.5.0)

- Filesystem scanner (read-only, symlink-safe, `.gitignore` + `.ziglensignore` aware, size-limited, generated-cache skip)
- 16 languages: JS/TS, Python, PHP, Rust, Go, Java, C/C++, C#, Kotlin, Swift, Dart, Ruby, Elixir, Zig
- Symbol index (function/class/interface/struct/enum) + imports/exports/calls
- File dependency graph, cycles, fan-in/fan-out, `path A B`, `why A B`, clustered `/api/v1/graph`
- Complexity + nesting, dead-code (HIGH/MEDIUM/LOW), impact + explainable risk
- Refactor ranking (`top`, "fix first" scoring), duplicate-block hints
- Detection maps: REST `map api`, external services, env/config (keys only), models
- `diff` / `analyze --staged`, `evolution` timeline, `baseline`/`compare` regression gates
- Security scan (masked, no plaintext secrets, `ziglens-ignore` suppression)
- Architecture layers + custom `[[rules]]` + health scores
- CLI (EN/ID via `--lang id`), JSON/MD/HTML/CSV, localhost dashboard + treemap, `/api/v1/*`
- `doctor`, `config`, shell completion, CI mode, quality gates, local plugins

## Privacy

Source code never leaves your machine. No telemetry by default. Index stays in
`.ziglens/` (add to `.gitignore`). Server binds `127.0.0.1` only.

## Docs

- `docs/CLI.md` - full command reference
- `docs/ARCHITECTURE.md` - engine design + score formulas
- `docs/CONFIG_EXAMPLE.toml` - `.ziglens.toml`, ignores, limits
- `docs/CI.md` - GitHub Actions + quality gates
- `docs/API.md` - local HTTP API
- `docs/PLUGIN.md` - plugin development
- `docs/TROUBLESHOOTING.md` - common issues
- `docs/BENCHMARKS.md` - measured performance
- `SECURITY.md` — threat model + secret handling

## Contributing

Zig 0.17.0, `zig build`, `zig build test`. See `docs/CONTRIBUTING.md`.
License: MIT.
