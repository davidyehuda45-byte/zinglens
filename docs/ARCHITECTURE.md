# ZigLens architecture

```
Project Scanner (Io.Dir.walk, symlink-safe, size-limited)
  → Language detect (16 langs, ext + filename heuristics)
  → Heuristic parser (symbols/imports/exports/calls/complexity)
  → Symbol index (in-memory; SQLite in Phase 2)
  → Dependency graph (resolve relative + suffix, DFS cycles, BFS paths)
  → Analysis (complexity/deadcode/impact/arch/security/git)
  → CLI / localhost server / exporters
```

## Score formulas (documented, explainable)

- **Architecture** = `100 − 8×cycles − 5×violations`
- **Maintainability** = `100 − 2×(complexity>20 files) − dead/10`
- **Risk (impact)** = base 10 + dependents (5/15/30) + transitive (10/25)
  + complexity (10/20) + tests + critical-path bonus; capped 100.
- **Hotspot (Phase 2)** = change-frequency × complexity.

Every score prints `Reasons:` — never a bare number.

## Determinism

Same source + same config → same output. No randomness, no network, no clock
dependence in scores.

## Limits

`max-file-size 50 MB` (skip), `warn 10 MB`, `max-files 200k`, `max-depth 64`,
per-file caps (500 calls). All configurable via `.ziglens.toml` (Phase 2).
