# ZigLens CLI reference

Global flags: `--json --quiet --verbose --no-color --threads --ignore --include --format --output --config --root --lang <en|id> --port --top --ci`

Exit codes: `0 pass · 1 analysis failure · 2 quality-gate failure · 3 config error`.

## scan

```
ziglens scan [root]
ziglens .                 # shorthand
```

Zero-config overview: files, symbols, languages, deps, scores, dashboard hint.

## analyze

Full health + top risk + recommendations. `--ci` fails (exit 2) on cycles/violations.

## search / symbol / refs

```
ziglens search UserService
ziglens symbol authenticate
ziglens refs authenticate
```

Searches files + symbols; `refs` lists callers. `--json` for tooling.

## deps / graph / path / why

```
ziglens deps src/database.ts
ziglens deps --json
ziglens path src/a.ts src/b.ts
ziglens why payment.ts database.ts
```

`deps <file>`: needs + needed-by. `path`: shortest dependency chain.

## impact

```
ziglens impact src/database.ts
```

Direct/indirect dependents, affected tests, risk 0–100 with reasons.

## deadcode

```
ziglens deadcode [--json]
```

Unused functions with `HIGH/MEDIUM/LOW` confidence. Never claims certainty
without evidence. Exported-but-uncalled = `LOW`.

## complexity

```
ziglens complexity --top 20
```

Cyclomatic approx + LOC + nesting, sorted desc.

## architecture

Layers (UI→Controller→Service→Repository→Database), `ARCH-001` inversions,
cycles. Score = `100 − 8×cycles − 5×violations`.

## security

Masked secret/config scan. Severities INFO→CRITICAL. Suppression:
`// ziglens-ignore SEC-001`.

## git

Branch + hotspot proxy (dependents). Full churn/ownership in Phase 2.

## report / export

```
ziglens report --format html --output report.html
ziglens export --format json --output data.json
```

Formats: `terminal|json|md|html|csv`.

## serve / watch / doctor / config

```
ziglens serve --port 4173        # http://127.0.0.1:4173 (localhost only)
ziglens watch .                  # incremental (size+mtime fingerprint)
ziglens doctor
ziglens config --json
ziglens completion powershell
```

## map

```
ziglens map api|services|config|models [--json]
```

REST endpoints, external services, env/config map (keys only, values never
stored), model relationships (LOW confidence, file-level).

## top

```
ziglens top [--top N] [--json]
```

Refactor priority: score = cx*2 + dependents*3 + violations*15 + dead*4,
plus duplicate-block hints.

## diff / --staged

```
ziglens diff [--cached] [base head]
ziglens analyze --staged
```

Changed files + affected modules + risk. `--cached` uses staged changes,
default compares worktree vs HEAD.

## evolution

```
ziglens evolution [--commits N] [--json]
```

Commit history, per-month activity bars, top churned files with first/last
seen dates.

## baseline / snapshot / compare / cache / plugin

```
ziglens baseline create .
ziglens compare [--json]         # exit 2 on new violations
ziglens snapshot create --output snap.json
ziglens cache clean
ziglens plugin list|install|remove
```
