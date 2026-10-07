# Changelog

## v0.7.0 — Dashboard console revamp

- Interactive SVG dependency graph: layered layout, pan/zoom, node detail
  (depends-on/needed-by), group + text filters, fullscreen, table alternative
- Health bars, recommendations list, breadcrumbs, density toggle, empty states,
  severity dots + text labels, visible focus, responsive nav
- JS syntax-checked with node --check in CI-style local gate

## v0.6.0 — Real dashboard pages

- Fixed project-JSON tail bug; added `top_complexity`, `recommendations`,
  `security_count` fields (Overview cards + table now populated)
- Dedicated endpoints: symbols, deadcode, complexity, architecture, security,
  git, impact (`?file=`, 400 without), report (`?format=`) — no more raw dumps
- Every dashboard page renders real tables/forms; impact has file form;
  reports page has download links; privacy page bilingual
- Suppression for detect.zig test fixture; security self-scan clean

## v0.5.1 — Output correctness + hardening audit

- Results to stdout, diagnostics to stderr: `--json > file` and `jq` pipelines work
- Unknown flags rejected (exit 3); `--` separator for paths starting with `-`
- Progress chatter (`Scanning…`, `Wrote …`) to stderr — stdout stays pure data
- Verified: 35 exit-code checks, 21 JSON-validity checks, secret/symlink/size probes,
  localhost-only bind (OS-level), 6 release artifacts + SHA256SUMS

## v0.5.0 — Maps, ranking, diff, evolution, treemap

- `map api|services|config|models` (endpoints, external services, env keys-only map, LOW-confidence model relations)
- `top` refactor ranking (shared scorer with `analyze` "fix first") + duplicate-block hints
- `diff [--cached|base head]` + `analyze --staged`; `report --template ci` for CI comments
- `evolution`: monthly activity bars, authors, churn with first/last seen
- `/api/v1/treemap` + dashboard Treemap page; hash deep-links, theme toggle, bookmarks, `?` overlay
- `scripts/release.ps1|.sh`: 6 targets + SHA256SUMS (ReleaseSafe ~1.5MB)
- Fixed: template priority with `--format md`, similar-code allocator leaks

## v0.4.0 — Clustered graph + hardening

- `/api/v1/graph`: directory clusters + inter-group edges + capped nodes/edges
  (500/1000, `truncated` flag) + table alternative; dashboard Dependencies page renders it
- Parser fuzz tests (NUL/unmatched/binary/100KB line) + 16-language smoke test
- Benchmarks recorded (`docs/BENCHMARKS.md`): 149 files in 0.73s

## v0.3.0 — Drift + plugins + incremental watch

- Baseline v2: stores files/deps/violation messages; `compare` shows NEW/removed
  violations with messages + files/deps delta (JSON + terminal), exit 2 on regression
- Plugin skeleton: `plugin list|install|remove`, `plugin.manifest` parsing,
  local registry `.ziglens/plugins.json`, untrusted-by-default notice
- Incremental watch: size+mtime fingerprint, full rescan only on change
- Fix: plugin registry no longer lists its own `"plugins"` key

## v0.2.0 — Phase 2 core

- `baseline create` + `compare` (exit 2 on regression) + `snapshot create` + `cache clean`
- `.ziglens.toml` + `.ziglensignore` active (limits + custom ignores)
- Custom architecture rules `[[rules]]` (e.g. ARCH-101 controllers→database)
- Git: branch + reflog commits/contributors + `git log` churn/ownership (temp-file redirect, no pipe hang)
- Report templates: `--template security|architecture|technical-debt|executive`
- Perf: generated-cache skip, 34s → 0.7s on 149-file Laravel project

## v0.1.0 — Scanner + Intelligence Core

- Zig CLI (20+ commands) with `--json`, `--lang en|id`, exit codes 0/1/2/3
- Filesystem scanner: read-only, symlink-safe, .gitignore-aware, size-limited, generated-cache aware
- 16-language heuristic parser: symbols, imports/exports, calls, complexity, nesting
- Dependency graph: resolve, cycles (DFS), fan-in/out, shortest path, dependents
- Analyses: complexity ranking, deadcode (HIGH/MEDIUM/LOW), impact + risk (explainable),
  architecture layers + ARCH-001, security scan (masked, suppression), git hotspots proxy
- Reports: terminal/JSON/MD/HTML/CSV; localhost dashboard + `/api/v1/*` (127.0.0.1 only)
- i18n EN/ID, shell completion, doctor, CI `--ci` mode, GitHub Actions example

## Roadmap

- v0.2 deps+graph hardening; v0.3 deadcode+complexity tuning; v0.4 impact;
  v0.5 dashboard graphs; v0.6 git history; v0.7 security rules; v0.8 CI/baseline;
  v0.9 more adapters; v1.0 stable.
