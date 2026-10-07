# ZigLens — X-ray for your codebase

![Version](https://img.shields.io/badge/version-0.5.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Zig](https://img.shields.io/badge/zig-0.17.0-orange)
<!-- After pushing to GitHub, replace USERNAME:
![CI](https://github.com/USERNAME/ziglens/actions/workflows/ziglens.yml/badge.svg)
-->

**English** | [Indonesia](./README.id.md)

> Point ZigLens at any project folder. In seconds, see how the code fits
> together, what is safe to change, and what needs fixing — all on your own
> machine, no internet needed.

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

## Who is this for?

- You just inherited a big project and nobody documented it
- You want to refactor but are afraid of breaking things
- You want to find unused code, tangled dependencies, and risky files
- You review code or onboard new developers

## Install (pick one)

**Download (Windows / Linux / macOS):** get the zip from GitHub Releases,
check it against `SHA256SUMS`, unpack, run.

```powershell
Expand-Archive ziglens-x86_64-windows.zip
.\ziglens.exe --help
```

> A SmartScreen warning is normal (unsigned open-source binary):
> *More info → Run anyway* — or build from source below.

**Build from source** (needs Zig 0.17+):

```powershell
zig build -Doptimize=ReleaseSafe
./zig-out/bin/ziglens --help
```

## Try it (2 minutes)

```powershell
ziglens scan .            # overview of any project
ziglens impact src/database.ts   # what breaks if I change this file?
ziglens deadcode          # unused code, with confidence levels
ziglens top               # what should I fix first?
ziglens serve             # open the visual dashboard in your browser
```

Every command also outputs clean JSON for scripts and CI:

```powershell
ziglens analyze --ci      # exits 2 if quality gates fail
```

## What it tells you (plain words)

- **Map** — which file depends on which, and who depends on a file
- **Risk** — what happens if you change a file, with reasons shown
- **Cleanup** — unused code, duplicated blocks, oversized files
- **Safety** — leaked secrets (masked, never stored), risky configs
- **History** — which files change most, who owns what, how it evolved
- **Health scores** — architecture, security, maintainability, each explainable

## Your code stays yours

- 100% offline. No account, no API key, no upload, no telemetry.
- Read-only: ZigLens never modifies or runs your code.
- Dashboard works on `127.0.0.1` only (your machine, nobody else).
- One small binary, no installer, no dependencies.

## Language / Bahasa

English by default, Indonesia available everywhere:

```powershell
ziglens scan . --lang id        # CLI in Indonesian
```

The dashboard has an **EN/ID button** in the top bar.

## Docs

- `docs/CLI.md` — every command, with examples
- `docs/TROUBLESHOOTING.md` — slow scans, false positives, port busy
- `docs/API.md` — local JSON API for your own scripts
- `docs/ARCHITECTURE.md` — how scores are calculated (no magic numbers)
- `docs/PLUGIN.md`, `docs/CI.md`, `docs/BENCHMARKS.md`

## Author & license

David Yehuda Surbakti — MIT License, see `LICENSE`.
Contributions welcome: `docs/CONTRIBUTING.md`.
