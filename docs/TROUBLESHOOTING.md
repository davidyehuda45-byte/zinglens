# Troubleshooting

## `ziglens scan` is slow on my repo

- Generated caches are skipped automatically (`storage/framework/views`,
  `bootstrap/cache`, `public/build`, `node_modules`, …). If yours lives
  elsewhere, add it to `.ziglensignore` or `.ziglens.toml [ignore]`.
- Files >50MB are skipped (`too-large`); lower via `[limits] max_file_mb`.
- Minified single-line files are parsed at 500 chars/line by design.

## `security` flags my own pattern list / test fixture

Add suppression (Sec.83):

```zig
const k = "sk_live_..."; // ziglens-ignore SEC-001 (test fixture)
```

## `serve` port already in use

```powershell
ziglens serve --port 4180
```

Server binds `127.0.0.1` only by design — no LAN exposure.

## Windows SmartScreen / antivirus warning

The binary is unsigned (no paid certificate). This is expected for a new
open-source release: click *More info → Run anyway*, or build from source:

```powershell
zig build -Doptimize=ReleaseSafe
```

Verify integrity with `SHA256SUMS` from the release page.

## `git` shows 0 commits in a real repo

`git log` parsing needs `git` on PATH. Reflog fallback covers branch
only. Check `ziglens doctor` and `git --version`.

## JSON looks truncated

Graph/treemap endpoints cap nodes/edges (`truncated:true`) for large repos.
Filter via search or `deps <file>` for detail.
