# Security Policy

## Principles

ZigLens is **read-only by default**: it never executes project code, never
modifies source files, never uploads code, binds localhost only.

## Threat model (v0.1 mitigations)

| Threat | Mitigation |
|---|---|
| Malicious repo / source file | No code execution; heuristic parser with size limits (50 MB skip, 10 MB warn); NUL/binary detection |
| Malicious symlink | Never followed (skipped); no traversal outside root |
| Path traversal | Normalized `/`-paths; `..` collapsed lexically; no writes into project |
| Oversized project | `max-files 200k`, `max-depth 64`, per-file cap; graceful `too-large` skip |
| Secret exposure | Patterns matched locally; evidence **masked** (`sk_live_****************`); plaintext never stored; `ziglens-ignore` suppression |
| Dashboard exposure | `serve` binds `127.0.0.1` only; no `0.0.0.0` unless explicit future flag |
| Parser fuzz | Line-bounded (2000 chars), capped calls/symbols per file; `zig build test` + fuzz corpus planned |

## Reporting

Open a GitHub issue with `security` label or contact maintainers. Do not post
live secrets in issues. Rotate any exposed credential immediately.

## Suppression

```zig
const k = "sk_live_..."; // ziglens-ignore SEC-001 (reason)
```

Plus `.ziglensignore` (Phase 2) and per-rule config.
