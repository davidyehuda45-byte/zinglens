# Local HTTP API (`/api/v1/`, localhost only)

Base: `http://127.0.0.1:4173/api/v1/`. Versioned from day one; breaking
changes bump to `/api/v2/`.

| Endpoint | Content |
|---|---|
| `GET /project` | Full snapshot: health, files, dependencies, cycles, top complexity, recommendations, security count |
| `GET /graph` | Directory clusters + capped nodes/edges + `truncated` |
| `GET /treemap` | Per-file LOC/complexity + group sums |
| `GET /symbols` | Symbol list (cap 500): name, kind, file, line |
| `GET /deadcode` | Dead-code candidates with confidence + reasons |
| `GET /complexity` | Complexity ranking (cap 100) |
| `GET /architecture` | Cycles (as paths) + violations with severity |
| `GET /security` | Masked findings (capped sample, values never stored) |
| `GET /git` | Branch, commit count, dependent hotspots |
| `GET /impact?file=X` | Risk, direct/indirect, tests, reasons (400 without `file`) |
| `GET /report?format=md\|html\|csv` | Generated report, correct content-type |
| `GET /search?q=` | File matches (cap 20) |
| `GET /files|dependencies|architecture|complexity|security|git|impact|symbols` | Snapshot alias (per-endpoint shaping roadmap) |

All JSON. No auth (localhost-only is the boundary). No CORS wide-open:
same-origin dashboard use.
