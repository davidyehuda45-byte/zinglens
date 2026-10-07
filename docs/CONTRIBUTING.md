# Contributing

Requires Zig 0.17.0.

```powershell
zig build
zig build test
./zig-out/bin/ziglens scan .
```

## Definition of Done (per feature)

- Unit tests (`zig build test`)
- Integration check on `examples/` + one real project
- CLI + `--json` if user-facing
- Docs (`docs/`, `README`, `CHANGELOG`)
- Error handling (no stack trace by default; `--verbose` for detail)
- Security review (no execution, no plaintext secrets, localhost-only)
- No regression in existing analysis (deterministic output)

## Style

- Zig, no external dependencies for core (single binary)
- `std.array_list.Managed` for lists (Zig 0.17 unmanaged migration)
- Explain every score (What/Why/Where/Impact/Confidence/Recommendation)
- Finding IDs: `DEP-*/ARCH-*/SEC-*/CODE-*/DEAD-*/GIT-*`
